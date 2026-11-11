# Seal staging plan — ggen_igniter @ 1a6e60d — 2026-11-07 (Lane T18)

Standing: PARTIAL_ALIVE

Lane T18, staging plan only. No commits, no git commands executed by this lane.
Inputs: G8 triage + B7 re-verification + F3 closure, all in
notes/inflight-triage-2026-11-07.md.

Census: file lists below were re-enumerated on disk 2026-11-07 (ls/find, no
git). They are presence checks; the coordinator reconciles every group against
`git status --short` before staging. Baseline entry count (F3): 99 dirty
entries. Receipts/, _build*, target/, tmp/ are outside the dirty set.

## Group 1 — review + risk-tier feature (core subsystem)

Stage recursively (new lib trees):

- lib/ggen_igniter/review/
- lib/ggen_igniter/landing_pipeline/
- lib/ggen_igniter/convergence/
- lib/ggen_igniter/security_review/

Modified lib files riding in G1:

- lib/ggen_igniter/reactors/reconcile_reactor.ex
- lib/ggen_igniter/receipt.ex
- lib/ggen_igniter/task_contract.ex
- lib/ggen_igniter/telemetry/ocel_emitter.ex

Mix tasks for G1 (7 files):

- lib/mix/tasks/ggen_igniter.review.ex
- lib/mix/tasks/ggen_igniter.review.pipeline.ex
- lib/mix/tasks/ggen_igniter.review.convergence.ex
- lib/mix/tasks/ggen_igniter.review_eval.run.ex
- lib/mix/tasks/ggen_igniter.review_eval.gate.ex
- lib/mix/tasks/ggen_igniter.review_eval.seed.ex
- lib/mix/tasks/ggen_igniter.security_review.ex

.claude files (F3 drift assignments) and workflows for G1:

- .claude/hooks/ (3 scripts: require-gate-receipt.sh,
  block-secrets-and-unsafe-code.sh, refuse-handwritten-ash.sh)
- .claude/skills/gate/SKILL.md
- .claude/settings.json
- .claude/agents/ggen-reviewer.md
- .claude/receipts/latest.json
- .github/workflows/machine-review.yml
- .github/workflows/risk-tier.yml
- .github/CODEOWNERS

Docs riding G1:

- docs/REVIEW_STATE.md
- docs/VERIFICATION_LEDGER.md
- docs/reference/cli/review.md
- docs/reference/cli/review-pipeline.md
- docs/reference/cli/review-convergence.md
- docs/reference/cli/review-eval-run.md
- docs/reference/cli/review-eval-gate.md
- docs/reference/cli/review-eval-seed.md
- docs/reference/cli/security-review.md
- docs/reference/refusals.md
- priv/ggen/adr-index-pack/ontology.ttl

G1 tests (untracked, 18 + fixture):

- test/ggen_igniter_convergence_test.exs
- test/ggen_igniter_convergence_review_store_test.exs
- test/ggen_igniter_landing_pipeline_test.exs
- test/ggen_igniter_review_eval_corpus_test.exs
- test/ggen_igniter_review_eval_gate_test.exs
- test/ggen_igniter_review_eval_scorer_test.exs
- test/ggen_igniter_review_filter_suppression_test.exs
- test/ggen_igniter_review_risk_tier_test.exs
- test/ggen_igniter_review_store_test.exs
- test/ggen_igniter_review_tally_test.exs
- test/ggen_igniter_security_gate_test.exs
- test/ggen_igniter_security_receipt_test.exs
- test/ggen_igniter_security_review_test.exs
- test/ggen_igniter_airo_risk_description_test.exs
- test/ggen_igniter_ephemeral_projection_test.exs
- test/ggen_igniter_eval_mode_igniter_test.exs
- test/ggen_igniter_sync_eval_mode_test.exs
- test/mix_ggen_igniter_review_pipeline_task_test.exs
- test/support/review_eval_fixture.ex

## Group 2 — epoch multi-plane freshness/watermark

Modified lib (3):

- lib/ggen_igniter/epoch_freshness.ex
- lib/ggen_igniter/epoch_watermark.ex
- lib/ggen_igniter/semantic_jira/epoch_plan.ex

Tests (2 untracked per F3 drift list):

- test/ggen_igniter_epoch_admission_test.exs
- test/ggen_igniter_epoch_config_migrations_test.exs

Other epoch tests on disk (epoch_freshness_test.exs, semantic_epoch_test.exs)
are NOT in any lane's dirty classification — likely already committed; stage
only if git status shows them dirty.

Receipts and lane docs:

- receipts/security/
- docs/jira/v26.10.20/ (lane plans)

## Group 3 — projection execution backend

New lib + fixtures + wiring:

- lib/ggen_igniter/semantic_jira/projection.ex
- lib/ggen_igniter/semantic_jira/cs2_projection.ex (on-disk check: stage only
  if git shows dirty)
- lib/ggen_igniter/semantic_jira/r_projection.ex (same rule)
- test/fixtures/projection-pack/
- lib/ggen_igniter/semantic_jira/execute.ex (M: projection backend)
- lib/mix/tasks/semantic_jira.execute.ex (M: --pack-lock flag wiring)
- lib/mix/tasks/semantic_jira.complete.ex (M: --packs-root backend)
- test/ggen_igniter_semantic_jira_projection_test.exs
- test/ggen_igniter_semantic_jira_cs2_projection_test.exs
- test/ggen_igniter_semantic_jira_r_projection_test.exs

## Group 4 — docs + changelog + aliases

- CHANGELOG.md
- docs/glossary.md
- docs/status.md
- docs/reference/cli/ (remaining modified/untracked cli docs not claimed by G1:
  doctor, engines, epoch, exit-codes, index, install, lock, manifest,
  pack-lock, packs-list, packs, plan, rename, replay, shacl, sync, upgrade)
- docs/architecture/adr/ADR-013-landing-pipeline-staged-composition.md
- docs/architecture/adr/ README (coordinator: resolve exact filename via git)
- .github/workflows/ci.yml
- mix.exs (test.shard + review.eval aliases)

## Group 5 — DELETE tmp-bp-validation/

- Coordinator deletes tmp-bp-validation/ (9 files, ~24K, intact on disk) in a
  standalone commit: git rm -r tmp-bp-validation/

## Per-group gates

Every group, in order, before its commit:

1. mix compile --warnings-as-errors   # exit 0 required
2. Targeted tests per group:
   - G1: mix test test/ggen_igniter_review_store_test.exs \
     test/ggen_igniter_review_tally_test.exs \
     test/ggen_igniter_review_risk_tier_test.exs \
     test/ggen_igniter_security_review_test.exs \
     test/ggen_igniter_landing_pipeline_test.exs \
     test/ggen_igniter_convergence_test.exs
   - G2: mix test test/ggen_igniter_epoch_admission_test.exs \
     test/ggen_igniter_epoch_config_migrations_test.exs
   - G3: mix test test/ggen_igniter_semantic_jira_projection_test.exs \
     test/ggen_igniter_semantic_jira_cs2_projection_test.exs \
     test/ggen_igniter_semantic_jira_r_projection_test.exs
   - G4: docs-only; compile gate suffices
   - G5: ls tmp-bp-validation (must be gone)
3. Full suite after ALL groups staged (pre-commit), expected: 1763 tests,
   2 failures, 5 skipped, exit 2 — the 2 named below and nothing else.
   Any additional failure blocks the seal.

Precedent (F3, receipts in triage note): targeted 11 tests 0 failures exit 0;
full 1763 tests 2 failures exit 2.

## The 2 remaining failures + fixes

1. GgenIgniter.ToolchainPinQualificationTest — running VM is OTP 28.3.1 /
   Elixir 1.19.5, .tool-versions pins erlang 27.2.4 /
   elixir 1.19.5-otp-27. OPERATOR DECISION REQUIRED: align the asdf/mise pin
   to the running VM (rewrite .tool-versions) or switch the VM to the pin
   (asdf install / mise use). Do not seal over this silently.

2. GgenIgniter.FleetReceiptConformanceTest — vendored
   priv/schema/fleet-receipt.v2.json drifted from machine
   ~/.claude/dfcm/receipt.schema.json (vendored b513126e…, machine a2c7510b…).
   Fix: run the test and execute the exact cp re-vendor command it prints:
   cp ~/.claude/dfcm/receipt.schema.json priv/schema/fleet-receipt.v2.json
   then refresh the sibling .sha256 sidecar and re-run the test. (Command
   form above; the test's printed form is authoritative — copy it verbatim.)

## Recommended commit messages (git commit -F <file> style)

Write each message to a temp file, commit with -F. Order: G1, G2, G3, G4, G5.

G1: "feat(review): review/landing-pipeline/convergence/security-review
subsystem + risk-tier wiring, review_eval mix tasks, .claude hooks/skills,
machine-review/risk-tier workflows (seal group G1)"

G2: "feat(epoch): multi-plane freshness/watermark (lib/config/migrations
planes), epoch admission + config-migrations tests (seal group G2)"

G3: "feat(projection): guarded projection execution backend (--pack-lock,
capability projection receipt) + packs-root resolution (seal group G3)"

G4: "docs(seal): changelog, cli reference, ADR-013, status/glossary, ci
aliases (seal group G4)"

G5: "chore(seal): delete tmp-bp-validation scratch debris (seal group G5)"

## Standing and NOT-DONE

Standing: PARTIAL_ALIVE.

NOT-DONE (operator/coordinator executes):

- All commits and any git transitions (lane ran zero git commands by law).
- ToolchainPin fix — blocked on the asdf/mise pin alignment decision.
- FleetReceiptConformance re-vendor cp — schema file not lane-owned.
- git status reconciliation of each group list at staging time.
- Full-suite re-run at staging time (F3's 1763/2 receipt is as-of 2026-11-07
  earlier today; re-verify before landing per receipt-freshness law).
