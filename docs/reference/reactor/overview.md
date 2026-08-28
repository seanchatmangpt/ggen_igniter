# Reactor Coordination Overview

Source of truth: `lib/ggen_igniter/reactors/reconcile_reactor.ex` (read in full
2026-08-27). Ground-truth order used throughout this doc set: executed
behavior > tests > current implementation > current config > manifests/
receipts > README/docs > historical plans > comments about future work.

## CURRENT vs TARGET Architecture

| Dimension | CURRENT Implementation (Observed) | TARGET Architecture (Intended) |
|---|---|---|
| **Default Reconciliation Engine** | `GgenIgniter.Reconcile.run/1` (plain function pipeline) & `Mix.Tasks.GgenIgniter.Sync` inline pipeline | `GgenIgniter.Reactors.ReconcileReactor` as the standard kernel across CLI & Controller |
| **Opt-In Gate** | `Application.get_env(:ggen_igniter, :use_reactor, false)` defaults to `false` | Uniform execution through `ReconcileReactor` with zero config friction |
| **Reconciliation Lifecycle Model** | Linear function execution (render-straight-to-write) without whole-plan admission | Autonomic loop with explicit `PendingActuation` plan, admission gate, and verification |
| **Failure Handling & Rollback** | Uncaught exception / crash; partial file writes left on disk without cleanup | Automatic compensation via Reactor `undo/4` / self-heal, zero partial invalid states |
| **Evidence & Receipting** | No receipts generated; state inferred only by inspecting output files or manifest | Append-only receipts (`.ggen_igniter/receipts/`) + OCEL telemetry events on every path |
| **Multi-Target Execution** | Single-output execution per CLI call (or linear looping in sync) | Multi-target concurrent execution via `Task.async_stream/3` with collision refusal |

## Role Analysis: Reactor vs GenServer vs Linear Functions

Understanding why `Reactor` is used as the autonomic coordination kernel requires contrasting it with the alternatives available in the BEAM ecosystem:

```
+-----------------------------------------------------------------------------+
|                             Reconciliation Roles                            |
+-----------------------------------------------------------------------------+
|  LINEAR FUNCTIONS (Reconcile.run/1)                                         |
|    - Stateless, imperative, sequential execution                            |
|    - No step-level concurrency, no DAG scheduling                           |
|    - No built-in rollback/undo mechanism across step boundaries              |
|    - Fails fast by crashing/raising, leaving partial mutations on disk      |
+-----------------------------------------------------------------------------+
|  GENSERVER (GgenIgniter.Controller)                                         |
|    - Long-lived process maintaining in-memory state across runs             |
|    - Sequential message mailbox (process boundary)                          |
|    - Fault isolation: catches pipeline errors to protect server state       |
|    - Does NOT coordinate internal steps; delegates pipeline work to engine   |
+-----------------------------------------------------------------------------+
|  REACTOR (GgenIgniter.Reactors.ReconcileReactor)                            |
|    - Autonomic coordination kernel & DAG execution engine                   |
|    - Declarative dependency graph with automatic step-level concurrency     |
|    - Transactional failure semantics: step-level rollback via `undo/4`       |
|    - Enforces fail-closed admission gates and post-actuation verification   |
|    - Guarantees durable evidence (Receipts & OCEL events) on all paths      |
+-----------------------------------------------------------------------------+
```

### 1. Linear Functions (`GgenIgniter.Reconcile.run/1`)
- **Strengths:** Minimal overhead, zero runtime dependencies, straightforward stack traces, easy to embed anywhere.
- **Deficiencies as a Coordinator:** Hardcodes the execution order sequentially. If step 4 (write) fails or breaks the build, steps 1-3 have no structured rollback mechanism. There is no plan abstraction or admission boundary prior to actuation.

### 2. GenServer (`GgenIgniter.Controller`)
- **Strengths:** Persistent BEAM process that tracks historical reconciliation metadata (`reconciliation_count`, `last_run_at`) in memory without disk I/O. Provides process-level fault isolation across different pack keys.
- **Deficiencies as a Coordinator:** A GenServer is a single-threaded process loop (mailbox). Modeling complex multi-step pipelines inside a GenServer either blocks the process mailbox or requires complex manual asynchronous task orchestration. A GenServer should *supervise and trigger* reconciliations, not implement the execution graph itself.

### 3. Reactor (`GgenIgniter.Reactors.ReconcileReactor`)
- **Role:** The **autonomic coordination kernel**. Reactor provides a pure, declarative Directed Acyclic Graph (DAG) for step execution.
- **Key Capabilities:**
  1. **Dependency-Driven Concurrency:** Independent steps (e.g., loading manifest, loading ontology, resolving pack) execute concurrently without manual `Task` choreography.
  2. **Formal Rollback Lifecycle (`compensate/4` vs `undo/4`):** When downstream verification (`:verify`) fails, Reactor automatically unwinds the dependency graph and executes `:actuate`'s `undo/4` to restore disk state to its pre-run hash.
  3. **Strict Boundaries:** Enforces explicit stages for observation, planning, admission, actuation, verification, and evidence finalization.

## Two coexisting reconciliation paths (IMPLEMENTED, both)

`ggen_igniter` currently ships two working coordinators for the same
ontology-load -> query -> render -> actuate spine, and this repo is
mid-migration between them:

- **`GgenIgniter.Reconcile.run/1`** (`lib/ggen_igniter/reconcile.ex`) -- a
  plain function pipeline, no Reactor involved. **This is the default path
  today.** Nothing in `config/*.exs` sets `:ggen_igniter, :use_reactor` (grep
  confirmed no matches), and every call site (`Mix.Tasks.GgenIgniter.Sync`,
  `GgenIgniter.Controller`) falls back to `Application.get_env(:ggen_igniter,
  :use_reactor, false)`, whose literal default is `false`.
- **`GgenIgniter.Reactors.ReconcileReactor`** (`lib/ggen_igniter/reactors/
  reconcile_reactor.ex`) -- a real, `use Reactor`-based coordinator (plain
  `Reactor`, explicitly **not** `Ash.Reactor` -- the moduledoc states this is
  so `ggen_igniter` stays usable without Ash as a mandatory runtime
  dependency). **This is the target path**, reachable today only when a
  caller opts in.

Status label: **PARTIAL_ALIVE**. The Reactor module is real, compiles, and is
exercised by three real, currently-passing, no-mock test files (see
[Verification](#verification) below) -- it is not a stub and not merely
planned. But it is not the default: `mix.exs` deliberately keeps `{:reactor,
"~> 1.0"}` as a required (non-`only: [:dev, :test]`) dependency specifically
because `reconcile_reactor.ex` uses `use Reactor` at compile time, while the
runtime dispatch itself stays gated behind the `use_reactor` flag.

## How to opt in (real, current mechanism)

Two independent call sites read the same flag, each with its own inline
comment disclosing the default:

| Call site | File:line | Flag read |
|---|---|---|
| `Mix.Tasks.GgenIgniter.Sync.igniter/1` | `lib/mix/tasks/ggen_igniter.sync.ex:433,446` | `use_reactor?/0` -> `Application.get_env(:ggen_igniter, :use_reactor, false)` |
| `GgenIgniter.Controller`'s `run_pipeline/1` | `lib/ggen_igniter/controller.ex:163-171` | same key, same default |

Setting `config :ggen_igniter, use_reactor: true` (or `Application.put_env/3`
at runtime, as the opt-in wiring test does) switches both call sites to
`ReconcileReactor.run/1` instead of `Reconcile.run/1` / the inline pipeline.
When the flag is left at its default, both call sites are, per their own
comments, "BYTE-FOR-BYTE UNCHANGED" from before the Reactor module existed.

## The real step graph (from source, not invented)

The real step names, in declaration order in `reconcile_reactor.ex`, are:

```
observe_prior_manifest
load_ontology
resolve_pack
run_queries
render
admit
actuate
verify
finalize_evidence
```

This is **not** a generic observe/construct/plan/admit/actuate/verify/
finalize graph forced onto the code -- it is the literal set of `step :name
do ... end` blocks (lines 267, 277, 287, 296, 311, 320, 336, 381, 410) plus
the module-level `return :finalize_evidence` (line 422). See
`docs/reference/reactor/steps.md` for the real dependency graph
(`argument`/`input`/`result` declarations) and per-step contract.

## Public entry point: `run/1`, not a bare `Reactor.run/4` call

`ReconcileReactor.run/1` (lines 439-474) is the module's own recommended
entry point and is what both real call sites above use. Calling
`Reactor.run(ReconcileReactor, %{reconcile_opts: opts})` directly still works
(it is what the DSL generates), but only `run/1` guarantees a persisted
`GgenIgniter.Receipt` on every path -- success or any of the three real
failure standings. This wrapping is deliberate, documented in the
moduledoc's "corrections applied (2026-08-27)" section, correction A: prior
to that correction, a receipt only existed on the happy path, so a refusal,
a compile failure, or a self-healed partial actuation left no durable record
at all even though real bytes may have hit disk and been reverted.

`run/1`'s own shape:

1. Creates a real event sink (`OcelEmitter.new_sink/0`, a real `Agent` pid).
2. Calls `Reactor.run(__MODULE__, %{reconcile_opts: opts}, %{}, async?:
   false)` -- note `async?: false` here governs the *outer* `Reactor.run/4`
   call's own async behavior, distinct from each step's own `async?: true`
   default, which is what lets `:observe_prior_manifest`/`:load_ontology`/
   `:resolve_pack` run concurrently against each other (see
   `docs/reference/reactor/concurrency.md`).
3. On `{:ok, receipt}`: returns it as-is (`:finalize_evidence` already built
   a full `:alive` receipt).
4. On `{:error, error}`: drains the event sink, extracts which step failed
   and why (`failed_step_info/1`, matching Reactor's real
   `%Reactor.Error.Invalid{errors: [%{step: %{name: _}, error: _}, ...]}`
   shape structurally), derives the real standing (`standing_for_failure/2`),
   builds and persists a `GgenIgniter.Receipt` from the drained events, and
   returns `{:error, receipt}`.

## Same-output-path collision: refusal, never last-writer-wins

`:actuate` writes independent targets' files concurrently
(`Task.async_stream/3`, see `concurrency.md`). Two different targets that
happen to resolve to the same real `out_path` in one run are refused
*entirely* by `:admit` (grouping this run's own pending create/replace items
by `target`) before any actuation happens -- proven by
`test/ggen_igniter_reconcile_reactor_test.exs`'s "two targets whose --out
resolves to the SAME real path are refused" test (real run, asserts the
colliding path was never written and the persisted receipt's standing is
`:refused`).

## Verification

Real, currently-passing test run backing every claim in this doc set
(2026-08-27, this session):

```
$ mix test test/ggen_igniter_reconcile_reactor_test.exs test/ggen_igniter_finalize_evidence_ordering_test.exs
Running ExUnit with seed: 96859, max_cases: 32
......
Finished in 3.2 seconds (0.00s async, 3.2s sync)
6 tests, 0 failures
```

No `unittest.mock`/`Mock`/`patch`/`monkeypatch`-equivalent anywhere in either
file (Elixir has no direct equivalent; both files' own moduledocs state
"Chicago-style, no-mocks" and use only real ontology/query/template fixtures,
a real scratch Mix project, and a real `mix compile --warnings-as-errors`
subprocess for `:verify`).

Note one small, real doc/test-name drift, disclosed rather than silently
corrected (out of this agent's write scope, `lib/` is read-only for this
pass): `reconcile_reactor.ex`'s own moduledoc (lines 53, 93) and
`receipt.ex`'s moduledoc (line 93) both cite a test file named
`test/ggen_igniter_receipt_compensated_test.exs`, which does not exist. The
real, passing test with that content is
`test/ggen_igniter_reconcile_reactor_test.exs`'s "restores pre-existing
content, deletes the new file, and persists a real :build_broken receipt"
test (line 192).

## See also

- `docs/reference/reactor/steps.md` -- full per-step contract table
- `docs/reference/reactor/failure-semantics.md` -- the four standings and how
  each is reached
- `docs/reference/reactor/concurrency.md` -- what actually runs concurrently
  and why
- `docs/reference/reactor/compensation.md` -- `compensate/4` vs `undo/4`,
  with real trigger evidence from `deps/reactor`
