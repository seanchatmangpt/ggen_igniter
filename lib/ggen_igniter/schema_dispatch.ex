defmodule GgenIgniter.FrontmatterConfig do
  @moduledoc """
  Mirrors Rust `ggen_engine::config::GgenConfig`
  (`~/ggen/crates/ggen-engine/src/config.rs:45-52`) -- the `[templates].dir`
  per-file frontmatter `ggen.toml` schema, the schema real consumers
  (beam4pm) actually use today.

  `packs` is an Elixir map keyed by pack name (mirroring
  `BTreeMap<String, PackRef>`), matching `ggen.toml`'s `[packs]`
  table-of-tables shape. `project`/`ontology`/`templates` mirror the Rust
  struct's required tables; `law` mirrors the optional `[law]` table
  (`rules`/`shapes`/`gates`/`reflexive`), defaulting to the Rust side's own
  `#[derive(Default)]` shape when the table is absent.

  Which schema a given `ggen.toml` uses is decided by
  `GgenIgniter.SchemaDispatch`, never re-derived here or at any other call
  site -- see that module's moduledoc. The sibling `DeclarativeRules` struct
  family is `GgenIgniter.ProjectConfig`/`GgenIgniter.PackRef`.
  """

  defstruct [:project, :ontology, :templates, packs: %{}, law: %{rules: [], shapes: [], gates: [], reflexive: false}]

  @type t :: %__MODULE__{
          project: %{name: String.t()},
          ontology: %{source: String.t(), prefixes: %{optional(String.t()) => String.t()}},
          templates: %{dir: String.t()},
          packs: %{optional(String.t()) => GgenIgniter.FrontmatterPackRef.t()},
          law: %{
            rules: [String.t()],
            shapes: [String.t()],
            gates: [String.t()],
            reflexive: boolean()
          }
        }
end

defmodule GgenIgniter.FrontmatterPackRef do
  @moduledoc """
  Mirrors Rust `ggen_engine::config::PackRef`
  (`~/ggen/crates/ggen-engine/src/config.rs`) -- the untagged
  `Path { path, extra_ontologies, lock } | Git { git, version }` enum used by
  `GgenIgniter.FrontmatterConfig`'s `[packs]` table-of-tables entries.

  Elixir has no untagged-union deserialization primitive, the same
  constraint `GgenIgniter.ProjectConfig.QuerySource`/`TemplateSource`
  document and solve via tagged tuples -- this module follows the same
  precedent: a discriminated tagged tuple,
  `{:path, %{path: ..., extra_ontologies: ..., lock: ...}}` |
  `{:git, %{git: ..., version: ...}}`, rather than a struct, since which
  variant applies is decided per-entry by which keys are present (`path` vs
  `git`), not by any explicit tag in the TOML itself.
  """

  @type t ::
          {:path, %{path: String.t(), extra_ontologies: [String.t()], lock: String.t() | nil}}
          | {:git, %{git: String.t(), version: String.t() | nil}}
end

defmodule GgenIgniter.SchemaDispatch do
  @moduledoc """
  The single shared classifier + dispatch point deciding which of
  `ggen.toml`'s two independently-defined schemas a project uses, mirroring
  `ggen_config::classify_ggen_toml`
  (`~/ggen/crates/ggen-config/src/config_schema.rs`) and `ggen-engine`'s
  `schema_dispatch::load`
  (`~/ggen/crates/ggen-engine/src/schema_dispatch.rs`).

  # Why this exists (BUG-005)

  Before `schema_dispatch.rs` existed in ggen core, six real call sites each
  guessed the `ggen.toml` schema by their own ad-hoc logic; `ggen doctor`
  unconditionally assumed the frontmatter schema and failed against ggen's
  own declarative-rules root `ggen.toml`. This module is `ggen_igniter`'s
  port of the fix: the *only* place in this codebase that decides which
  schema a `ggen.toml` uses. Any future `ggen_igniter` call site that needs
  to know the schema calls `classify/1` or `load/1` here -- none re-derives
  the check locally.

  # The two schemas

  - `:declarative_rules` -- `GgenIgniter.ProjectConfig` /
    `GgenIgniter.PackRef` (`[[generation.rules]]` non-empty,
    `[[packs]]` array-of-tables with a flat `PackRef{name, registry, path,
    version}`).
  - `:frontmatter` -- `GgenIgniter.FrontmatterConfig` /
    `GgenIgniter.FrontmatterPackRef` (`[templates].dir`-driven,
    `[packs]` table-of-tables keyed by name, untagged `Path | Git` entries).
    This is the schema beam4pm's real `ggen.toml` uses today, and the one
    exercised first and by default in new bundle-installer work.

  Fail-closed cases mirror the Rust classifier exactly: `:ambiguous`
  (conflicting structural markers from both schemas), `:unsupported`
  (matches neither schema), `:malformed` (invalid TOML) -- never a raised
  exception, never a silent wrong-schema guess.
  """

  @declarative_only_tables ~w(inference validation sync output ai sparql lifecycle security performance logging telemetry features env build test package mcp a2a)

  @strong_declarative_markers ~w(declarative:generation_table_present declarative:packs_array_shaped)

  @type classification ::
          {:declarative_rules, GgenIgniter.ProjectConfig.t()}
          | {:frontmatter, GgenIgniter.FrontmatterConfig.t()}
          | {:refused, refusal()}

  @type refusal ::
          {:ambiguous, matched: [String.t()]}
          | {:unsupported, observed_markers: [String.t()]}
          | {:malformed, diagnostic: String.t()}

  @doc """
  Read `<project_dir>/ggen.toml`, classify it, and parse it with the
  matching typed struct. `project_dir` is an explicit argument -- no
  `File.cwd!()` implicit dependency, matching `GgenIgniter.DoctorFixes`'s
  established `project_dir`-as-explicit-argument convention.
  """
  @spec load(String.t()) :: classification()
  def load(project_dir) when is_binary(project_dir) do
    ggen_toml_path = Path.join(project_dir, "ggen.toml")

    case File.read(ggen_toml_path) do
      {:ok, raw} -> load_raw(raw)
      {:error, reason} ->
        {:refused, {:malformed, diagnostic: "could not read #{ggen_toml_path}: #{inspect(reason)}"}}
    end
  end

  @doc """
  Classify and parse a raw `ggen.toml` document's text (no filesystem
  access) -- mirrors `ggen_config::classify_ggen_toml`'s pure-function
  contract, plus the typed parse `schema_dispatch::load` layers on top.
  """
  @spec load_raw(String.t()) :: classification()
  def load_raw(raw) when is_binary(raw) do
    case Toml.decode(raw) do
      {:ok, table} ->
        case classify_table(table) do
          :declarative_rules -> {:declarative_rules, build_project_config(table)}
          :frontmatter -> {:frontmatter, build_frontmatter_config(table)}
          {:ambiguous, matched} -> {:refused, {:ambiguous, matched: matched}}
          {:unsupported, observed} -> {:refused, {:unsupported, observed_markers: observed}}
        end

      {:error, reason} ->
        {:refused, {:malformed, diagnostic: "invalid ggen.toml document: #{inspect(reason)}"}}
    end
  end

  @doc """
  Pure classifier: which schema does this already-decoded `ggen.toml` table
  match? Mirrors `ggen_config::classify_ggen_toml`'s marker/decision logic
  exactly (project.version presence, generation table/rules, law.shapes,
  packs array-vs-table shape, declarative-only extra tables, the
  strong-marker override, and the frontmatter-minimum positive-confirmation
  fallback).
  """
  @spec classify_table(map()) ::
          :declarative_rules
          | :frontmatter
          | {:ambiguous, [String.t()]}
          | {:unsupported, [String.t()]}
  def classify_table(table) when is_map(table) do
    declarative = MapSet.new()
    frontmatter = MapSet.new()

    {declarative, frontmatter} = mark_project_version(table, declarative, frontmatter)
    {declarative, frontmatter} = mark_generation(table, declarative, frontmatter)
    {declarative, frontmatter} = mark_law_shapes(table, declarative, frontmatter)
    {declarative, frontmatter} = mark_packs_shape(table, declarative, frontmatter)
    declarative = mark_declarative_only_tables(table, declarative)

    has_strong_declarative =
      Enum.any?(declarative, &(&1 in @strong_declarative_markers))

    decide(declarative, frontmatter, has_strong_declarative, table)
  end

  defp mark_project_version(table, declarative, frontmatter) do
    case Map.get(table, "project") do
      %{} = project ->
        if Map.has_key?(project, "version") do
          {MapSet.put(declarative, "declarative:project_version_present"), frontmatter}
        else
          {declarative, MapSet.put(frontmatter, "frontmatter:project_missing_version")}
        end

      _ ->
        {declarative, frontmatter}
    end
  end

  defp mark_generation(table, declarative, frontmatter) do
    case Map.get(table, "generation") do
      %{} = generation ->
        declarative = MapSet.put(declarative, "declarative:generation_table_present")

        rules = Map.get(generation, "rules")

        declarative =
          if is_list(rules) and rules != [] do
            MapSet.put(declarative, "declarative:generation_rules_non_empty")
          else
            declarative
          end

        {declarative, frontmatter}

      _ ->
        {declarative, frontmatter}
    end
  end

  defp mark_law_shapes(table, declarative, frontmatter) do
    case Map.get(table, "law") do
      %{} = law ->
        if Map.has_key?(law, "shapes") do
          {declarative, MapSet.put(frontmatter, "frontmatter:law_shapes_present")}
        else
          {declarative, frontmatter}
        end

      _ ->
        {declarative, frontmatter}
    end
  end

  defp mark_packs_shape(table, declarative, frontmatter) do
    case Map.get(table, "packs") do
      entries when is_list(entries) ->
        declarative = MapSet.put(declarative, "declarative:packs_array_shaped")

        declarative =
          if Enum.any?(entries, &(is_map(&1) and Map.has_key?(&1, "name"))) do
            MapSet.put(declarative, "declarative:packref_entry_has_name")
          else
            declarative
          end

        {declarative, frontmatter}

      %{} = map ->
        frontmatter = MapSet.put(frontmatter, "frontmatter:packs_table_shaped")

        frontmatter =
          if Enum.any?(map, fn {_k, v} -> is_map(v) and not Map.has_key?(v, "name") end) do
            MapSet.put(frontmatter, "frontmatter:packref_entry_missing_name")
          else
            frontmatter
          end

        {declarative, frontmatter}

      _ ->
        {declarative, frontmatter}
    end
  end

  defp mark_declarative_only_tables(table, declarative) do
    Enum.reduce(@declarative_only_tables, declarative, fn name, acc ->
      if Map.has_key?(table, name) do
        MapSet.put(acc, "declarative:extra_table_present:#{name}")
      else
        acc
      end
    end)
  end

  defp decide(declarative, frontmatter, has_strong_declarative, table) do
    declarative_empty? = MapSet.size(declarative) == 0
    frontmatter_empty? = MapSet.size(frontmatter) == 0

    cond do
      not declarative_empty? and frontmatter_empty? and has_strong_declarative ->
        :declarative_rules

      not declarative_empty? and frontmatter_empty? ->
        if satisfies_frontmatter_minimum?(table) do
          matched = Enum.sort(MapSet.to_list(declarative) ++ ["frontmatter:satisfies_minimum_shape"])
          {:ambiguous, matched}
        else
          {:unsupported, observed_top_level_tables(table)}
        end

      declarative_empty? and not frontmatter_empty? ->
        :frontmatter

      not declarative_empty? and not frontmatter_empty? ->
        matched = Enum.sort(MapSet.to_list(declarative) ++ MapSet.to_list(frontmatter))
        {:ambiguous, matched}

      true ->
        if satisfies_frontmatter_minimum?(table) do
          :frontmatter
        else
          {:unsupported, observed_top_level_tables(table)}
        end
    end
  end

  defp observed_top_level_tables(table) do
    table
    |> Map.keys()
    |> Enum.map(&"unknown_top_level_table:#{&1}")
    |> Enum.sort()
  end

  defp satisfies_frontmatter_minimum?(table) do
    has_project_name =
      case get_in(table, ["project", "name"]) do
        s when is_binary(s) and s != "" -> true
        _ -> false
      end

    has_ontology_source =
      case get_in(table, ["ontology", "source"]) do
        s when is_binary(s) -> true
        _ -> false
      end

    has_templates_dir =
      case get_in(table, ["templates", "dir"]) do
        s when is_binary(s) -> true
        _ -> false
      end

    has_project_name and has_ontology_source and has_templates_dir
  end

  # -- DeclarativeRules struct construction -------------------------------

  defp build_project_config(table) do
    project = Map.get(table, "project", %{})
    ontology = Map.get(table, "ontology", %{})

    %GgenIgniter.ProjectConfig{
      project: %GgenIgniter.ProjectConfig.ProjectSection{
        name: Map.get(project, "name"),
        version: Map.get(project, "version")
      },
      ontology: %GgenIgniter.ProjectConfig.OntologyConfig{
        source: Map.get(ontology, "source")
      },
      generation: build_generation_config(Map.get(table, "generation", %{})),
      packs: Map.get(table, "packs", []) |> Enum.map(&build_declarative_pack_ref/1)
    }
  end

  defp build_declarative_pack_ref(entry) do
    %GgenIgniter.PackRef{
      name: Map.get(entry, "name"),
      registry: Map.get(entry, "registry", "local"),
      path: Map.get(entry, "path"),
      version: Map.get(entry, "version")
    }
  end

  # `[[generation.rules]]` and `[generation]`'s own scalar fields were, until
  # this ticket (GI-05, `docs/jira/v26.9.1/05-FORTUNE5-READY-MIX-TASK-AND-
  # E2E-TEST.md`), silently dropped -- `build_project_config/1` hardcoded
  # `rules: []` regardless of what was actually on disk. That is a real
  # round-trip-losing gap (surfaced by GI-05's own DeclarativeRules
  # end-to-end test: `parse! |> merge |> serialize! |> ggen sync run`
  # against a real fixture with a non-empty `[[generation.rules]]`
  # silently wrote back an empty rules array, breaking the real subprocess
  # sync it was supposed to drive), not a cosmetic one -- fixed here rather
  # than worked around in the mix task, since every caller of `SchemaDispatch.
  # load/1` against a DeclarativeRules `ggen.toml` needs its real rules,
  # not just this ticket's own task.
  defp build_generation_config(generation) do
    %GgenIgniter.ProjectConfig.GenerationConfig{
      rules: Map.get(generation, "rules", []) |> Enum.map(&build_generation_rule/1),
      max_sparql_timeout_ms: Map.get(generation, "max_sparql_timeout_ms", 30_000),
      require_audit_trail: Map.get(generation, "require_audit_trail", false),
      determinism_salt: Map.get(generation, "determinism_salt"),
      output_dir: Map.get(generation, "output_dir", "generated"),
      enable_llm: Map.get(generation, "enable_llm", false),
      llm_provider: Map.get(generation, "llm_provider"),
      llm_model: Map.get(generation, "llm_model")
    }
  end

  defp build_generation_rule(entry) do
    %GgenIgniter.ProjectConfig.GenerationRule{
      name: Map.fetch!(entry, "name"),
      query: build_query_source(Map.fetch!(entry, "query")),
      template: build_template_source(Map.fetch!(entry, "template")),
      output_file: Map.fetch!(entry, "output_file"),
      skip_empty: Map.get(entry, "skip_empty", false),
      mode: parse_generation_mode(Map.get(entry, "mode", "create")),
      when: Map.get(entry, "when")
    }
  end

  defp build_query_source(%{"inline" => inline}), do: {:inline, %{inline: inline}}

  defp build_query_source(%{"pack" => pack, "output" => output, "file" => file}),
    do: {:pack, %{pack: pack, output: output, file: file}}

  defp build_query_source(%{"file" => file}), do: {:file, %{file: file}}

  defp build_template_source(%{"inline" => inline}), do: {:inline, %{inline: inline}}

  defp build_template_source(%{"pack" => pack, "output" => output, "file" => file}),
    do: {:pack, %{pack: pack, output: output, file: file}}

  defp build_template_source(%{"git" => git} = entry),
    do: {:git, %{git: git, branch: Map.get(entry, "branch"), path: Map.fetch!(entry, "path")}}

  defp build_template_source(%{"package" => package} = entry),
    do:
      {:package,
       %{package: package, version: Map.get(entry, "version"), path: Map.fetch!(entry, "path")}}

  defp build_template_source(%{"file" => file}), do: {:file, %{file: file}}

  defp parse_generation_mode(mode) when is_atom(mode), do: mode

  defp parse_generation_mode(mode) when is_binary(mode),
    do: mode |> String.downcase() |> String.to_atom()

  # -- FrontmatterConfig struct construction ------------------------------

  defp build_frontmatter_config(table) do
    project = Map.get(table, "project", %{})
    ontology = Map.get(table, "ontology", %{})
    templates = Map.get(table, "templates", %{})
    law = Map.get(table, "law", %{})
    packs = Map.get(table, "packs", %{})

    %GgenIgniter.FrontmatterConfig{
      project: %{name: Map.get(project, "name")},
      ontology: %{
        source: Map.get(ontology, "source"),
        prefixes: Map.get(ontology, "prefixes", %{})
      },
      templates: %{dir: Map.get(templates, "dir")},
      packs: Map.new(packs, fn {name, entry} -> {name, build_frontmatter_pack_ref(entry)} end),
      law: %{
        rules: Map.get(law, "rules", []),
        shapes: Map.get(law, "shapes", []),
        gates: Map.get(law, "gates", []),
        reflexive: Map.get(law, "reflexive", false)
      }
    }
  end

  defp build_frontmatter_pack_ref(entry) when is_map(entry) do
    cond do
      Map.has_key?(entry, "path") ->
        {:path,
         %{
           path: Map.get(entry, "path"),
           extra_ontologies: Map.get(entry, "extra_ontologies", []),
           lock: Map.get(entry, "lock")
         }}

      Map.has_key?(entry, "git") ->
        {:git, %{git: Map.get(entry, "git"), version: Map.get(entry, "version")}}

      true ->
        {:path, %{path: nil, extra_ontologies: [], lock: nil}}
    end
  end
end
