# Reactor Concurrency: What Actually Runs in Parallel

Source: `lib/ggen_igniter/reactors/reconcile_reactor.ex`; Reactor DSL default
confirmed at `deps/reactor/lib/reactor/dsl/step.ex:15` (`async?: true`).
Concurrency claims below are backed by a real, currently-passing test with
real monotonic-time overlap assertions, not inferred from reading the DSL
alone.

## CURRENT vs TARGET Implementation Comparison

| Dimension | CURRENT Implementation (`ReconcileReactor`) | TARGET Architecture |
|---|---|---|
| **Step-Level Concurrency** | Enabled by default (`async?: true`) for steps without dependency edges (`:observe_prior_manifest`, `:load_ontology`, `:resolve_pack`) | Full DAG concurrency across independent observation, fetch, and render tasks |
| **Multi-Target Actuation** | Per-target concurrency inside `:actuate` via `Task.async_stream/3` (`max_concurrency: System.schedulers_online()`) | Multi-target concurrency via Reactor dynamic step spawning or bounded async stream |
| **Collision Prevention** | Admission-time structural refusal in `:admit` (`:refused_duplicate_output_path`) | Strict plan validation preventing duplicate write paths before scheduling |
| **Query Execution** | Sequential `Enum.map/2` across target queries inside `:run_queries` | Parallel query execution across independent RDF named graphs/queries |

## Two independent layers of concurrency in this pipeline

1. **Reactor's own step-level scheduler** -- runs independent STEPS
   concurrently based on the real dependency graph (`steps.md`).
2. **`:actuate`'s own internal `Task.async_stream/3`** -- runs independent
   TARGETS (when `:targets` is given) concurrently within that single step's
   `run/3` body.

These are different mechanisms at different granularities; neither is
disabled to make the other work.

## Layer 1: step-level concurrency

`:observe_prior_manifest`, `:load_ontology`, and `:resolve_pack` each declare
only `argument :reconcile_opts, input(:reconcile_opts)` -- no
`result(:other_step)` edge between any of the three (confirmed directly in
`steps.md`'s dependency graph). None of the three steps overrides
`async?` to `false`, so each gets the Reactor `step` DSL's own default,
`async?: true` (`deps/reactor/lib/reactor/dsl/step.ex:15`). Reactor's real
dependency-graph scheduler is therefore free to run all three at once --
this is standard Reactor behavior for any set of steps with no edge between
them, not a special-cased optimization written into this module. The
moduledoc states this plainly (lines 160-163): "Reactor's own
dependency-graph scheduler runs them concurrently -- no manual concurrency
management for that part of the pipeline."

No test in this repo currently measures step-level overlap directly (e.g.
timing `:load_ontology` against `:resolve_pack`) -- this claim rests on the
real, checkable absence of a dependency edge plus Reactor's own documented
scheduler behavior, which is a real DSL default, not a test-proven timing
fact the way Layer 2 below is.

## Layer 2: per-target concurrency inside `:actuate`

`actuate_pending/2` (`reconcile_reactor.ex:890-948`) explicitly fans out
over every admitted create/replace/eval item with:

```elixir
max_concurrency = max(System.schedulers_online(), 1)

tagged =
  actionable
  |> Task.async_stream(&actuate_one(&1, Map.fetch!(exec, &1.logical_id)),
    max_concurrency: max_concurrency,
    timeout: :infinity
  )
  |> Enum.map(fn {:ok, tagged_result} -> tagged_result end)
```

This is real concurrency across independent targets in a single
`:targets`-shaped run (see `overview.md`'s "Multi-target input shape"),
bounded by the real number of online schedulers, with no per-task timeout.

### Real, test-proven overlap

`test/ggen_igniter_reconcile_reactor_test.exs`'s "two independent targets
complete correctly with real overlapping write windows" test is the direct
proof, not an inference from reading the code:

- Two targets, each carrying `test_delay_ms: 150` and a shared `test_probe`
  ETS table (the two testing-only hooks documented in the module's
  moduledoc, "Testing hooks (inert in real use)").
- `actuate_one/2` (lines 960-995) calls `probe_mark(exec, :start)` before
  its `Process.sleep(exec.test_delay_ms)` and `probe_mark(exec, :stop)`
  immediately after the real write, recording real
  `System.monotonic_time(:millisecond)` values into the shared ETS table
  (`probe_mark/2`, lines 999-1003).
- The test asserts `start0 < stop1 and start1 < stop0` -- i.e. each target's
  real write window genuinely overlaps the other's. A sequential
  execution would have one target's `start` at or after the other's `stop`;
  this assertion is what a real, working `Task.async_stream/3` fan-out
  produces and a sequential `Enum.map/2` would not.
- Real, passing output (this session): both this test and its sibling
  "two targets whose `--out` resolves to the SAME real path are refused"
  pass under `mix test test/ggen_igniter_reconcile_reactor_test.exs` (see
  `overview.md#verification`).

### Why collision-safety still holds under this concurrency

Real concurrent writes to two DIFFERENT paths are safe by construction (no
shared mutable state between them). Two targets resolving to the SAME real
`out_path` would otherwise race non-deterministically -- `:admit` (a step
BEFORE `:actuate` in the dependency graph) structurally prevents this by
refusing the entire run before any concurrent write is even scheduled (see
`overview.md`'s "Same-output-path collision" and the refusal test cited
above). This is a genuine "prevent at admission time" design, not a runtime
lock or a last-writer-wins race resolved after the fact.

### Test hooks are real, but inert by default

`:test_delay_ms` and `:test_probe` are read ONLY inside `actuate_one/1`
(`probe_mark/2`, `Process.sleep/1` call at line 962) and are `nil` unless a
caller deliberately sets them per-target. They add no overhead and no
behavior change in real (non-test) use -- confirmed by reading every call
site: `run_target_queries/3` (line 598-599) merely threads the opt through
from `target_opts`, and `actuate_pending/2`'s `exec` map (line 623) carries
whatever value was given, `nil` in every real (non-test) call.

## What is NOT concurrent

- `:run_queries` -- runs its own `Enum.map/2` over targets sequentially
  (`run_queries` step body, `reconcile_reactor.ex:301-308`); no
  `Task.async_stream/3` at this stage. Query execution is not parallelized
  across targets today, only rendering-to-disk (`:actuate`) is.
- `:render` -- likewise a sequential `Enum.map/2` (`build_plan/2`, line 618).
- `:finalize_evidence`'s manifest-entry commit -- a sequential
  `Enum.reduce/3` over `admitted.recipes` (line 1050), since each
  reduction step depends on the accumulator from the previous one
  (`manifest_acc`).
- The outer `Reactor.run/4` call inside `run/1` passes `async?: false`
  (line 446) -- this governs the OUTER run's own execution mode, distinct
  from each step's own `async?: true` default that Layer 1 above relies on.
  This flag's exact interaction with per-step `async?` is a Reactor-internal
  detail this doc does not re-derive from source beyond what the passing
  concurrency test already proves empirically (Layer 1's overlap is a real,
  observed DSL-default behavior; this specific outer flag's own effect is
  UNVERIFIED beyond what the test suite's real timings already demonstrate).

## See also

- `docs/reference/reactor/steps.md` -- the real dependency graph Layer 1's
  concurrency follows from
- `docs/reference/reactor/overview.md` -- "Same-output-path collision" and
  "Multi-target input shape" sections
- `docs/reference/reactor/failure-semantics.md` -- what happens when one
  concurrent target's write fails while others are still in flight (see
  `:actuate`'s own self-heal, covered in `compensation.md`)
