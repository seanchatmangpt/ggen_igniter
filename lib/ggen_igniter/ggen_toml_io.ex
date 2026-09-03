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

  alias GgenIgniter.{SchemaDispatch, FrontmatterConfig, ProjectConfig, Bundle}

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

  @doc """
  GI-07 targeted fix for story (c)'s disclosed comment/key-order-preservation
  gap, scoped narrowly to the one path that actually needs it: the
  merge-then-write-back of a bundle's new pack entries into an existing
  Frontmatter-schema `ggen.toml`'s `[packs]` table (GGEN-1803/1807's
  consumer, `Mix.Tasks.GgenIgniter.Fortune5Ready`).

  Unlike `serialize!/1` (a full hand-written re-render of the whole typed
  struct, which necessarily drops every field the struct has no
  representation for -- comments included, per the moduledoc's accepted
  limitation), this function never re-renders the file. It works over the
  **original raw text** and performs a pure textual splice: it locates the
  contiguous run of real `key = { ... }` entry lines directly under the
  `[packs]` header, and inserts one new line per `to_add` pack immediately
  after the last such entry line -- before whatever follows it (a trailing
  comment block, a blank line, the next `[section]`, or end of file).

  Every existing line -- including beam4pm's real
  `# gh-terraform-pack: investigated 2026-08-30, NOT wired -- ...` comment
  block, and the original `[packs]` entries' key order -- is reproduced
  byte-for-byte. The diff between `raw` and this function's return value is
  addition-only: new lines appended into the entries run, nothing removed,
  nothing reordered, nothing rewritten.

  Raises `GgenIgniter.GgenToml.IO.Error` if `raw` has no `[packs]` header at
  all (this splice has nothing to anchor on) -- callers with that shape
  should fall back to `serialize!/1` or install a `[packs]` header first.
  """
  @spec splice_added_packs!(String.t(), [Bundle.Pack.t()]) :: String.t()
  def splice_added_packs!(raw, to_add) when is_binary(raw) and is_list(to_add) do
    lines = String.split(raw, "\n")

    header_idx =
      Enum.find_index(lines, &(String.trim(&1) == "[packs]")) ||
        raise Error, message: "splice_added_packs!/2: raw ggen.toml text has no [packs] header"

    last_entry_idx = last_contiguous_entry_index(lines, header_idx)

    new_lines =
      Enum.map(to_add, fn %Bundle.Pack{name: name, path_hint: path_hint} ->
        "#{toml_key(name)} = { path = #{toml_string(path_hint)} }"
      end)

    {before, after_} = Enum.split(lines, last_entry_idx + 1)
    Enum.join(before ++ new_lines ++ after_, "\n")
  end

  @packs_entry_re ~r/^[A-Za-z0-9_-]+\s*=\s*\{.*\}\s*$/

  # Walks forward from the `[packs]` header line, returning the index of the
  # last line that is itself a real `key = { ... }` entry (skips nothing --
  # the first non-matching line, comment or otherwise, ends the run). When
  # the table has no entries at all (header immediately followed by a
  # comment, blank line, next section, or EOF), returns the header's own
  # index so new entries are inserted directly under `[packs]`.
  defp last_contiguous_entry_index(lines, header_idx) do
    entries_start = header_idx + 1
    max_idx = length(lines) - 1

    if entries_start > max_idx do
      header_idx
    else
      do_last_contiguous_entry_index(lines, entries_start, max_idx, header_idx)
    end
  end

  defp do_last_contiguous_entry_index(lines, entries_start, max_idx, header_idx) do
    Enum.reduce_while(entries_start..max_idx, header_idx, fn idx, last_idx ->
      line = Enum.at(lines, idx)

      if Regex.match?(@packs_entry_re, line) do
        {:cont, idx}
      else
        {:halt, last_idx}
      end
    end)
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

    lines =
      if rule.mode != :create,
        do: lines ++ ["mode = #{toml_string(mode_to_string(rule.mode))}"],
        else: lines

    lines = if rule.when, do: lines ++ ["when = #{toml_string(rule.when)}"], else: lines

    Enum.join(lines, "\n")
  end

  defp mode_to_string(:create), do: "Create"
  defp mode_to_string(:overwrite), do: "Overwrite"
  defp mode_to_string(:merge), do: "Merge"

  defp source_inline_table({:inline, %{inline: text}}),
    do: "{ inline = #{toml_multiline_string(text)} }"

  defp source_inline_table({:file, %{file: file}}), do: "{ file = #{toml_string(file)} }"

  defp source_inline_table({:pack, %{pack: pack, output: output, file: file}}),
    do:
      "{ pack = #{toml_string(pack)}, output = #{toml_string(output)}, file = #{toml_string(file)} }"

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
