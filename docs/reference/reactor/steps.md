# Reactor Steps: Real Dependency Graph and Per-Step Contract

Source: `lib/ggen_igniter/reactors/reconcile_reactor.ex`, `use Reactor` steps
at lines 267 (`:observe_prior_manifest`), 277 (`:load_ontology`), 287
(`:resolve_pack`), 296 (`:run_queries`), 311 (`:render`), 320 (`:admit`), 336
(`:actuate`), 381 (`:verify`), 410 (`:finalize_evidence`); module `input
:reconcile_opts` at line 265; `return :finalize_evidence` at line 422.

## Real dependency graph (from `argument`/`input`/`result` declarations)

```
input(:reconcile_opts)
  |-- observe_prior_manifest   [argument :reconcile_opts <- input]
  |-- load_ontology            [argument :reconcile_opts <- input]
  |-- resolve_pack             [argument :reconcile_opts <- input]
         |
         v (all three feed run_queries; only :load_ontology's result is read)
  run_queries  [argument :reconcile_opts <- input, :ontology <- result(:load_ontology)]
         |
         v
  render  [argument :queried <- result(:run_queries), :observed <- result(:observe_prior_manifest)]
         |
         v
  admit   [argument :render <- result(:render), :reconcile_opts <- input]
         |
         v
  actuate [argument :admitted <- result(:admit), :reconcile_opts <- input]
         |
         v
  verify  [argument :actuated <- result(:actuate), :reconcile_opts <- input]
         |
         v
  finalize_evidence
    [argument :verify <- result(:verify), :admitted <- result(:admit),
     :actuated <- result(:actuate), :observed <- result(:observe_prior_manifest),
     :pack <- result(:resolve_pack), :ontology <- result(:load_ontology),
     :reconcile_opts <- input]
         |
         v
  return :finalize_evidence
```

`:observe_prior_manifest`, `:load_ontology`, and `:resolve_pack` each depend
only on `input(:reconcile_opts)` -- no step-to-step `result(...)` edge
between them -- so Reactor's own scheduler is free to run all three
concurrently. See `docs/reference/reactor/concurrency.md`.

`:finalize_evidence` is the only step with seven declared arguments -- it
genuinely reaches back to `:resolve_pack` and `:load_ontology`'s results
(for `pack_dir` and `ontology_path`, needed to build the manifest entry and
the receipt's `graph_hash`), not just its immediate predecessor `:verify`.

## CURRENT vs TARGET Implementation Comparison

| Step / Boundary | CURRENT Implementation (`ReconcileReactor`) | TARGET Architecture |
|---|---|---|
| **Filesystem Mutation Boundary** | Strictly isolated to `Actuate.write_file!/3` (whole-file writes) in `:actuate`. `inject_content!/5` text splice is in `Actuate` module but only called by CLI sync, not yet in `ReconcileReactor`. | Unified through `PendingActuation` supporting `:create`, `:replace`, `:inject`, and `:eval` operations uniformly inside `:actuate`. |
| **Prune Timing** | `--on-stale prune` deletions deferred to `:finalize_evidence` (after `:verify` succeeds). | Deletion planning in `:render`, admission gate in `:admit`, deletion execution post-verification. |
| **Retry Policies** | `max_retries 0` on `:actuate` and `:verify`. `:finalize_evidence` defaults to `:infinity`. | `max_retries 0` across all mutation/side-effect boundaries including evidence appending. |
| **Verification Scope** | Real `mix compile --warnings-as-errors` subprocess. | `mix compile` + in-process format check + domain semantic invariant checkers. |

## The Single Filesystem-Mutation Boundary

**`:actuate`** (lines 336-379, `run` body `actuate_pending/2` at lines 890-948) is the **ONLY** step in the Reactor pipeline that performs mutation on project source files:
- **`Actuate.write_file!/3`**: Guarded whole-file write with idempotency checks (`:written`, `:unchanged`, `:skipped_exists`, `:skipped_match`).
- **`Actuate.eval_code!/2`**: In-process code evaluation for `mode: eval` templates.
- *(Note on `Actuate.inject_content!/5`)*: Marker-based text splicing into existing files exists in `GgenIgniter.Actuate` (used by `Mix.Tasks.GgenIgniter.Sync`), with planned integration into `PendingActuation` for Reactor execution.

Every step before `:actuate` (`:observe_prior_manifest` through `:admit`) is a pure read or in-memory computation; every step after it (`:verify`) only reads (a `mix compile` subprocess against files `:actuate` already wrote). `:finalize_evidence` writes receipt entries and manifest updates, but does NOT touch project source code. `:actuate` is the unique boundary that tracks mutation state (`%{tracked: tracked}`) and provides the `undo/4` callback to restore pre-run disk state.

## Per-step contract

### `:observe_prior_manifest` (line 267)

- **Inputs:** `reconcile_opts` (input).
- **Dependencies:** none (input only).
- **Outputs:** `%{manifest_dir: String.t(), manifest: GgenIgniter.Manifest.t()}`.
- **Side effects:** pure read -- `GgenIgniter.Manifest.load/1` (line 272).
- **Retry policy:** no `max_retries` declared -> Reactor DSL default,
  confirmed from `deps/reactor/lib/reactor/dsl/step.ex:21`
  (`max_retries: :infinity`).
- **Compensation:** none declared (`compensate`/`undo` absent) -- correct,
  since this step never mutates anything for a later failure to undo.
- **Standing contribution:** failing here (a bad `manifest_dir`) maps to
  `:refused` in `standing_for_failure/2` (line 507) -- no actuation ever
  reached.

### `:load_ontology` (line 277)

- **Inputs:** `reconcile_opts` (input).
- **Dependencies:** none (input only).
- **Outputs:** `%{ontology_path: String.t(), graph: term()}`.
- **Side effects:** pure read -- `GgenIgniter.Ontology.load!/1` (line 282),
  after resolving the real path via `resolve_ontology_path!/1` (raises
  `ArgumentError` if neither `:ontology` nor a pack is given).
- **Retry policy:** default `:infinity` (no override present).
- **Compensation:** none declared.
- **Standing contribution:** `:refused` (in the pre-actuation list at line
  506-513).

### `:resolve_pack` (line 287)

- **Inputs:** `reconcile_opts` (input).
- **Dependencies:** none (input only).
- **Outputs:** `%{pack_dir: String.t() | nil}` (`nil` when no `:pack`/
  `:pack_dir` given -- `pack_given?/1` at line 719).
- **Side effects:** pure read -- `GgenIgniter.Pack.resolve_dir!/1` (line
  291), only called when a pack is actually given.
- **Retry policy:** default `:infinity`.
- **Compensation:** none declared.
- **Standing contribution:** `:refused`.

### `:run_queries` (line 296)

- **Inputs:** `reconcile_opts` (input), `ontology` (`result(:load_ontology)`).
- **Dependencies:** `:load_ontology`.
- **Outputs:** `%{targets: [map()]}` -- one map per target (from
  `normalize_targets/1`, line 561), each carrying `index`, `engine_name`,
  `template_path`, `bindings`, `mode`, `out_template`, `write_opts`, and the
  two test-only hooks `test_delay_ms`/`test_probe`.
- **Side effects:** pure computation over already-loaded data --
  `Engine.fetch!/1`, `engine_module.prepare!/2`, `engine_module.run/2` per
  named query (`run_target_queries/3`, line 576) -- no filesystem writes,
  though template files ARE read here indirectly via `resolve_template_path!/1`
  (path resolution only; the template body itself is read later, in
  `:render`'s `render_target/2` at line 629).
- **Retry policy:** default `:infinity`.
- **Compensation:** none declared.
- **Standing contribution:** `:refused`.

### `:render` (line 311)

- **Inputs:** `queried` (`result(:run_queries)`), `observed`
  (`result(:observe_prior_manifest)`).
- **Dependencies:** `:run_queries`, `:observe_prior_manifest`.
- **Outputs:** `%{pending: [%PendingActuation{}], recipes: [map()], exec:
  %{logical_id => map()}}` (`build_plan/2`, line 617) -- the full intended
  delta as `GgenIgniter.PendingActuation` structs (one create/replace/eval
  intent per target, plus one real `:delete` item per stale-prune
  candidate), never a bare `{out_path, content}` pair.
- **Side effects:** reads each target's real template file
  (`File.read!/1`, line 629) and renders it (`GgenIgniter.Render.render/2`);
  no writes.
- **Retry policy:** default `:infinity`.
- **Compensation:** none declared.
- **Standing contribution:** `:refused`.

### `:admit` (line 320)

- **Inputs:** `render` (`result(:render)`), `reconcile_opts` (input).
- **Dependencies:** `:render`.
- **Outputs:** on success, `%{pending:, recipes:, exec:, stale_paths:
  MapSet.t(), on_stale: atom()}`; on failure, one of three real refusal
  reasons (see `failure-semantics.md`).
- **Side effects:** none (pure inspection of the plan) except emitting one
  real OCEL event, `"GUARD_REFUSED"`, via `OcelEmitter.emit/4` (line 330) --
  ONLY on the refusal path, into `opts[:event_sink]`.
- **Retry policy:** default `:infinity` (no override).
- **Compensation:** none declared.
- **Standing contribution:** `:refused` for all three of its own refusal
  reasons (duplicate output path, unowned delete, stale-with-`on_stale:
  refuse`) -- still in the pre-actuation list.

### `:actuate` (line 336) -- the filesystem-mutation boundary

- **Inputs:** `admitted` (`result(:admit)`), `reconcile_opts` (input).
- **Dependencies:** `:admit`.
- **Outputs:** `%{results: [map()], tracked: %{path => %{path:, prior:}}}`.
- **Side effects:** the ONLY step that writes real files for
  create/replace intents (`GgenIgniter.Actuate.write_file!/3`, line 965) or
  evaluates real code for eval intents (`GgenIgniter.Actuate.eval_code!/2`,
  line 952). Real `:delete` items are admitted but deliberately left
  unactuated here (see "Prune timing" in `overview.md`'s source moduledoc
  and this doc's `finalize_evidence` entry below). Emits real OCEL events
  `"ACTUATION_STARTED"` (line 895) and, on success, `"FILES_CHANGED"` (line
  912); on partial internal failure, also `"COMPENSATION_STARTED"` /
  `"FILES_RESTORED"` (lines 930, 938) as part of its own self-heal.
- **Retry policy:** `max_retries 0` -- **explicit**, line 378. Confirmed
  directly at the source line (`step :actuate do ... max_retries 0 end`).
- **Compensation:** BOTH callbacks are implemented, with genuinely different
  triggers (see `compensation.md` for the full explanation, sourced against
  `deps/reactor/lib/reactor/step.ex` and
  `deps/reactor/documentation/tutorials/02-error-handling.md`):
  - `compensate fn _reason -> :ok end` (lines 344-353) -- a no-op by
    design. `run/3`'s own body already self-heals any partial writes from
    ITS OWN failure (the `errors != []` branch at lines 917-947, which calls
    `revert_all/1` at line 934) before ever returning `{:error, ...}`, so
    there is nothing left for `compensate/4` to revert.
  - `undo fn %{tracked: tracked}, %{reconcile_opts: opts} -> ... end` (lines
    355-376) -- the REAL, tested revert path, triggered when a LATER step
    (`:verify`) fails. Computes `pre_hash`/`post_hash` via
    `GgenIgniter.Receipt.hash_entries/1` / `hash_files/1`, emits real
    `"COMPENSATION_STARTED"` / `"FILES_RESTORED"` OCEL events (with
    `"matches_pre_run_hash"` in the attributes), calls `revert_all/1` (line
    364) to actually restore/delete each tracked path, and returns `:ok`.
- **Standing contribution:** its OWN failure (the internal self-heal path)
  maps to `:compensated` (`standing_for_failure/2` line 522); a LATER
  step's failure that triggers its `undo/4` is attributed to whichever step
  actually failed (`:verify`, in every real test case) -- see
  `failure-semantics.md`.

### `:verify` (line 381)

- **Inputs:** `actuated` (`result(:actuate)`), `reconcile_opts` (input).
- **Dependencies:** `:actuate`.
- **Outputs:** `{:ok, :verified}` or `{:error, {:compile_failed,
  output_string}}`.
- **Side effects:** a real subprocess, `System.cmd("mix", ["compile",
  "--warnings-as-errors"], cd: project_dir, stderr_to_stdout: true)` (line
  389), against `opts[:verify_cwd] || opts[:manifest_dir] || File.cwd!()`
  (line 387) -- the actuated project's own directory. Emits real
  `"VERIFICATION_SUCCEEDED"` or `"VERIFICATION_FAILED"` OCEL events (lines
  394, 398); the failure event's attributes carry `"reason_type" =>
  "build_broken"` specifically (line 399), distinct from a generic
  verification failure.
- **Retry policy:** `max_retries 0` -- **explicit**, line 407. Confirmed
  directly at the source line (`step :verify do ... max_retries 0 end`).
  Retrying a failing `mix compile` without changing anything would never
  succeed differently, so 0 retries here is the only sound choice, same
  reasoning as `:actuate`.
- **Compensation:** none declared on `:verify` itself -- `:verify` never
  writes anything for its OWN failure to compensate. It is `:actuate`'s
  `undo/4` (declared on the earlier step) that Reactor invokes when
  `:verify` fails, per Reactor's real "roll back an earlier successful step
  when a later one fails" semantics.
- **Standing contribution:** `{:compile_failed, _}` -> `:build_broken`;
  anything else raised at this step -> `:compensated` (lines 516-520).

### `:finalize_evidence` (line 410)

- **Inputs:** `verify` (`result(:verify)`), `admitted` (`result(:admit)`),
  `actuated` (`result(:actuate)`), `observed`
  (`result(:observe_prior_manifest)`), `pack` (`result(:resolve_pack)`),
  `ontology` (`result(:load_ontology)`), `reconcile_opts` (input).
- **Dependencies:** `:verify`, `:admit`, `:actuate`,
  `:observe_prior_manifest`, `:resolve_pack`, `:load_ontology` (six real
  upstream steps -- the only step with this many).
- **Outputs:** `{:ok, %GgenIgniter.Receipt{}}` (a real, fully-populated,
  `standing: :alive` receipt).
- **Side effects, in this exact order** (`finalize_evidence/1`, lines
  1036-1137; see `compensation.md` and `overview.md`'s "correction B" for
  why this ordering is load-bearing):
  1. Prepares BOTH the next manifest content (`commit_recipe/5` over each
     admitted recipe) and the new `Receipt` struct entirely in memory --
     nothing durable yet.
  2. `Receipt.append!(manifest_dir, receipt)` (line 1102) -- a real,
     append-only `File.write!/3` to
     `<manifest_dir>/.ggen_igniter/receipts/<date>.jsonl`. If this itself
     raises, the step fails like any other, and `:actuate`'s `undo/4`
     rolls back the real files it wrote (a real `:compensated` outcome via
     `run/1`'s failure path).
  3. Only once the append succeeds: attempts `Manifest.persist!(new_manifest,
     manifest_dir)` (line 1113), but wrapped in `try/rescue` -- a failure
     HERE is caught locally, not re-raised, and recorded instead in
     `receipt.metadata["manifest_promotion"]` as `{:pending, message}`. The
     already-durable receipt is the real recovery anchor.
  4. If `admitted.on_stale == :prune` and there are real stale paths,
     `Manifest.prune!/1` (line 1123) runs the actual deletions here --
     deliberately AFTER `:verify`, never before (see "Prune timing" in
     `overview.md`).
  5. Emits a real `"STANDING_SET"` OCEL event (line 1126) whose attributes
     include the real `manifest_promotion` outcome.
- **Retry policy:** no `max_retries` declared -> default `:infinity`.
  Notably NOT hardened to `0` the way `:actuate`/`:verify` are, even though
  this step performs real durable writes (`Receipt.append!/2`,
  `Manifest.persist!/2`) -- disclosed here as the real, current state (a
  retry of `Receipt.append!/2` after a transient failure would append a
  SECOND receipt line for the same attempt, which is a real, live
  correctness question this doc does not resolve on the source's behalf;
  see `failure-semantics.md`'s "known gap" note).
- **Compensation:** none declared (`compensate`/`undo` absent on this
  step). Per correction B's own reasoning: if `Receipt.append!/2` fails,
  this step's failure triggers `:actuate`'s `undo/4` (an EARLIER step being
  rolled back for THIS step's failure) rather than any compensation logic
  of its own.
- **Standing contribution:** on success, always `:alive` (the receipt built
  here IS the `:alive` receipt). `standing_for_failure/2` also lists
  `:finalize_evidence` in the `:compensated` bucket (line 522) for the case
  where this step itself raises.

## See also

- `docs/reference/reactor/overview.md` -- the two-path migration context and
  how to opt into this pipeline
- `docs/reference/reactor/failure-semantics.md` -- the four standings, and
  exactly which step-failure maps to which
- `docs/reference/reactor/concurrency.md` -- which of the above steps
  actually run in parallel, and the real per-target concurrency inside
  `:actuate`
- `docs/reference/reactor/compensation.md` -- `compensate/4` vs `undo/4` in
  full, with the real Reactor source citations
