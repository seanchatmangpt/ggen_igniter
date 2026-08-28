# Runtime Topology

What actually starts, in what process, under what OTP application, when
`ggen_igniter` is loaded as a dependency or run as its own project. Status
labels below (IMPLEMENTED / PARTIAL_ALIVE / PLANNED) follow the ground-truth
order: executed behavior > tests > current implementation > current config >
manifests/receipts > README/docs > historical plans > future-work comments.

## The OTP application: `GgenIgniter.Application`

**IMPLEMENTED.** `lib/ggen_igniter/application.ex` is the `mod:` entry point
registered in `mix.exs` (`mod: {GgenIgniter.Application, []}`). On `start/2`
it builds a plain `Supervisor.start_link/3` (`strategy: :one_for_one`, name
`GgenIgniter.Supervisor`) with up to two children:

1. **`{Finch, name: GgenIgniter.Finch}`** — started only when
   `Code.ensure_loaded?(Finch)` succeeds. `Finch` arrives transitively via
   `:gno` (`only: [:dev, :test]` in that dep's own tree), so a `prod` build
   that never uses `--engine qlever` need not have it compiled. This pool is
   what `Tesla.Adapter.Finch` (configured in `config/config.exs`:
   `config :tesla, adapter: {Tesla.Adapter.Finch, name: GgenIgniter.Finch}`)
   and `gno`'s own `SPARQL.Client` HTTP calls ride on.
2. **`{GgenIgniter.Controller, name: GgenIgniter.Controller}`** — started
   only when the CONSUMING application has set
   `config :ggen_igniter, start_controller: true` in its own config. The
   default is `false`. See `docs/operations/controller.md` for what this
   process is and why it is opt-in.

With both flags left at their defaults (`start_controller: false`, and no
`:gno` in the dependency tree), a consumer that only runs
`mix ggen_igniter.sync`/`mix ggen_igniter.doctor` gets a supervisor with zero
children — no behavior change from before this application module existed.

## Two execution models, not one

`ggen_igniter` code runs in exactly one of two distinct process shapes,
depending on how it is invoked. Neither is a hidden alternative to the
other — both are real, both are documented, and a consumer chooses which one
by how they call in.

### 1. The CLI (`mix ggen_igniter.sync`, `mix ggen_igniter.doctor`) — per-invocation, no continuity

**IMPLEMENTED**, the default and most-used path. Each invocation is a fresh
`mix` OS process: it boots the BEAM, runs the `Igniter.Mix.Task` body, and
exits. There is no in-memory state carried from one `mix ggen_igniter.sync`
call to the next — "what did the last run do" can only be answered by
re-reading disk (the manifest, the receipts log — see
`docs/operations/failure-recovery.md`), never by asking a live process,
because there is no process left to ask once the OS process exits.

### 2. The Controller (`GgenIgniter.Controller`) — persistent, in-process, opt-in

**PARTIAL_ALIVE** — real and tested, but a bounded proof-of-concept, not a
general workflow engine (see `docs/operations/controller.md` and
`docs/contributing/architecture-rules.md`'s "GenServer does not become a
workflow engine" rule). A real `GenServer`, started under
`GgenIgniter.Application`'s supervision tree only when
`start_controller: true` is set, that holds live reconciliation state
**in this one process** across multiple calls, answering things like "how
many times has pack key X actually been reconciled, in this process"
without touching disk.

## Which reconciliation pipeline actually runs

Both execution models above ultimately call into one of two pipeline
implementations, selected by a **third**, independent config flag:

- **`GgenIgniter.Reconcile.run/1`** — the plain function pipeline
  (`Ontology.load! -> engine prepare!/run -> Render.render -> Actuate.write_file!/eval_code!`).
  This is the **default today** — it runs whenever
  `Application.get_env(:ggen_igniter, :use_reactor, false)` is left at its
  default `false`. No receipt is written, no compensation/undo exists at
  this layer, no OCEL events are emitted. `Mix.Tasks.GgenIgniter.Sync` (the
  actual `mix ggen_igniter.sync` CLI task) has its own separate, older
  implementation of this same spine and does **not** currently delegate to
  `GgenIgniter.Reconcile.run/1` — the two are parallel, not yet unified (see
  `GgenIgniter.Reconcile`'s own moduledoc, which discloses this directly:
  "a separate, concurrent effort owns wiring the CLI to delegate here").
  `GgenIgniter.Controller` **does** call `GgenIgniter.Reconcile.run/1`
  directly when `use_reactor` is `false`.
- **`GgenIgniter.Reactors.ReconcileReactor.run/1`** — the real Reactor-based
  coordinator (`use Reactor`, not `Ash.Reactor`). This is the **target**
  architecture (see `docs/contributing/architecture-rules.md`), but it is
  **opt-in today**: it only runs when the consuming application sets
  `config :ggen_igniter, use_reactor: true`. `GgenIgniter.Controller` is the
  only caller in this codebase that branches on this flag
  (`run_pipeline/1` in `lib/ggen_igniter/controller.ex`); `mix
  ggen_igniter.sync` itself does not read this flag at all today.

**Default-today vs. target, stated plainly**: with every consumer's config
at its shipped default, the ReconcileReactor pipeline **never runs** — every
real reconciliation attempt goes through `GgenIgniter.Reconcile.run/1` (via
`Controller`) or `Mix.Tasks.GgenIgniter.Sync`'s own inline pipeline (via the
CLI). The Reactor pipeline is real, tested, and has the receipt/compensation
guarantees described in `docs/operations/failure-recovery.md` — but only for
a consumer that has explicitly opted in.

## Native NIF: `native/ggen_graph_nif`

**IMPLEMENTED.** A Rustler NIF (`GgenIgniter.Native.GraphNif`) wrapping
ggen's own `ggen-graph-wasm` `OxigraphEngine` natively (not via WASM), used
by `GgenIgniter.Query.Oxigraph` (the `--engine oxigraph` query path, and the
default engine for `mix ggen_igniter.sync` per `sync.ex`). `mix
ggen_igniter.doctor` check 14 verifies this crate is compiled and
up to date (`priv/native/ggen_graph_nif.so` newer than every `.rs` source
file); check 15 runs a real functional smoke query against it. See
`docs/operations/debugging.md` for what to do when either check fails.

**Known, disclosed runtime bug (as of 2026-08-27, PARTIAL_ALIVE)**: the
oxigraph engine's string-literal bindings come back with the literal quote
characters baked in (confirmed in `test/e2e/lifecycle_test.ex`'s own inline
comment and `.ggen_igniter_factory/capability_matrix.md`), which is why the
project's own e2e suite pins `--engine sparql` explicitly rather than
relying on the CLI's oxigraph default. Do not assume oxigraph-engine string
bindings are byte-identical to sparql/qlever engine bindings until this is
fixed.

## Config surface actually read at runtime

| Config key | App | Default | Effect |
|---|---|---|---|
| `:ggen_igniter, :start_controller` | consumer's own config | `false` | Adds `GgenIgniter.Controller` as a supervised, named child of `GgenIgniter.Supervisor`. |
| `:ggen_igniter, :use_reactor` | consumer's own config | `false` | `GgenIgniter.Controller.reconcile/3` dispatches to `ReconcileReactor.run/1` instead of `Reconcile.run/1`. Read only by `Controller`; the CLI task does not check this flag. |
| `:tesla, :adapter` | this project's `config/config.exs` | `{Tesla.Adapter.Finch, name: GgenIgniter.Finch}` | Routes every `Tesla`-based HTTP call (marketplace pack fetch, `gno`'s Qlever client) through the supervised Finch pool above. |
| `:dcatr, :env` | consumer's own `config/config.exs` | none (must be set if `:gno`/`:dcatr` present) | Required by `:gno`'s `Fuseki` adapter at compile time; `mix ggen_igniter.doctor` check 6 detects a missing value and `--fix` adds it. |

## See Also

- `docs/operations/controller.md` — the `GgenIgniter.Controller` GenServer in depth
- `docs/operations/failure-recovery.md` — receipts, standings, compensation/undo
- `docs/operations/debugging.md` — the doctor checklist and a practical triage playbook
- `docs/contributing/architecture-rules.md` — which layer owns what, and why the two pipelines coexist
- `docs/reference/cli/index.md` — the CLI tasks' own flag reference
