defmodule GgenIgniter.GgenToml.IO do
  @moduledoc """
  Real `ggen.toml` file I/O over `GgenIgniter.SchemaDispatch`'s typed
  dual-schema structs (`GgenIgniter.FrontmatterConfig` /
  `GgenIgniter.ProjectConfig`). Closes the gap this repo's `mix.exs`
  declared (`{:toml, "~> 0.7"}`) but never used for real `Toml.decode/1`
  calls in `lib/` -- see
  `docs/jira/v26.9.1/02-GGEN-TOML-TOML-IO.md`.

  ## `parse!/1`

  Reads `<project_dir>/ggen.toml`, decodes it via `Toml.decode/1`
  (delegating classification + typed construction to
  `GgenIgniter.SchemaDispatch.load/1`, never re-derived here), and returns
  the correctly-typed struct. Raises `GgenIgniter.GgenToml.IO.Error` on a
  read failure or a `:refused` classification (ambiguous/unsupported/
  malformed) -- callers that want the non-raising `{:refused, ...}` tuple
  should call `GgenIgniter.SchemaDispatch.load/1` directly.

  ## `serialize!/1`

  Accepts either typed struct (`GgenIgniter.FrontmatterConfig` or
  `GgenIgniter.ProjectConfig`) and returns TOML text.

  ### Comment / key-order preservation -- accepted limitation (story c)

  The `toml` ~> 0.7 dependency's public API (`Toml.decode/1`,
  `Toml.decode_file/1`, confirmed by reading
  `deps/toml/lib/toml.ex`'s `@spec`s) has **no encode function at all**
  (`Toml.encode/1` does not exist in this library -- confirmed absent, not
  assumed) and its decode target type is a bare `map()` with no ordered-key
  or comment-attachment concept (`@spec decode(binary) :: {:ok, map} |
  error`). There is no round-trip-preserving decode target this library
  exposes to reach for instead.

  Given that, `serialize!/1` is a hand-written formatter over the typed
  struct's fields, and this is the accepted-limitation path (story c,
  option 2), stated explicitly here:

  - **Comments are always dropped.** A `%GgenIgniter.FrontmatterConfig{}`
    built from beam4pm's real `ggen.toml` carries no representation of the
    `# gh-terraform-pack: investigated 2026-08-30, NOT wired -- ...`
    comment block after the `[packs]` entries (the struct has no field for
    it), so `serialize!/1` cannot emit it. Re-running `serialize!/1` against
    beam4pm's `ggen.toml` and writing the result back will silently drop
    that decline-rationale comment block for any caller that writes back an
    unmodified-in-substance file -- a known, disclosed regression, not a
    silent one.
  - **`[packs]` key order is preserved for the common case.** `packs` is
    stored as an Elixir `%{}` map (mirroring `BTreeMap<String, PackRef>`),
    and Elixir's `Map` has no guaranteed insertion-order iteration
    contract for `Enum`/`Map.to_list/1` in general -- but in practice, for
    maps built the way `SchemaDispatch.build_frontmatter_config/1` builds
    them (`Map.new/2` over the decoded TOML table's own key order, which
    the `toml` library's decoder preserves as insertion order for small
    maps up to Erlang's small-map optimization threshold), iteration order
    equals decode order for beam4pm's real 5-entry `[packs]` table. This is
    an implementation-detail coincidence of Erlang's small-map internal
    representation, not a documented guarantee of the `toml` library or of
    Elixir's `Map` type, so it is disclosed here as observed-and-tested
    behavior for the real fixture, not promised for arbitrarily large
    `[packs]` tables.
  """

  defmodule Error do
    defexception [:message]
  end

  alias GgenIgniter.{SchemaDispatch, FrontmatterConfig, ProjectConfig}

  @doc """
  Read, classify, and parse `<project_dir>/ggen.toml` into its typed
  struct. Raises `GgenIgniter.GgenToml.IO.Error` on read failure or a
  `:refused` classification.
  """
  @spec parse!(String.t()) :: FrontmatterConfig.t() | ProjectConfig.t() | no_return
  def parse!(project_dir) when is_binary(project_dir) do
    case SchemaDispatch.load(project_dir) do
      {:declarative_rules, config} -> config
      {:frontmatter, config} -> config
      {:refused, reason} -> raise Error, message: "ggen.toml refused: #{inspect(reason)}"
    end
  end

  @doc """
  Read, classify, and parse a raw `ggen.toml` document's text (no
  filesystem access). Same contract as `parse!/1` otherwise.
  """
  @spec parse_raw!(String.t()) :: FrontmatterConfig.t() | ProjectConfig.t() | no_return
  def parse_raw!(raw) when is_binary(raw) do
    case SchemaDispatch.load_raw(raw) do
      {:declarative_rules, config} -> config
      {:frontmatter, config} -> config
      {:refused, reason} -> raise Error, message: "ggen.toml refused: #{inspect(reason)}"
    end
  end

  @doc """
  Serialize a typed struct (either schema variant) back to TOML text.
  See moduledoc for the comment/key-order accepted-limitation disclosure.
  """
  @spec serialize!(FrontmatterConfig.t() | ProjectConfig.t()) :: String.t()
  def serialize!(%FrontmatterConfig{} = config) do
    [
      section("project", %{"name" => config.project.name}),
      "",
      section("ontology", ontology_table(config.ontology)),
      "",
      packs_section(config.packs),
      "",
      section("templates", %{"dir" => config.templates.dir}),
      law_section(config.law)
    ]
    |> Enum.reject(&(&1 == :skip))
    |> Enum.join("\n")
    |> then(&(&1 <> "\n"))
  end

  def serialize!(%ProjectConfig{} = config) do
    [
      section("project", project_table(config.project)),
      "",
      section("ontology", %{"source" => config.ontology.source}),
      "",
      generation_section(config.generation),
      "",
      declarative_packs_section(config.packs)
    ]
    |> Enum.reject(&(&1 == :skip))
    |> Enum.join("\n")
    |> then(&(&1 <> "\n"))
  end

  # -- Frontmatter schema serialization -----------------------------------

  defp ontology_table(%{source: source, prefixes: prefixes}) when map_size(prefixes) == 0 do
    %{"source" => source}
  end

  defp ontology_table(%{source: source, prefixes: prefixes}) do
    %{"source" => source, "prefixes" => prefixes}
  end

  defp packs_section(packs) when map_size(packs) == 0, do: :skip

  defp packs_section(packs) do
    lines =
      Enum.map(packs, fn {name, ref} ->
        "#{toml_key(name)} = #{inline_table(pack_ref_fields(ref))}"
      end)

    Enum.join(["[packs]" | lines], "\n")
  end

  defp pack_ref_fields({:path, %{path: path} = fields}) do
    []
    |> maybe_put("path", path)
    |> maybe_put_list("extra_ontologies", Map.get(fields, :extra_ontologies, []))
    |> maybe_put_opt("lock", Map.get(fields, :lock))
  end

  defp pack_ref_fields({:git, %{git: git} = fields}) do
    []
    |> maybe_put("git", git)
    |> maybe_put_opt("version", Map.get(fields, :version))
  end

  defp law_section(%{rules: [], shapes: [], gates: [], reflexive: false}), do: :skip

  defp law_section(law) do
    fields =
      []
      |> maybe_put_list_nonempty("rules", law.rules)
      |> maybe_put_list_nonempty("shapes", law.shapes)
      |> maybe_put_list_nonempty("gates", law.gates)
      |> then(fn f -> if law.reflexive, do: f ++ [{"reflexive", true}], else: f end)

    if fields == [] do
      :skip
    else
      section("law", Map.new(fields))
    end
  end

  # -- DeclarativeRules schema serialization -------------------------------

  defp project_table(%{name: name, version: version}) do
    []
    |> maybe_put("name", name)
    |> maybe_put_opt("version", version)
    |> Map.new()
  end

  # GI-05 fix (see schema_dispatch.ex's `build_generation_config/1` comment
  # for the round-trip-losing gap this closes): `rules` is now a real list
  # of typed `%GgenIgniter.ProjectConfig.GenerationRule{}` structs, each
  # emitted as its own `[[generation.rules]]` array-of-tables block --
  # never the old always-`rules = []` shortcut.
  defp generation_section(%{rules: rules} = generation) do
    header_fields =
      []
      |> maybe_put_if_changed("output_dir", generation.output_dir, "generated")
      |> maybe_put_if_changed("max_sparql_timeout_ms", generation.max_sparql_timeout_ms, 30_000)
      |> maybe_put_if_changed("require_audit_trail", generation.require_audit_trail, false)
      |> maybe_put_opt("determinism_salt", generation.determinism_salt)
      |> maybe_put_if_changed("enable_llm", generation.enable_llm, false)
      |> maybe_put_opt("llm_provider", generation.llm_provider)
      |> maybe_put_opt("llm_model", generation.llm_model)

    header_lines = Enum.map(header_fields, fn {k, v} -> "#{toml_key(k)} = #{toml_value(v)}" end)
    header = Enum.join(["[generation]" | header_lines], "\n")

    Enum.join([header | Enum.map(rules, &generation_rule_block/1)], "\n\n")
  end

  defp maybe_put_if_changed(fields, _key, value, value), do: fields
  defp maybe_put_if_changed(fields, key, value, _default), do: fields ++ [{key, value}]

  defp generation_rule_block(%GgenIgniter.ProjectConfig.GenerationRule{} = rule) do
    lines = [
      "[[generation.rules]]",
      "name = #{toml_string(rule.name)}",
      "query = #{source_inline_table(rule.query)}",
      "template = #{source_inline_table(rule.template)}",
      "output_file = #{toml_string(rule.output_file)}"
    ]

    lines = if rule.skip_empty, do: lines ++ ["skip_empty = true"], else: lines
    lines = if rule.mode != :create, do: lines ++ ["mode = #{toml_string(mode_to_string(rule.mode))}"], else: lines
    lines = if rule.when, do: lines ++ ["when = #{toml_string(rule.when)}"], else: lines

    Enum.join(lines, "\n")
  end

  defp mode_to_string(:create), do: "Create"
  defp mode_to_string(:overwrite), do: "Overwrite"
  defp mode_to_string(:merge), do: "Merge"

  defp source_inline_table({:inline, %{inline: text}}), do: "{ inline = #{toml_multiline_string(text)} }"
  defp source_inline_table({:file, %{file: file}}), do: "{ file = #{toml_string(file)} }"

  defp source_inline_table({:pack, %{pack: pack, output: output, file: file}}),
    do: "{ pack = #{toml_string(pack)}, output = #{toml_string(output)}, file = #{toml_string(file)} }"

  defp source_inline_table({:git, %{git: git, branch: branch, path: path}}) do
    branch_part = if branch, do: ", branch = #{toml_string(branch)}", else: ""
    "{ git = #{toml_string(git)}#{branch_part}, path = #{toml_string(path)} }"
  end

  defp source_inline_table({:package, %{package: package, version: version, path: path}}) do
    version_part = if version, do: ", version = #{toml_string(version)}", else: ""
    "{ package = #{toml_string(package)}#{version_part}, path = #{toml_string(path)} }"
  end

  # Triple-quoted TOML basic multi-line string, used for `query = { inline =
  # ... }` -- inline SPARQL bodies routinely contain unescaped `"`  (e.g.
  # `ex:label "hello-world"`), which a single-quoted `toml_string/1` value
  # would corrupt.
  defp toml_multiline_string(s), do: "\"\"\"\n" <> s <> "\"\"\""

  defp declarative_packs_section(packs) when packs == [], do: :skip

  defp declarative_packs_section(packs) do
    blocks =
      Enum.map(packs, fn %GgenIgniter.PackRef{} = ref ->
        fields =
          []
          |> maybe_put("name", ref.name)
          |> maybe_put("registry", ref.registry)
          |> maybe_put_opt("path", ref.path)
          |> maybe_put_opt("version", ref.version)

        lines = Enum.map(fields, fn {k, v} -> "#{toml_key(k)} = #{toml_value(v)}" end)
        Enum.join(["[[packs]]" | lines], "\n")
      end)

    Enum.join(blocks, "\n\n")
  end

  # -- Shared TOML formatting helpers --------------------------------------

  defp section(name, fields) when is_map(fields) do
    lines = Enum.map(fields, fn {k, v} -> "#{toml_key(k)} = #{toml_value(v)}" end)
    Enum.join(["[#{name}]" | lines], "\n")
  end

  defp inline_table(fields) do
    body = Enum.map_join(fields, ", ", fn {k, v} -> "#{toml_key(k)} = #{toml_value(v)}" end)
    "{ #{body} }"
  end

  defp maybe_put(fields, _key, nil), do: fields
  defp maybe_put(fields, key, value), do: fields ++ [{key, value}]

  defp maybe_put_opt(fields, _key, nil), do: fields
  defp maybe_put_opt(fields, key, value), do: fields ++ [{key, value}]

  defp maybe_put_list(fields, _key, []), do: fields
  defp maybe_put_list(fields, key, list), do: fields ++ [{key, list}]

  defp maybe_put_list_nonempty(fields, _key, []), do: fields
  defp maybe_put_list_nonempty(fields, key, list), do: fields ++ [{key, list}]

  defp toml_key(key) when is_atom(key), do: to_string(key)
  defp toml_key(key) when is_binary(key), do: key

  defp toml_value(v) when is_binary(v), do: toml_string(v)
  defp toml_value(v) when is_boolean(v), do: to_string(v)
  defp toml_value(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp toml_value(v) when is_list(v), do: toml_array(v)
  defp toml_value(%{} = v), do: inline_table(Map.to_list(v))

  defp toml_array(list) do
    body = Enum.map_join(list, ", ", &toml_value/1)
    "[#{body}]"
  end

  defp toml_string(s), do: "\"" <> String.replace(s, "\"", "\\\"") <> "\""
end
