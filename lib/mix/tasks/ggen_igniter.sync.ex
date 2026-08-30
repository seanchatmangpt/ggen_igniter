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

  alias GgenIgniter.{
    Actuate,
    Controller,
    Engine,
    Frontmatter,
    Injection,
    Manifest,
    Ontology,
    Receipt,
    Render,
    ShellHook
  }

  alias GgenIgniter.Reactors.ReconcileReactor

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
        mode: :string,
        on_stale: :string,
        manifest_dir: :string,
        verify_cwd: :string,
        allow_sh: :boolean,
        help: :boolean,
        version: :boolean
      ],
      aliases: [h: :help, v: :version],
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

  ## `sh_before:`/`sh_after:` shell hooks (frontmatter-only, gated by `--allow-sh`)

  Mirroring the real Rust ggen's own `Frontmatter.sh_before`/`sh_after`
  fields (`GgenIgniter.Frontmatter`'s own moduledoc, field-by-field
  provenance): a template's frontmatter may declare a real shell command to
  run before (`sh_before:`) and/or after (`sh_after:`) that row's real
  `write_file!/3`/`inject_content!/5` call, executed via
  `GgenIgniter.ShellHook.run/3` (`System.cmd("sh", ["-c", cmd], cd:
  --manifest-dir/File.cwd!(), stderr_to_stdout: true)`, real timeout,
  default 60s).

  **`--allow-sh` is required** (default `false`) whenever ANY resolved
  template's frontmatter sets `sh_before:`/`sh_after:` -- absent it, the
  WHOLE run refuses before any actuation happens at all (fail-closed,
  matching `--on-stale refuse`'s own default posture), naming the exact
  template and field(s) that triggered the refusal. This refusal is checked
  BEFORE `run_via_reactor/3`'s own Reactor dispatch AND before
  `run_pipeline!/3`'s own inline actuation loop -- both are genuinely
  separate call paths (see the `## Reactor dispatch` /
  `GgenIgniter.Reactors.ReconcileReactor` sections), and
  `ReconcileReactor.run/1` independently re-checks the same
  `allow_sh`/`sh_before`/`sh_after` combination for ITS OWN direct callers
  (not only calls arriving through this task) -- see that module's
  moduledoc.

  **DISCLOSED, INTENTIONAL LIMITATION** (mirrors ADR-0006's disclosure
  style for `inject_content!/5`'s own scope, and the v26.8.30 CHANGELOG's
  "`:run_queries` concurrency: investigated, NOT changed" entry): a
  `sh_before:`/`sh_after:` command's real side effects are **NOT**
  integrated into `GgenIgniter.PendingActuation`'s `operation()` type,
  **NOT** inspected by `:admit`'s guards (duplicate-path refusal,
  path-escape refusal, unowned-delete refusal), and **NOT** tracked by
  `undo/4`'s compensation/revert machinery -- a template author declaring
  `sh_before:`/`sh_after:` is trusted the same way this repo already
  trusts a frontmatter `to:` path (an existing, accepted trust boundary,
  not a new one). `--allow-sh` is the one new, deliberately small
  admission-adjacent check this pass adds to mitigate the highest-severity
  real finding here (a destructive command bypassing admission entirely) --
  it is a single explicit opt-in flag, not a new operation-type/IR change.

  **Failure semantics differ from every other row-level failure in this
  module.** A nonzero exit or a real timeout from `sh_before:`/`sh_after:`
  does **NOT** abort the whole run -- this is a genuinely new
  failure-tolerance pattern for `sync.ex` (today, a raised exception from
  any other row aborts the entire run). It produces a new per-row outcome
  atom instead, extending the existing `:written`/`:injected`/`:unchanged`/
  `:skipped_exists`/`:skipped_match` vocabulary:

    * `sh_before:` fails (nonzero exit or timeout) -- the row's real
      `write_file!/3`/`inject_content!/5` call is SKIPPED entirely (treated
      as a failed precondition), outcome `:sh_before_failed`.
    * `sh_after:` fails AFTER a real `:written`/`:injected` outcome -- the
      write/inject already genuinely happened and is NOT reverted (no
      compensation exists for this, per the disclosed limitation above);
      outcome `:sh_after_failed`.

  See `outcome_summary_suffix/2`/`summary_bucket/1` for how these two new
  atoms are counted and reported in the final run summary, alongside every
  other outcome.

  `--dry-run` previews a shell hook exactly like every other actuation
  decision in this module: `"planned: run sh_before: <cmd>"` /
  `"planned: run sh_after: <cmd>"` is printed, and `GgenIgniter.ShellHook.run/3`
  is never called at all (the real subprocess never starts under
  `--dry-run`, matching this whole module's "zero real side effects" dry-run
  contract).

  Every real `sh_before:`/`sh_after:` invocation (success, nonzero exit, or
  timeout) is appended to `GgenIgniter.Receipt.commands` -- see that
  module's moduledoc for the entry shape. `sync.ex`'s inline pipeline does
  not otherwise construct a `GgenIgniter.Receipt` at all (verified: no
  `Receipt.new/1`/`Receipt.append!/2` call existed anywhere in this file
  before this feature); a minimal receipt (`standing: :alive` -- this
  module's inline pipeline has no compensation/verification step of its own
  to fail, so `:alive` here describes "an attempt was made and files were
  actuated via the normal write-safety guards," not "every shell hook
  succeeded" -- any hook failure is named explicitly in `reason`/`commands`
  instead) is constructed and appended ONLY for a real (non-`--dry-run`) run
  that actually declared `sh_before:`/`sh_after:`, so a run with no shell
  hooks at all produces no new receipt traffic.

  ## Reconciliation manifest (stale-output detection, `--on-stale`)

  Every real, disk-written `mode: file` output (whole-file `write_file!/3`
  writes; NOT `inject: true` splices, NOT `mode: eval`) is recorded in a
  RECONCILIATION MANIFEST at `<manifest_dir>/.ggen_igniter/manifest.json`
  (`manifest_dir` defaults to `File.cwd!()` -- the consumer project's own
  directory, i.e. wherever `mix ggen_igniter.sync` is actually invoked from;
  override with `--manifest-dir DIR`), keyed by the `(--template,
  --out/to:)` "recipe" pair (`GgenIgniter.Manifest.recipe_key/2` -- see that
  module's moduledoc for the full, grounded reasoning for why THIS pair, and
  not ontology path or pack name alone, is the real reconciliation identity).

  Before writing anything, the manifest's EXISTING entry for this run's
  recipe (if any) is read; this run's own real output-path set is computed
  (every row's rendered `--out`, whether from `--for-each` fan-out or the
  single static case); `stale = old_paths - new_paths` -- paths a PRIOR run
  of this exact recipe wrote that this run does NOT write (the mechanical
  signature of a rename or removal upstream in the ontology).

  `--on-stale` (default **`refuse`** -- the safest default; silent orphaning
  is never the default, and silent deletion is never the default either)
  decides what happens when `stale` is non-empty:

    * `refuse` (default) -- if `stale` is non-empty, raises a clear
      `ArgumentError` naming every exact stale path, BEFORE writing anything
      at all this run (not even the non-stale outputs) -- complete
      reconciliation or a refusal before any partial actuation, never a
      silent orphan. Fix by re-running with `--on-stale prune` or
      `--on-stale preserve`.
    * `prune` -- proceeds with this run's writes, then really deletes
      (`File.rm/1`) every stale path, reporting each real deletion
      (`"pruned: PATH"`, or `"pruned (already absent): PATH"` if it was
      already gone).
    * `preserve` -- proceeds with this run's writes, leaves every stale path
      untouched on disk, and prints a clear warning naming each one every
      time (they are also dropped from the manifest's tracked output set for
      this recipe -- this pack no longer claims ownership of a path it
      isn't producing this run).

  The manifest is only ever persisted AFTER this run's own writes (and, for
  `prune`, the real deletions) fully succeed -- a raised exception mid-run
  (a failed write, a `refuse` refusal) never touches the manifest file, so it
  always reflects the last KNOWN-GOOD run, never a partial one. A run whose
  real output-path-plus-content-hash set is IDENTICAL to what the manifest
  already recorded (a true no-op re-run) does not rewrite the manifest file
  at all -- not even its timestamp.

  `--dry-run` previews reconciliation the same honest way it previews every
  other actuation: a `refuse`-triggering `stale` set still raises (a dry run
  is a real preview of what WOULD happen, and "this run would be refused" is
  exactly that); `prune`/`preserve` print `"planned: prune PATH"` /
  `"planned: preserve PATH"` lines instead of touching disk; the manifest
  file itself is never written under `--dry-run`.

      mix ggen_igniter.sync --pack-dir priv/ggen/ash-lifecycle-pack \\
        --ontology priv/ggen/ash-lifecycle-pack/ontology.ttl \\
        --template priv/ggen/ash-lifecycle-pack/templates/resource.ex.eex \\
        --for-each resource \\
        --out "lib/support_desk/support/<%= String.downcase(resource_name) %>.ex" \\
        --on-stale prune

  ## `--verify-cwd DIR` (Reactor pipeline only, `use_reactor: true`)

  When the opt-in Reactor pipeline is active (see "Reactor dispatch" below),
  its terminal `:verify` step runs a REAL `mix compile --warnings-as-errors`
  subprocess to confirm the just-actuated project still builds
  (`GgenIgniter.Reactors.ReconcileReactor`'s `:verify` step). That subprocess
  needs a real Mix project directory (one containing `mix.exs`) to `cd:`
  into. By default it uses `--manifest-dir` (falling back to `File.cwd!()`)
  for this -- correct whenever the reconciliation manifest and the actual
  Mix project live in the same directory, which is the common case.

  `--verify-cwd DIR` overrides just this one directory, independently of
  `--manifest-dir`, for the one real scenario where the two differ: writing
  actuated output into an ISOLATED directory (e.g. a throwaway tmp dir used
  as `--manifest-dir` so the reconciliation manifest and path-escape
  boundary don't touch the real project at all) while still wanting
  `:verify` to run its `mix compile` against the REAL project root. Concrete
  worked example -- generating into an isolated tmp dir, verifying against
  this repo itself:

      mkdir -p /tmp/ggen_verify_cwd_demo
      mix ggen_igniter.sync \\
        --pack-dir priv/ggen/adr-index-pack \\
        --out /tmp/ggen_verify_cwd_demo/out.md \\
        --manifest-dir /tmp/ggen_verify_cwd_demo \\
        --verify-cwd /Users/sac/ggen_igniter \\
        --engine oxigraph

  Without `--verify-cwd` in this exact scenario (`--manifest-dir` pointing
  outside any Mix project), `:verify`'s `mix compile` subprocess runs `cd:`
  into that same non-project tmp dir, Mix itself raises `** (Mix) Could not
  find a Mix.Project...`, and this task's `:verify`-failure path
  (`maybe_add_verify_cwd_hint/3` in `ReconcileReactor`) detects that exact
  Mix error text and a nil `--verify-cwd` and prepends a concrete pointer at
  this flag to the raised `RuntimeError`, rather than surfacing the bare Mix
  crash text alone.

  ## Controller delegation (opt-in, thin-adapter mode)

  When a real `GgenIgniter.Controller` `GenServer` is already running,
  registered under the name `GgenIgniter.Controller` (`Process.whereis/1` --
  the same registration idiom this codebase's own `GgenIgniter.Engine.Qlever`
  already uses for `GgenIgniter.Finch`), THIS run's reconciliation work is
  delegated to it (`GgenIgniter.Controller.reconcile/3`, wrapping the shared
  `GgenIgniter.Reconcile.run/1` pipeline) instead of running the pipeline
  inline -- giving this one invocation access to the controller's real,
  in-process reconciliation history (`reconciliation_count`, surfaced in the
  notice line below) instead of a fresh, state-free OS process. When no such
  process is registered (the common case today -- the controller is
  opt-in and off by default), behavior is EXACTLY the pre-existing inline
  pipeline, unchanged.

  Delegation only ever applies to a call within `GgenIgniter.Reconcile.run/1`'s
  own deliberately bounded scope (see that module's moduledoc): the resolved
  template must have NO frontmatter header at all, and `--for-each` must not
  be requested (by flag or by frontmatter -- moot here since frontmatter is
  required absent). Any call using frontmatter, `--for-each`, `inject: true`,
  or `mode: eval`'s frontmatter defaults, or a `Controller.reconcile/3` whose
  real arity/behavior no longer matches what this module was written against
  (`function_exported?/3`, checked every call -- a live defensive guard, not a
  one-time check, since this integration point was wired against a
  concurrently-developed module), transparently falls back to the exact same
  inline pipeline used when no controller is running at all -- never a silent
  behavior change for a feature the controller's bounded pipeline does not
  yet implement.

  One real, disclosed trade-off of controller-mode delegation specifically:
  the RECONCILIATION MANIFEST (`--on-stale`/`manifest.json`, described above)
  is a property of the inline pipeline's own bookkeeping and is NOT consulted
  or updated on the delegated path -- the controller's own in-process state
  (keyed on `{template_path, --out}`) is the reconciliation record for that
  call instead. This is intentional: controller mode exists precisely to
  replace disk-based manifest tracking with in-process tracking for whichever
  recipes it is enabled for, not to duplicate both.
  """
  # AR-9 correction (2026-08-27): every `mix ggen_igniter.sync` invocation now
  # ALWAYS acquires a real cross-process lock (`GgenIgniter.Lock.acquire/2`)
  # before doing any work, and ALWAYS attempts the receipt-writing Reactor
  # pipeline (`GgenIgniter.Reactors.ReconcileReactor.run/1`) FIRST, instead of
  # this being gated behind `Application.get_env(:ggen_igniter, :use_reactor,
  # false)` -- that config flag is no longer read here. The lock is released
  # in a `try/after` around the WHOLE plan+actuate sequence, so it is
  # released on a normal return, a raised exception, or a `dispatch_pipeline`
  # fallback alike -- never left held.
  #
  # `run_via_reactor/3` only ever returns `{:not_delegatable, reason}` for a
  # request outside `GgenIgniter.Reactors.ReconcileReactor.run/1`'s own
  # documented bounded scope. As of v26.9.2 (workstreams A and B, see
  # `run_via_reactor/3`'s own doc comment and `run_for_each_via_reactor!/7`),
  # that scope is down to exactly ONE real gap: `mode: eval` combined with
  # template frontmatter (a pre-existing `ReconcileReactor` `:render`-step
  # defect, independent of frontmatter parsing itself -- see that clause's
  # own comment). Both `--for-each` fan-out and a template's frontmatter
  # inline `sparql:` query text -- the two gaps THIS comment originally
  # described -- now route through the Reactor pipeline for real. For the
  # one request still outside scope, this task keeps the exact pre-existing
  # `dispatch_pipeline/3` behavior (controller delegation when running, else
  # the plain inline pipeline) -- never a silent reinterpretation of what an
  # unsupported flag does -- and logs a one-time migration notice naming
  # exactly which flag/feature has no Reactor-pipeline equivalent yet.
  #
  # Correction (2026-08-27, AR-10): before this correction, `run_via_reactor/3`
  # refused delegation for ANY frontmatter-bearing template, including
  # `inject: true` ones -- meaning a `mode: file`/`inject: true` write NEVER
  # got `ReconcileReactor`'s real admission-gate coverage (duplicate-
  # output-path refusal, path-escape refusal, a persisted `GgenIgniter.Receipt`)
  # via the actual `mix ggen_igniter.sync` CLI, even though
  # `ReconcileReactor`'s own `:render`/`:admit`/`:actuate` steps already
  # fully implement `operation: :inject` `%PendingActuation{}` construction
  # and dispatch (`render_inject_target/8`, reusing the SAME
  # `GgenIgniter.Frontmatter.split_template/1` + `GgenIgniter.Injection`
  # this task's own inline pipeline uses) -- proven directly, with no
  # frontmatter parsing reinvented, by
  # `test/ggen_igniter_reconcile_reactor_inject_test.exs`, which calls
  # `ReconcileReactor.run/1` itself. The real gap was ONLY this dispatch
  # guard being broader than the Reactor pipeline's real capability. Fixed
  # by narrowing the guard to the one frontmatter feature the Reactor path
  # genuinely does not implement (inline `sparql:` queries -- see above),
  # and by resolving frontmatter's `to:`/`unless_exists:`/`skip_if:` (mode
  # was already resolved) into concrete `reconcile_opts` values before
  # delegating, since `ReconcileReactor.run_target_queries/3` reads ONLY the
  # flat opts/`:targets` keyword list for those fields, never the
  # template's own frontmatter directly (unlike its `:render` step, which
  # DOES re-read frontmatter for `inject`/`before`/`after`/`at_line`
  # specifically). See `test/ggen_igniter_sync_inject_reactor_admission_test.exs`
  # for the real, CLI-level proof this correction closes: an `inject: true`
  # write now genuinely routes "(via reactor)", and an `inject: true` write
  # targeting a path outside the authorized project root is refused the
  # same real way a `mode: file` write already was.
  # AR-11 correction (2026-08-28): `Igniter.Mix.Task`'s generated `run/1` (the
  # macro body in `Igniter.Mix.Task.__using__/1`) intercepts `--help`
  # (long form only -- `Igniter.Mix.Task.help_requested?/1` literally checks
  # `"--help" in argv`, never `-h`) BEFORE this module's own `igniter/1` ever
  # runs, dispatching to `Mix.Task.run("help", [task_name])` instead -- which
  # prints this module's full 184-line `@moduledoc` via Mix's own generic
  # help renderer, not the concise USAGE block below. `-h` is unaffected
  # (`help_requested?/1` doesn't match it), so it falls through to Igniter's
  # normal `run/1` -> `configure_and_run/2` -> `igniter/1` pipeline, where
  # `opts[:help]` (true via the `h: :help` alias) reaches `print_help_and_halt/0`
  # exactly as intended -- this is the real, confirmed source of the
  # `--help`-vs-`-h` output split. Fixed by overriding `run/1` (the generated
  # one is `defoverridable run: 1`) to catch literal `"--help"` in `argv`
  # ourselves, before Igniter's own `help_requested?/1` check ever runs, and
  # dispatch to the exact same `print_help_and_halt/0` `-h` already uses.
  # Every other argv (including `-h`, which still reaches `igniter/1` via the
  # unchanged `super/1` path) is untouched.
  @impl Mix.Task
  def run(argv) do
    if "--help" in argv do
      print_help_and_halt()
    else
      super(argv)
    end
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    {opts, pack_template_stem} = split_pack_template_stem(igniter.args.options)

    cond do
      opts[:help] -> print_help_and_halt()
      opts[:version] -> print_version_and_halt()
      true -> run_sync(igniter, opts, pack_template_stem)
    end
  end

  defp print_help_and_halt do
    IO.puts("""
    mix ggen_igniter.sync -- ontology -> query -> render -> actuate pipeline

    USAGE
        mix ggen_igniter.sync --ontology path.ttl --query name=path.rq (repeatable)
                               --template path.eex --out path.ex
                               [--engine oxigraph|sparql|qlever] [--store-id ID]
                               [--pack NAME | --pack-dir DIR] [--for-each NAME]
                               [--mode file|eval] [--on-stale refuse|prune|preserve]
                               [--manifest-dir DIR] [--unless-exists] [--skip-if EXPR]
                               [--allow-sh] [--dry-run] [--help] [--version]

    FLAGS
        --ontology PATH     Path to the RDF/Turtle ontology to load.
        --query NAME=PATH   Named SPARQL query (repeatable).
        --template PATH     EEx template to render (or resolved via --pack/--pack-dir).
        --out PATH          Output path (or an EEx path template with --for-each).
        --engine ENGINE     One of: oxigraph, sparql, qlever. Default: oxigraph.
        --store-id ID       Named store to resolve for --engine qlever.
        --pack NAME         Resolve a marketplace-convention pack by name (priv/ggen/NAME).
        --pack-dir DIR      Use an explicit pack directory (bypasses the --pack convention).
        --for-each NAME     Fan out one render per row of the named query result.
        --mode MODE         file (default, writes to disk) or eval (evaluates in-process).
        --on-stale POLICY   refuse (default) | prune | preserve stale manifest paths.
        --manifest-dir DIR  Directory holding .ggen_igniter/manifest.json. Default: cwd.
        --unless-exists     Skip writing if the output path already exists.
        --skip-if EXPR      Skip writing if EXPR (literal string) matches.
        --allow-sh          Required if any template frontmatter sets sh_before:/sh_after:
                             (default: refuse the whole run before any actuation).
        --dry-run           Preview actuation without writing/deleting anything.
        --help, -h          Print this help and exit 0.
        --version, -v       Print ggen_igniter's version and exit 0.

    EXAMPLES
        mix ggen_igniter.sync \\
          --ontology test/fixtures/audit_trail_ontology.ttl \\
          --query spec=test/fixtures/spec.rq \\
          --template test/fixtures/extension.ex.eex \\
          --out tmp_out/probe.ex

        mix ggen_igniter.sync --pack audit-trail-pack --out lib/generated.ex

    See `mix help ggen_igniter.sync` for the full moduledoc (engines, --for-each
    fan-out, frontmatter injection, mode: eval, reconciliation manifest, and
    controller delegation).
    """)

    System.halt(0)
  end

  defp print_version_and_halt do
    version = Application.spec(:ggen_igniter, :vsn) |> to_string()
    IO.puts("ggen_igniter #{version}")
    System.halt(0)
  rescue
    _ -> IO.puts("ggen_igniter unknown") && System.halt(0)
  end

  defp run_sync(igniter, opts, pack_template_stem) do
    lock_key = opts[:manifest_dir] || File.cwd!()
    {:ok, lock_ref} = GgenIgniter.Lock.acquire(lock_key, [])

    try do
      case run_via_reactor(igniter, opts, pack_template_stem) do
        {:ok, result_igniter} ->
          result_igniter

        {:not_delegatable, reason} ->
          migration_notice_once(
            "ggen_igniter: #{reason} has no GgenIgniter.Reactors.ReconcileReactor " <>
              "equivalent yet (AR-9) -- falling back to the pre-existing plain/controller " <>
              "pipeline for this run only"
          )

          dispatch_pipeline(igniter, opts, pack_template_stem)
      end
    after
      GgenIgniter.Lock.release(lock_ref)
    end
  end

  # Logs `message` via `Mix.shell().info/1` at most once per BEAM process
  # (tracked with `:persistent_term`, cheap read-mostly global state) -- a
  # migration notice about an unsupported flag should be seen once per run,
  # not once per `--for-each` row or per test-suite invocation flooding
  # output.
  @migration_notice_key {__MODULE__, :ar9_migration_notice_logged}
  defp migration_notice_once(message) do
    unless :persistent_term.get(@migration_notice_key, false) do
      Mix.shell().info(message)
      :persistent_term.put(@migration_notice_key, true)
    end
  end

  # The exact pre-Reactor entry-point body: delegate to a running Controller
  # when possible, else run the standalone inline pipeline. Unchanged from
  # before `use_reactor?/0` existed.
  defp dispatch_pipeline(igniter, opts, pack_template_stem) do
    case Process.whereis(GgenIgniter.Controller) do
      nil ->
        run_pipeline!(igniter, opts, pack_template_stem)

      controller ->
        case delegate_to_controller(igniter, opts, pack_template_stem, controller) do
          {:ok, result_igniter} -> result_igniter
          :not_delegatable -> run_pipeline!(igniter, opts, pack_template_stem)
        end
    end
  end

  # Runs the real Reactor pipeline directly (independent of whether a
  # `GgenIgniter.Controller` happens to be registered -- the Reactor path
  # does not need the Controller's in-process state). Only within
  # `ReconcileReactor.run/1`'s own bounded scope: `--for-each` fan-out must
  # not be requested, and the resolved template's frontmatter must not
  # declare INLINE `sparql:` query text (the one frontmatter feature
  # `ReconcileReactor.run_target_queries/3` genuinely does not resolve --
  # see the AR-10 correction above). A template with `inject: true` (or any
  # other frontmatter field `ReconcileReactor`'s own `:render` step already
  # handles or that is resolved into `reconcile_opts` below) DOES route
  # through here. Outside this scope, falls back to `dispatch_pipeline/3`,
  # never a silent behavior change for a feature the bounded Reactor
  # pipeline does not implement.
  defp run_via_reactor(igniter, opts, pack_template_stem) do
    template_path = resolve_template!(opts, pack_template_stem)

    {frontmatter, frontmatter_mode, _template_string} =
      Frontmatter.split_template(File.read!(template_path))

    check_allow_sh!(opts, frontmatter, template_path)

    for_each = opts[:for_each] || frontmatter_field(frontmatter, :for_each)

    # `mode` is always `:file` or `:eval` -- `resolve_mode!/2` returns
    # `frontmatter_mode` (never `nil`; `Frontmatter.split_template/1` itself
    # always returns `:file` or `:eval`, even for a header-less template)
    # whenever `--mode` is not given.
    mode = resolve_mode!(opts, frontmatter_mode)

    cond do
      # `mode: eval` (frontmatter-driven or `--mode eval`) is deliberately
      # EXCLUDED from Reactor delegation, independent of frontmatter/inject/
      # `--for-each`: `ReconcileReactor`'s `:render` step has a real,
      # separately documented, unconditional crash for ANY `:eval` target --
      # `PendingActuation.for_eval/3`'s `target` is always `nil`, and
      # `:render`'s own `PLAN_CONSTRUCTED` telemetry emission
      # (`file_objects/1` -> `OcelEmitter.file_object/1`) has no clause for
      # a `nil` path, so it raises `FunctionClauseError` before `:admit` or
      # `:actuate` ever run -- see
      # `test/ggen_igniter_reconcile_reactor_test.exs`'s ":eval
      # compensation-completeness: REAL FINDING -- unreachable, not just
      # untested" test for the direct, reproduced proof. Checked BEFORE the
      # `--for-each` clause below (v26.9.2) so a `--for-each` +
      # `mode: eval` combination cannot accidentally reach the newly-real
      # `--for-each`-via-reactor path and hit that same crash through a
      # different door -- this is a pre-existing `ReconcileReactor` defect,
      # entirely independent of the `inject: true`/`sparql:`/`--for-each`
      # gaps this module's AR-10/v26.9.2 corrections close, and out of
      # THIS correction's scope to fix. A header-less `mode: eval` template
      # (`frontmatter == nil`, `--mode eval` on the CLI) is UNCHANGED by
      # this clause -- it already routed through the Reactor pipeline
      # before AR-10 and still does; the same pre-existing `:render` crash
      # would already apply to it today, independent of this correction.
      frontmatter != nil and mode == :eval ->
        {:not_delegatable,
         "template frontmatter combined with mode: eval (#{template_path} -- " <>
           "GgenIgniter.Reactors.ReconcileReactor.run/1's :render step has a real, " <>
           "pre-existing, documented crash for :eval targets independent of frontmatter; " <>
           "see test/ggen_igniter_reconcile_reactor_test.exs's \":eval " <>
           "compensation-completeness\" finding)"}

      # v26.9.2 (workstream B): `--for-each NAME` fan-out now routes through
      # `GgenIgniter.Reactors.ReconcileReactor.run/1` too -- see
      # `run_for_each_via_reactor!/7`'s own doc comment for the real
      # mechanism and the disclosed all-or-nothing/stricter-admission
      # trade-offs this brings. Before v26.9.2, this was
      # `{:not_delegatable, "--for-each ..."}` unconditionally, falling back
      # to `dispatch_pipeline/3`'s inline `run_pipeline!/3`.
      for_each not in [nil, ""] ->
        run_for_each_via_reactor!(
          igniter,
          opts,
          pack_template_stem,
          template_path,
          frontmatter,
          for_each,
          mode
        )

      true ->
        resolved_out = opts[:out] || frontmatter_field(frontmatter, :to)

        # Same early, clear `--out`-required validation `run_pipeline!/3` has
        # always done -- BEFORE any query/render work -- restored here for
        # parity now that this bounded path is reached unconditionally
        # (rather than only as a fallback). Without this, a `mode: file`
        # template missing `--out` would instead fail deep inside
        # `ReconcileReactor.build_plan/3`'s real body-render step (a
        # confusing `Render.render/2` error about an undefined template
        # binding, or a differently-worded internal `ArgumentError`) --
        # never this task's own documented, tested "--out is required"
        # message.
        if mode == :file and resolved_out == nil do
          raise ArgumentError,
                "--out is required (directly, or via the template's own frontmatter \"to:\" field)"
        end

        # AR-10: `ReconcileReactor.run_target_queries/3` reads `:mode`/
        # `:out`/`:unless_exists`/`:skip_if` ONLY from this flat keyword
        # list (or a `:targets` entry) -- it never re-reads the template's
        # own frontmatter for these (unlike `:render`'s own inject-specific
        # re-read of `frontmatter.inject`/`before`/`after`/`at_line`, via
        # `render_target/1`). A header-less template never needed this
        # resolution step (every routing value always came from an explicit
        # CLI flag in that case, so `opts` alone was already correct) --
        # resolving these four fields here, with the CLI flag always
        # winning over the same-named frontmatter field (`||`, matching
        # every other frontmatter/CLI precedence rule in this module), is
        # what makes a frontmatter-only template (no explicit --out/--mode/
        # --unless-exists/--skip-if) route through the Reactor pipeline
        # with the exact same resolved routing `run_pipeline!/3`'s inline
        # fallback would have used.
        reconcile_opts =
          opts
          |> Keyword.put(:pack_template_stem, pack_template_stem)
          |> Keyword.put(:out, resolved_out)
          |> Keyword.put(:mode, mode)
          |> Keyword.put(
            :unless_exists,
            opts[:unless_exists] || frontmatter_field(frontmatter, :unless_exists) || false
          )
          |> Keyword.put(:skip_if, opts[:skip_if] || frontmatter_skip_if!(frontmatter))

        dispatch_reactor_reconcile(igniter, reconcile_opts)
    end
  end

  # v26.9.2 (workstream B): expands ONE `--for-each NAME`-bearing target into
  # N real per-row targets, and runs them as a SINGLE
  # `GgenIgniter.Reactors.ReconcileReactor.run/1` invocation via its
  # EXISTING `opts[:targets]` mechanism (`ReconcileReactor.normalize_targets/1`)
  # -- never a second, parallel fan-out mechanism inside the reactor itself.
  #
  # The driver query is run here via the EXACT SAME call path
  # `run_pipeline!/3` already uses to get its own `rows`
  # (`Engine.fetch!/1` -> `Ontology.load!/1` -> `resolve_named_queries!/2` ->
  # `run_queries/4` -> `fetch_driver_rows!/2`, all reused verbatim, never
  # reinvented) -- so a query result the inline pipeline and this reactor
  # dispatch would ever disagree about is structurally impossible: both call
  # the identical private functions against the identical `opts`/
  # `frontmatter`. Each row becomes one `[for_each_row: row]` per-target
  # override; `ReconcileReactor.run_target_queries/3` merges that row's own
  # columns into its EEx bindings LAST (same precedence
  # `Mix.Tasks.GgenIgniter.Sync.build_bindings/2` already documents for
  # `--for-each`), so both the rendered body and the EEx-rendered `--out`
  # path see the row's own values.
  #
  # DISCLOSED, INTENTIONAL BEHAVIOR CHANGE (the deliberate trade-off this
  # whole task exists to deliver): because all N rows now run inside ONE
  # `ReconcileReactor.run/1` invocation, `:actuate` is all-or-nothing -- one
  # row's write (or `sh_before:`/`sh_after:`) failure triggers the real
  # Reactor `undo/3`/self-heal compensation, reverting EVERY row's writes in
  # THIS run, not just the failing one. Before this change, `--for-each`
  # always ran via the inline `run_pipeline!/3` pipeline, which allowed
  # genuine per-row partial success (a failed row did not abort or revert
  # its siblings) -- see
  # `test/ggen_igniter_sync_for_each_reactor_test.exs` for
  # the real, no-mock proof that a mid-run failure on one row now reverts
  # every row's writes.
  #
  # A second, real, disclosed strictness increase this same routing brings:
  # every row now passes through `ReconcileReactor`'s own `:admit` gate,
  # including its real duplicate-canonical-output-path refusal (a `--out`
  # EEx template that fails to interpolate a row field, producing the SAME
  # resolved path for two rows, used to silently last-writer-win under the
  # inline pipeline's sequential writes -- it is now refused outright before
  # any actuation happens at all) and its real authorized-project-root
  # escape refusal (`GgenIgniter.ArtifactIdentity.within_root?/2`, scoped to
  # `--manifest-dir`/`File.cwd!()` -- a `--for-each` run whose `--out` lands
  # outside that root, previously silently allowed by the inline pipeline,
  # is now refused the same real way a single-target reactor-routed write
  # already was).
  defp run_for_each_via_reactor!(
         igniter,
         opts,
         pack_template_stem,
         _template_path,
         frontmatter,
         for_each,
         mode
       ) do
    engine_name = opts[:engine] || "oxigraph"
    engine_module = Engine.fetch!(engine_name)
    ontology_path = resolve_ontology!(opts)
    graph = Ontology.load!(ontology_path)
    named_queries = resolve_named_queries!(opts, frontmatter)
    named_results = run_queries(engine_module, graph, opts, named_queries)
    rows = fetch_driver_rows!(named_results, for_each)

    resolved_out = opts[:out] || frontmatter_field(frontmatter, :to)

    if mode == :file and resolved_out == nil do
      raise ArgumentError,
            "--out is required (directly, or via the template's own frontmatter \"to:\" field)"
    end

    reconcile_opts =
      opts
      |> Keyword.put(:pack_template_stem, pack_template_stem)
      |> Keyword.put(:out, resolved_out)
      |> Keyword.put(:mode, mode)
      |> Keyword.put(
        :unless_exists,
        opts[:unless_exists] || frontmatter_field(frontmatter, :unless_exists) || false
      )
      |> Keyword.put(:skip_if, opts[:skip_if] || frontmatter_skip_if!(frontmatter))
      |> Keyword.put(:targets, Enum.map(rows, fn row -> [for_each_row: row] end))

    dispatch_reactor_reconcile(igniter, reconcile_opts)
  end

  # Shared success/failure handling for every `ReconcileReactor.run/1`
  # dispatch site in this module (the single-target `true ->` branch above,
  # and `run_for_each_via_reactor!/7`) -- extracted so both real call sites
  # report the identical `"... (via reactor)"` notice convention and the
  # identical reconciliation-failure error text, never two independently
  # drifting copies.
  defp dispatch_reactor_reconcile(igniter, reconcile_opts) do
    case ReconcileReactor.run(reconcile_opts) do
      {:ok, receipt} ->
        notice = receipt.metadata["notice"] || "reconciled"

        # Mirrors `run_pipeline!/3`'s own `if dry_run, do:
        # Mix.shell().info(line)` -- printed DURING the run (not just
        # returned as an `Igniter.add_notice/2` notice, which an
        # in-process caller invoking `igniter/1` directly -- never
        # through the outer Mix-task/`Igniter.do_or_dry_run/2`
        # printing machinery -- would otherwise never see at all).
        for line <- receipt.metadata["dry_run_lines"] || [], do: Mix.shell().info(line)

        # v26.9.2 (workstream B): real `--on-stale prune`/`preserve` notice
        # text, mirroring `apply_stale_policy!/2`'s own conventions -- see
        # `ReconcileReactor.finalize_evidence/1`'s own comment for why this
        # is returned as metadata (printed here, not inside the reactor
        # module) rather than a silent notice-text regression for
        # `--for-each` recipes now that they reach this pipeline too.
        for line <- receipt.metadata["prune_lines"] || [], do: Mix.shell().info(line)
        if warning = receipt.metadata["preserve_warning"], do: Mix.shell().error(warning)

        {:ok, Igniter.add_notice(igniter, "ggen_igniter: #{notice} (via reactor)")}

      {:error, receipt} ->
        raise "ggen_igniter: reactor reconciliation failed (#{receipt.standing}): " <>
                (receipt.reason || "no reason recorded")
    end
  end

  # Decides whether THIS invocation can be safely handed to a running
  # controller, and does so when it can. Returns `{:ok, updated_igniter}` on a
  # real, successful delegated reconciliation, or `:not_delegatable` when
  # either the controller's real API no longer matches what this call site
  # expects (`function_exported?/3`) or this invocation uses a feature outside
  # `GgenIgniter.Reconcile.run/1`'s bounded scope (template frontmatter,
  # `--for-each`) -- in both cases the caller falls back to
  # `run_pipeline!/3`, the exact unchanged standalone pipeline.
  #
  # A real pipeline failure inside the controller (`{:error, reason}` from
  # `Controller.reconcile/3` -- the controller itself already caught the
  # underlying exception, per its own moduledoc's fault-isolation guarantee)
  # is re-raised here rather than silently falling back to the inline
  # pipeline: a real ontology/template/engine error is a real error either
  # way, and silently re-running it inline would both mask which path
  # actually failed and do real work (a second ontology load, a second query
  # run) the controller had already attempted once.
  defp delegate_to_controller(igniter, opts, pack_template_stem, controller) do
    if function_exported?(Controller, :reconcile, 3) do
      template_path = resolve_template!(opts, pack_template_stem)

      {frontmatter, _frontmatter_mode, _template_string} =
        Frontmatter.split_template(File.read!(template_path))

      for_each = opts[:for_each] || frontmatter_field(frontmatter, :for_each)

      if frontmatter == nil and for_each in [nil, ""] do
        reconcile_opts = Keyword.put(opts, :pack_template_stem, pack_template_stem)
        pack_key = {template_path, opts[:out]}

        case Controller.reconcile(controller, pack_key, reconcile_opts) do
          {:ok, record} ->
            {:ok, Igniter.add_notice(igniter, controller_notice(pack_key, record))}

          {:error, reason} ->
            raise "ggen_igniter: controller reconciliation failed for #{inspect(pack_key)}: " <>
                    inspect(reason)
        end
      else
        :not_delegatable
      end
    else
      :not_delegatable
    end
  end

  # Mirrors the standalone pipeline's own notice shape ("engine: ..., N
  # queries, M total row(s)") so controller-mode output stays recognizable,
  # with a real, controller-only fact appended (`reconciliation_count`) that a
  # fresh, state-free CLI process could never report on its own -- see
  # `GgenIgniter.Controller`'s moduledoc for why that count is genuinely not
  # derivable from disk alone.
  defp controller_notice(pack_key, %{reconciliation_count: count, receipt: receipt}) do
    query_word = if receipt.query_count == 1, do: "query", else: "queries"

    "ggen_igniter: #{receipt.notice} (engine: #{receipt.engine}, #{receipt.query_count} " <>
      "#{query_word}, #{receipt.total_rows} total row(s), via controller: reconciliation " <>
      "##{count} for #{inspect(pack_key)})"
  end

  # The exact standalone pipeline, unchanged in behavior from before
  # controller delegation existed -- this is the fallback path when no
  # controller is running, and it is also literally what
  # `test/ggen_igniter_sync_*.exs` all still exercise, since no controller
  # runs in the normal test environment. `opts`/`pack_template_stem` arrive
  # already split out of `igniter.args.options` by `igniter/1` above (the only
  # change from before: this body used to compute that destructure itself as
  # its own first line).
  defp run_pipeline!(igniter, opts, pack_template_stem) do
    engine_name = opts[:engine] || "oxigraph"
    engine_module = Engine.fetch!(engine_name)

    ontology_path = resolve_ontology!(opts)
    graph = Ontology.load!(ontology_path)

    template_path = resolve_template!(opts, pack_template_stem)

    {frontmatter, frontmatter_mode, template_string} =
      Frontmatter.split_template(File.read!(template_path))

    check_allow_sh!(opts, frontmatter, template_path)

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
        Injection.resolve_injection!(frontmatter)
      end

    # `sh_before:`/`sh_after:` are, like the injection anchor above, a
    # property of the TEMPLATE, resolved once per `sync` run -- not per
    # `--for-each` row. `check_allow_sh!/3` above has already refused the
    # whole run before this point if either is set without `--allow-sh`, so
    # by the time `actuate_row!/11` below actually runs a hook, `sh_before`/
    # `sh_after` being non-`nil` implies `--allow-sh` was given.
    sh_before = frontmatter_field(frontmatter, :sh_before)
    sh_after = frontmatter_field(frontmatter, :sh_after)
    sh_project_dir = opts[:manifest_dir] || File.cwd!()

    total_rows = named_results |> Enum.map(fn {_name, rows} -> length(rows) end) |> Enum.sum()

    # One binding set per row (`--for-each`'s driver rows), or exactly one
    # `nil` "row" for the ordinary static-output case -- `build_bindings/2`'s
    # own `for_each_row \\ nil` default already treats those identically, so
    # this single `rows` list replaces what used to be two near-duplicate
    # `case for_each do nil -> ...; driver_name -> ... end` branches.
    rows =
      case for_each do
        nil -> [nil]
        driver_name -> fetch_driver_rows!(named_results, driver_name)
      end

    # Every row's content AND (when applicable) its real output path are
    # rendered exactly ONCE, up front, before any actuation -- both are pure
    # computations over `bindings` (no filesystem I/O), so precomputing them
    # here is what lets the reconciliation manifest below compute this run's
    # REAL new-path set and decide `--on-stale` policy BEFORE a single byte
    # is written, without rendering `out_template` a second time later.
    renders =
      Enum.map(rows, fn row ->
        bindings = build_bindings(named_results, row)
        content = Render.render(template_string, bindings)
        out_path = if out_template, do: Render.render(out_template, bindings)
        {bindings, content, out_path}
      end)

    # Reconciliation applies ONLY to the actuation path where this pack fully
    # OWNS the target file (creates it, and can safely recreate/delete it):
    # `mode: file` writes via `Actuate.write_file!/3`. It deliberately
    # excludes `mode: eval` (nothing is ever written to disk) and `inject:
    # true` targets (`Actuate.inject_content!/5` requires and never creates a
    # PRE-EXISTING file this pack does not own -- treating a splice target as
    # "manufactured by this pack" would let `--on-stale prune` delete a file
    # this pack never created). See `GgenIgniter.Manifest`'s moduledoc for the
    # full reasoning.
    reconcile? = mode == :file and inject_spec == nil

    manifest_dir = opts[:manifest_dir] || File.cwd!()
    on_stale = resolve_on_stale!(opts[:on_stale])

    recipe_key = if reconcile?, do: Manifest.recipe_key(template_path, out_template)
    manifest = if reconcile?, do: Manifest.load(manifest_dir)
    old_entry = if reconcile?, do: Manifest.get_entry(manifest, recipe_key)

    new_paths =
      renders
      |> Enum.map(fn {_bindings, _content, out_path} -> out_path end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    stale = if reconcile?, do: Manifest.stale_paths(old_entry, new_paths), else: MapSet.new()

    if reconcile? and on_stale == :refuse and MapSet.size(stale) > 0 do
      raise ArgumentError, refuse_stale_message(stale, recipe_key)
    end

    render_results =
      Enum.map(renders, fn {bindings, content, out_path} ->
        {line, out_path2, outcome, hook_status, commands} =
          actuate_row!(
            mode,
            content,
            bindings,
            out_path,
            template_path,
            write_opts,
            dry_run,
            inject_spec,
            sh_before,
            sh_after,
            sh_project_dir
          )

        if dry_run, do: Mix.shell().info(line)
        {line, out_path2, outcome, hook_status, commands}
      end)

    notices =
      Enum.map(render_results, fn {line, _out_path, _outcome, _hook_status, _cmds} -> line end)

    all_sh_commands =
      Enum.flat_map(render_results, fn {_line, _out, _outcome, _hs, cmds} -> cmds end)

    # DX: with `--for-each` fanning out to many rows (a pack with 8+ queries,
    # or many driver rows), the per-file notice line above becomes a wall of
    # undifferentiated `"; "`-joined text -- real, observed on an 8-row fixture
    # (`test/fixtures/for_each_ontology_8.ttl`/`modules_8.rq`): all 8 "wrote
    # ..." lines joined onto one line with no differentiation at a glance.
    # `outcome_summary_suffix/2` appends a real, counted-from-actual-outcomes
    # summary ("wrote 8, skipped 2, unchanged 1" style) WITHOUT removing the
    # per-file detail above -- both stay present; this is purely additive.
    # Only appended when there's more than one row (a single-output run's
    # existing notice is already exactly as readable as a summary would be).
    summary_suffix = outcome_summary_suffix(render_results, dry_run)

    if reconcile? do
      if dry_run do
        preview_stale!(on_stale, stale)
      else
        apply_stale_policy!(on_stale, stale)

        # Only a path THIS run actually wrote or reconfirmed byte-identical
        # (`:written`/`:unchanged`) is manifest-owned. A path this run merely
        # left alone (`:skipped_exists`/`:skipped_match`, from
        # `--unless-exists`/`--skip-if`) is deliberately excluded -- see
        # `actuate!/8`'s comments for why recording it would let a later
        # rename's `--on-stale prune` delete a file this pack never wrote.
        outputs =
          for {_line, out_path, outcome, _hook_status, _cmds} <- render_results,
              outcome in [:written, :unchanged],
              into: %{} do
            {out_path, Manifest.hash_content(File.read!(out_path))}
          end

        unless Manifest.same_outputs?(old_entry, outputs) do
          pack_dir = if pack_given?(opts), do: GgenIgniter.Pack.resolve_dir!(opts)
          entry = Manifest.build_entry(template_path, out_template, pack_dir, outputs)

          manifest
          |> Manifest.put(recipe_key, entry)
          |> Manifest.persist!(manifest_dir)
        end
      end
    end

    # A minimal, best-effort `GgenIgniter.Receipt` for `sh_before:`/
    # `sh_after:` invocations ONLY -- `run_pipeline!/3` otherwise never
    # constructs a receipt at all (this inline pipeline has no `:verify`/
    # compensation step of its own; `GgenIgniter.Reactors.ReconcileReactor`
    # is the pipeline with the full receipt lifecycle). `standing: :alive`
    # here describes "a real reconciliation attempt was made and files were
    # actuated via the normal write-safety guards" -- NOT "every shell hook
    # succeeded"; any hook failure is named explicitly in `reason` and in
    # each `commands` entry's own `"status"` field instead of being hidden
    # behind a misleading standing atom. Skipped entirely under `--dry-run`
    # (no hook ever really ran) and whenever no template in this run
    # declared `sh_before:`/`sh_after:` at all (`all_sh_commands == []`) --
    # a run with no shell hooks produces no new receipt traffic.
    unless dry_run or all_sh_commands == [] do
      failed = Enum.filter(all_sh_commands, &(&1["status"] != "ok"))

      reason =
        case failed do
          [] ->
            nil

          _ ->
            "sh hook failure(s): " <>
              Enum.map_join(failed, "; ", fn c -> "#{c["kind"]} (#{c["status"]}): #{c["cmd"]}" end)
        end

      written_paths =
        for {_line, out_path, outcome, _hook_status, _cmds} <- render_results,
            outcome in [:written, :injected],
            do: out_path

      receipt =
        Receipt.new(%{
          standing: :alive,
          recipe_key: if(reconcile?, do: recipe_key),
          files: written_paths,
          reason: reason,
          commands: all_sh_commands,
          metadata: %{"source" => "inline_pipeline_sh_hooks"}
        })

      Receipt.append!(manifest_dir, receipt)
    end

    Igniter.add_notice(
      igniter,
      "ggen_igniter: #{Enum.join(notices, "; ")} (engine: #{engine_name}, #{length(named_queries)} quer#{if length(named_queries) == 1, do: "y", else: "ies"}, #{total_rows} total row(s))#{summary_suffix}"
    )
  end

  # Builds a real, counted-from-actual-outcomes summary suffix like
  # `" -- summary: wrote 6, skipped 1, unchanged 1"`, or `""` when
  # `render_results` has one or fewer entries (a single-output run's own
  # per-file line is already the summary -- adding a second one would be
  # noise, not clarity). Counts are grouped by real `Actuate`/`actuate!/8`
  # outcome atoms (`:written`, `:injected`, `:unchanged`, `:skipped_exists`,
  # `:skipped_match`) -- `:skipped_exists`/`:skipped_match` are folded into
  # one `"skipped"` bucket since both mean the same thing to a human reading
  # the summary (an `--unless-exists`/`--skip-if` guard fired), and `nil`
  # (only ever returned for `mode: eval`, which never has a summary-worthy
  # per-row outcome) is silently excluded from the count entirely. Order is
  # fixed (`written`, `injected`, `unchanged`, `skipped`, `sh_before_failed`,
  # `sh_after_failed`) rather than insertion order, so the summary reads the
  # same shape run to run; a zero-count bucket is omitted rather than
  # printed as "wrote 0". Under `--dry-run`, the label is "planned to ..."
  # instead of the past-tense verb, matching every other dry-run notice in
  # this module's own convention of never claiming a real action happened
  # when nothing was written. `sh_before_failed`/`sh_after_failed` come from
  # a row's `hook_status` (its 4th tuple element), NOT its underlying
  # `outcome` -- see `actuate_row!/11` -- and are always `nil` under
  # `--dry-run` (a shell hook never actually runs under `--dry-run`).
  @spec outcome_summary_suffix(
          [{String.t(), String.t() | nil, atom() | nil, atom() | nil, [map()]}],
          boolean()
        ) :: String.t()
  defp outcome_summary_suffix(render_results, dry_run) when length(render_results) > 1 do
    counts =
      render_results
      |> Enum.map(fn {_line, _out_path, outcome, hook_status, _cmds} ->
        hook_status || summary_bucket(outcome)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    parts =
      for bucket <- [
            :written,
            :injected,
            :unchanged,
            :skipped,
            :sh_before_failed,
            :sh_after_failed
          ],
          count = Map.get(counts, bucket, 0),
          count > 0 do
        "#{summary_verb(bucket, dry_run)} #{count}"
      end

    case parts do
      [] -> ""
      _ -> " -- summary: " <> Enum.join(parts, ", ")
    end
  end

  defp outcome_summary_suffix(_render_results, _dry_run), do: ""

  defp summary_bucket(:written), do: :written
  defp summary_bucket(:injected), do: :injected
  defp summary_bucket(:unchanged), do: :unchanged
  defp summary_bucket(:skipped_exists), do: :skipped
  defp summary_bucket(:skipped_match), do: :skipped
  defp summary_bucket(nil), do: nil

  defp summary_verb(:written, false), do: "wrote"
  defp summary_verb(:written, true), do: "planned to write"
  defp summary_verb(:injected, false), do: "injected"
  defp summary_verb(:injected, true), do: "planned to inject"
  defp summary_verb(:unchanged, _dry_run), do: "unchanged"
  defp summary_verb(:skipped, _dry_run), do: "skipped"
  defp summary_verb(:sh_before_failed, false), do: "sh_before failed"
  defp summary_verb(:sh_after_failed, false), do: "sh_after failed"

  # -- `sh_before:`/`sh_after:` shell hooks -----------------------------------
  #
  # See this module's own moduledoc ("## `sh_before:`/`sh_after:` shell
  # hooks") for the full disclosed scope/failure-semantics contract these
  # three functions implement. Checked from BOTH `run_via_reactor/3` and
  # `run_pipeline!/3` -- genuinely separate call paths, per this module's own
  # AR-9/AR-10 comments -- so neither can silently skip the refusal.
  @spec check_allow_sh!(keyword(), Frontmatter.t() | nil, String.t()) :: :ok
  defp check_allow_sh!(opts, frontmatter, template_path) do
    sh_before = frontmatter_field(frontmatter, :sh_before)
    sh_after = frontmatter_field(frontmatter, :sh_after)

    if (sh_before || sh_after) && not (opts[:allow_sh] || false) do
      raise ArgumentError, refuse_sh_message(template_path, sh_before, sh_after)
    end

    :ok
  end

  defp refuse_sh_message(template_path, sh_before, sh_after) do
    fields =
      [{"sh_before", sh_before}, {"sh_after", sh_after}]
      |> Enum.filter(fn {_k, v} -> v not in [nil, false] end)
      |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)

    "ggen_igniter: refusing to sync -- #{template_path} declares #{fields} in its frontmatter. " <>
      "A sh_before:/sh_after: command runs an arbitrary real shell command that is NOT " <>
      "covered by GgenIgniter.PendingActuation's admission gate (:admit) and NOT tracked by " <>
      "compensation/undo -- a disclosed, intentional limitation (see this module's moduledoc, " <>
      "\"## sh_before:/sh_after: shell hooks\"). Nothing was actuated this run. Pass " <>
      "--allow-sh to explicitly opt in and run this sync with shell hooks enabled."
  end

  # Runs ONE row's `sh_before:` (if any), then the row's real
  # `write_file!/3`/`inject_content!/5` call, then `sh_after:` (if any and
  # only when the write/inject genuinely happened -- `outcome in [:written,
  # :injected]`). Returns `{line, out_path, outcome, hook_status, commands}`:
  #
  #   * `outcome` is the SAME real `Actuate` outcome atom `actuate!/8` always
  #     returned before this feature existed -- unaffected by hook failure,
  #     so manifest-tracking/stale-computation logic downstream (which keys
  #     on `outcome`, never on `hook_status`) is completely unchanged.
  #   * `hook_status` is `nil` (no hook failure) or `:sh_before_failed` /
  #     `:sh_after_failed` -- purely a REPORTING signal (notice text,
  #     `outcome_summary_suffix/2`), never fed back into manifest logic.
  #   * A failed `sh_before:` SKIPS the real write/inject entirely for this
  #     row (`outcome` is `nil`, mirroring `mode: eval`'s own "no writable
  #     outcome" convention) -- this row's precondition failed, so nothing
  #     is written; sh_before's own real command output is not silently
  #     dropped, it goes out in `line`/`commands`. Other rows in the SAME
  #     `--for-each` run are NOT aborted (they call `actuate_row!/11`
  #     independently, one `Enum.map/2` iteration each).
  @spec actuate_row!(
          :file | :eval,
          String.t(),
          keyword(),
          String.t() | nil,
          String.t(),
          keyword(),
          boolean(),
          {String.t() | Regex.t() | nil, :before | :after | :at_line, keyword()} | nil,
          String.t() | nil,
          String.t() | nil,
          String.t()
        ) :: {String.t(), String.t() | nil, atom() | nil, atom() | nil, [map()]}
  defp actuate_row!(
         mode,
         content,
         bindings,
         out_path,
         template_path,
         write_opts,
         dry_run,
         inject_spec,
         sh_before,
         sh_after,
         project_dir
       ) do
    {before_status, before_line, before_commands} =
      run_hook(:sh_before, sh_before, dry_run, project_dir, template_path, out_path)

    if before_status == :failed do
      {before_line, out_path, nil, :sh_before_failed, before_commands}
    else
      {main_line, outcome} =
        actuate!(
          mode,
          content,
          bindings,
          out_path,
          template_path,
          write_opts,
          dry_run,
          inject_spec
        )

      if outcome in [:written, :injected] do
        {after_status, after_line, after_commands} =
          run_hook(:sh_after, sh_after, dry_run, project_dir, template_path, out_path)

        hook_status = if after_status == :failed, do: :sh_after_failed
        line = [before_line, main_line, after_line] |> Enum.reject(&is_nil/1) |> Enum.join("; ")

        {line, out_path, outcome, hook_status, before_commands ++ after_commands}
      else
        line = [before_line, main_line] |> Enum.reject(&is_nil/1) |> Enum.join("; ")
        {line, out_path, outcome, nil, before_commands}
      end
    end
  end

  # Real per-hook dispatch: `:absent` (cmd is `nil`, nothing to do -- the
  # overwhelmingly common case), `:planned` (`--dry-run`, prints the exact
  # `"planned: run #{label}: <cmd>"` line this module's moduledoc documents,
  # `GgenIgniter.ShellHook.run/3` never called), `:ok` (real command, real
  # zero exit), or `:failed` (real nonzero exit or a real
  # `GgenIgniter.ShellHook` timeout). `commands` is `[]` for `:absent`/
  # `:planned` (no real invocation happened -- nothing to append to
  # `GgenIgniter.Receipt.commands`) or a one-element list for a REAL
  # invocation (`:ok` or `:failed` alike -- "every invocation, success or
  # failure" per this module's moduledoc).
  @spec run_hook(
          :sh_before | :sh_after,
          String.t() | nil,
          boolean(),
          String.t(),
          String.t(),
          String.t() | nil
        ) ::
          {:absent | :planned | :ok | :failed, String.t() | nil, [map()]}
  defp run_hook(_label, nil, _dry_run, _project_dir, _template_path, _out_path),
    do: {:absent, nil, []}

  defp run_hook(label, cmd, true, _project_dir, _template_path, _out_path) do
    {:planned, "planned: run #{label}: #{cmd}", []}
  end

  defp run_hook(label, cmd, false, project_dir, template_path, out_path) do
    started = System.monotonic_time(:millisecond)

    case ShellHook.run(cmd, project_dir) do
      {:ok, output} ->
        duration = System.monotonic_time(:millisecond) - started

        {:ok, "ran #{label}: #{cmd}",
         [command_entry(label, cmd, template_path, out_path, 0, output, duration, "ok")]}

      {:error, {:sh_exit, code, output}} ->
        duration = System.monotonic_time(:millisecond) - started

        {:failed, "#{label} failed (exit #{inspect(code)}): #{cmd}\n#{output}",
         [command_entry(label, cmd, template_path, out_path, code, output, duration, "failed")]}

      {:error, :sh_timeout} ->
        duration = System.monotonic_time(:millisecond) - started

        {:failed, "#{label} timed out after #{ShellHook.default_timeout_ms()}ms: #{cmd}",
         [command_entry(label, cmd, template_path, out_path, nil, nil, duration, "timeout")]}
    end
  end

  # `GgenIgniter.Receipt.commands`'s entry shape for a `sh_before:`/
  # `sh_after:` invocation -- see `GgenIgniter.Receipt`'s moduledoc, which
  # documents this exact shape (the first real production call site to
  # populate this field).
  defp command_entry(label, cmd, template_path, target, exit_code, output, duration_ms, status) do
    %{
      "kind" => Atom.to_string(label),
      "cmd" => cmd,
      "template_path" => template_path,
      "target" => target,
      "exit_code" => exit_code,
      "output" => output,
      "duration_ms" => duration_ms,
      "status" => status
    }
  end

  # Validates `--on-stale` up front (regardless of whether reconciliation
  # actually applies to this run's mode -- cheap to check, and a typo here
  # should never silently fall back to the default). `nil` (flag omitted)
  # resolves to the safest default, `:refuse`, per this task's own design:
  # silent orphaning must never be the default, and silent deletion must
  # never be the default either.
  @spec resolve_on_stale!(String.t() | nil) :: :refuse | :prune | :preserve
  defp resolve_on_stale!(nil), do: :refuse
  defp resolve_on_stale!("refuse"), do: :refuse
  defp resolve_on_stale!("prune"), do: :prune
  defp resolve_on_stale!("preserve"), do: :preserve

  defp resolve_on_stale!(other) do
    raise ArgumentError,
          "--on-stale must be \"refuse\", \"prune\", or \"preserve\", got: #{inspect(other)}"
  end

  defp refuse_stale_message(stale, recipe_key) do
    stale_list = stale |> Enum.sort() |> Enum.map_join("\n", &"  - #{&1}")

    "ggen_igniter: refusing to sync -- #{MapSet.size(stale)} stale output path(s) from a " <>
      "PRIOR run of this recipe (#{inspect(recipe_key)}) are not written by this run " <>
      "(a rename or removal upstream in the ontology, most likely):\n\n#{stale_list}\n\n" <>
      "Nothing was written this run (complete reconciliation or refusal before any " <>
      "partial actuation -- never a silent orphan). Re-run with --on-stale prune to " <>
      "really delete the stale path(s) above, or --on-stale preserve to leave them on " <>
      "disk (with a warning) and proceed."
  end

  # Non-dry-run: really applies `on_stale`'s policy to a (possibly empty)
  # `stale` set. `:refuse` is a no-op here -- by the time this runs, a
  # non-empty `stale` under `:refuse` has already raised above, so `stale` is
  # guaranteed empty whenever `:refuse` reaches this function.
  defp apply_stale_policy!(:refuse, _stale), do: :ok

  defp apply_stale_policy!(:preserve, stale) do
    if MapSet.size(stale) > 0 do
      Mix.shell().error(preserve_warning(stale))
    end

    :ok
  end

  defp apply_stale_policy!(:prune, stale) do
    for {path, outcome} <- Manifest.prune!(MapSet.to_list(stale)) do
      case outcome do
        :pruned -> Mix.shell().info("pruned: #{path}")
        :absent -> Mix.shell().info("pruned (already absent): #{path}")
      end
    end

    :ok
  end

  # `--dry-run` preview: `:refuse` needs nothing further here (a non-empty
  # `stale` under `:refuse` already raised above, dry-run or not -- a dry run
  # previews a REAL decision, including a real refusal, it does not suppress
  # one). `:prune`/`:preserve` print the same "planned: ..." convention every
  # other dry-run notice in this task uses, without touching disk or the
  # manifest file.
  defp preview_stale!(:refuse, _stale), do: :ok

  defp preview_stale!(:preserve, stale) do
    if MapSet.size(stale) > 0 do
      Mix.shell().info(
        "planned: preserve #{MapSet.size(stale)} stale path(s) (see --on-stale preserve):\n" <>
          (stale |> Enum.sort() |> Enum.map_join("\n", &"  - #{&1}"))
      )
    end

    :ok
  end

  defp preview_stale!(:prune, stale) do
    for path <- Enum.sort(stale), do: Mix.shell().info("planned: prune #{path}")
    :ok
  end

  defp preserve_warning(stale) do
    stale_list = stale |> Enum.sort() |> Enum.map_join("\n", &"  - #{&1}")

    "ggen_igniter: WARNING -- #{MapSet.size(stale)} stale output path(s) from a prior run of " <>
      "this recipe were NOT written this run and are being preserved untouched on disk " <>
      "(--on-stale preserve):\n\n#{stale_list}\n"
  end

  # `out_path` arrives ALREADY EEx-rendered (computed once, up front, in
  # `igniter/1`'s `renders` list -- see that function's comments for why:
  # the reconciliation manifest needs every row's real output path BEFORE any
  # actuation happens, and rendering it a second time here would both be
  # redundant and -- since `--out`/`to:` is itself an arbitrary EEx template,
  # same trust boundary as the template body -- a real behavior change for a
  # pathological `--out` template with a side effect. Exactly one render per
  # row, same as before this module existed.
  #
  # Returns `{notice_line, outcome_or_nil}` -- the raw `Actuate` outcome atom
  # is threaded back to the caller so the reconciliation manifest can tell a
  # path THIS run actually wrote/reconfirmed (`:written`/`:unchanged`) apart
  # from one it deliberately left alone (`:skipped_exists`/`:skipped_match`,
  # from `--unless-exists`/`--skip-if`). A path this run only ever SKIPPED
  # must never be recorded as manifest-owned: if it were, a later rename that
  # drops that row would flag it stale, and `--on-stale prune` would delete a
  # file this pack never actually wrote a byte of -- exactly the same
  # destructive-ownership mistake `inject: true` targets are excluded from
  # for. `:eval` never writes to disk at all, so it always reports `nil`.
  #
  # `inject_spec` is `nil` for the ordinary (non-`inject:`) write path, or
  # `{marker, insert_mode, inject_opts}` (from `resolve_injection!/1`) when
  # the template's frontmatter has `inject: true` -- these are separate
  # clauses, not an `if` inside one clause, so each actuation path's real
  # behavior stays independently readable.
  defp actuate!(:file, content, _bindings, out_path, _template_path, write_opts, dry_run, nil) do
    {:ok, outcome} = Actuate.write_file!(out_path, content, write_opts)
    {notice_line(outcome, out_path, dry_run), outcome}
  end

  defp actuate!(
         :file,
         content,
         _bindings,
         out_path,
         _template_path,
         _write_opts,
         dry_run,
         {marker, insert_mode, inject_opts}
       ) do
    {:ok, outcome} =
      Actuate.inject_content!(
        out_path,
        marker,
        Injection.strip_single_trailing_newline(content),
        insert_mode,
        Keyword.put(inject_opts, :dry_run, dry_run)
      )

    # The REAL `inject_content!/5` outcome (`:injected`/`:unchanged`) is
    # returned here -- NOT hardcoded `nil` as before `sh_after:` wiring
    # needed to distinguish "a real splice just happened" from "already
    # spliced in, no-op". This is safe: `igniter/1`'s manifest-tracking
    # `outputs` computation is already gated on `reconcile?`
    # (`mode == :file and inject_spec == nil`), never on this outcome
    # value, so an inject target still never becomes manifest-owned --
    # unchanged behavior, just no longer discarding real information this
    # caller (`actuate_row!/11`) now needs.
    {notice_line(outcome, out_path, dry_run), outcome}
  end

  defp actuate!(
         :eval,
         _content,
         _bindings,
         _out_path,
         template_path,
         _write_opts,
         true,
         _inject_spec
       ),
       do: {"planned: evaluate #{template_path} (mode: eval)", nil}

  defp actuate!(
         :eval,
         content,
         bindings,
         _out_path,
         template_path,
         _write_opts,
         false,
         _inject_spec
       ) do
    {:ok, value} = Actuate.eval_code!(content, bindings)
    {"evaluated #{template_path} -> #{inspect(value)}", nil}
  end

  # `strip_single_trailing_newline/1` and `resolve_injection!/1` (plus the
  # `match_spec_to_marker!/2`/`build_regex_marker/1` conversion they depend
  # on) now live in `GgenIgniter.Injection`, shared verbatim with
  # `GgenIgniter.Reactors.ReconcileReactor` -- see that module's moduledoc.

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
