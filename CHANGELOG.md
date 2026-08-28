# Changelog

## v26.8.27

Template frontmatter execution modes, plus a new opt-in end-to-end tier.

- **AR-10: `inject: true` now gets real Reactor admission-gate coverage via
  `mix ggen_igniter.sync`** -- `Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3`
  used to refuse delegating ANY frontmatter-bearing template to
  `GgenIgniter.Reactors.ReconcileReactor.run/1`, falling back to the
  pre-Reactor inline pipeline -- which has no duplicate-output-path or
  path-escape admission checks at all. Since `inject: true` can only be
  expressed via frontmatter, every `inject: true` write was silently
  exempt from those real checks. `ReconcileReactor` itself already fully
  implements `operation: :inject` construction/dispatch (real, tested by
  `test/ggen_igniter_reconcile_reactor_inject_test.exs`); the gap was only
  the CLI's own dispatch guard being broader than the pipeline's real
  capability. Fixed by narrowing that guard to the one frontmatter feature
  `ReconcileReactor` genuinely does not resolve (inline `sparql:` query
  text) and threading frontmatter `to:`/`unless_exists:`/`skip_if:` into
  the resolved reconcile options explicitly. `mode: eval` frontmatter
  templates are deliberately excluded from this widening (a real,
  separately-tracked `ReconcileReactor` `:render` crash for `:eval`
  targets, independent of this change -- see `docs/status.md`). See
  `test/ggen_igniter_sync_inject_reactor_admission_test.exs` for the real,
  CLI-subprocess proof: an `inject: true` write now genuinely routes
  `"(via reactor)"`, and an `inject: true` write escaping the authorized
  project root is refused the exact same real way an ordinary `mode: file`
  write already was.

- **`mode: eval` frontmatter execution mode** (`GgenIgniter.Frontmatter.split_template/1`,
  `GgenIgniter.Actuate.eval_code!/2`) -- a template's `---`-fenced YAML header
  can now carry `mode: eval` (or `--mode eval` on the CLI, which always wins
  over the frontmatter value) alongside the existing `mode: file` default.
  Under `mode: eval`, the rendered template body is never written to disk at
  all: instead it is real Elixir source, evaluated in-process via
  `Code.eval_string/2` using the exact same `bindings` keyword list the
  template body renders with, so eval'd code can reference `module_name`, a
  single-row query's flattened columns, or a `--for-each` row's columns just
  like the template body itself can. `eval_code!/2` returns `{:ok, value}`
  (the real, unwrapped return value of the evaluated code) and turns any
  `CompileError`/`SyntaxError`/`TokenMissingError` into a clear `RuntimeError`
  naming the real failure rather than letting the raw exception struct
  surface. `--out`/`to:` is not required in this mode, and
  `--unless-exists`/`--skip-if` do not apply. This is a deliberate, disclosed
  arbitrary-code-execution capability -- ontology/RDF-driven data becomes
  literally-executed Elixir code under `mode: eval` -- at the same trust
  boundary an EEx template body already is (an EEx template can already run
  arbitrary Elixir inside `<%= %>` during rendering).
- **Template frontmatter parsing (hygen/ggen parity)** -- `mix ggen_igniter.sync`
  now recognizes a `---\n...\n---\n` YAML header on the first line of a
  `--template` file, mirroring real hygen and the real Rust ggen's own
  `ggen-engine/src/template.rs` `Frontmatter` convention. The header supplies
  defaults for `to:` (equivalent to `--out`), `sparql:` (named inline query
  text, not file paths), `for_each:`, `skip_if:` (literal-string form),
  `unless_exists:`, and the new `mode:` field, so a self-contained template
  can be rendered with just `--template`/`--ontology` and no repeated
  `--out`/`--for-each`/`--query` flags -- exactly like `hygen generate <name>`
  needs no routing flags because the template's own header carries them. Any
  explicit CLI flag always overrides the same-named frontmatter field, and a
  template with no `---` header behaves exactly as before this feature
  existed.
- **`mix e2e` task** (aliased in `mix.exs` to `run test/e2e/run_e2e.exs`,
  separate from and not run by plain `mix test`) -- a real, sequential,
  multi-stage lifecycle test (`test/e2e/lifecycle_test.ex`) that scaffolds a
  fresh, throwaway Ash+Phoenix application (via real `mix archive.install` +
  `mix igniter.new`, no mocking) and drives it through resource creation,
  attribute addition, a relationship, a custom action, a real
  `AshPhoenix.Form`, a real `mix ash_phoenix.gen.live`-generated LiveView, and
  a rename -- all via real `mix ggen_igniter.sync` subprocess runs against the
  `test/fixtures/ash-lifecycle-pack/` fixture pack -- to prove
  ggen_igniter-generated code stays consistent across real Ash, AshPhoenix,
  and Phoenix APIs as an application evolves. This tier requires network
  access (archive installs, dependency fetches) and takes several minutes to
  run; it is intentionally not part of `mix test` and must be invoked
  explicitly with `mix e2e`.

## v26.8.26

Packaging pass: real hex.pm package metadata (`package:` entry in `mix.exs`),
MIT `LICENSE`, `.formatter.exs`, and this changelog/README pass. No source
changes to `lib/` or `native/` in this release beyond what v0.1.0's six
commits already established below.

## v0.1.0 (pre-release history, commits `d94cedc`..`f70d7ec`)

- **`d94cedc`** — Bootstrapped `ggen_igniter`: a pure-Elixir
  ontology -> SPARQL -> EEx -> Igniter pipeline (`GgenIgniter.Ontology`,
  `GgenIgniter.Query`, `GgenIgniter.Render`, `GgenIgniter.Actuate`, and the
  `mix ggen_igniter.sync` task), with write-safety guards
  (`unless_exists`/`skip_if`/idempotent no-op) mirroring the real Rust
  ggen's `ggen-engine/src/write.rs` decision table.
- **`312ac08`** — Added a cross-repo composition test proving the pipeline
  against a real external pack (`ash_r2rml`), not just in-repo fixtures.
- **`549cec2`** — Added a real QLever-backed alternate SPARQL engine
  (`GgenIgniter.Query.Qlever`), demonstrating that a known `sparql` hex
  package 0.3.12 bug (`FILTER NOT EXISTS` + `BIND` inside `UNION`) is
  engine-specific rather than a query-shape limitation.
- **`279dab7`** — Fixed manifest graph splitting for Gno's Manifest Graph
  Expansion (MGE).
- **`46a4d11`** — Wired `GgenIgniter.Query.Qlever` into
  `mix ggen_igniter.sync` as `--engine qlever` (real HTTP against an
  already-running QLever endpoint, `--store-id` required).
- **`f70d7ec`** — Added the `--pack` convention
  (`priv/ggen/<pack-name>/{ontology.ttl,gates/*.rq,templates/*.eex}`,
  `GgenIgniter.Pack`) and the `mix ggen_igniter.doctor` diagnostic task
  (fixed checklist of real environment/dep/pack-shape/SPARQL-syntax checks).

### Also present in this working tree (uncommitted-history features exercised
by the current test suite and moduledocs, folded into this release)

- **`--engine oxigraph`** — a real native [oxigraph](https://github.com/oxigraph/oxigraph)
  query engine via a Rustler NIF (`native/ggen_graph_nif`,
  `GgenIgniter.Native.GraphNif`, `GgenIgniter.Query.Oxigraph`) over ggen's
  `ggen-graph-wasm` `OxigraphEngine`, as a third alternative to `sparql` and
  `qlever` for queries that trip the pure-Elixir `sparql` package's
  `FILTER NOT EXISTS`/`UNION` limitation.
- **`--for-each NAME`** — multi-row fan-out mirroring the real Rust ggen's
  `for_each:` frontmatter field: renders the template once per row of a
  named query result and writes each rendering to its own output path
  (`--out` itself rendered as an EEx template per row).
- **`--dry-run`** — previews planned writes/skips without touching disk.
- **Marketplace pack fetch** (`GgenIgniter.Pack.fetch_pack!/2`) — resolves
  `github:owner/repo[@ref]` (print-only checksum, no verification available
  from GitHub's archive endpoint) and `hex:name[@version]` (fail-closed
  SHA-256 verification against hex.pm's published checksum) pack sources.
- **`GgenIgniter.Frontmatter`** — an Elixir struct mirroring the real Rust
  `ggen::Frontmatter` field-for-field (`to`, `sparql`, `for_each`,
  `construct`, `inject`, `before`/`after`, `at_line`, `skip_if`,
  `unless_exists`, `unattended_write_eligible`, `force`), and
  `GgenIgniter.PackManifest` mirroring `pack.toml` shape, so the Elixir and
  Rust/WASM sides of the templating engine describe the identical field set.
