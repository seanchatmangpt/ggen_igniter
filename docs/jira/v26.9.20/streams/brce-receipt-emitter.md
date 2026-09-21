# Stream: brce-receipt-emitter

v26.9.20. Branch `errc/brce-receipt-emitter`, base `dcebc422978498fefff90854a475b1001804f17a`.
ERRC: Eliminate caller-supplied receipts, Create a receipt emitter. Consolidated by the
integrator into `docs/status.md`; this stream does not edit `docs/status.md`, `CHANGELOG.md` or
the `mix.exs` version.

## Charter

`SemanticJira.Reconciler.reconcile/4` admitted whatever receipt map a caller built
(`docs/status.md`: "receipts are caller-supplied not produced by BRCE"). This stream adds
`GgenIgniter.SemanticJira.ReceiptEmitter`: the receipt is produced by admitting a WorkOrder and its
`execution_package`, running a real subprocess in a scratch dir, and sealing what was observed.
Evidence is derived from the observed consequence, never asserted by the caller.

## What BRCE means in this repo

`BRCE` appears in this repo only as a boundary name: the kernel moduledoc
(`lib/ggen_igniter/semantic_jira.ex`), `SemanticJira.do_intent/2` (`"owner" => "BRCE/CommandBus"`,
`"executed" => false`) and RFC-SEMANTIC-JIRA-v26.9.19 section 4 ("consequential DO remains
BRCE-owned"). No BRCE/CommandBus executor exists as code here. `GgenIgniter.Receipt` and
`ReconcileReactor` are the Reactor pipeline's own evidence path (file actuation), a different
receipt type. The emitter therefore implements the smallest faithful subset of
`parse -> route -> admit/refuse -> diagnose/repair -> construct -> actuate -> receipt -> replay ->
standing` and records each stage's real state in the receipt's `"stages"` ledger.

| Stage | State | Where |
|---|---|---|
| parse | executed | `normalize_plan/2` (steps, seed files, watched files) |
| route | UNSUPPORTED(single-route) | one route: local `sh` subprocess |
| admit / refuse | executed | WorkOrder, RuntimeShape package (digest, work order, subject), plan bindings, authority; all before any command runs |
| diagnose / repair | UNSUPPORTED | a failing run is a non-success receipt; `repair_work_order/2` is not driven |
| construct | executed | fresh scratch dir under `System.tmp_dir!/0`, seed files written |
| actuate | executed | `System.cmd("sh", ...)` per step, cwd = scratch dir, fail-fast |
| receipt | executed | digest-sealed map, `SemanticJira.digest/1` |
| replay | executed on request | inline when `replay: true` or `replay_required`; `replay/2` post hoc |
| standing | not applied | `Reconciler.reconcile/4` owns the transition; receipt has `transition_applied: false` |

## Changes

Generated vs handwritten: all handwritten. There is no generator path for a runtime emitter over
an admitted WorkOrder; the pack ontology does not model receipts as executable producers.
UNSUPPORTED(generator-capability) for this file; no Ash surface was touched.

| File | Change |
|---|---|
| `lib/ggen_igniter/semantic_jira/receipt_emitter.ex` | new: `emit/4`, `emit_command/4`, `command_plan/3`, `verify/2`, `check_success/1`, `replay/2`, `persist/2`, `load/1` |
| `lib/ggen_igniter/semantic_jira/reconciler.ex` | `opts` now honored: emitted/sealed receipts verified before idempotent-replay lookup and before admission; `require_sealed: true`; `replay_plan: plan` |
| `test/ggen_igniter_semantic_jira_receipt_emitter_test.exs` | new: 29 tests, real subprocesses and files |

Backward compatibility: `promote/3`, `definition_digest/1`, `project/2`, `frontier_from_events/3`,
`execution_package/2`, `TransitionLog`, `Descriptor`, `Shacl`, `SemanticA2A` are unchanged. A
hand-built receipt without `"kind" => "brce_receipt"` and without `"receipt_digest"` is admitted
exactly as before unless the caller passes `require_sealed: true`.

## Receipt shape

```text
kind schema receipt_class emitted_by emitted_at
definition_digest snapshot_digest candidate_sha target        <- Reconciler-facing
identity      work order id/digest, definition digest, package digest, graph/source digest, ...
authority     level NONE, requirement, prepared_receipt
requirements  acceptance falsifiers courts evidence receipt_classes replay_required ceiling
consequence   steps[exit_code stdout_digest stderr_digest passed ...] files[before after changed]
              files_after_digest (Receipt.hash_files) portable_files_digest (Receipt.hash_entries)
              exit_code success consequence_digest
replay        plan plan_digest toolchain_identity environment_identity requested passed
evidence      DERIVED: acceptance/court/falsifier results, evidence_types, receipt_classes, ...
standing      from proposed authority NONE transition_applied false
stages        BRCE stage ledger
receipt_digest  seal
```

## Refusals

| Situation | Result |
|---|---|
| package for another WorkOrder, edited package, non-RuntimeShape | `{:refused, :package_*}` before anything runs |
| plan binds an id the WorkOrder lacks, escaping paths, empty plan, duplicate step ids | `{:refused, ...}` before anything runs |
| `authority_requirement` not NONE without a matching prepared authority receipt | `{:refused, :authority_not_prepared}` |
| edited exit code / digest / evidence / requirements | `{:refused, {:receipt_invalid, reason}}` |
| valid receipt of a failing run | `{:refused, {:non_success_receipt, exit_code}}`, log unchanged |
| hand-built receipt with `require_sealed: true` | `{:refused, :unsealed_receipt}` |
| forged-but-self-consistent receipt with `replay_plan: plan` | `{:refused, {:replay_refused, ...}}` |

## Falsifiers

Each is exercised in `test/ggen_igniter_semantic_jira_receipt_emitter_test.exs`.

1. Editing the exit code, the seal digest, the evidence or the requirements of an emitted receipt
   is refused (seal mismatch, then re-derivation, then WorkOrder cross-check).
2. A failing command never transitions standing; the dependent stays blocked.
3. Refused admission never runs the command (marker file absent).
4. A self-consistent forgery (every derived field and the seal recomputed) passes `verify/2` and is
   admitted by a plain `reconcile/4`. The seal is integrity, not a signature. `replay_plan: plan`
   refuses it because the trusted plan does not reproduce the claimed consequence.
5. `replay/2` does not execute the receipt's embedded argv unless `trust_receipt_plan: true`.
6. A nondeterministic command fails replay and cannot satisfy `replay_required`.

Mutation checks run against the new tests (each mutation applied, suite run, file restored and
diffed identical): seal digest check disabled (3 failures), Reconciler verification bypassed (10
failures), `check_success/1` always ok (2 failures), step pass derivation ignoring the exit code
(6 failures). All four mutants were killed.

## PARTIAL / UNSUPPORTED / BLOCKED

| Item | Status | Evidence |
|---|---|---|
| Real BRCE/CommandBus executor, claim store, leases | UNSUPPORTED | not in this repo; `do_intent/2` only builds an intent |
| Routing beyond one local `sh` route | UNSUPPORTED(single-route) | `stages.route` |
| Diagnose/repair loop from a failed receipt | UNSUPPORTED | `stages.diagnose_repair` |
| Filesystem/process isolation | UNSUPPORTED(isolation) | only cwd is scoped; timeout kills the Elixir task, not the OS process group |
| Windows / non-POSIX `sh` | UNSUPPORTED | `sh -c 'exec "$0" "$@"'` wrapper |
| Signed receipts / tamper-evidence chain | UNSUPPORTED | digest seal only; same disclosure as ADR-010 |
| Failure moving standing to BLOCKED / BUILD_BROKEN | PARTIAL | `promote/3` requires every check for every target, so a failing receipt is refused rather than recorded as BLOCKED |
| Evidence ceilings above `observed` (`hosted-ci`, ...) | PARTIAL | local run proposes `PARTIAL_ALIVE`; forcing `ALIVE` is refused with `[:ceiling]` |
| Deterministic replay of nondeterministic commands | UNSUPPORTED | replay reports `consequence_set` mismatch |
| Env vars in plan | not implemented | subprocess inherits the VM environment |
| Reconciler `replay_plan` when plan itself is untrusted | n/a | caller must supply a trusted plan |

## Proposed `docs/status.md` rows (for the integrator)

| Capability | Status | Evidence |
|---|---|---|
| Semantic Jira receipt emitter (`ReceiptEmitter`): admit WorkOrder + package, run real `sh` subprocess in scratch dir, seal receipt (identity, authority NONE, consequence, replay, derived evidence, standing proposal); `Reconciler` verifies emitted receipts, `require_sealed`, `replay_plan` | PARTIAL_ALIVE | new emitter test file (29 tests, real subprocesses) plus reconciler tests; not ALIVE: no BRCE/CommandBus, no signing, no isolation, single route |

## Verification

Run in the worktree `/Users/sac/ggen_igniter-wt2/brce-receipt-emitter` (base
`dcebc422978498fefff90854a475b1001804f17a`), 2026-09-21. Pre-existing failures: none observed in
the suites below. Introduced failures: none at head; the first run of the new test file had 1
failure (a test expecting `:requirements_mismatch` while the stale `evidence` was caught first),
fixed by editing requirements and the derived evidence consistently.

| Command | Exit | Result |
|---|---|---|
| `mix compile --warnings-as-errors` | 0 | clean (only the pre-existing `mix.exs` `:preferred_cli_env` deprecation notice) |
| `mix format --check-formatted` (3 touched files) | 0 | formatted |
| `mix credo --strict` (3 touched files) | 0 | `found no issues` |
| `mix test` new emitter + reconciler files, `--seed 0` | 0 | `34 tests, 0 failures` |
| `mix test` emitter, reconciler, descriptor, autonomics_crown, pack_health, shacl, work_order, semantic_jira_pack, semantic_a2a_pack, semantic_epoch, `--seed 0` | 0 | `167 tests, 0 failures` (1210 s; sync pack tests spawn `mix` subprocesses) |
| Chicago mock grep (repo command) | 1 | no output |
| `mix dialyzer` | not run | no PLT in the cloned `_build`; UNKNOWN |
| Full `mix test` | not run | out of scope for this stream (primary tree runs it) |

The `error: undefined variable "undefined_health_probe_binding"` line in the 167-test output is
stderr from a pre-existing pack-health test that feeds a deliberately broken query.

## See Also

- `docs/architecture/adr/ADR-010-event-sourced-standing.md`
- `docs/rfc/RFC-SEMANTIC-JIRA-v26.9.19.md`
- `docs/architecture/adr/0009-runtime-shape-semantic-ir.md`
- `lib/ggen_igniter/semantic_jira/reconciler.ex`
