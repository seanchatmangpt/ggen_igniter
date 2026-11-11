# _LANES.md — v26.10.20 no-human review pipeline + ggen-loop closure

Canonical checkout: `/Users/sac/ggen_igniter`. Coordinator owns ALL git transitions.
Lane builds: `MIX_BUILD_ROOT=_build-lane-<name>`. `git commit -F <file>` only.
Compile-freeze SLA: owner fixes/reverts a shared-compile break within ~10 min; minimal
disclosed unblock fixes allowed. No `git stash`. smalt (`/Users/sac/smalt`) is READ-ONLY
this window (its wave-6 is in flight there).

## In-flight lanes (already dispatched)

| lane | owns |
|---|---|
| w8-projection | `lib/ggen_igniter/semantic_jira/execute.ex` (additive), `lib/ggen_igniter/semantic_jira/projection.ex` (new), `test/ggen_igniter_semantic_jira_projection_test.exs` |
| epoch-courts | `lib/ggen_igniter/epoch_watermark.ex`, `lib/ggen_igniter/epoch_freshness.ex`, `lib/ggen_igniter/semantic_jira/epoch_plan.ex` (minimal additive), `test/ggen_igniter_epoch_config_migrations_test.exs` |

## Wave-2 write lanes

| lane | owns (exclusive) |
|---|---|
| L1 claude-config | `.claude/**` (agents/ggen-reviewer.md round protocol; skills review-round + adjudicate-findings; gate glue line; hooks require-gate-receipt.sh + security content gate; settings.json Stop/PreToolUse entries) |
| L2 review-core | `lib/ggen_igniter/review.ex`, `review/finding.ex`, `review/perspective.ex`, `review/perspectives/*`, `review/verifier.ex`, `review/tally.ex`, `review/filter.ex`, `review/store.ex`, `lib/mix/tasks/ggen_igniter.review.ex`, tests `ggen_igniter_review_{tally,filter_suppression,store}_test.exs` |
| L3 risk-tier | `lib/ggen_igniter/review/risk_tier.ex`, `lib/ggen_igniter/receipt.ex` (additive risk fields via put_optional), `lib/ggen_igniter/reactors/reconcile_reactor.ex` (Receipt.new sites), `test/ggen_igniter_review_risk_tier_test.exs`, receipt round-trip test additions |
| L4 convergence | `lib/ggen_igniter/convergence.ex`, `convergence/hunks.ex`, `convergence/classes.ex`, `lib/ggen_igniter/review_store.ex` (rounds.jsonl — distinct from L2's review/store.ex), `lib/mix/tasks/ggen_igniter.review.convergence.ex`, tests `ggen_igniter_{convergence,review_store}_test.exs`, `telemetry/ocel_emitter.ex` additive event |
| L5 security | `lib/ggen_igniter/task_contract.ex` (exit code 5 SECURITY_BLOCKED), `security_review.ex`, `security_review/*`, `lib/mix/tasks/ggen_igniter.security_review.ex`, `lib/ggen_igniter/refusals.ex` (two codes), `lib/ggen_igniter/semantic_jira/complete.ex` (pre-step), tests `ggen_igniter_security_{review,receipt,gate}_test.exs` |
| L6 review-eval | `lib/ggen_igniter/review_eval/*`, `lib/mix/tasks/ggen_igniter.review_eval.{seed,run,gate}.ex`, `test/ggen_igniter_review_eval_{corpus,scorer,gate}_test.exs`, `test/support/review_eval_fixture.ex` (real tmp-dir git repo — no checked-in corpus), mix.exs alias |
| L7 landing-pipeline | `lib/ggen_igniter/landing_pipeline.ex`, `landing_pipeline/stage.ex`, `lib/mix/tasks/ggen_igniter.review.pipeline.ex`, `test/ggen_igniter_landing_pipeline_test.exs`, `test/mix_ggen_igniter_review_pipeline_task_test.exs` |
| L8 ci | `.github/workflows/**` (machine-review.yml, risk-tier.yml, merge_group trigger on ci.yml) |

## Coordinator-reserved (integration, after lanes land)

`docs/status.md`, `docs/architecture/adr/` (ADR-013 + ontology.ttl + regen),
`docs/glossary.md`, `CHANGELOG.md`, `docs/REVIEW_STATE.md` seed, per-lane atomic commits.

## Shared-file conflict resolutions

- `review.ex` = Perspective behaviour (L2). Risk-tier classifier is `review/risk_tier.ex` (L3), no top-level behaviour edit.
- `receipt.ex` + `reconcile_reactor.ex`: L3 only.
- `task_contract.ex`: L5 only (code 5). L2/L3/L4 exit codes 0/1/2 only.
- `settings.json` + hooks: L1 only. L5 ships the security task; L1 wires the Stop-hook call.
- `.claude/skills/gate/SKILL.md` glue (review-state line + eval-gate step): L1 only.
- `semantic_jira/`: w8 (execute/projection), epoch (epoch_plan), L5 (complete) — file-disjoint.

## Sequencing law

Stage modules are independently landable: a missing stage module is a typed
`{:refused, {:stage_module_missing, name}}` (L7's contract), never a silent skip.
Integration order: per-lane verify → coordinator receipts/docs/ADR → commits per lane.
