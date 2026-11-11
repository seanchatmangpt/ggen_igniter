# RESTART_HANDOFF — v26.10.20 no-human review pipeline + ggen-loop closure

Written 2026-10-20 on canonical checkout `/Users/sac/ggen_igniter`, branch `main`,
remote `origin https://github.com/seanchatmangpt/ggen_igniter.git`,
HEAD `1a6e60d feat(sj-execute): pre-digest Elixir formatting of manufactured artifacts`.
`mix compile --warnings-as-errors` → **exit 0**.

## 1. Mission

Ship the v26.10.20 wave: a no-human review pipeline (adversarial review → risk tiering →
convergence → security gate → review-eval corpus/scorer/gate → staged landing pipeline) that
closes the ggen-loop: W8 `:projection` backend for `mix semantic_jira.execute`, epoch courts
extended to `config/` + `priv/repo/migrations/`, pack-bootstrap pack in `~/ggen-marketplace`,
and a reference receipt whose kill-criterion falsifier is F1 (`|Δ|=0`, §4). A fresh session
picks up at §3; all lane code in §2 is on disk and uncommitted.

## 2. Lane table (observed on disk, 2026-10-20)

All lane code is LANDED and UNCOMMITTED unless noted. Lane ownership is defined in
`docs/jira/v26.10.20/_LANES.md`.

| lane | status | owned files (verified on disk) |
|---|---|---|
| w8-projection | LANDED (uncommitted) | `lib/ggen_igniter/semantic_jira/projection.ex` (new), `lib/ggen_igniter/semantic_jira/execute.ex` (modified, additive), `test/ggen_igniter_semantic_jira_projection_test.exs`, `test/fixtures/projection-pack/` |
| epoch-courts | LANDED (uncommitted) | `lib/ggen_igniter/epoch_watermark.ex` (default globs now `lib/**/*.ex`, `config/**/*.exs`, `priv/repo/migrations/**/*.exs` — `epoch_watermark.ex:60`), `lib/ggen_igniter/epoch_freshness.ex`, `lib/ggen_igniter/semantic_jira/epoch_plan.ex`, `test/ggen_igniter_epoch_config_migrations_test.exs` |
| L1 claude-config | LANDED (uncommitted) | `.claude/skills/review-round/`, `.claude/skills/adjudicate-findings/`, `.claude/hooks/require-gate-receipt.sh`, `.claude/hooks/block-secrets-and-unsafe-code.sh`, `.claude/agents/ggen-reviewer.md`, `.claude/skills/gate/SKILL.md`, `.claude/settings.json` |
| L2 review-core | LANDED (uncommitted) | `lib/ggen_igniter/review.ex`, `lib/ggen_igniter/review/{finding,perspective,verifier,tally,filter,store}.ex`, `lib/ggen_igniter/review/perspectives/{correctness,chicago_tests,epoch_law,invariants}.ex`, `lib/mix/tasks/ggen_igniter.review.ex`, `test/ggen_igniter_review_{tally,filter_suppression,store}_test.exs` |
| L3 risk-tier | LANDED (uncommitted) | `lib/ggen_igniter/review/risk_tier.ex`, `lib/ggen_igniter/receipt.ex` (additive risk fields), `lib/ggen_igniter/reactors/reconcile_reactor.ex`, `test/ggen_igniter_review_risk_tier_test.exs` |
| L4 convergence | LANDED (uncommitted) | `lib/ggen_igniter/convergence.ex`, `lib/ggen_igniter/convergence/{hunks,classes}.ex`, `lib/ggen_igniter/review_store.ex` (rounds.jsonl; distinct from L2's `review/store.ex`), `lib/mix/tasks/ggen_igniter.review.convergence.ex`, `test/ggen_igniter_{convergence,review_store}_test.exs`, `lib/ggen_igniter/telemetry/ocel_emitter.ex` (additive event) |
| L5 security | LANDED (uncommitted) | `lib/ggen_igniter/task_contract.ex` (exit code 5 SECURITY_BLOCKED, lines 57-59), `lib/ggen_igniter/security_review.ex`, `lib/ggen_igniter/security_review/{receipt,diff_source}.ex`, `lib/ggen_igniter/security_review/checks/{secrets_in_diff,shell_interpolation,path_traversal,dependency_change,hook_settings_change}.ex`, `lib/mix/tasks/ggen_igniter.security_review.ex`, `lib/ggen_igniter/semantic_jira/complete.ex` (pre-step), `test/ggen_igniter_security_review_test.exs` (exists; `_receipt_`/`_gate_` variants MISSING — see §6.3) |
| L6 review-eval | LANDED (uncommitted) | `lib/ggen_igniter/review_eval/{corpus,scorer,gate,case_runner,receipt,seed}.ex`, `lib/mix/tasks/ggen_igniter.review_eval.{seed,run,gate}.ex`, `test/ggen_igniter_review_eval_{corpus,scorer,gate}_test.exs`, `test/support/review_eval_fixture.ex`, `mix.exs` alias `"review.eval"` at line 125. **MISSING: `test/fixtures/review_eval/`** (declared in _LANES.md L6 row, absent on disk) |
| L7 landing-pipeline | LANDED (uncommitted) | `lib/ggen_igniter/landing_pipeline.ex`, `lib/ggen_igniter/landing_pipeline/stage.ex`, `lib/mix/tasks/ggen_igniter.review.pipeline.ex`, `test/ggen_igniter_landing_pipeline_test.exs`, `test/mix_ggen_igniter_review_pipeline_task_test.exs` |
| L8 ci | LANDED (uncommitted) | `.github/workflows/machine-review.yml`, `.github/workflows/risk-tier.yml` (both new), `.github/workflows/ci.yml` (modified: `merge_group` trigger at line 7) |
| Coordinator | NOT-STARTED | `docs/status.md` review-pipeline rows (0 present — grepped), `docs/architecture/adr/ADR-013-no-human-review-pipeline.md` + `priv/ggen/adr-index-pack/ontology.ttl` individuals + regen, `docs/glossary.md` terms, `CHANGELOG.md` v26.10.20 entry (file exists, no wave entry), `docs/REVIEW_STATE.md` seed (does not exist), per-lane atomic commits |

## 3. What remains

### 3a. Per-lane verification gates

Compose per lane: `MIX_BUILD_ROOT=_build-lane-<name> mix test <that lane's test files from §2>`.
A summary is not a receipt — paste real output.

```
# w8-projection
MIX_BUILD_ROOT=_build-lane-w8 mix test test/ggen_igniter_semantic_jira_projection_test.exs

# epoch-courts
MIX_BUILD_ROOT=_build-lane-epoch mix test test/ggen_igniter_epoch_config_migrations_test.exs

# L2 review-core
MIX_BUILD_ROOT=_build-lane-L2 mix test test/ggen_igniter_review_tally_test.exs test/ggen_igniter_review_filter_suppression_test.exs test/ggen_igniter_review_store_test.exs

# L3 risk-tier (also rerun receipt round-trip tests it touched)
MIX_BUILD_ROOT=_build-lane-L3 mix test test/ggen_igniter_review_risk_tier_test.exs test/ggen_igniter_receipt_schema_test.exs test/ggen_igniter_task_contract_test.exs

# L4 convergence
MIX_BUILD_ROOT=_build-lane-L4 mix test test/ggen_igniter_convergence_test.exs test/ggen_igniter_review_store_test.exs

# L5 security (FIRST probe: ls test/ggen_igniter_security_*_test.exs; files unverified on disk)
MIX_BUILD_ROOT=_build-lane-L5 mix test test/ggen_igniter_security_review_test.exs test/ggen_igniter_security_receipt_test.exs test/ggen_igniter_security_gate_test.exs

# L6 review-eval (alias: mix review.eval)
MIX_BUILD_ROOT=_build-lane-L6 mix test test/ggen_igniter_review_eval_corpus_test.exs test/ggen_igniter_review_eval_scorer_test.exs test/ggen_igniter_review_eval_gate_test.exs

# L7 landing-pipeline
MIX_BUILD_ROOT=_build-lane-L7 mix test test/ggen_igniter_landing_pipeline_test.exs test/mix_ggen_igniter_review_pipeline_task_test.exs

# L1 claude-config (no mix tests)
ls -l .claude/hooks/require-gate-receipt.sh .claude/hooks/block-secrets-and-unsafe-code.sh  # executable bits
python3 -c "import json; json.load(open('.claude/settings.json'))"                          # valid JSON
```

Lane build roots (`_build-lane-*`) are leases: the coordinator deletes every one at
integration, before the final commit. W8 additionally exercises
`mix semantic_jira.execute --backend projection` end-to-end against
`test/fixtures/projection-pack/`.

### 3b. Coordinator integration steps, in order

1. Run §3a gates per lane; record real output per lane.
2. `docs/status.md`: add one sourced row per new capability (review pipeline stages,
   risk tier, convergence, security gate, review-eval, landing pipeline, W8 projection
   backend, epoch courts to config/migrations), each with file:line + test citations.
3. ADR-013: add individuals to `priv/ggen/adr-index-pack/ontology.ttl`, then
   `mix ggen_igniter.sync --pack adr-index-pack --engine sparql --out docs/architecture/adr/README.md`;
   write `docs/architecture/adr/ADR-013-no-human-review-pipeline.md` matching the existing
   ADR scheme in that directory.
4. `docs/glossary.md`: add terms (risk tier, convergence, review-eval gate, landing stage,
   SECURITY_BLOCKED) with sourced definitions.
5. `CHANGELOG.md`: v26.10.20 entry.
6. Seed `docs/REVIEW_STATE.md` (empty findings ledger; consumed by the adjudicate-findings skill).
7. Per-lane atomic commits, `git commit -F <file>` only, never `-m`; coordinator owns ALL git
   transitions. Delete `_build-lane-*` dirs before the final commit.
8. Pack-bootstrap pack in `~/ggen-marketplace` (cross-repo; smalt read-only constraint does
   not block ggen-marketplace — verify its wave state before writing).

## 4. Falsifier register

- **F1** (kill criterion): the reference receipt replays with `|Δ|=0` — any nonzero delta
  between recorded and recomputed state refuses the receipt; if a mutated artifact still
  admits, F1 is violated and the pipeline is not ALIVE.
- **F2** (epoch courts): a post-watermark edit to `config/**/*.exs` or
  `priv/repo/migrations/**/*.exs` without attribution must refuse
  (`REFUSED_*` verdict, exit != 0); if it compiles in clean, F2 is violated.
- **F3** (no-human review gate): `mix ggen_igniter.review_eval.gate` must fail (exit 1)
  with an open blocking finding in `docs/REVIEW_STATE.md`; if the gate passes with open
  blockers, F3 is violated.
- **F4** (security gate): a diff containing a planted secret must exit 5 SECURITY_BLOCKED
  through `mix ggen_igniter.security_review`; if it lands clean, F4 is violated.

## 5. Repo laws a restart must honor

- One canonical checkout `/Users/sac/ggen_igniter`; NO worktrees, no `~/wt/`, no clones
  (topology guard refuses).
- Coordinator owns ALL git transitions; lanes never run git state commands; no `git stash`.
- Chicago-style tests only: real collaborators, state assertions; no Mox/:meck/Mimic/Patch/mockall.
- Epoch law: `Admit(f) ⟺ FreshEpoch(f)` for implementation-plane files; receipts admit,
  similarity only refuses.
- `git commit -F <file>`, never inline `-m`.
- smalt (`/Users/sac/smalt`) is READ-ONLY this window — its wave-6 is in flight there.
- Compile-freeze SLA: fix/revert a shared-compile break within ~10 min, disclosed.
- A summary is not a receipt: `mix compile --warnings-as-errors` + `mix test` output pasted.

## 6. Open risks (this audit, 2026-10-20)

1. **Compile**: `mix compile --warnings-as-errors` exit 0 — clean.
2. **`test/fixtures/review_eval/` missing** (L6, declared in _LANES.md): corpus tests may
   depend on it — run L6 gate before integration.
3. **L5 security tests partial** (probed after draft): only
   `test/ggen_igniter_security_review_test.exs` exists on disk;
   `test/ggen_igniter_security_receipt_test.exs` and `test/ggen_igniter_security_gate_test.exs`
   (named in _LANES.md) are MISSING, and none of the three appear in `git status --short`
   (even the existing one — likely inside an untracked dir or unlisted; `git status --short`
   lists it nowhere). Run the L5 gate before citing L5 ALIVE.
4. **All lane work is uncommitted** on `main` (19 modified + ~45 untracked paths); a crash
   loses nothing on disk but there are zero wave commits yet — per-lane atomic commits are the
   first coordinator action after gates.
5. **ADR-013 / status rows / glossary / changelog / REVIEW_STATE.md** all not started.
6. This file was first written corrupted (mid-generation degradation) and was rewritten clean
   by delete + piecewise rewrite; if any §2 path looks wrong, trust `git status --short` +
   `ls` over this table.

## 7. Disclosed residue closed (write lane, 2026-10-20)

`--packs-root` is now documented at full density in the
`mix semantic_jira.complete` moduledoc
(`lib/mix/tasks/semantic_jira.complete.ex`): mutual exclusion with `--pack-dir`
at the invocation boundary (exit 2, `pack_source_exclusive/1`), per-order
`sj:targetPack` resolution to `<packs-root>/<target_pack>` (multi-pack backlog
closes in one run), per-order `Execute.run/1` WORLD check
(`REFUSED(target_pack_mismatch)` on mismatch), and the settled-blocked receipt
law (blocked rows are the kernel's own settled work, recorded in the exit-0
receipt — never re-executed, never a failure; unchanged by `--packs-root`).
Verified, no change needed: `--pack-lock` is already documented on
`mix semantic_jira.execute` (projection backend entry,
`lib/mix/tasks/semantic_jira.execute.ex` Backends section, citing
PROJECTION-ARCH-PLAN §D4). No code behavior changed — moduledoc-only edit.
Chicago receipt: `mix help semantic_jira.complete` output captured in the lane
receipt; completion verified by re-read on disk.
