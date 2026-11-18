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

Three call sites, two implementations — **not** "Reactor never runs by
default." Corrected 2026-11-18 against `lib/mix/tasks/ggen_igniter.sync.ex`
and `lib/ggen_igniter/controller.ex` (the prior revision of this section
claimed CLI never touched Reactor; that has been false since ADR-0007 /
`sync`-always-attempts-receipts):

- **`mix ggen_igniter.sync` (CLI)** — **always**
  `GgenIgniter.Reactors.ReconcileReactor.run/1` via `run_via_reactor/3` /
  `run_for_each_via_reactor!/7` (including `mode: eval`). It does **not**
  read `use_reactor`. Sync's former inline coordinator
  (`run_pipeline!/3` / `dispatch_pipeline/3` / Controller delegation) is
  deleted — Sync is a CLI facade, not a third spine. Receipts and
  compensation therefore apply on every ordinary CLI sync.
- **`GgenIgniter.Controller`** — branches on
  `Application.get_env(:ggen_igniter, :use_reactor, false)`:
  - `false` (shipped default) → `GgenIgniter.Reconcile.run/1` (bounded:
    no frontmatter / `--for-each` / inject / manifest / receipt).
  - `true` → `ReconcileReactor.run/1`.
- **`GgenIgniter.Reconcile.run/1`** — the bounded plain-function residual
  for Controller-default and programmatic callers that opt out of Reactor.
  It is **not** what the CLI uses.

**Consolidation choice (2026-11-18)**: preferred path is
`ReconcileReactor`; Sync inline spine is gone; keep Controller
`use_reactor` default `false` until an operator product decision (in-process
consumers would suddenly get receipts/compensation/verify). See
`docs/jira/v26.11.18/RECEIPT-finish-slice.md` and
`docs/contributing/architecture-rules.md`.

## Native NIF: `native/ggen_graph_nif`

**IMPLEMENTED.** A Rustler NIF (`GgenIgniter.Native.GraphNif`) wrapping
ggen's own `ggen-graph-wasm` `OxigraphEngine` natively (not via WASM), used
by `GgenIgniter.Query.Oxigraph` (the `--engine oxigraph` query path, and the
default engine for `mix ggen_igniter.sync` per `sync.ex`). `mix
ggen_igniter.doctor` check 14 verifies this crate is compiled and
up to date (`priv/native/ggen_graph_nif.so` newer than every `.rs` source
file); check 15 runs a real functional smoke query against it. See
`docs/operations/debugging.md` for what to do when either check fails.

**Historical note (closed)**: an earlier oxigraph NIF quote-mangling bug
was fixed at the source (`normalize_term/1` in the Rust NIF; plain values
by default — see `docs/status.md` "Native oxigraph NIF string-literal
binding shape"). Residual caveat: plain defaults still return literal
lexical strings for typed literals (e.g. `xsd:boolean` → `"true"`), unlike
`Query.run/2`'s datatype coercion path historically.

## Config surface actually read at runtime

| Config key | App | Default | Effect |
|---|---|---|---|
| `:ggen_igniter, :start_controller` | consumer's own config | `false` | Adds `GgenIgniter.Controller` as a supervised, named child of `GgenIgniter.Supervisor`. |
| `:ggen_igniter, :use_reactor` | consumer's own config | `false` | `GgenIgniter.Controller.reconcile/3` dispatches to `ReconcileReactor.run/1` instead of `Reconcile.run/1`. Read **only** by `Controller`. The CLI already attempts Reactor first and does not consult this flag. |
| `:tesla, :adapter` | this project's `config/config.exs` | `{Tesla.Adapter.Finch, name: GgenIgniter.Finch}` | Routes every `Tesla`-based HTTP call (marketplace pack fetch, `gno`'s Qlever client) through the supervised Finch pool above. |
| `:dcatr, :env` | consumer's own `config/config.exs` | none (must be set if `:gno`/`:dcatr` present) | Required by `:gno`'s `Fuseki` adapter at compile time; `mix ggen_igniter.doctor` check 6 detects a missing value and `--fix` adds it. |

## See Also

- `docs/operations/controller.md` — the `GgenIgniter.Controller` GenServer in depth
- `docs/operations/failure-recovery.md` — receipts, standings, compensation/undo
- `docs/operations/debugging.md` — the doctor checklist and a practical triage playbook
- `docs/contributing/architecture-rules.md` — which layer owns what, and why the two pipelines coexist
- `docs/reference/cli/index.md` — the CLI tasks' own flag reference
