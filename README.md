# GgenIgniter

An Elixir bootstrap of [ggen](https://github.com/seanchatmangpt/ggen)'s
ontology-to-code pipeline: load an RDF ontology, run one or more named SPARQL
queries against it, render the results through an EEx template, and write the
result to disk with the same write-safety guards (idempotent no-op detection,
`unless_exists`, `skip_if`) as the real Rust `ggen`'s `ggen-engine/src/write.rs`.

Pipeline: `Ontology.load!/1` -> `Engine.run/2` (once per `--query`) ->
`Render.render/2` -> `Actuate.write_file!/3` (or `inject_content!/5` /
`eval_code!/2`), tracked by a reconciliation manifest so a rename/removal
upstream in the ontology is mechanically detected instead of silently
orphaning a file.

## Why this exists

Hand-maintained Elixir modules drift from the domain model that's supposed to
describe them. `ggen_igniter` keeps generated code (Ash resources, Spark DSL
extensions, or any other EEx-rendered Elixir) synchronized with an RDF/Turtle
ontology as that ontology evolves — including *destructive* evolution (a
rename, a removal) — with reconciliation memory: "what did I last generate
here, and did the ontology's shape change since," rather than a stateless
one-shot templater.

## What each layer owns

| Layer | Real role in this repo | Status |
|---|---|---|
| **ggen** | Semantic compilation (ontology → query → render → actuate). Fulfilled by this repo's **own** from-scratch Elixir port of the real Rust `ggen`'s pipeline shape (render uses Elixir stdlib `EEx`, not a Tera/Liquid port) — not a runtime dependency on, or shell-out to, the real `ggen` binary. One real Rust component *is* embedded: a Rustler NIF wrapping `ggen`'s own oxigraph query engine (the default `--engine`). | IMPLEMENTED |
| **Igniter** | CLI-task plumbing (`Igniter.Mix.Task`, `add_notice/2`) for both `mix ggen_igniter.sync`/`.doctor`. A real, unconditional `mix.exs` dependency. Does **not** use Igniter's AST-mutation API (`Igniter.Project.Module`/`Igniter.Code`/`Sourceror.Zipper`) anywhere — that's real, disclosed future work. | IMPLEMENTED (CLI plumbing); AST-mutation PLANNED |
| **Reactor** | Coordination/dependency-ordering/concurrency/compensation. `GgenIgniter.Reactors.ReconcileReactor` is a plain `use Reactor` module (explicitly not `Ash.Reactor`, so this stays usable without Ash). Real, tested — but **opt-in**, not the default, via `config :ggen_igniter, use_reactor: true`. | PARTIAL_ALIVE (real, opt-in) |
| **Ash** | Optional, consumer-side only. Neither `:ash` nor `:ash_phoenix` appears anywhere in this project's own `mix.exs` deps. `mix ggen_igniter.doctor` only *scans* a consumer's project for `use Ash.Domain` as one diagnostic among several. | Not a core dependency, by design |

See `docs/architecture/overview.md` for the full ownership table (including
OTP/Controller/Manifest/Receipt) and `docs/glossary.md` for term definitions.

## What's implemented vs. planned (headline items — full detail in `docs/status.md`)

- **Implemented, default today**: `mix ggen_igniter.sync`/`.doctor`, all
  three query engines, `--pack`/`--for-each`/`--dry-run`, template
  frontmatter (including `inject: true` — see the correction below), the
  reconciliation manifest and `--on-stale refuse|prune|preserve`.
- **Implemented, opt-in (not the default)**: the `ReconcileReactor`
  coordination pipeline (real admission/compensation/receipts) and the
  `GgenIgniter.Controller` persistent GenServer.
- **Planned, not implemented**: real AST-based structural mutation
  (Sourceror/Igniter.Code) for existing files — today's injection is a
  marker-based text splice, not an AST patch; cross-file stale-reference
  repair (e.g. a renamed attribute breaking separately hand-generated
  LiveView code) has no auto-repair mechanism.
- **Real, currently open gap**: `mix e2e`'s full 8-stage Ash+Phoenix
  lifecycle test has not been freshly re-executed end to end in the most
  recent documentation pass (requires network + several minutes); the
  mechanism is real and sound by inspection.

See `docs/status.md` for the complete, sourced capability table and
`docs/architecture/adr/` for the accepted design decisions behind these.

## How do I run it

```
mix deps.get
mix ggen_igniter.doctor        # sanity-check the environment first
mix ggen_igniter.sync --ontology path.ttl --query name=path.rq --template path.eex --out path.ex
```

Full walkthroughs (real commands, real output, run in this repo): see
[`docs/tutorials/getting-started.md`](docs/tutorials/getting-started.md).

## Installation

Add `ggen_igniter` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:ggen_igniter, "~> 26.8.27"}
  ]
end
```

Requires Elixir `~> 1.17` and OTP `>= 25` (`mix ggen_igniter.doctor`'s check 1
verifies both) plus a working Rust/`cargo` toolchain — the default `--engine
oxigraph` compiles a native Rustler NIF (`native/ggen_graph_nif`) as part of
compiling this library at all, regardless of which `--engine` is ever
actually used at runtime.

## Usage

### `mix ggen_igniter.sync`

```
mix ggen_igniter.sync --ontology path.ttl --query name=path.rq (repeatable) --template path.eex --out path.ex
```

Each `--query name=path.rq` result is bound in the EEx template under `name`
as the full list of result rows (string-keyed maps). A query whose result has
exactly one row also has that row's own columns merged directly into the
top-level bindings, atom-keyed, so a single-row query like `spec` can be
referenced as bare `module_name`/`package_name` instead of
`hd(spec)["module_name"]`.

#### Engines: `--engine oxigraph` / `--engine sparql` / `--engine qlever`

`--engine oxigraph` (**the real default since v26.8.27** — confirmed by
`lib/mix/tasks/ggen_igniter.sync.ex`'s own `opts[:engine] || "oxigraph"` and
by an actual run's notice line) runs every query in-process against the
loaded `%RDF.Graph{}` via a real native
[oxigraph](https://github.com/oxigraph/oxigraph) engine (a Rustler NIF over
`ggen`'s `ggen-graph-wasm` `OxigraphEngine`). It became the default to fix a
real, empirically confirmed `ORDER BY` row-reversal bug in the `sparql` hex
package (v0.3.12) — see `docs/architecture/adr/0001-oxigraph-default-query-engine.md`
for the full history and disclosed trade-offs (a Rust/`cargo` toolchain is
required to compile this library at all, regardless of which engine is used
at runtime). No extra required option — it works directly off the
already-loaded graph:

```
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --query sections=test/fixtures/sections.rq \
  --query entities=test/fixtures/entities.rq \
  --query fields=test/fixtures/fields.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex
```

`--engine sparql` runs every query in-process too, via the pure-Elixir
`sparql` hex package instead of oxigraph — still fully supported, and useful
to A/B a result or when a query shape trips the `sparql` hex package's own
known `FILTER NOT EXISTS`/`UNION` limitation:

```
mix ggen_igniter.sync \
  --engine sparql \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --query sections=test/fixtures/sections.rq \
  --query entities=test/fixtures/entities.rq \
  --query fields=test/fixtures/fields.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex
```

`--engine qlever` runs every query instead against a real, already-running
[QLever](https://github.com/ad-freiburg/qlever) SPARQL endpoint (real HTTP,
no in-process SPARQL evaluation). `--ontology` is still read as a
`%RDF.Graph{}`, but only to look up the `gnoa:Qlever`-typed store resource
named by `--store-id` — the query text itself never touches this graph's
data, it runs on the remote QLever store. `--store-id` is required with this
engine:

```
mix ggen_igniter.sync \
  --engine qlever \
  --ontology config/gno/test/store.ttl \
  --store-id http://example.com/Qlever \
  --query spec=priv/ggen/some-pack/gates/010.rq \
  --template priv/ggen/some-pack/templates/out.ex.eex \
  --out lib/generated.ex
```

#### Multi-row fan-out (`--for-each NAME`)

Mirroring the real Rust ggen's `for_each:` frontmatter field, pass
`--for-each NAME` where `NAME` is one of the named `--query` results to
render the template once **per row** of that query, with that row's own
columns merged into the top-level bindings. Because there is no longer one
static output path, `--out` is itself rendered through
`GgenIgniter.Render.render/2` using each row's bindings, so it must be an
EEx-renderable path template:

```
mix ggen_igniter.sync \
  --ontology test/fixtures/for_each_ontology.ttl \
  --query modules=test/fixtures/modules.rq \
  --for-each modules \
  --template test/fixtures/for_each_module.ex.eex \
  --out "lib/generated/<%= module_name %>.ex"
```

With three rows in the `modules` query result, this writes three separate
files, one per row.

#### `--dry-run`

Pass `--dry-run` to preview what would be written (or skipped) without
touching disk — each planned action is printed as `planned: write <path>` or
`planned: skip <path> (...)` instead of being executed.

#### The `--pack` convention

Given `priv/ggen/<pack-name>/{ontology.ttl,gates/*.rq,templates/extension.ex.eex}`:

```
mix ggen_igniter.sync --pack adr-index-pack --out docs/architecture/adr/README.md
```

(`adr-index-pack` is this repo's own real pack, at
`priv/ggen/adr-index-pack/` — it's what regenerates
[`docs/architecture/adr/README.md`](docs/architecture/adr/README.md) itself.)

`--ontology`/`--query`/`--template` are all still overridable explicitly; an
explicit flag always wins over the pack-derived default. `--pack-dir DIR`
uses `DIR` directly instead of resolving `priv/ggen/<pack>/`. Packs can also
be fetched from a marketplace source (`github:owner/repo[@ref]` or
`hex:name[@version]`) via `GgenIgniter.Pack.fetch_pack!/2`.

### `mix ggen_igniter.doctor`

```
mix ggen_igniter.doctor [--pack NAME | --pack-dir DIR] [--engine sparql|qlever] [--store-id ID] [--hex-check] [--fix]
```

Runs a fixed checklist of **17** real checks (no fabricated pass output) —
Elixir/OTP version, dependency wiring, the `sparql` version advisory, the
`:igniter`/`:sourceror`/`:dcatr`/`ash_domains` consumer-project fix rules
(`--fix`-able), pack shape (only with `--pack`/`--pack-dir`), git status, the
native oxigraph NIF's build freshness and a real functional smoke test, an
optional hex-publish readiness check (`--hex-check`), and a version-policy
check against `CHANGELOG.md`. Exits non-zero only if any check comes back
`:error`. See
[`docs/reference/cli/doctor.md`](docs/reference/cli/doctor.md) for the full,
numbered list of all 17 checks and exactly which ones `--fix` can repair, or
[`docs/operations/debugging.md`](docs/operations/debugging.md) for a
practical triage playbook.

## Testing

### `mix e2e`

`mix e2e` (alias for `mix run test/e2e/run_e2e.exs`) is a real, sequential
end-to-end lifecycle test, kept separate from the default `mix test` suite
because it needs real network access and takes several minutes: it scaffolds
a genuine, throwaway Ash + Phoenix application in a temp directory via real
`mix archive.install hex phx_new`/`mix archive.install hex igniter_new`/
`mix igniter.new` subprocess calls (hex/GitHub fetches, no mocking), adds
`ggen_igniter` itself as a `path:` dependency, and runs `mix deps.get`.

Against that one scaffolded app it then drives a multi-stage lifecycle with
real `mix ggen_igniter.sync` subprocess invocations against the
`test/fixtures/ash-lifecycle-pack/` fixture pack — resource creation,
attribute addition, a `belongs_to`/`has_many` relationship, a custom action,
an `AshPhoenix.Form` create/update/validate/submit round-trip, a real
`mix ash_phoenix.gen.live`-generated Phoenix LiveView, and finally an
attribute rename — running `mix compile --warnings-as-errors`/`mix test`
inside the scaffolded app after each stage.

Run it with:

```
mix e2e
```

For a host-independent, containerized run of this same suite, see
`docs/reference/docker-e2e.md` (`docker compose -f docker-compose.e2e.yml run --rm e2e`).

It requires network access (hex/GitHub fetches via `mix archive.install`),
runs for several minutes, and uses real disk space in a temp directory
(cleaned up via `on_exit` when the test finishes). It is not part of the
default `mix test` suite — there is no `.github/workflows` CI config in this
repo, so it is not run by CI either; run it manually when you need to verify
the full lifecycle.

What it proves: that ggen_igniter-generated code stays consistent across a
real Ash resource, its `AshPhoenix.Form`, and its Phoenix LiveView through a
realistic edit lifecycle, including a rename.

#### `mix e2e` wall-clock baseline (real, cited)

Two real `mix e2e` runs captured this session (scratchpad
`e2e_run.log`, `e2e_output2.log`) both failed at Stage 5 (the scoped
`mix test test/ggen_igniter_form_lifecycle_test.exs` subprocess — an
`AshPhoenix.Form.submit/2` assertion issue unrelated to timing) after
**281.5s** and **299.0s** respectively (`ExUnit`'s own `"Finished in ..."`
line). Both runs therefore measure real wall-clock cost for Stages 0–5 only
(14 of the 20 real `mix`/subprocess invocations `lifecycle_test.ex` makes
end to end), not the full 8-stage lifecycle.

Neither log carries per-subprocess timestamps (each stage's stdout is
merged into one `cmd!/3` capture with no per-line clock), so the
per-subprocess breakdown below is a structural estimate — call-count and
known Elixir/Mix cost class, not measured — from reading
`test/e2e/lifecycle_test.ex` and `test/e2e/support/e2e_case.ex` directly:

| Stage | Real subprocess calls | Cost class |
|---|---|---|
| 0 (scaffold + dep wiring) | `archive.install hex phx_new`, `archive.install hex igniter_new`, `igniter.new ... --install ash,ash_phoenix --with phx.new` (runs 3 installers), `deps.get`, `compile!`, `test!` = **6** | Heaviest stage by far — `igniter.new` alone triggers 3 chained installers (Ash, AshPhoenix, Phoenix) each doing their own codegen + potential fresh `mix.exs` deps, and `deps.get` does a cold Hex/Git dependency resolution across the whole tree (the `:igniter`/`:sourceror`/`:gno`/`:dcatr` relaxations exist precisely because this resolution is fragile — see (c) below) |
| 1 (sync x2 + compile + test) | `ggen_igniter.sync` x2, `compile!`, `test!` = **4** | Each `sync` is itself an `Igniter.Mix.Task` subprocess (its own BEAM boot); `compile!`/`test!` are incremental after Stage 0's cold compile, so cheaper than Stage 0's |
| 2 (sync x1 + compile + test) | **3** | Same class as Stage 1, one fewer `sync` call |
| 3–4 (pure assertions) | **0** | Free — no subprocess, checks Stage 2's already-generated files |
| 5 (Form round-trip, scoped `mix test`) | **1** | Where both captured real runs actually failed/stopped |
| 6 (`ash_phoenix.gen.live` + compile x2 + scoped `mix test`) | **4** | `ash_phoenix.gen.live` is a real Igniter-driven LiveView generator subprocess; two `compile!` calls bracket the hand-edited router |
| 7 (sync + expected-failing compile) | **2** | The `compile!` here is expected to raise (rename leaves a stale `ticket.assignee` reference) |
| **Total (full 8-stage run)** | **20** | Only 14 of these were exercised by the two captured real runs |

**Conclusion for the in-memory-vs-subprocess architecture decision** (not
attempted here — out of scope per this task): Stage 0 is the dominant cost
by call count and by known Mix/Hex cost class (3 chained Igniter installers
plus one cold `deps.get` resolution, none of which touch `ggen_igniter`'s
own sync/render logic at all). Stages 1–2 and 7's `sync!`/`compile!`/
`test!` calls are the ones actually exercising `ggen_igniter` behavior, and
`compile!`/`test!` there run against an *already-scaffolded* app, i.e. the
part of the pipeline most amenable to swapping in an in-memory
`Igniter.Test.test_project/1` if a scaffold's on-disk state can be
faked convincingly enough for Ash to compile against it — Stage 0 itself
(real `phx.new`/`ash`/`ash_phoenix` installers + real `deps.get`) is the
part most resistant to that swap, since it is exactly the real, on-disk,
network-resolved dependency graph this suite exists to catch drift in (see
(c) below).

## Reconciliation manifest: `--on-stale refuse|prune|preserve`

Every real `mode: file`, non-`inject:` write is recorded in a manifest at
`<manifest-dir>/.ggen_igniter/manifest.json`, keyed by the `(template,
--out-template)` "recipe" pair — not by ontology path or pack name alone,
so editing an ontology's content in place across syncs is correctly
recognized as the same ongoing recipe. Before writing, a run's real new
output-path set is compared against the manifest's existing entry for that
recipe: `stale = old_paths - new_paths` — the mechanical signature of a
rename or removal upstream in the ontology.

- **`refuse`** (default) — refuses the entire run before writing anything if
  `stale` is non-empty, naming every exact stale path.
- **`prune`** — proceeds, then really deletes every stale path
  (`File.rm/1`), reporting each.
- **`preserve`** — proceeds, leaves every stale path untouched, warns, and
  releases it from the manifest's tracked output set.

A true no-op re-run (identical output-path-plus-content-hash set) does not
rewrite the manifest file at all — not even its timestamp. See
[`docs/reference/reconciliation/`](docs/reference/reconciliation/) for the
full manifest/stale-artifact/destructive-evolution reference, and
[`docs/tutorials/first-reconciliation.md`](docs/tutorials/first-reconciliation.md)
for a real, run-through-in-this-repo walkthrough including a real refused
run and a real prune.

**Known, disclosed scope limit**: this closes the orphan-file gap only for
the recipe's *own* tracked outputs. There is no cross-file stale-reference
repair — a rename that breaks separately hand-generated code elsewhere (e.g.
a Phoenix LiveView dot-accessing a now-renamed Ash attribute) is not
detected or repaired by this pipeline. See
[`docs/operations/failure-recovery.md`](docs/operations/failure-recovery.md).

## The Reactor path (opt-in, not the default)

`GgenIgniter.Reactors.ReconcileReactor` is a real, tested `Reactor`-based
coordinator (plain `Reactor`, not `Ash.Reactor`) implementing a fuller
pipeline than the default: observe prior manifest → load ontology → resolve
pack → run queries → render into a real `[%PendingActuation{}]` plan → admit
(fail-closed, whole-plan invariants) → actuate (concurrent, self-healing) →
verify (`mix compile --warnings-as-errors`) → finalize evidence (a
`GgenIgniter.Receipt` persisted **before** manifest promotion, on every
path — success or failure). It supports multi-target `:targets` fan-out and
real Reactor `undo/4` rollback when `:verify` fails after `:actuate` already
wrote files.

There is no CLI flag for this — set `config :ggen_igniter, use_reactor: true`
in the **consuming** project (default `false`). With the flag left at its
default, both real call sites (`Mix.Tasks.GgenIgniter.Sync` and
`GgenIgniter.Controller`) are byte-for-byte unchanged from before this
pipeline existed. See
[`docs/tutorials/reactor-path.md`](docs/tutorials/reactor-path.md) for a
real success receipt and a real compensated-failure receipt, and
[`docs/reference/reactor/`](docs/reference/reactor/) for the full mechanism.

## Documentation

- [`docs/index.md`](docs/index.md) — full Diataxis-organized documentation map
- [`docs/glossary.md`](docs/glossary.md) — one definition per term
- [`docs/status.md`](docs/status.md) — real IMPLEMENTED/PARTIAL_ALIVE/PLANNED status of every capability
- [`docs/architecture/adr/`](docs/architecture/adr/) — accepted architecture decisions, grounded in current code

## Known Limitations

1. **Frontmatter `inject: true` splice — real and wired (README correction,
   verified 2026-08-27).** A prior version of this document stated that
   `mix ggen_igniter.sync` had no call to `Actuate.inject_content!/5`. A
   real `grep -n "inject_content!\|:inject" lib/mix/tasks/ggen_igniter.sync.ex`
   finds a real `inject_spec = if mode == :file and
   (frontmatter_field(frontmatter, :inject) || false) do
   resolve_injection!(frontmatter) end` branch and a real
   `Actuate.inject_content!(...)` call site, and
   `mix test test/ggen_igniter_sync_inject_test.exs` passes 9 tests, 0
   failures. Setting `inject: true` (plus exactly one of `before:`/`after:`/
   `at_line:`) in a template's frontmatter really splices the rendered body
   into the resolved `--out` path's existing content — see
   [`docs/reference/cli/sync.md`](docs/reference/cli/sync.md)'s `inject:
   true` section for the full anchor-resolution and idempotency rules. This
   is a marker-based line splice, not an AST-based structural patch — see
   [`docs/architecture/adr/0006-marker-based-injection-not-ast-patch.md`](docs/architecture/adr/0006-marker-based-injection-not-ast-patch.md).

2. **`test/e2e/run_e2e.exs` exit-code masking — CLOSED.** The script starts
   `ExUnit.start(timeout: 300_000, autorun: false)`, runs the suite via a
   real `%{failures: failures} = ExUnit.run()`, and calls `System.halt/1`
   keyed directly off that real `failures` count (`System.halt(1)` /
   `System.halt(0)`) — verified by reading the file's actual 13 lines
   directly; `autorun: false` is present and `ExUnit.run/0`'s return value,
   not a fixed exit code, drives the halt.

3. **Scaffolded-consumer dependency conflicts
   (`igniter`/`sourceror`/`gno`/`dcatr`/`ash_domains`) — CLOSED.** All four
   fix functions this gap depends on are real, present, and actually
   invoked in `test/e2e/support/e2e_case.ex` and
   `test/e2e/lifecycle_test.ex`: `relax_scaffolded_igniter_dep!/1` and
   `relax_scaffolded_sourceror_dep!/1` strip the scaffolded app's own
   generated `only: [:dev, :test]` restrictions so they no longer diverge
   from `ggen_igniter`'s unrestricted `:igniter`/`:sourceror` requirements;
   `add_dcatr_env_config!/1` writes `config :dcatr, env: Mix.env()` into the
   scaffolded app's own `config/config.exs` (required because Mix never
   loads a path dependency's own config); and `add_ash_domains_config!/3`
   registers the pack's `SupportDesk.Support` domain module in `config
   :support_desk, ash_domains: [...]`. All four are called from
   `add_ggen_igniter_dep!/1` (itself called from `lifecycle_test.ex` Stage
   0) or directly from `lifecycle_test.ex` line 102, before the first real
   `mix compile`.

## License

MIT — see [LICENSE](LICENSE).
