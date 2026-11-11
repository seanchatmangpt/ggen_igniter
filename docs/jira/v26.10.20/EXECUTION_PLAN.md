# EXECUTION_PLAN

Closing execution plan for the v26.10.20 wave. Written 2026-10-20 on canonical
checkout `/Users/sac/ggen_igniter`, branch `main`, HEAD `1a6e60d`. Every status
claim below cites a check executed in the write pass that produced this file
(2026-10-20, ~11:07–11:35 local). No git mutations were performed by this lane.
Lane ownership: `docs/jira/v26.10.20/_LANES.md` (this file is the only owned
path of the write lane that produced it).

## 1. Gate receipt attestation — what is still red/open

| check | command run this pass | result |
|---|---|---|
| Compile gate | `mix compile --warnings-as-errors` | exit 0, clean |
| Full suite | `mix test` (full, default `_build`) | ATTEMPT 1 launched 11:27 local, killed at the 10-min background limit — 29 concurrent beam processes on the host (other lanes' gates) starved it; no receipt produced. **Coordinator must run and paste the real tail (`N tests, M failures`) into §1a before any commit or F1 run.** A summary is not a receipt. |
| F1 | `docs/jira/v26.10.20/F1_RUNBOOK.md` | header line 3: `STATUS: NOT-YET-EXECUTED`; §6 checkboxes all empty — F1 not executed, no F1_REFERENCE_RECEIPT exists |
| REVIEW_STATE | `docs/REVIEW_STATE.md` | exists; `current_round: 0`, `rounds_run: 0`, verdict `none` — no adversarial review round has run against the wave diff |
| VERIFICATION_LEDGER | `docs/VERIFICATION_LEDGER.md` | exists; falsifier table empty (example row commented out) — all falsifier rows open |
| Commits | `git log --oneline -3` | HEAD still `1a6e60d` — zero wave commits; all lane work uncommitted (87 changed/untracked paths in `git status --short`) |

Open (red) items are exactly: (a) full-suite green receipt not yet pasted,
(b) F1 not executed, (c) REVIEW_STATE round 0 — no adversarial round against
the wave diff, (d) VERIFICATION_LEDGER falsifier rows open, (e) zero wave
commits.

## 1a. Full-suite receipt (coordinator to overwrite)

```
# PASTE REAL `mix test` TAIL HERE BEFORE ANY COMMIT OR F1 RUN
```

§1a is the blocking hop for §3. No green receipt, no commits, no F1.

## 2. Residue closure checklist (re-verified on disk this pass)

| item | owner lane | check run this pass | status |
|---|---|---|---|
| `--packs-root` doc | write lane (RESTART_HANDOFF §7) | `grep -n "packs-root" lib/mix/tasks/semantic_jira.complete.ex` → mutual exclusion with `--pack-dir` (`pack_source_exclusive/1`, exit 2, lines 121–126), per-order `sj:targetPack` resolution (lines 135–138); RESTART_HANDOFF §7 records closure | **LANDED** |
| CODEOWNERS | L8 ci (`_LANES.md` L8 owns `.github/**`) | `head .github/CODEOWNERS` → risk-tier floor rationale + `.github/workflows/` and `lib/` owned `@seanchatmangpt` | **LANDED** |
| ADR-013 file | docs lane | `ls docs/architecture/adr/ADR-013-landing-pipeline-staged-composition.md` → exists | **LANDED** |
| ADR-013 README regen | docs lane | `grep -n "ADR-013" docs/architecture/adr/README.md` → line 46 row, "Accepted (2026-10-20)" | **LANDED** |
| ADR-013 ontology individual | docs lane | `grep -n "ADR-013" priv/ggen/adr-index-pack/ontology.ttl` → individual at lines 162–165 (`adr:number "ADR-013"`, "Added v26.10.20 (docs lane, ADR-013)") | **LANDED** |
| Replay fence (C7) | w8-projection | `grep -n "replay fence" lib/ggen_igniter/semantic_jira/execute.ex` → moduledoc lines 80/95 citing `test/ggen_igniter_semantic_jira_execute_replay_fence_test.exs`; `ls test/ggen_igniter_semantic_jira_execute_replay_fence_test.exs` → exists | **LANDED** |
| Stage modules (C14) | L7 landing-pipeline | `ls lib/ggen_igniter/landing_pipeline/` → all 8 files: `stage.ex`, `build_gate.ex`, `convergence_cap.ex`, `epoch_check.ex`, `fanout_review.ex`, `incident_eval.ex`, `risk_tier.ex`, `security_block.ex` | **LANDED** |
| human_minutes (C18) | C18 | `grep -n human_minutes` → `lib/ggen_igniter/landing_pipeline.ex:54,328,356`; `priv/schema/receipt.schema.json:151`; `test/ggen_igniter_receipt_schema_test.exs:400-408` (dedicated describe block "human_minutes (lane C18, additive F2 seed)") | **LANDED** |
| eval fixtures (C19) | L6 review-eval | `ls test/support/review_eval_fixture.ex` → exists (real tmp-dir git repo builder); `ls test/fixtures/` → no `review_eval/` entry, and that absence is declared by design in the `_LANES.md` L6 row ("real tmp-dir git repo — no checked-in corpus") | **LANDED (by design; no checked-in corpus)** |

The C-numbering (C5/C6/C7/C10/C14/C18/C19) does not appear in `_LANES.md`, PRD,
or ARD — those were first-wave dispatch lanes; their outputs are verified above
by file checks, not lane-number bookkeeping.

## 2a. Status corrections vs RESTART_HANDOFF §6 open risks

- §6.2 (`test/fixtures/review_eval/` missing): **CLOSED as by-design** — the
  `_LANES.md` L6 row declares the fixture is
  `test/support/review_eval_fixture.ex` (exists on disk this pass), a real
  tmp-dir git repo; no checked-in corpus.
- §6.3 (L5 security tests missing): **CLOSED** — `ls test/ggen_igniter_security_*_test.exs`
  → all three exist (`_review_`, `_receipt_`, `_gate_`).

## 3. Coordinator atomic-commit plan (no git mutations performed by this lane)

Precondition: §1a green receipt pasted. Then, in order:

1. **Per-lane gates** (RESTART_HANDOFF §3a commands,
   `MIX_BUILD_ROOT=_build-lane-<name>`), real output recorded per lane. L1 gate
   = `ls -l` executable bits on both hooks + `python3 -m json.tool .claude/settings.json`.
2. **Purge `_build-lane-*`** — 21 lease dirs present this pass
   (`ls -d _build-lane-*`: c1, c14, c15, c16, c18, c19, c2, c3, c4, c7, c8,
   docs, ep, g1, l2, l3, l4, l5, l6, l7, w8). Coordinator deletes all before the
   final integration commit (same-checkout-fanout cleanup law). Note: c15/c16
   have build roots but no `_LANES.md` row — first-wave lanes; the dirs are
   untracked leases, deleting them destroys nothing owned.
3. **Per-lane atomic commits**, `git commit -F <file>` only (never inline `-m`),
   one commit per lane, respecting `_LANES.md` exclusive ownership. Suggested
   partition (paths from `git status --short`, 87 paths counted this pass):
   - w8-projection → `lib/ggen_igniter/semantic_jira/projection.ex`,
     `execute.ex`, replay-fence test, `test/fixtures/projection-pack/`
   - epoch-courts → `epoch_watermark.ex`, `epoch_freshness.ex`,
     `epoch_plan.ex`, `test/ggen_igniter_epoch_config_migrations_test.exs`
   - L1 → `.claude/**`
   - L2 → `review.ex`, `review/{finding,perspective,verifier,tally,filter,store}.ex`,
     `review/perspectives/*`, `lib/mix/tasks/ggen_igniter.review.ex`, L2 tests
   - L3 → `review/risk_tier.ex`, `receipt.ex`, `reactors/reconcile_reactor.ex`,
     `test/ggen_igniter_review_risk_tier_test.exs`
   - L4 → `convergence.ex`, `convergence/*`, `review_store.ex`,
     `lib/mix/tasks/ggen_igniter.review.convergence.ex`,
     `telemetry/ocel_emitter.ex`, L4 tests
   - L5 → `task_contract.ex`, `security_review*`, `refusals` schema/code 5,
     `semantic_jira/complete.ex` pre-step, all three security tests
   - L6 → `review_eval/*`, review_eval mix tasks, review-eval tests,
     `test/support/review_eval_fixture.ex`, `mix.exs` alias
   - L7 → `landing_pipeline.ex`, `landing_pipeline/*`, pipeline task, pipeline tests
   - L8 → `.github/**` (machine-review.yml, risk-tier.yml, ci.yml, CODEOWNERS)
   - coordinator-docs → `docs/status.md`, `docs/architecture/adr/` (ADR-013 +
     README + ontology.ttl), `docs/glossary.md`, `CHANGELOG.md`,
     `docs/REVIEW_STATE.md`, `docs/VERIFICATION_LEDGER.md`,
     `docs/jira/v26.10.20/*`, `docs/reference/cli/review*.md`,
     `docs/reference/cli/exit-codes.md`, `docs/reference/cli/index.md`
   Shared seams per `_LANES.md`: `receipt.ex`=L3 only, `task_contract.ex`=L5
   only, `settings.json`=L1 only, `review.ex`=L2 only.
4. **Final integration commit** carries this file + the §1a receipt; the
   `_build-lane-*` purge (step 2) completes before it.

## 3a. Remaining docs-lane open item

`docs/status.md` sourced rows (RESTART_HANDOFF §3b step 2): grep this pass
counted 13 wave-term hits in `docs/status.md`, but per-row sourcing density was
not audited row-by-row this pass — the coordinator must verify each new
capability row carries file:line + test citations during integration. This is
the only docs-lane residue item still OPEN.

## 4. F1 pointer

F1 (reference receipt, `|Δ|=0`) is **NOT-YET-EXECUTED**. Procedure, preconditions,
invocation sequence, and the §6 execution-receipt checklist live in
`docs/jira/v26.10.20/F1_RUNBOOK.md` (exists on disk, verified this pass).
Coordinator runs F1 only after: green §1a receipt → per-lane gates → per-lane
commits → `_build-lane-*` purge. F1's mutation probe is the non-vacuity leg.

## Disclosure

First write of this file degraded mid-generation and was rewritten clean in
full (piecewise-rewrite law, same disclosure as RESTART_HANDOFF §6.6). This
file is the record; no other file was edited by this lane.
