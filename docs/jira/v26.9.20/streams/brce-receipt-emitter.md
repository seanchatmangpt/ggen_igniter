# Stream: brce-receipt-emitter

v26.9.20. Branch `errc/brce-receipt-emitter`, base `dcebc422978498fefff90854a475b1001804f17a`.
ERRC: Eliminate caller-supplied receipts, Create a receipt emitter. Consolidated by the
integrator into `docs/status.md`; this stream does not edit `docs/status.md`, `CHANGELOG.md` or
the `mix.exs` version.

Updated 2026-09-21 after the qualification round (commit `98ee9d9`, 6 failing falsifier tests) and
the repair round below.

## Charter

`SemanticJira.Reconciler.reconcile/4` admitted whatever receipt map a caller built
(`docs/status.md`: "receipts are caller-supplied not produced by BRCE"). This stream adds
`GgenIgniter.SemanticJira.ReceiptEmitter`: the receipt is produced by admitting a WorkOrder and its
`execution_package`, running a real subprocess in a private run directory, and sealing what was
observed. Evidence is derived from the observed consequence and from what the WorkOrder itself
declares; the caller can no longer choose which command backs which claim, which subject it ran
against, or whether an authority receipt counts.

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
| parse | executed | `normalize_plan/2` (steps, seed files, watched files, subject source, pin) |
| route | UNSUPPORTED(single-route) | one route: local `sh` subprocess |
| admit / refuse | executed | WorkOrder, options, RuntimeShape package (digest AND content), plan (bindings, pin, UTF-8), subject commit, authority; all before any command runs |
| diagnose / repair | UNSUPPORTED | a failing run is a non-success receipt; `repair_work_order/2` is not driven |
| construct | executed | private run dir (exclusive mkdir, 0700, OS pid + random bytes); `work/` seeded or filled by `git archive` of the WorkOrder's exact commit |
| actuate | executed | `System.cmd("sh", ...)` per step, cwd = `work/`, stderr file in the run dir, fail-fast |
| receipt | executed | digest-sealed map, `SemanticJira.digest/1` |
| replay | executed on request | inline when `replay: true` or `replay_required`; `replay/2` post hoc |
| standing | not applied | `Reconciler.reconcile/4` owns the transition; receipt has `transition_applied: false` |

## What an ALIVE proposal means

ALIVE is proposed, and `evidence.observed_execution` / `evidence_ceiling: "observed"` derived, only
when all hold. Otherwise the target is `PARTIAL_ALIVE`, `evidence_ceiling` is `"none"`, and a forced
`ALIVE` is refused by `SemanticJira.promote/3` with `[:ceiling]`.

1. Subject bound: the plan named a `subject_source` (local git repository) and the command ran in
   a `git archive` checkout of exactly the WorkOrder's `candidate_sha` (else `base_sha`).
2. Commands pinned: the WorkOrder's `expected_consequence` is
   `%{"commands" => [%{"argv" => [...], "expect_exit" => 0}]}` (part of its definition digest) and
   the plan's steps are exactly those commands. A pinned command backs every claim the WorkOrder
   names; the plan cannot narrow, widen or reorder.
3. Authority: `authority_requirement` is `NONE`, or the prepared authority receipt passed the
   caller-supplied `:authority_verifier`.
4. The WorkOrder's own `evidence_ceiling` is `observed`.

The binding is recorded in `evidence.binding` (`subject`, `commands_pinned`, `authority`) and
re-derived by `verify/2`.

## Changes

Generated vs handwritten: all handwritten. There is no generator path for a runtime emitter over
an admitted WorkOrder; the pack ontology does not model receipts as executable producers.
UNSUPPORTED(generator-capability) for these files; no Ash surface was touched.

| File | Change |
|---|---|
| `lib/ggen_igniter/semantic_jira/receipt_emitter.ex` | new: `emit/4`, `emit_command/4`, `command_plan/3`, `verify/2`, `check_success/1`, `replay/2`, `persist/2`, `load/1`; repair round: JSON-safety admission, private run dir, package content enforcement, pinned commands, subject materialization, authority verifier, derived ALIVE conditions; schema `semantic-jira/brce-receipt/v2` |
| `lib/ggen_igniter/semantic_jira/reconciler.ex` | `opts` honored: emitted/sealed receipts verified before idempotent-replay lookup and admission; `require_sealed: true`; `replay_plan: plan`; repair round: an emitter-shaped receipt without its seal is `{:receipt_invalid, :stripped_seal}` |
| `test/support/subject_repo.ex` | new: real git repository (two real commits) used as a WorkOrder subject |
| `test/ggen_igniter_semantic_jira_receipt_emitter_test.exs` | 29 tests, real subprocesses and files; e2e now runs against a real subject with a pinned command |
| `test/ggen_igniter_semantic_jira_receipt_emitter_falsifier_test.exs` | 11 tests: the 6 qualifier counterexamples (all red at `98ee9d9`, now guards) plus generalizations |
| `test/ggen_igniter_semantic_jira_receipt_emitter_binding_test.exs` | 24 tests: ALIVE conditions, pinned commands, subject materialization, package content, authority |

Backward compatibility: `promote/3`, `definition_digest/1`, `project/2`, `frontier_from_events/3`,
`execution_package/2`, `TransitionLog`, `Descriptor`, `Shacl`, `SemanticA2A` are unchanged. A
hand-built receipt with none of the emitter's sections is admitted exactly as before unless the
caller passes `require_sealed: true`. Behavior change inside the emitter: a run that is not bound to
the exact subject and pinned commands proposes `PARTIAL_ALIVE` (was `ALIVE`); persisted v1 receipts
do not verify under v2.

## Receipt shape

```text
kind schema receipt_class emitted_by emitted_at
definition_digest snapshot_digest candidate_sha target        <- Reconciler-facing
identity      work order id/digest, definition digest, package digest, graph/source digest, ...
authority     level NONE, requirement, prepared_receipt, verified
requirements  acceptance falsifiers courts evidence receipt_classes replay_required ceiling pinned_commands
consequence   steps[exit_code stdout_digest stderr_digest passed ...] files[before after changed]
              files_after_digest (Receipt.hash_files) portable_files_digest (Receipt.hash_entries)
              subject[bound sha tree source] exit_code success consequence_digest
replay        plan plan_digest toolchain_identity environment_identity requested passed
evidence      DERIVED: acceptance/court/falsifier results, evidence_types, receipt_classes, binding, ...
standing      from proposed authority NONE transition_applied false
stages        BRCE stage ledger
receipt_digest  seal
```

## Refusals

| Situation | Result |
|---|---|
| WorkOrder, package, plan, options or authority receipt with a value that has no JSON encoding (invalid UTF-8, tuple, pid) | `{:refused, ...}` before anything runs (`:plan_not_utf8`, `:package_not_json_safe`, `{:work_order, :not_json_safe}`, `{:invalid_target, _}`, ...) |
| package for another WorkOrder, edited package, non-RuntimeShape | `{:refused, :package_*}` before anything runs |
| self-consistent package whose content violates `worker_not_verifier`, `base_must_not_move`, repository/base binding, action or replay identity | `{:refused, :package_worker_not_verifier_violated / :package_base_policy_mismatch / :package_binding_mismatch / :package_action_mismatch / :package_content_mismatch}` |
| plan binds an id the WorkOrder lacks, escaping paths, empty plan, duplicate step ids | `{:refused, ...}` before anything runs |
| pinned WorkOrder, plan with other/extra/edited steps or narrowed binds | `{:refused, :plan_not_pinned / :pinned_binds_mismatch}` |
| malformed `expected_consequence.commands` | `{:refused, :invalid_expected_consequence}` |
| WorkOrder commit absent from `subject_source`, relative source, seed files beside a subject | `{:refused, {:subject_unavailable, sha} / :invalid_subject_source / :seed_files_with_subject}` |
| `authority_requirement` not NONE without a matching prepared receipt (with `authority_identity`) | `{:refused, :authority_not_prepared}` |
| authority verifier rejects, raises or answers nonsense | `{:refused, {:authority_unverified / :authority_verifier_failed / :authority_verifier_invalid, _}}` |
| edited exit code / digest / evidence / requirements / pinned steps | `{:refused, {:receipt_invalid, reason}}` |
| emitter-shaped receipt with `kind` and `receipt_digest` deleted | `{:refused, {:receipt_invalid, :stripped_seal}}` |
| valid receipt of a failing run | `{:refused, {:non_success_receipt, exit_code}}`, log unchanged |
| hand-built receipt with `require_sealed: true` | `{:refused, :unsealed_receipt}` |
| forged-but-self-consistent receipt with `replay_plan: plan` | `{:refused, {:replay_refused, ...}}` |

## Falsifiers

Exercised in the three emitter test files.

1. Editing the exit code, the seal digest, the evidence, the requirements or the steps of an emitted
   receipt is refused (seal mismatch, re-derivation, WorkOrder cross-check, pin cross-check).
2. A failing command never transitions standing, and deleting `kind` and `receipt_digest` does not
   change that: an emitter-shaped receipt without its seal is refused by default. Residual: a
   receipt stripped of EVERY emitter section is a plain hand-built receipt, admitted by default;
   `require_sealed: true` is what eliminates those.
3. Refused admission never runs the command (marker file absent), including for values with no JSON
   encoding.
4. A self-consistent forgery (every derived field and the seal recomputed) passes `verify/2` and is
   admitted by a plain `reconcile/4`. The seal is integrity, not a signature. `replay_plan: plan`
   refuses it because the trusted plan does not reproduce the claimed consequence.
5. `replay/2` does not execute the receipt's embedded argv unless `trust_receipt_plan: true`.
6. A nondeterministic command fails replay and cannot satisfy `replay_required`.
7. Concurrent emits, in one VM and across 10 real OS VMs, each attest their own stderr.
8. A trivial `true` bound to every claim, in an empty directory or against an unpinned WorkOrder,
   proposes at most `PARTIAL_ALIVE`; a forced `ALIVE` is refused with `[:ceiling]`.

## Repair round (2026-09-21): issues from qualification

| Issue | Root cause | Fix | Permanent guard |
|---|---|---|---|
| Admission did not precede actuation for invalid UTF-8 plans (blocker; reported twice) | `normalize_plan/2` did not prove the plan JSON-encodable; `SemanticJira.digest/1` is `Jason.encode!/1` and ran after `execute/1` | `json_safe?/1` on the normalized plan (`:plan_not_utf8`), and on the WorkOrder, package, prepared authority receipt and options before anything runs | falsifier tests 1-4 (argv, seed content, step id, watch path) plus the generalized WorkOrder/options/authority test |
| Sealed receipt attested another run's stderr (major; reported twice) | stderr file `brce_err_<System.unique_integer/1>` is unique per VM only and was deleted after reading | private run dir per execution: exclusive `File.mkdir`, mode 0700, OS pid + random bytes; stderr files live beside `work/` | falsifier test 6 (10 OS VMs), in-VM 16-way concurrency test, 0700/no-leak test |
| Tampered-receipt refusal bypassed by deleting `kind` + `receipt_digest` (major; reported twice) | `Reconciler` decided "emitted" from the two fields a forger controls | emitter-only sections without a seal are `:stripped_seal` | falsifier test 5, per-section variants, plain hand-built control |
| Sealed receipt laundered caller-asserted claims: (a) plan-chosen bindings and commands (b) fabricated authority receipt (c) package policies not enforced | evidence derived from what the plan asserted | (a) `expected_consequence.commands` pins commands and binds, ALIVE requires it; (b) `:authority_verifier`, unverified receipts never enter evidence; (c) package `bindings`/`policies`/`actions`/`provenance`/`relationships` checked against the WorkOrder | binding test file (24 tests) |
| ALIVE proposal not bound to the WorkOrder subject (major) | command ran in an empty scratch dir; subject fields were copied from the WorkOrder | `subject_source` + `git archive` of the exact commit, ALIVE requires `consequence.subject.bound`; else `PARTIAL_ALIVE` | binding test file (subject, forged sha, replay) |

Mutation checks (each mutant applied, the three emitter test files run, the source restored):

| Mutant | Failures | Killed |
|---|---|---|
| UTF-8 plan admission removed | 4 | yes |
| stderr path back to a shared tmp name | 1 | yes |
| `:stripped_seal` refusal removed | 2 | yes |
| ALIVE binding always exact | 4 | yes |
| package policy enforcement removed | 3 | yes |
| authority always verified | 2 | yes |
| pin enforcement removed | 2 | yes |
| subject binding not derived from sha | 2 | yes |

## PARTIAL / UNSUPPORTED / BLOCKED

| Item | Status | Evidence |
|---|---|---|
| Real BRCE/CommandBus executor, claim store, leases | UNSUPPORTED | not in this repo; `do_intent/2` only builds an intent |
| Routing beyond one local `sh` route | UNSUPPORTED(single-route) | `stages.route` |
| Diagnose/repair loop from a failed receipt | UNSUPPORTED | `stages.diagnose_repair` |
| Filesystem/process isolation | UNSUPPORTED(isolation) | only cwd is scoped; timeout kills the Elixir task, not the OS process group |
| Windows / non-POSIX `sh` | UNSUPPORTED | `sh -c 'exec "$0" "$@"'` wrapper |
| Signed receipts / tamper-evidence chain | UNSUPPORTED | digest seal only; same disclosure as ADR-010 |
| Authority provenance (issuer, signature, claim store) | UNSUPPORTED(authority-issuer) | the emitter only structurally matches a prepared receipt; trust is the caller's `:authority_verifier`; without one the receipt is recorded but never evidence |
| Repository identity of the subject | UNSUPPORTED | the subject is bound by commit sha from a caller-named local repository; the WorkOrder's `repository` name is copied, not verified against it |
| Acceptance relevance for unpinned WorkOrders | UNSUPPORTED(acceptance-relevance) | without `expected_consequence.commands` the plan author asserts which command backs which claim; such a receipt proposes at most `PARTIAL_ALIVE` |
| Caller-supplied hand-built receipts by default | PARTIAL | a receipt with none of the emitter's sections is admitted unless `require_sealed: true`; defaulting it on is a behavior change for the next major |
| Failure moving standing to BLOCKED / BUILD_BROKEN | PARTIAL | `promote/3` requires every check for every target, so a failing receipt is refused rather than recorded as BLOCKED |
| Evidence ceilings above `observed` (`hosted-ci`, ...) | PARTIAL | local run proposes `PARTIAL_ALIVE`; forcing `ALIVE` is refused with `[:ceiling]` |
| Deterministic replay of nondeterministic commands | UNSUPPORTED | replay reports `consequence_set` mismatch |
| Env vars in plan | not implemented | subprocess inherits the VM environment |
| Reconciler `replay_plan` when plan itself is untrusted | n/a | caller must supply a trusted plan |

## Proposed `docs/status.md` rows (for the integrator)

| Capability | Status | Evidence |
|---|---|---|
| Semantic Jira receipt emitter (`ReceiptEmitter`): admit WorkOrder + package (content enforced), run real `sh` subprocess in a private run dir against a git-archive checkout of the WorkOrder's exact commit, seal receipt (identity, authority NONE, consequence, replay, derived evidence, standing proposal); `Reconciler` verifies emitted receipts, refuses stripped seals, `require_sealed`, `replay_plan` | PARTIAL_ALIVE | three emitter test files (64 tests, real subprocesses, real git); not ALIVE: no BRCE/CommandBus, no signing, no isolation, single route, no authority issuer, repository identity unverified |

## Verification

Run in the worktree `/Users/sac/ggen_igniter-wt2/brce-receipt-emitter` (base
`dcebc422978498fefff90854a475b1001804f17a`), 2026-09-21. Pre-existing failures: none observed in
the suites below. Introduced failures: none at head. At `98ee9d9` (before the repair) the falsifier
file was `6 tests, 6 failures`.

| Command | Exit | Result |
|---|---|---|
| `mix test` falsifier file at `98ee9d9`, `--seed 0` | non-zero | `6 tests, 6 failures` (reproduced) |
| `mix compile --warnings-as-errors` | 0 | clean (only the pre-existing `mix.exs` `:preferred_cli_env` deprecation notice) |
| `mix format --check-formatted` (touched lib and test files) | 0 | formatted |
| `mix credo --strict` (6 touched files) | 0 | `176 mods/funs, found no issues.` |
| `mix test` emitter, falsifier, binding, reconciler, descriptor, autonomics_crown, work_order, shacl, `--seed 0` | 0 | `107 tests, 0 failures` |
| Chicago mock grep (repo command) | 1 | no output |
| Mutation checks (8 mutants, see above) | 2 each | all killed, sources restored |
| pack, pack_health, a2a, epoch suites | not re-run | they reference neither `ReceiptEmitter` nor `Reconciler` (`grep -rln`); the earlier stream run reported `167 tests, 0 failures` at the prior head |
| `mix dialyzer` | not run | no PLT in the cloned `_build`; UNKNOWN |
| Full `mix test` | not run | out of scope for this stream (primary tree runs it) |

## See Also

- `docs/architecture/adr/ADR-010-event-sourced-standing.md`
- `docs/rfc/RFC-SEMANTIC-JIRA-v26.9.19.md`
- `docs/architecture/adr/0009-runtime-shape-semantic-ir.md`
- `lib/ggen_igniter/semantic_jira/reconciler.ex`
