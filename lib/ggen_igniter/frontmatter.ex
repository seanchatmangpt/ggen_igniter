defmodule GgenIgniter.Frontmatter do
  @moduledoc """
  Elixir shape mirroring the real Rust `ggen::Frontmatter` struct 1:1
  (`~/ggen/crates/ggen-engine/src/template.rs:40-175`, ggen v26.8.24).

  This module exists so a template-frontmatter block parsed on the Elixir side
  (`ggen_igniter`) and the same block parsed on the Rust/WASM side (the
  planned WASM bridge for the templating/write-safety engine, handled by
  another agent) describe the identical field set with the identical names —
  no field renames, no field drops, no Elixir-only additions to this struct.
  Fields not yet consumed by any `ggen_igniter` code path are still declared
  here (as `nil`-defaulted) so the shape stays a faithful mirror; wiring their
  actual behavior is separate follow-on work, not part of this alignment
  pass.

  Field-by-field provenance (all from `template.rs:40-175` unless noted):

  - `to` — `String` (required). Output path template string.
  - `sparql` — `%{String.t() => String.t()}`, default `%{}`. Named query
    sources (Rust: `BTreeMap<String, String>` via `sparql_map`).
  - `for_each` — `String.t() | nil`. Name of the query whose rows drive
    multi-row fan-out.
  - `construct` — `String.t() | nil`. A CONSTRUCT query string.
  - `inject` — `boolean()`, default `false`.
  - `before` / `after` — `GgenIgniter.Frontmatter.MatchSpec.t() | nil`.
  - `at_line` — `pos_integer() | nil`.
  - `skip_if` — `GgenIgniter.Frontmatter.MatchSpec.t() | nil`.
  - `unless_exists` — `boolean()`, default `false`.
  - `unattended_write_eligible` — `boolean()`, default `false`.
  - `force` — `boolean()`, default `false`.
  - `when` — `String.t() | nil`. A SPARQL ASK guard expression.
  - `skip_empty` — `boolean()`, default `false`.
  - `from` — `String.t() | nil`.
  - `sh_before` — `String.t() | nil` (Rust field is aliased from `sh`).
  - `sh_after` — `String.t() | nil`.
  - `backup` — `boolean()`, default `false`.
  - `shape` — `[String.t()]`, default `[]`. SHACL shape file paths.
  - `determinism` — `boolean() | nil`.
  - `freeze_policy` — `GgenIgniter.Frontmatter.FreezePolicy.t() | nil`.
  - `freeze_slots_dir` — `String.t() | nil`.
  - `rdf` — `[String.t()]`, default `[]`.
  - `rdf_inline` — `[String.t()]`, default `[]`.
  - `prefixes` — `%{String.t() => String.t()}`, default `%{}`.
  - `base` — `String.t() | nil`.

  ## `inject`/`before`/`after`/`at_line` are wired into `mix ggen_igniter.sync`

  When a `mode: file` template's frontmatter has `inject: true`,
  `Mix.Tasks.GgenIgniter.Sync` dispatches the rendered body to
  `GgenIgniter.Actuate.inject_content!/5` against the resolved output path,
  instead of `GgenIgniter.Actuate.write_file!/3` -- using exactly one of
  `before:`, `after:`, or `at_line:` as the anchor (a template with zero, or
  more than one, of these three set while `inject: true` raises a clear,
  named `ArgumentError` -- an ambiguous anchor is a template-authoring error,
  never a silent pick). `before`/`after`'s `t:GgenIgniter.Frontmatter.MatchSpec.t/0`
  is converted into `inject_content!/5`'s real `marker` arg
  (`String.t() | Regex.t() | nil`) by `Mix.Tasks.GgenIgniter.Sync`'s private
  `match_spec_to_marker!/2` -- a `{:literal, s}` spec maps directly onto a
  plain string marker; a `{:structured, %MatchRule{}}` spec honors `matcher`
  (`:contains`/`:exact`/`:regex`) and `case_sensitive`, and `trim` when
  paired with `matcher: :exact`, converting each combination into the
  equivalent `Regex` (or, for the `:contains` + case-sensitive default, the
  same plain string `inject_content!/5` already treats as a substring match).
  `scope: :file`, any `occurrence` other than the default `:first`, and
  `trim: true` on a non-`:exact` matcher have no equivalent in
  `inject_content!/5`'s real anchor-resolution behavior (it always requires
  the marker to match EXACTLY one line, has no whole-file matching mode, and
  no "pick the last/nth occurrence" logic) -- setting one of those raises a
  clear error naming the exact unsupported combination, rather than being
  silently dropped. `--dry-run` previews an injection the same honest way it
  previews a write: the real anchor/idempotency check runs
  (`inject_content!/5`'s own `:dry_run` option), nothing is written, and the
  notice line reads `"planned: inject ..."` / `"planned: skip ... (unchanged)"`.

  See `Mix.Tasks.GgenIgniter.Sync`'s moduledoc (`## Injection mode
  (inject: true)`) for the full CLI-facing behavior and examples.
  """

  @enforce_keys [:to]
  defstruct to: nil,
            sparql: %{},
            for_each: nil,
            construct: nil,
            inject: false,
            before: nil,
            after: nil,
            at_line: nil,
            skip_if: nil,
            unless_exists: false,
            unattended_write_eligible: false,
            force: false,
            when: nil,
            skip_empty: false,
            from: nil,
            sh_before: nil,
            sh_after: nil,
            backup: false,
            shape: [],
            determinism: nil,
            freeze_policy: nil,
            freeze_slots_dir: nil,
            rdf: [],
            rdf_inline: [],
            prefixes: %{},
            base: nil

  @type t :: %__MODULE__{
          to: String.t(),
          sparql: %{optional(String.t()) => String.t()},
          for_each: String.t() | nil,
          construct: String.t() | nil,
          inject: boolean(),
          before: GgenIgniter.Frontmatter.MatchSpec.t() | nil,
          after: GgenIgniter.Frontmatter.MatchSpec.t() | nil,
          at_line: pos_integer() | nil,
          skip_if: GgenIgniter.Frontmatter.MatchSpec.t() | nil,
          unless_exists: boolean(),
          unattended_write_eligible: boolean(),
          force: boolean(),
          when: String.t() | nil,
          skip_empty: boolean(),
          from: String.t() | nil,
          sh_before: String.t() | nil,
          sh_after: String.t() | nil,
          backup: boolean(),
          shape: [String.t()],
          determinism: boolean() | nil,
          freeze_policy: GgenIgniter.Frontmatter.FreezePolicy.t() | nil,
          freeze_slots_dir: String.t() | nil,
          rdf: [String.t()],
          rdf_inline: [String.t()],
          prefixes: %{optional(String.t()) => String.t()},
          base: String.t() | nil
        }

  @doc """
  Builds a `t:t/0` from a plain string-keyed map (e.g. the result of parsing a
  YAML frontmatter block), applying the same field-name-for-field-name mapping
  as the Rust struct -- no renames. Raises `ArgumentError` if `"to"` is
  missing (mirrors Rust's non-`Option` `to: String` being a required field).

  See `from_map/2` for the `require_to: false` escape hatch used by
  `split_template/1` for `mode: eval` templates, which have no `to:` at all.

  ## Examples

      iex> fm = GgenIgniter.Frontmatter.from_map(%{"to" => "lib/foo.ex"})
      iex> {fm.to, fm.sparql, fm.skip_empty}
      {"lib/foo.ex", %{}, false}

      iex> GgenIgniter.Frontmatter.from_map(%{})
      ** (ArgumentError) frontmatter is missing required field "to"

  """
  @spec from_map(map()) :: t()
  def from_map(map), do: from_map(map, [])

  @doc """
  Same as `from_map/1`, but accepts `require_to: false` to skip the "to" is
  required check -- used only for `mode: eval` templates (see
  `split_template/1`), which write nothing to disk and so have no output path
  to require. Every other field's mapping is identical to `from_map/1`.
  """
  @spec from_map(map(), keyword()) :: t()
  def from_map(map, opts) when is_map(map) and is_list(opts) do
    require_to = Keyword.get(opts, :require_to, true)

    to =
      case Map.get(map, "to") do
        nil when require_to -> raise ArgumentError, "frontmatter is missing required field \"to\""
        value -> value
      end

    %__MODULE__{
      to: to,
      sparql: Map.get(map, "sparql", %{}),
      for_each: Map.get(map, "for_each"),
      construct: Map.get(map, "construct"),
      inject: Map.get(map, "inject", false),
      before: parse_match_spec(Map.get(map, "before")),
      after: parse_match_spec(Map.get(map, "after")),
      at_line: Map.get(map, "at_line"),
      skip_if: parse_match_spec(Map.get(map, "skip_if")),
      unless_exists: Map.get(map, "unless_exists", false),
      unattended_write_eligible: Map.get(map, "unattended_write_eligible", false),
      force: Map.get(map, "force", false),
      when: Map.get(map, "when"),
      skip_empty: Map.get(map, "skip_empty", false),
      from: Map.get(map, "from"),
      sh_before: Map.get(map, "sh_before") || Map.get(map, "sh"),
      sh_after: Map.get(map, "sh_after"),
      backup: Map.get(map, "backup", false),
      shape: Map.get(map, "shape", []),
      determinism: Map.get(map, "determinism"),
      freeze_policy: parse_freeze_policy(Map.get(map, "freeze_policy")),
      freeze_slots_dir: Map.get(map, "freeze_slots_dir"),
      rdf: string_or_seq(Map.get(map, "rdf", [])),
      rdf_inline: string_or_seq(Map.get(map, "rdf_inline", [])),
      prefixes: Map.get(map, "prefixes", %{}),
      base: Map.get(map, "base")
    }
  end

  defp string_or_seq(nil), do: []
  defp string_or_seq(s) when is_binary(s), do: [s]
  defp string_or_seq(list) when is_list(list), do: list

  defp parse_match_spec(nil), do: nil
  defp parse_match_spec(s) when is_binary(s), do: GgenIgniter.Frontmatter.MatchSpec.literal(s)

  defp parse_match_spec(%{} = map),
    do:
      GgenIgniter.Frontmatter.MatchSpec.structured(
        GgenIgniter.Frontmatter.MatchRule.from_map(map)
      )

  defp parse_freeze_policy(nil), do: nil
  defp parse_freeze_policy("never"), do: :never
  defp parse_freeze_policy("always"), do: :always
  defp parse_freeze_policy("checksum"), do: :checksum

  @doc """
  Splits a raw template file's text into its leading YAML frontmatter block
  (if any), its execution `mode`, and the remaining template body, mirroring
  the real Rust ggen's own header convention (a `---` fence at the very top of
  the file, matched by `ggen-engine`'s frontmatter scanner) and hygen's
  identical `---\\n...\\n---\\n` convention that this module's moduledoc names
  as the parity target.

  `mode` is read from the same YAML block's `mode:` key (default `"file"`,
  the only behavior that existed before this field did), but is deliberately
  NOT one of `t:t/0`'s mirrored fields -- it has no counterpart in the real
  Rust `ggen::Frontmatter` struct this module otherwise mirrors 1:1. It is an
  Elixir/Igniter-specific execution concern: `:file` (default) means the
  rendered body is written to disk as before; `:eval` means the rendered body
  is real Elixir source meant to be `Code.eval_string`'d in-process instead
  (see `Mix.Tasks.GgenIgniter.Sync`'s `## Execution mode` docs) -- never
  written to disk at all. `from_map/1` already ignores unrecognized keys, so
  `mode:` sitting in the same block as every mirrored field is harmless to it.

  Returns `{%__MODULE__{}, mode, body}` when the file starts with a `---`
  fence on its own line (the fence must be the file's first line, matching
  both ggen's and hygen's convention -- leading whitespace before it means "no
  header", not "malformed header"), or `{nil, :file, template_string}`
  unchanged when it does not -- a template with no header is not an error, it
  just has no frontmatter-derived defaults (every routing option must then
  come from the CLI, exactly as before this function existed).

  ## Examples

      iex> {fm, mode, body} = GgenIgniter.Frontmatter.split_template("---\\nto: lib/foo.ex\\n---\\nhello")
      iex> {fm.to, mode, body}
      {"lib/foo.ex", :file, "hello"}

      iex> GgenIgniter.Frontmatter.split_template("plain body, no header")
      {nil, :file, "plain body, no header"}

  """
  @spec split_template(String.t()) :: {t() | nil, :file | :eval, String.t()}
  def split_template(template_string) when is_binary(template_string) do
    case String.split(template_string, "\n", parts: 2) do
      ["---", rest] ->
        case String.split(rest, "\n---\n", parts: 2) do
          [yaml, body] ->
            {frontmatter, mode} = parse_header!(yaml)
            {frontmatter, mode, body}

          [_no_closing_fence] ->
            raise ArgumentError,
                  "template frontmatter block is missing its closing \"---\" fence"
        end

      _no_header ->
        {nil, :file, template_string}
    end
  end

  defp parse_header!(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, map} when is_map(map) ->
        mode = parse_mode!(Map.get(map, "mode", "file"))
        {from_map(map, require_to: mode != :eval), mode}

      {:ok, nil} ->
        raise ArgumentError, "template frontmatter block is empty"

      {:error, reason} ->
        raise ArgumentError, "template frontmatter YAML is invalid: #{inspect(reason)}"
    end
  end

  defp parse_mode!("file"), do: :file
  defp parse_mode!("eval"), do: :eval

  defp parse_mode!(other),
    do:
      raise(
        ArgumentError,
        "template frontmatter \"mode:\" must be \"file\" or \"eval\", got: #{inspect(other)}"
      )
end

defmodule GgenIgniter.Frontmatter.MatchRule do
  @moduledoc """
  Mirrors Rust `MatchRule` (`template.rs:189-200`).
  """

  @enforce_keys [:pattern]
  defstruct pattern: nil,
            matcher: :contains,
            scope: :auto,
            occurrence: :first,
            index: 0,
            case_sensitive: true,
            trim: false

  @type match_kind :: :contains | :exact | :regex
  @type match_scope :: :auto | :line | :file
  @type match_occurrence :: :first | :last | :unique | :nth

  @type t :: %__MODULE__{
          pattern: String.t(),
          matcher: match_kind(),
          scope: match_scope(),
          occurrence: match_occurrence(),
          index: non_neg_integer(),
          case_sensitive: boolean(),
          trim: boolean()
        }

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    pattern =
      Map.get(map, "pattern") ||
        raise ArgumentError, "match rule is missing required field \"pattern\""

    %__MODULE__{
      pattern: pattern,
      matcher: to_atom(Map.get(map, "matcher", "contains")),
      scope: to_atom(Map.get(map, "scope", "auto")),
      occurrence: to_atom(Map.get(map, "occurrence", "first")),
      index: Map.get(map, "index", 0),
      case_sensitive: Map.get(map, "case_sensitive", true),
      trim: Map.get(map, "trim", false)
    }
  end

  defp to_atom(a) when is_atom(a), do: a
  defp to_atom(s) when is_binary(s), do: String.to_existing_atom(s)
end

defmodule GgenIgniter.Frontmatter.FreezePolicy do
  @moduledoc "Mirrors Rust `enum FreezePolicy { Never, Always, Checksum }` (`template.rs:326-328`)."
  @type t :: :never | :always | :checksum
end

defmodule GgenIgniter.Frontmatter.MatchSpec do
  @moduledoc """
  Mirrors Rust's `#[serde(untagged)] enum MatchSpec { Literal(String),
  Structured(MatchRule) }` (`template.rs:184-187`). An Elixir "untagged enum"
  is a tagged tuple here (`{:literal, string}` / `{:structured, match_rule}`)
  since Elixir has no untagged-union deserialization primitive to mirror
  directly -- the tag is added, not removed, information.
  """

  @type t :: {:literal, String.t()} | {:structured, GgenIgniter.Frontmatter.MatchRule.t()}

  @doc """
  Wraps a literal substring/marker pattern as a `t:t/0`, tagging it `:literal`
  the way the real Rust untagged enum's `MatchSpec::Literal(String)` variant
  is distinguished from `MatchSpec::Structured(MatchRule)` at the type level.

  ## Examples

      iex> GgenIgniter.Frontmatter.MatchSpec.literal("ggen:slot")
      {:literal, "ggen:slot"}

  """
  @spec literal(String.t()) :: t()
  def literal(s) when is_binary(s), do: {:literal, s}

  @doc """
  Wraps a `GgenIgniter.Frontmatter.MatchRule.t()` as a `t:t/0`, tagging it
  `:structured` -- the counterpart to `literal/1` above.

  ## Examples

      iex> rule = GgenIgniter.Frontmatter.MatchRule.from_map(%{"pattern" => "ggen:slot"})
      iex> GgenIgniter.Frontmatter.MatchSpec.structured(rule)
      {:structured,
       %GgenIgniter.Frontmatter.MatchRule{
         pattern: "ggen:slot",
         matcher: :contains,
         scope: :auto,
         occurrence: :first,
         index: 0,
         case_sensitive: true,
         trim: false
       }}

  """
  @spec structured(GgenIgniter.Frontmatter.MatchRule.t()) :: t()
  def structured(%GgenIgniter.Frontmatter.MatchRule{} = rule), do: {:structured, rule}
end
