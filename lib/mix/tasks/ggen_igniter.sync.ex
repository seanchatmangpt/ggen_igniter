defmodule Mix.Tasks.GgenIgniter.Sync do
  @moduledoc """
  CLI entrypoint: `mix ggen_igniter.sync --ontology path.ttl --query name=path.rq (repeatable) --template path.eex --out path.ex`.

  Wires `Ontology.load!/1` -> `Query.run/2` (once per `--query`) -> `Render.render/2` ->
  `Actuate.write_new_file!/2` in sequence.

  Each `--query name=path.rq` result is bound in the EEx template under `name` as the
  full list of result rows (string-keyed maps). Additionally, mirroring ggen's own
  single-row-flattening convention (found live this session working with the Rust
  `ggen` tool): a query whose result has EXACTLY ONE row also has that row's own
  columns merged directly into the top-level bindings, atom-keyed, so a single-row
  query like `spec` can be referenced as bare `module_name`/`package_name` instead of
  `hd(spec)["module_name"]`. Later `--query` flags win on key collisions in the
  flattened namespace -- pass queries in the order you want that tie-break to resolve.

  ## Multi-row fan-out (`--for-each NAME`)

  Mirroring the real Rust ggen's `for_each:` frontmatter field
  (`ggen-engine/src/template.rs`'s `Frontmatter.for_each`, `ggen-engine/src/sync.rs`'s
  `ProjectionMode::Row` fan-out): pass `--for-each NAME` where `NAME` is one of the
  named `--query` results to render the template once PER ROW of that query, each
  render getting that row's own columns merged into the top-level bindings (same
  atom-keyed flattening convention as the existing single-row case -- so row-local
  fields are bare `module_name` etc., not `hd(modules)["module_name"]`), and to write
  each rendering to its own output file.

  Because there is no longer one static output path, `--out` is itself rendered
  through `GgenIgniter.Render.render/2` using each row's bindings, so it must be an
  EEx-renderable path template, e.g.:

      mix ggen_igniter.sync \\
        --ontology test/fixtures/for_each_ontology.ttl \\
        --query modules=test/fixtures/modules.rq \\
        --for-each modules \\
        --template test/fixtures/for_each_module.ex.eex \\
        --out "lib/generated/<%= module_name %>.ex"

  With three rows in the `modules` query result (`Multi.Alpha`, `Multi.Beta`,
  `Multi.Gamma`), this writes three separate files:
  `lib/generated/Multi.Alpha.ex`, `lib/generated/Multi.Beta.ex`,
  `lib/generated/Multi.Gamma.ex`.

  If `--for-each` is not given, behavior is unchanged: `--out` is a single static
  path, written once, with the existing single-row-flatten convention.

  ## Engines

  `--engine oxigraph` (default, since v26.8.27) runs every query in-process
  against the loaded `%RDF.Graph{}` via a real, native oxigraph engine (a
  Rustler NIF over `~/ggen/crates/ggen-graph-wasm`'s `OxigraphEngine`,
  `GgenIgniter.Query.Oxigraph.run/2`) instead of the pure-Elixir `sparql` hex
  package. This became the default because of a real, empirically confirmed
  data-corruption bug in the previous default: `GgenIgniter.Query.run/2` (the
  `sparql` hex package, v0.3.12) does not correctly honor `ORDER BY` -- a
  join-shaped query mirroring the real gate fixtures (`?field ex:fieldOf
  ?entity ; ex:fieldOrder ?field_order . ?entity ex:entityStruct
  ?entity_struct .` with `ORDER BY ?field_order` over 10 rows) came back in
  reverse order (`[9, 8, ..., 0]` instead of the requested ascending `[0, 1,
  ..., 9]`) -- see `GgenIgniter.Query`'s moduledoc for the full writeup. The
  same query run through oxigraph (a real, independent, spec-conformant
  SPARQL 1.1 engine) returned the correct ascending order. Silent row-order
  reversal is a real corruption risk for any `--for-each` fan-out template
  that assumes row order (e.g. numbering, positional joins), so the engine
  that gets that right is now the one that runs unless `--engine` says
  otherwise.

  Two real, disclosed trade-offs from this default change, not silently
  accepted:

    * **Row-value shape differs from `sparql`.** `--engine sparql`'s rows are
      plain unwrapped Elixir strings (`RDF.IRI.to_string/1` /
      `RDF.Literal.value/1`). `--engine oxigraph`'s rows are the real,
      unprocessed N-Triples-style term strings oxigraph itself returns --
      IRIs come back angle-bracket-wrapped (`<https://example.org/...>`) and
      literals come back quoted (and datatype/language-tagged when
      applicable, e.g. `"42"^^<http://www.w3.org/2001/XMLSchema#integer>`),
      not bare values. A template that renders a query column directly
      (`<%= module_name %>`) will see this real shape difference if it
      switches from `sparql` to `oxigraph`.
    * **A working Rust toolchain is required to compile this library at
      all**, regardless of which `--engine` a consumer ever actually invokes
      at runtime -- `lib/ggen_igniter/native/graph_nif.ex`'s `use Rustler`
      compiles `native/ggen_graph_nif` via a real `cargo` subprocess as part
      of that module's own compilation (confirmed by reading
      `Rustler.__using__/1`/`Rustler.Compiler.compile_crate/3` in the
      `rustler` 0.38 hex package -- there is no separate `mix compilers:`
      entry gating this; it runs whenever `graph_nif.ex` itself is
      compiled). This requirement already existed before this default
      changed (that loader module has been unconditionally part of this
      library's `lib/` since `--engine oxigraph` was first added as an
      opt-in engine) -- changing the *default* `--engine` string here is a
      runtime-only behavior change and adds no new compile-time requirement
      beyond what already existed. A consumer without `cargo` on `$PATH`
      already could not `mix compile` this library before this change,
      opt-in or not.

  `--engine sparql` runs every query in-process against the loaded
  `%RDF.Graph{}` via `GgenIgniter.Query.run/2` (the `sparql` hex package) --
  still available, useful for a query shape known to depend on `sparql`
  hex's specific (non-ORDER-BY) behavior, or to A/B a result against the new
  default.

  `--engine qlever` runs every query instead against a real, already-running
  QLever SPARQL endpoint via `GgenIgniter.Query.Qlever.run/2` (`gno` + real
  HTTP, no in-process SPARQL evaluation). `--ontology` is then still read as a
  `%RDF.Graph{}` (via the same `Ontology.load!/1`), but only to look up the
  `gnoa:Qlever`-typed store resource named by `--store-id` -- the query text
  itself never touches this graph's data, it runs on the remote QLever store.
  `--store-id` is required when `--engine qlever` is given.

  ## Example (default oxigraph engine)

      mix ggen_igniter.sync \\
        --ontology test/fixtures/audit_trail_ontology.ttl \\
        --query spec=test/fixtures/spec.rq \\
        --template test/fixtures/extension.ex.eex \\
        --out tmp_out/probe.ex

  ## Example (sparql engine)

      mix ggen_igniter.sync \\
        --engine sparql \\
        --ontology test/fixtures/audit_trail_ontology.ttl \\
        --query spec=test/fixtures/spec.rq \\
        --query sections=test/fixtures/sections.rq \\
        --query entities=test/fixtures/entities.rq \\
        --query fields=test/fixtures/fields.rq \\
        --template test/fixtures/extension.ex.eex \\
        --out tmp_out/probe.ex

  ## Example (qlever engine)

      mix ggen_igniter.sync \\
        --engine qlever \\
        --ontology config/gno/test/store.ttl \\
        --store-id http://example.com/Qlever \\
        --query spec=priv/ggen/some-pack/gates/010.rq \\
        --template priv/ggen/some-pack/templates/out.ex.eex \\
        --out lib/generated.ex

  ## Example (`--pack` convention)

  Given `priv/ggen/audit-trail-pack/{ontology.ttl,gates/*.rq,templates/extension.ex.eex}`:

      mix ggen_igniter.sync --pack audit-trail-pack --out lib/generated.ex

  `--ontology`/`--query`/`--template` are all still overridable explicitly; an
  explicit flag always wins over the pack-derived default. `--pack-dir DIR` uses
  `DIR` directly instead of resolving `priv/ggen/<pack>/`.

  ## Example (`--pack NAME:TEMPLATE` -- selecting one of several templates)

  A pack with more than one file under `templates/` is normally ambiguous --
  `--pack NAME` alone raises rather than guessing which one is "the"
  template. Append `:TEMPLATE_STEM` (the template's filename up to its
  first `.`) to `--pack` to select one explicitly, bypassing the ambiguity
  error entirely for that pack:

      mix ggen_igniter.sync --pack ash-lifecycle-pack:resource --out lib/generated/resource.ex

  Given `priv/ggen/ash-lifecycle-pack/templates/{resource.ex.eex,domain.ex.eex}`,
  this selects `resource.ex.eex` specifically (`resource.ex.eex`'s stem is
  `"resource"`); `--pack ash-lifecycle-pack:domain` selects `domain.ex.eex`
  instead. Plain `--pack ash-lifecycle-pack` (no `:TEMPLATE_STEM`) keeps
  today's behavior unchanged: auto-select when exactly one template exists,
  raise the same "multiple templates found" error when there is more than
  one. `--pack-dir` does not take this `:TEMPLATE_STEM` suffix -- pass
  `--template` explicitly instead when using `--pack-dir` against a
  multi-template pack.
  """
  use Igniter.Mix.Task

  alias GgenIgniter.{Actuate, Engine, Frontmatter, Ontology, Render}
  alias GgenIgniter.Frontmatter.MatchRule

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example:
        "mix ggen_igniter.sync --ontology spec.ttl --query spec=rows.rq --query entities=entities.rq --template out.ex.eex --out lib/generated.ex",
      positional: [],
      schema: [
        ontology: :string,
        query: [:string, :keep],
        template: :string,
        out: :string,
        engine: :string,
        store_id: :string,
        pack: :string,
        pack_dir: :string,
        skip_if: :string,
        unless_exists: :boolean,
        for_each: :string,
        dry_run: :boolean,
        mode: :string
      ],
      required: []
    }
  end

  @doc """
  Reads --ontology/--query(N)/--template/--out/--engine/--store-id/--pack(-dir)
  options and runs the pipeline.

  ## Template frontmatter (hygen/ggen parity)

  Mirroring real hygen and real Rust ggen's own `---\\n...\\n---\\n` header
  convention (`ggen-engine/src/template.rs`'s `Frontmatter`, mirrored 1:1 by
  `GgenIgniter.Frontmatter`): if `--template`'s file starts with a `---` fence
  on its first line, everything between that fence and the closing `---` is
  parsed as YAML frontmatter, and the remainder is the actual template body.
  A template's own header supplies defaults for `to` (`--out`), `for_each`,
  `unless_exists`, `skip_if` (literal-string form only), and `sparql` (named
  queries given as inline query text, not file paths) -- so a self-contained
  template can be rendered with just `--template`/`--ontology`, no repeated
  `--out`/`--for-each`/`--query` flags, exactly like `hygen generate <name>`
  needs no routing flags because the template's own header carries them.

  Any explicit CLI flag always overrides the same-named frontmatter field.
  `--query name=path.rq` and frontmatter `sparql:` inline queries can both be
  present; an explicit `--query` with the same `name` overrides the
  frontmatter's inline query text for that name. A template with no `---`
  header behaves exactly as before this feature existed -- every routing
  option must then come from the CLI/pack convention.

  ## Injection mode (`inject: true`)

  Mirroring the real Rust ggen's own injection frontmatter fields
  (`ggen-engine/src/template.rs`'s `Frontmatter.inject`/`before`/`after`/
  `at_line`, mirrored 1:1 by `GgenIgniter.Frontmatter`): when a `mode: file`
  template's frontmatter has `inject: true`, the rendered body is spliced
  into the resolved output path's EXISTING content via
  `GgenIgniter.Actuate.inject_content!/5`, instead of being written whole via
  `GgenIgniter.Actuate.write_file!/3`. Exactly one of `before:`, `after:`, or
  `at_line:` must be set as the anchor -- zero or more than one raises a
  clear `ArgumentError` (an ambiguous or missing anchor is a template-authoring
  error, never a silent pick, never a best-effort partial match):

    * `before: "marker"` / `after: "marker"` -- a literal string frontmatter
      value maps directly onto `inject_content!/5`'s own literal-marker
      "contains" match; splices the rendered body immediately before/after
      the single matched line.
    * `before:`/`after:` as a structured map (`pattern:`, `matcher:`,
      `case_sensitive:`, `scope:`, `occurrence:`, `trim:` -- the real
      `GgenIgniter.Frontmatter.MatchRule` shape) is converted into
      `inject_content!/5`'s `String.t() | Regex.t()` marker arg by this
      module's private `match_spec_to_marker!/2`:
        * `matcher: "contains"` (default) -- a plain string marker
          (`case_sensitive: true`, the default) or a case-insensitive
          unanchored `Regex` (`case_sensitive: false`).
        * `matcher: "exact"` -- a `^...$`-anchored `Regex` (escaped pattern),
          with `\\s*` padding on both sides instead of bare anchors when
          `trim: true`.
        * `matcher: "regex"` -- the pattern string compiled directly as a
          `Regex` (never escaped -- it IS a regex), `case_sensitive: false`
          adding the `i` flag.
      `scope: "file"`, any `occurrence:` other than the default `"first"`,
      and `trim: true` paired with a `matcher` other than `"exact"` have no
      equivalent in `inject_content!/5`'s real anchor-resolution behavior
      (always-exactly-one-line, no whole-file mode, no
      pick-a-specific-occurrence logic) -- setting one of those raises a
      clear error naming the exact unsupported combination, rather than
      silently proceeding as if it had been honored.
    * `at_line: N` -- an anchor-free alternative: splices the rendered body
      at the 1-based line number `N` (`marker` is not used; `before`/`after`
      must both be unset).

  `--dry-run` previews an injection the same honest way it previews a write:
  the real anchor-resolution and idempotency check both run for real (via
  `inject_content!/5`'s own `:dry_run` option), nothing is written, and the
  notice line reads `"planned: inject \#{out_path}"` (or `"planned: skip
  \#{out_path} (unchanged)"` when the content is already spliced in at that
  exact position). A real, non-dry-run injection reports `"injected
  \#{out_path}"` on the first run and `"unchanged (skipped, identical
  content): \#{out_path}"` on an idempotent re-run -- distinct from
  `write_file!/3`'s `"wrote \#{out_path}"`, since the two are different
  actuation paths.

  Injection always requires the target file to ALREADY exist (mirroring
  `inject_content!/5`'s own fail-closed gate) -- it is not a substitute for
  file creation; a first-run template should not set `inject: true` against a
  path nothing has created yet.

      mix ggen_igniter.sync \\
        --ontology test/fixtures/audit_trail_ontology.ttl \\
        --query spec=test/fixtures/spec.rq \\
        --template test/fixtures/inject_before_marker.ex.eex \\
        --out lib/existing_module.ex

  ## Execution mode (`mode: eval`)

  `mode:` (frontmatter, or `--mode` on the CLI -- explicit CLI wins) selects
  what happens to the rendered template body: `mode: file` (the default,
  unchanged from every example above) writes it to disk via the write-safety
  guards described elsewhere in this doc. `mode: eval` instead treats the
  rendered body as real Elixir source and evaluates it in-process via
  `GgenIgniter.Actuate.eval_code!/2`, using the exact same bindings the
  template body renders with (so eval'd code can reference `module_name`,
  a single-row query's flattened columns, a `--for-each` row's columns, etc.,
  exactly like the template body itself can) -- nothing is ever written to
  disk under this mode, so `--out`/`to:` is not required, and
  `--unless-exists`/`--skip-if` are not applicable and are ignored.

      mix ggen_igniter.sync \\
        --ontology test/fixtures/audit_trail_ontology.ttl \\
        --query spec=test/fixtures/spec.rq \\
        --template test/fixtures/eval_mode_module.exs.eex \\
        --mode eval

  With `--for-each`, the eval'd body runs once per row (same fan-out as file
  mode, just evaluated instead of written). `--dry-run` shows a `"planned:
  evaluate ..."` notice and does not actually evaluate anything.

  This is a deliberate, disclosed arbitrary-code-execution capability:
  ontology/RDF-driven query results become literally-executed Elixir code
  under `mode: eval`. Threading an eval result into a *later* query/render/
  write stage is not implemented in this pass -- each named query's results
  and each eval's return value are independent of one another within a single
  `sync` run.
  """
  @impl Igniter.Mix.Task
  def igniter(igniter) do
    {opts, pack_template_stem} = split_pack_template_stem(igniter.args.options)
    engine_name = opts[:engine] || "oxigraph"
    engine_module = Engine.fetch!(engine_name)

    ontology_path = resolve_ontology!(opts)
    graph = Ontology.load!(ontology_path)

    template_path = resolve_template!(opts, pack_template_stem)

    {frontmatter, frontmatter_mode, template_string} =
      Frontmatter.split_template(File.read!(template_path))

    named_queries = resolve_named_queries!(opts, frontmatter)
    named_results = run_queries(engine_module, graph, opts, named_queries)

    mode = resolve_mode!(opts, frontmatter_mode)
    for_each = opts[:for_each] || frontmatter_field(frontmatter, :for_each)
    dry_run = opts[:dry_run] || false

    out_template =
      case mode do
        :eval ->
          nil

        :file ->
          opts[:out] || frontmatter_field(frontmatter, :to) ||
            raise ArgumentError,
                  "--out is required (directly, or via the template's own frontmatter \"to:\" field)"
      end

    write_opts = [
      unless_exists:
        opts[:unless_exists] || frontmatter_field(frontmatter, :unless_exists) || false,
      skip_if: opts[:skip_if] || frontmatter_skip_if!(frontmatter),
      dry_run: dry_run
    ]

    # Only a `mode: file` template with frontmatter `inject: true` takes the
    # injection actuation path; every other template (the overwhelming
    # majority -- no frontmatter, or frontmatter with `inject` absent/false)
    # keeps dispatching to `write_file!/3` exactly as before this feature
    # existed. Resolved once per `sync` run, not per for-each row: the anchor
    # (`before`/`after`/`at_line`) is a property of the template, not of any
    # one query result row.
    inject_spec =
      if mode == :file and (frontmatter_field(frontmatter, :inject) || false) do
        resolve_injection!(frontmatter)
      end

    total_rows = named_results |> Enum.map(fn {_name, rows} -> length(rows) end) |> Enum.sum()

    notices =
      case for_each do
        nil ->
          bindings = build_bindings(named_results)
          content = Render.render(template_string, bindings)

          line =
            actuate!(
              mode,
              content,
              bindings,
              out_template,
              template_path,
              write_opts,
              dry_run,
              inject_spec
            )

          if dry_run, do: Mix.shell().info(line)
          [line]

        driver_name ->
          rows = fetch_driver_rows!(named_results, driver_name)

          Enum.map(rows, fn row ->
            bindings = build_bindings(named_results, row)
            content = Render.render(template_string, bindings)

            line =
              actuate!(
                mode,
                content,
                bindings,
                out_template,
                template_path,
                write_opts,
                dry_run,
                inject_spec
              )

            if dry_run, do: Mix.shell().info(line)
            line
          end)
      end

    Igniter.add_notice(
      igniter,
      "ggen_igniter: #{Enum.join(notices, "; ")} (engine: #{engine_name}, #{length(named_queries)} quer#{if length(named_queries) == 1, do: "y", else: "ies"}, #{total_rows} total row(s))"
    )
  end

  # `out_template` is always EEx-rendered before use, whether it came from
  # explicit --out or from frontmatter's `to:` -- a static path with no
  # `<%= %>` renders back to itself unchanged, so this is a no-op for the
  # common static case and a real render for a templated `to:`/`--out`.
  #
  # `inject_spec` is `nil` for the ordinary (non-`inject:`) write path, or
  # `{marker, insert_mode, inject_opts}` (from `resolve_injection!/1`) when
  # the template's frontmatter has `inject: true` -- these are separate
  # clauses, not an `if` inside one clause, so each actuation path's real
  # behavior stays independently readable.
  defp actuate!(:file, content, bindings, out_template, _template_path, write_opts, dry_run, nil) do
    out_path = Render.render(out_template, bindings)
    {:ok, outcome} = Actuate.write_file!(out_path, content, write_opts)
    notice_line(outcome, out_path, dry_run)
  end

  defp actuate!(
         :file,
         content,
         bindings,
         out_template,
         _template_path,
         _write_opts,
         dry_run,
         {marker, insert_mode, inject_opts}
       ) do
    out_path = Render.render(out_template, bindings)

    {:ok, outcome} =
      Actuate.inject_content!(
        out_path,
        marker,
        strip_single_trailing_newline(content),
        insert_mode,
        Keyword.put(inject_opts, :dry_run, dry_run)
      )

    notice_line(outcome, out_path, dry_run)
  end

  defp actuate!(
         :eval,
         _content,
         _bindings,
         _out_template,
         template_path,
         _write_opts,
         true,
         _inject_spec
       ),
       do: "planned: evaluate #{template_path} (mode: eval)"

  defp actuate!(
         :eval,
         content,
         bindings,
         _out_template,
         template_path,
         _write_opts,
         false,
         _inject_spec
       ) do
    {:ok, value} = Actuate.eval_code!(content, bindings)
    "evaluated #{template_path} -> #{inspect(value)}"
  end

  # A rendered template body ends in a trailing "\n" as a plain file-formatting
  # convention -- the same convention every fixture `.eex` file in this
  # project's `write_file!/3` path already relies on (the rendered body is
  # written byte-for-byte, trailing newline included). `Actuate.inject_content!/5`
  # itself has no opinion on this: it does `String.split(content, "\n")`
  # un-trimmed, so an un-stripped trailing "\n" would splice in one real extra
  # blank line at the end of the injected block. Stripping exactly one
  # trailing "\n" here (mirroring `Actuate`'s own `drop_trailing_empty/1` for
  # the TARGET file's lines) keeps an injected block's line count matching
  # what the template body actually says, without guessing at or discarding
  # any blank lines the template author put there deliberately (a second
  # trailing blank line in the template body is left fully intact).
  defp strip_single_trailing_newline(content) do
    case String.split(content, "\n") do
      [_single] ->
        content

      parts ->
        case List.last(parts) do
          "" -> parts |> List.delete_at(-1) |> Enum.join("\n")
          _ -> content
        end
    end
  end

  # Converts a template's `inject:`/`before:`/`after:`/`at_line:` frontmatter
  # fields into `Actuate.inject_content!/5`'s real args. Exactly one anchor is
  # required -- `before` OR `after` OR `at_line`, never zero, never more than
  # one. There is no real "inject relative to both before AND after" mode in
  # the Rust `ggen::Frontmatter` shape this mirrors, so more than one anchor
  # set is always a template-authoring error, resolved here rather than left
  # for `inject_content!/5` to reject less clearly downstream.
  defp resolve_injection!(%Frontmatter{} = frontmatter) do
    anchors =
      [before: frontmatter.before, after: frontmatter.after, at_line: frontmatter.at_line]
      |> Enum.filter(fn {_k, v} -> v != nil end)

    case anchors do
      [] ->
        raise ArgumentError,
              "template frontmatter has \"inject: true\" but none of before:/after:/at_line: " <>
                "is set -- injection requires exactly one anchor"

      [{:before, spec}] ->
        {match_spec_to_marker!(spec, "before"), :before, []}

      [{:after, spec}] ->
        {match_spec_to_marker!(spec, "after"), :after, []}

      [{:at_line, at_line}] ->
        {nil, :at_line, [line: at_line]}

      many ->
        names = Enum.map_join(many, ", ", fn {k, _v} -> "#{k}:" end)

        raise ArgumentError,
              "template frontmatter has \"inject: true\" but more than one anchor is set " <>
                "(#{names}) -- injection requires exactly one of before:/after:/at_line:"
    end
  end

  # Converts a `GgenIgniter.Frontmatter.MatchSpec.t()` into whatever
  # `Actuate.inject_content!/5`'s real `marker` arg expects
  # (`String.t() | Regex.t()`).
  #
  # `{:literal, s}` maps directly onto a plain string marker --
  # `inject_content!/5` already treats a string marker as a same-line-or-
  # substring "contains" match, exactly what a literal frontmatter marker
  # means.
  #
  # `{:structured, %MatchRule{}}` is translated field-by-field (see this
  # task's `## Injection mode` moduledoc section above for the full mapping
  # table); what is genuinely NOT implemented against `inject_content!/5`'s
  # real anchor-resolution behavior raises a clear, honest error naming the
  # exact unsupported combination, rather than silently proceeding as if it
  # had been honored:
  #
  #   * `scope: :file` -- `inject_content!/5` only ever matches a marker
  #     against individual lines (`marker_matches?/2`, one line at a time);
  #     it has no whole-file/multi-line matching mode.
  #   * `occurrence:` other than the default `:first` -- `inject_content!/5`'s
  #     anchor resolution always requires the marker to match EXACTLY one
  #     line (raising on zero or on more-than-one match); it has no concept
  #     of picking a specific occurrence (last/unique/nth) among several
  #     matches, so `index:` has no meaningful effect either.
  #   * `trim: true` paired with any `matcher` other than `:exact` -- there is
  #     no "trim before comparing" hook to honor for a `:contains` (substring
  #     matching is already trim-insensitive) or `:regex` (a user-supplied
  #     pattern; trimming it would silently change its meaning) marker.
  @spec match_spec_to_marker!(GgenIgniter.Frontmatter.MatchSpec.t(), String.t()) ::
          String.t() | Regex.t()
  defp match_spec_to_marker!({:literal, s}, _label), do: s

  defp match_spec_to_marker!({:structured, %MatchRule{} = rule}, label) do
    if rule.scope == :file do
      unsupported_match_rule!(
        label,
        "scope: :file",
        "inject_content!/5 only matches a marker against individual lines, never across " <>
          "the whole file"
      )
    end

    if rule.occurrence != :first do
      unsupported_match_rule!(
        label,
        "occurrence: #{inspect(rule.occurrence)}",
        "inject_content!/5 always requires the marker to match exactly one line (raising on " <>
          "zero or on more than one match) -- it has no concept of selecting a specific " <>
          "occurrence (last/unique/nth) among several matches; only occurrence: :first " <>
          "(the default) maps onto that real behavior"
      )
    end

    if rule.trim and rule.matcher != :exact do
      unsupported_match_rule!(
        label,
        "trim: true with matcher: #{inspect(rule.matcher)}",
        "trim is only implemented for matcher: :exact"
      )
    end

    build_regex_marker(rule)
  end

  defp unsupported_match_rule!(label, option, reason) do
    raise ArgumentError,
          "template frontmatter's structured #{label}: rule sets #{option}, which is not yet " <>
            "supported by ggen_igniter's injection engine (Actuate.inject_content!/5): #{reason}"
  end

  defp build_regex_marker(%MatchRule{matcher: :contains, pattern: pattern, case_sensitive: true}),
    do: pattern

  defp build_regex_marker(%MatchRule{
         matcher: :contains,
         pattern: pattern,
         case_sensitive: false
       }),
       do: compile_regex!(Regex.escape(pattern), false)

  defp build_regex_marker(%MatchRule{
         matcher: :exact,
         pattern: pattern,
         case_sensitive: case_sensitive,
         trim: trim
       }) do
    escaped = Regex.escape(pattern)
    source = if trim, do: "^\\s*#{escaped}\\s*$", else: "^#{escaped}$"
    compile_regex!(source, case_sensitive)
  end

  defp build_regex_marker(%MatchRule{matcher: :regex, pattern: pattern, case_sensitive: cs}),
    do: compile_regex!(pattern, cs)

  defp compile_regex!(source, case_sensitive?) do
    flags = if case_sensitive?, do: "", else: "i"
    Regex.compile!(source, flags)
  end

  defp resolve_mode!(opts, frontmatter_mode) do
    case opts[:mode] do
      nil -> frontmatter_mode
      "file" -> :file
      "eval" -> :eval
      other -> raise ArgumentError, "--mode must be \"file\" or \"eval\", got: #{inspect(other)}"
    end
  end

  # In `--dry-run` mode, prefix every line with "planned: " and use the
  # plain-English guard names the task doc promises ("unchanged",
  # "unless_exists/skip_if match") rather than the normal-mode past-tense
  # verbs -- this is a preview of what *would* happen, nothing was written.
  # `:written` only ever comes from `write_file!/3`; `:injected` only ever
  # comes from `inject_content!/5` -- distinct atoms from distinct actuation
  # paths, reported with distinct verbs (`"wrote"` vs `"injected"`) below and
  # distinct "planned: " lines here (`:unchanged` is genuinely the same
  # meaning from either path -- content already exactly where it belongs --
  # so it keeps one shared line).
  defp notice_line(:written, path, true), do: "planned: write #{path}"
  defp notice_line(:injected, path, true), do: "planned: inject #{path}"
  defp notice_line(:unchanged, path, true), do: "planned: skip #{path} (unchanged)"

  defp notice_line(:skipped_exists, path, true),
    do: "planned: skip #{path} (unless_exists/skip_if match)"

  defp notice_line(:skipped_match, path, true),
    do: "planned: skip #{path} (unless_exists/skip_if match)"

  defp notice_line(outcome, path, false), do: "#{outcome_verb(outcome)} #{path}"

  defp fetch_driver_rows!(named_results, driver_name) do
    case List.keyfind(named_results, driver_name, 0) do
      {^driver_name, rows} ->
        rows

      nil ->
        raise ArgumentError,
              "--for-each #{inspect(driver_name)} does not name a declared --query result " <>
                "(known: #{Enum.map_join(named_results, ", ", &elem(&1, 0))})"
    end
  end

  defp outcome_verb(:written), do: "wrote"
  defp outcome_verb(:injected), do: "injected"
  defp outcome_verb(:unchanged), do: "unchanged (skipped, identical content):"
  defp outcome_verb(:skipped_exists), do: "skipped (unless_exists, already exists):"
  defp outcome_verb(:skipped_match), do: "skipped (skip_if matched):"

  defp pack_given?(opts), do: opts[:pack] not in [nil, ""] or opts[:pack_dir] not in [nil, ""]

  # Parses a `--pack NAME:TEMPLATE_STEM` value (e.g. `--pack
  # ash-lifecycle-pack:resource`) BEFORE `opts[:pack]` is handed to anything
  # else in this module -- `Pack.resolve_dir!/1`, `pack_given?/1`,
  # `Pack.discover_queries/1`, `Pack.default_ontology/1` must only ever see
  # the bare pack NAME (`"ash-lifecycle-pack"`), never a `:stem` suffix, since
  # none of them know what a template stem is. Returns `{opts, stem}` where
  # `opts` has `:pack` rewritten to the bare name (untouched if `--pack` was
  # not given, had no `:`, or is `--pack-dir` instead) and `stem` is the
  # `TEMPLATE_STEM` string when present, else `nil`.
  #
  # `String.split(raw, ":", parts: 2)` splits on the FIRST `:` only, so a pack
  # name that itself legitimately contains no colon (every real pack name in
  # this codebase) round-trips unchanged when no stem is given -- `[name]`,
  # one element, falls through to the `_ -> {opts, nil}` clause below.
  defp split_pack_template_stem(opts) do
    case opts[:pack] do
      raw when is_binary(raw) and raw != "" ->
        case String.split(raw, ":", parts: 2) do
          [name, stem] when name != "" and stem != "" ->
            {Keyword.put(opts, :pack, name), stem}

          _ ->
            {opts, nil}
        end

      _ ->
        {opts, nil}
    end
  end

  defp resolve_ontology!(opts) do
    cond do
      opts[:ontology] not in [nil, ""] ->
        opts[:ontology]

      pack_given?(opts) ->
        path = GgenIgniter.Pack.default_ontology(GgenIgniter.Pack.resolve_dir!(opts))

        unless File.exists?(path) do
          raise ArgumentError, "--pack/--pack-dir resolved ontology not found at #{path}"
        end

        path

      true ->
        raise ArgumentError, "--ontology is required (directly, or via --pack/--pack-dir)"
    end
  end

  # Resolves every named query to its actual query TEXT (not a path) up front,
  # merging three sources by ascending priority (later overrides same-named
  # earlier): frontmatter inline `sparql:` queries, pack-discovered
  # `gates/*.rq` files, explicit `--query name=path.rq` flags. This lets a
  # self-contained template (frontmatter `sparql:` block, no --query/--pack at
  # all) drive the whole run, matching real hygen/ggen parity.
  @doc false
  @spec resolve_named_queries!(keyword(), Frontmatter.t() | nil) :: [{String.t(), String.t()}]
  def resolve_named_queries!(opts, frontmatter) do
    frontmatter_queries =
      case frontmatter_field(frontmatter, :sparql) do
        map when is_map(map) and map_size(map) > 0 -> Map.to_list(map)
        _ -> []
      end

    explicit =
      opts
      |> Keyword.get_values(:query)
      |> Enum.map(&parse_named_query!/1)
      |> Enum.map(fn {name, path} -> {name, File.read!(path)} end)

    file_named_queries =
      if pack_given?(opts) do
        pack_queries =
          GgenIgniter.Pack.resolve_dir!(opts)
          |> GgenIgniter.Pack.discover_queries()
          |> Enum.map(fn {name, path} -> {name, File.read!(path)} end)

        if pack_queries == [] and explicit == [] and frontmatter_queries == [] do
          raise ArgumentError,
                "no *.rq files found in #{GgenIgniter.Pack.resolve_dir!(opts)}/gates/ and no explicit --query given"
        end

        # Pack-derived gate queries come first; explicit --query flags can add
        # extra named queries or override a gate name (later-wins on collisions,
        # same tie-break as explicit-only --query flags today).
        pack_queries ++ explicit
      else
        if explicit == [] and frontmatter_queries == [] do
          raise ArgumentError,
                "at least one --query name=path.rq is required (or use --pack/--pack-dir, " <>
                  "or a template frontmatter \"sparql:\" block)"
        end

        explicit
      end

    Enum.reduce(file_named_queries, frontmatter_queries, fn {name, text}, acc ->
      List.keystore(acc, name, 0, {name, text})
    end)
  end

  # `frontmatter` is `nil` for a header-less template -- every accessor here
  # collapses that case to `nil`/absent, same as any other missing option.
  defp frontmatter_field(nil, _key), do: nil
  defp frontmatter_field(%Frontmatter{} = fm, key), do: Map.get(fm, key)

  # Only a literal-string `skip_if:` (`GgenIgniter.Frontmatter.MatchSpec`'s
  # `{:literal, s}` shape) maps onto `Actuate.write_file!/3`'s `skip_if`
  # option, which only understands a plain substring/regex. A structured
  # `skip_if:` (matcher/scope/occurrence) is real, declared frontmatter this
  # module faithfully parses, but has no write-safety engine behind it yet --
  # raising here is honest; silently ignoring it would let a template author's
  # actual guard silently not apply.
  defp frontmatter_skip_if!(nil), do: nil
  defp frontmatter_skip_if!(%Frontmatter{skip_if: nil}), do: nil
  defp frontmatter_skip_if!(%Frontmatter{skip_if: {:literal, s}}), do: s

  defp frontmatter_skip_if!(%Frontmatter{skip_if: {:structured, _rule}}) do
    raise ArgumentError,
          "template frontmatter's structured skip_if: (matcher/scope/occurrence) is not yet " <>
            "supported by ggen_igniter's write-safety engine -- use a literal skip_if: \"substring\" " <>
            "in the template header instead, or pass --skip-if on the CLI"
  end

  defp resolve_template!(opts, pack_template_stem) do
    cond do
      opts[:template] not in [nil, ""] ->
        opts[:template]

      pack_given?(opts) ->
        pack_dir = GgenIgniter.Pack.resolve_dir!(opts)

        case GgenIgniter.Pack.discover_template(pack_dir, pack_template_stem) do
          {:ok, path} ->
            path

          {:error, :none} ->
            raise ArgumentError,
                  "no *.eex/*.tmpl template found in #{pack_dir}/templates/ -- pass --template explicitly"

          {:error, {:ambiguous, paths}} ->
            raise ArgumentError,
                  "multiple templates found in #{pack_dir}/templates/ (#{Enum.join(paths, ", ")}) -- pass --template explicitly"

          {:error, {:stem_not_found, stem, paths}} ->
            raise ArgumentError,
                  "--pack ...:#{stem} did not match any template in #{pack_dir}/templates/ " <>
                    "(available: #{Enum.join(paths, ", ")})"
        end

      true ->
        raise ArgumentError,
              "--template is required (directly, or via --pack/--pack-dir with exactly one template)"
    end
  end

  # Dispatches through the `GgenIgniter.Engine` behaviour instead of a
  # hardcoded, per-engine-name function clause: `prepare!/2` runs once per
  # sync (graph/store/HTTP-client setup), `run/2` runs once per named query.
  # Adding a new `--engine` means adding a module to `Engine.registry/0`, not
  # editing this function.
  defp run_queries(engine_module, graph, opts, named_queries) do
    context = engine_module.prepare!(graph, opts)

    Enum.map(named_queries, fn {name, query_text} ->
      {name, engine_module.run(context, query_text)}
    end)
  end

  defp parse_named_query!(arg) do
    case String.split(arg, "=", parts: 2) do
      [name, path] -> {name, path}
      [_no_name] -> raise ArgumentError, "each --query must be name=path.rq, got: #{arg}"
    end
  end

  # Builds the EEx binding keyword list: every named query is bound as `name: rows`
  # (list of string-keyed maps), and any single-row query additionally has its own
  # columns flattened to top-level atom-keyed bindings -- mirroring ggen's own
  # single-row-query flattening behavior.
  #
  # `for_each_row`, when given (the `--for-each` multi-row fan-out path -- see
  # ggen's own `ProjectionMode::Row` in `ggen-engine/src/sync.rs`), is one row
  # (a string-keyed map) from the `--for-each` driver query's results. Its columns
  # are merged into the top-level atom-keyed bindings using the exact same
  # flattening convention as the single-row case, and are applied LAST so a
  # for-each row's columns win over same-named columns from an unrelated
  # single-row query -- the row actually driving this render should never be
  # shadowed by an incidental other query.
  @doc false
  @spec build_bindings([{String.t(), [map()]}], map() | nil) :: keyword()
  def build_bindings(named_results, for_each_row \\ nil) do
    list_bindings =
      Enum.map(named_results, fn {name, rows} -> {String.to_atom(name), rows} end)

    flattened =
      named_results
      |> Enum.filter(fn {_name, rows} -> length(rows) == 1 end)
      |> Enum.flat_map(fn {_name, [row]} -> row end)
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)

    row_flattened =
      case for_each_row do
        nil -> []
        row -> Enum.map(row, fn {k, v} -> {String.to_atom(k), v} end)
      end

    list_bindings
    |> Keyword.merge(flattened)
    |> Keyword.merge(row_flattened)
  end
end
