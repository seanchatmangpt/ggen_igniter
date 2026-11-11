# COMMIT_PLAN.md — v26.10.20 per-lane commit partition

Generated from live `git status --porcelain` (read-only) against `_LANES.md`
ownership + shared-file resolutions. Base: `main` @ 1a6e60d. No git mutations
performed by this lane; coordinator executes.

## Shared-seam files (collision flags)

| file | lanes claiming | resolution (per _LANES.md) | commit home |
|---|---|---|---|
| `lib/ggen_igniter/receipt.ex` | L3 (+ read by L4/L6/L7) | L3 only | L3 |
| `lib/ggen_igniter/task_contract.ex` | L5 (+L2/L3/L4 use exit codes) | L5 only (code 5) | L5 |
| `lib/ggen_igniter/review.ex` | L2 (+L3 risk_tier subfile) | L2 only (Perspective behaviour) | L2 |
| `lib/ggen_igniter/landing_pipeline.ex` | L7 (+L1 settings wiring, L6 eval gate consumer) | L7 only | L7 |
| `.claude/settings.json` | L1 (+L5 hook content) | L1 only | L1 |
| `lib/ggen_igniter/reactors/reconcile_reactor.ex` | L3 only | — | L3 |
| `lib/ggen_igniter/telemetry/ocel_emitter.ex` | L4 only (additive event) | — | L4 |
| `mix.exs` | L6 (eval aliases); verify no other lane edited | check diff before committing | L6 |
| `semantic_jira/` files | w8 (execute/projection), epoch (epoch_plan), L5 (complete) | file-disjoint | split per lane |

No live write-write collisions detected — the disjoint resolutions held.

## Atomic commit order (shared seams earliest, dependencies first)

1. **epoch-courts** — `lib/ggen_igniter/epoch_watermark.ex`,
   `epoch_freshness.ex`, `semantic_jira/epoch_plan.ex`,
   `test/ggen_igniter_epoch_config_migrations_test.exs`.
   (Landing pipeline's `epoch_check.ex` stage depends on it.)
2. **w8-projection** — `semantic_jira/execute.ex` (additive),
   `semantic_jira/projection.ex`,
   `test/ggen_igniter_semantic_jira_projection_test.exs`,
   `test/ggen_igniter_semantic_jira_execute_replay_fence_test.exs`,
   `test/fixtures/projection-pack/`.
3. **L2 review-core** — `review.ex`, `review/{finding,perspective,verifier,
   tally,filter,store}.ex`, `review/perspectives/`,
   `mix/tasks/ggen_igniter.review.ex`,
   `test/ggen_igniter_review_{tally,filter_suppression,store}_test.exs`.
4. **L3 risk-tier** — `review/risk_tier.ex` (lives under `review/`, lands
   after L2's dir exists), `receipt.ex`, `reactors/reconcile_reactor.ex`,
   `test/ggen_igniter_review_risk_tier_test.exs`,
   `test/ggen_igniter_receipt_schema_test.exs`, `priv/schema/receipt.schema.json`.
5. **L4 convergence** — `convergence.ex`, `convergence/`,
   `review_store.ex`, `mix/tasks/ggen_igniter.review.convergence.ex`,
   `telemetry/ocel_emitter.ex`,
   `test/ggen_igniter_{convergence,convergence_review_store}_test.exs`.
6. **L5 security** — `task_contract.ex`, `security_review.ex`,
   `security_review/`, `mix/tasks/ggen_igniter.security_review.ex`,
   `semantic_jira/complete.ex`, `mix/tasks/semantic_jira.complete.ex`,
   `refusals.md`-backing `priv/schema/refusals.schema.json`,
   `docs/reference/refusals.md`, `docs/reference/cli/exit-codes.md`,
   `test/ggen_igniter_security_{review,receipt,gate}_test.exs`,
   `test/ggen_igniter_task_contract_test.exs`,
   `receipts/security/` (see receipts note).
7. **L6 review-eval** — `review_eval/`, `mix/tasks/ggen_igniter.review_eval.*`,
   `test/ggen_igniter_review_eval_*_test.exs`,
   `test/support/review_eval_fixture.ex`, `mix.exs`.
8. **L7 landing-pipeline** — `landing_pipeline.ex`, `landing_pipeline/`,
   `mix/tasks/ggen_igniter.review.pipeline.ex`,
   `test/ggen_igniter_landing_pipeline_test.exs`,
   `test/mix_ggen_igniter_review_pipeline_task_test.exs`,
   `docs/reference/cli/review-pipeline.md`.
9. **L8 ci** — `.github/workflows/{machine-review,risk-tier}.yml`,
   `.github/workflows/ci.yml` (merge_group trigger), `.github/CODEOWNERS`.
10. **L1 claude-config** — `.claude/settings.json`, `.claude/agents/ggen-reviewer.md`,
    `.claude/skills/{gate/SKILL.md,review-round/,adjudicate-findings/}`,
    `.claude/hooks/{require-gate-receipt,block-secrets-and-unsafe-code}.sh`,
    `.claude/receipts/` (see receipts note — likely should NOT be committed).
11. **Coordinator docs/integration** — `docs/status.md`, `docs/glossary.md`,
    `CHANGELOG.md`, `docs/REVIEW_STATE.md`, `docs/VERIFICATION_LEDGER.md`,
    `docs/architecture/adr/ADR-013-*.md`, `docs/architecture/adr/README.md`
    (generated — commit alongside `priv/ggen/adr-index-pack/ontology.ttl`
    in the same commit, ontology first),
    `docs/reference/cli/{index,review,review-convergence,review-eval-*,
    security-review}.md`, `docs/jira/v26.10.20/` (this file, _LANES.md,
    runbooks, falsifiers), `test/support/semantic_a2a_manufactured.ex`
    (verify owning lane — currently unattributed, ask before committing).

## Generated / receipt / scratch files — handle explicitly

- **Generated**: `docs/architecture/adr/README.md` — regenerate from
  `priv/ggen/adr-index-pack/` via ggen sync; never hand-edit; commit with the
  ontology.ttl edit in the same commit.
- **Receipts**: `.claude/receipts/latest.json`, `receipts/security/1a6e60d6.json`
  — NOT covered by `.gitignore` (verified via `git check-ignore`: no match).
  Proposal: `.claude/receipts/` → add to `.gitignore` (session-local harness
  state); `receipts/security/` → keep committed (per-security-review receipt
  is a replay artifact, keyed by head SHA) or gitignore if the cohort decides
  receipts live out-of-tree. Coordinator decides; default: ignore
  `.claude/receipts/`, commit `receipts/security/`.
- **`.ggen_igniter/`** — already ignored (`.gitignore:18`); no action.
- **Scratch**: `tmp-bp-validation/` (gate/pack census scratch) — not ignored;
  proposal: delete at integration or add `/tmp-bp-validation/` to `.gitignore`.
  `_build-lane-*/` and `target-lane-*/` already ignored (`.gitignore:72`).

## `_build-lane-*` dirs to purge at integration (coordinator, before final commit)

```
_build-lane-c1 _build-lane-c14 _build-lane-c15 _build-lane-c16 _build-lane-c18
_build-lane-c19 _build-lane-c2 _build-lane-c3 _build-lane-c4 _build-lane-c7
_build-lane-c8 _build-lane-docs _build-lane-e6 _build-lane-ep _build-lane-g1
_build-lane-l2 _build-lane-l3 _build-lane-l4 _build-lane-l5 _build-lane-l6
_build-lane-l7 _build-lane-w8
```

(22 dirs; git-invisible via `_build-lane*/` but consuming disk — delete at
integration per the cleanup law.)

## Unattributed (ask owner before committing)

- `test/support/semantic_a2a_manufactured.ex` (M) — not in any lane's owns list.
- `mix.exs` (M) — L6 claims the alias; confirm diff contains only eval aliases.
- `test/ggen_igniter_semantic_jira_execute_replay_fence_test.exs` (??) —
  assumed w8 (execute.ex adjacency); confirm.
- `docs/reference/cli/exit-codes.md`, `docs/reference/refusals.md` — assumed L5
  (code 5 SECURITY_BLOCKED); coordinator may prefer doc batch in commit 11.
