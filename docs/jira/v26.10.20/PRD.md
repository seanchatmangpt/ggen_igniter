# PRD — v26.10.20 no-human review pipeline

Status: DRAFT consolidating the 2026-10-20 wave. Every capability claim below cites an
artifact verified on disk 2026-10-20 on `main` (HEAD `1a6e60d`, dirty tree). Claims not
backed by an on-disk artifact or a pasted run output are marked **UNKNOWN** — never ALIVE.

## 1. Mission and scope

Ship the v26.10.20 wave: a no-human review pipeline — adversarial review, risk tiering,
convergence capping, security gate, review-eval corpus/scorer/gate, and a staged landing
pipeline — plus the W8 `:projection` backend for `mix semantic_jira.execute` and epoch
courts extended to `config/**/*.exs` and `priv/repo/migrations/**/*.exs`. All lane code is
on disk, uncommitted, on `main` (see `docs/jira/v26.10.20/RESTART_HANDOFF.md` §2).

In scope: `lib/ggen_igniter/{review,review_eval,security_review,convergence,landing_pipeline}`,
`semantic_jira/projection.ex`, `epoch_watermark.ex`/`epoch_freshness.ex`/`semantic_jira/epoch_plan.ex`,
`receipt.ex` risk fields, `.github/workflows/{machine-review,risk-tier,ci}.yml`, CLI docs under
`docs/reference/cli/`, `.claude/{skills,hooks,agents}` wiring.

Out of scope: pack-bootstrap pack in `~/ggen-marketplace` (cross-repo, not this checkout),
coordinator integration steps (status.md rows, ADR regen, glossary, changelog, commits —
coordinator-owned).

## 2. Per-subsystem requirements

### 2.1 Review core (L2)

Sources: `lib/ggen_igniter/review.ex`, `lib/ggen_igniter/review/{finding,perspective,verifier,tally,filter,store}.ex`,
`review/perspectives/{correctness,chicago_tests,epoch_law,invariants}.ex`,
`lib/mix/tasks/ggen_igniter.review.ex`, tests `test/ggen_igniter_review_{tally,filter_suppression,store}_test.exs`.

- R2.1-1: a `Perspective` behaviour (`review.ex`) with four real perspectives
  (correctness, chicago_tests, epoch_law, invariants); each returns findings over a real
  diff.
- R2.1-2: findings follow the REVIEW_STATE schema (id/severity/bug-class/invariant/
  file:line/status/what/fix criterion) — same schema as `docs/REVIEW_STATE.md`.
- R2.1-3: `tally.ex` verdict law: PROCEED only if blockers == 0 (mirrors `docs/REVIEW_STATE.md`).
- R2.1-4: `filter.ex` suppresses duplicate/stale findings; suppression itself is tested
  (`ggen_igniter_review_filter_suppression_test.exs`).
- R2.1-5: `store.ex` persists findings to a real store; state-based tests only.

Acceptance: the L2 gate from `RESTART_HANDOFF.md` §3a —
`MIX_BUILD_ROOT=_build-lane-L2 mix test test/ggen_igniter_review_tally_test.exs test/ggen_igniter_review_filter_suppression_test.exs test/ggen_igniter_review_store_test.exs`.

### 2.2 Risk tier (L3)

Sources: `lib/ggen_igniter/review/risk_tier.ex`, `receipt.ex` (additive risk fields
`risk_tier`/`risk_score`/`risk_approvals`, `receipt.ex:204-206`, defaults at `:255-257`,
JSON projection via `put_optional` at `:465-467`), `reconcile_reactor.ex` (Receipt.new sites),
`test/ggen_igniter_review_risk_tier_test.exs`.

- R2.2-1: deterministic classifier: `score >= 10 → :high`, `score >= 3 → :medium`,
  else `:low` (`risk_tier.ex:27-28`); hard floors: workflows path → at least `:high`,
  `lib/**/*.ex` → at least `:medium`, ≥10 files → `:medium`, ≥25 files → `:high`,
  `:delete` under `lib/` → `:high`, empty diff → `:low`/score 0/`empty_diff` signal
  (`risk_tier.ex:32-36`).
- R2.2-2: risk fields are reproducible from the receipt: the classification is derivable
  from fields the receipt already carries (doc at `risk_tier.classifier` header lines 11-15).
- R2.2-3: additive receipt fields round-trip through the JSON schema
  (`test/ggen_igniter_receipt_schema_test.exs` modified this wave).

Acceptance: L3 gate (`RESTART_HANDOFF.md` §3a) — risk-tier test + receipt round-trip tests.

### 2.3 Convergence (L4)

Sources: `convergence.ex`, `convergence/hunks.ex`, `convergence/classes.ex`,
`review_store.ex` (rounds.jsonl — distinct from L2's `review/store.ex`),
`lib/mix/tasks/ggen_igniter.review.convergence.ex` (on disk),
`docs/reference/cli/review-convergence.md`.

- R2.3-1: convergence classes are a closed set:
  `[:formatting, :dead_code, :type_mismatch, :missing_doc, :test_gap, :naming]`
  (`convergence/classes.ex:9`).
  Closed-set law: an unknown class is refused, never silently skipped
  (`apply_class_fix` guards `class in @classes`, `classes.ex:30-32`).
- R2.3-2: hunk attribution over the real diff (`convergence/hunks.ex`).
- R2.3-3: rounds.jsonl append-only store with an additive OCEL event in
  `telemetry/ocel_emitter.ex` (per `_LANES.md` L4 row).
- R2.3-4: `mix ggen_igniter.review.convergence` CLI exists
  (`docs/reference/cli/review-convergence.md` on disk).

Acceptance: L4 gate (`RESTART_HANDOFF.md` §3a).

### 2.4 Security review (L5)

Sources: `security_review.ex`, `security_review/{receipt,diff_source}.ex`,
`security_review/checks/{secrets_in_diff,shell_interpolation,path_traversal,dependency_change,hook_settings_change}.ex`,
`task_contract.ex` exit code 5 `:security_blocked` (`task_contract.ex:57-59`),
`semantic_jira/complete.ex` pre-step, CLI doc `docs/reference/cli/security-review.md`.

- R2.4-1: five real checks (secrets_in_diff, shell_interpolation, path_traversal,
  dependency_change, hook_settings_change) over the real diff
  (`security_review/diff_source.ex`).
- R2.4-2: open security findings → exit 5 SECURITY_BLOCKED (documented exit-code table,
  `task_contract.ex:15,57-59`).
- R2.4-3: `security_review/receipt.ex` emits a receipt; `complete.ex` runs security review
  as a pre-step before completion admission.
- R2.4-4: tests `ggen_igniter_security_{review,receipt,gate}_test.exs` — all three exist on
  disk (2026-10-20, superseding the RESTART_HANDOFF §6.3 "MISSING" note).

Acceptance: L5 gate (`RESTART_HANDOFF.md` §3a) with all three security test files.

### 2.5 Review-eval (L6)

Sources: `review_eval/{corpus,scorer,gate,case_runner,receipt,seed}.ex` (all on disk),
`lib/mix/tasks/ggen_igniter.review_eval.{seed,run,gate}.ex` (on disk); alias
`"review.eval"` at `mix.exs:125`; CLI docs `docs/reference/cli/review-eval-{seed,run,gate}.md`.

- R2.5-1: corpus/scorer/gate/case_runner/receipt/seed modules on disk.
- R2.5-2: alias `mix review.eval` = run + gate (`mix.exs:123-125`).
- R2.5-3 (residue): `test/fixtures/review_eval/` is **absent on disk** (checked 2026-10-20) —
  declared in `_LANES.md` L6 but not landed. Corpus tests may be self-seeding; this is a
  disclosed residue, status UNKNOWN until the L6 gate runs.

### 2.6 Landing pipeline (L7)

Sources: `landing_pipeline.ex`, `landing_pipeline/stage.ex`, `lib/mix/tasks/ggen_igniter.review.pipeline.ex`,
`test/ggen_igniter_landing_pipeline_test.exs`, `test/mix_ggen_igniter_review_pipeline_task_test.exs`,
`docs/reference/cli/review-pipeline.md`, ADR-013 (`docs/architecture/adr/ADR-013-landing-pipeline-staged-composition.md`).

- R2.6-1: fixed registry of 7 stages, order 1-7 (`landing_pipeline.ex:73-82`): `epoch_check`,
  `risk_tier`, `build_gate`, `fanout_review`, `security_block`, `convergence_cap`,
  `incident_eval`; stage 0 = base integrity (SHA-verify the base ref + worktree SHA).
- R2.6-2: short-circuit: later stages never run once an earlier gate refuses
  (`landing_pipeline.ex:15`); final status "ALIVE" only when every stage passes.
- R2.6-3: a missing stage module refuses typed `{:refused, {:stage_module_missing, name}}` —
  never a silent skip (`landing_pipeline.ex` module doc; `_LANES.md` sequencing law).
- R2 requirements: stage receipts written under `.ggen_igniter/receipts/pipeline`
  (`landing_pipeline.ex:84`).

Acceptance: L7 gate (`RESTART_HANDOFF.md` §3a).

### 2.7 W8 projection backend

Sources: `semantic_jira/projection.ex` (new), `semantic_jira/execute.ex` (additive),
`test/ggen_igniter_semantic_jira_projection_test.exs`, `test/fixtures/projection-pack/` (on disk).

- R2.7-1: `mix semantic_jira.execute --backend projection` executes orders through a
  projection path rather than direct template rendering.
- R2.7-2: additive execute.ex changes only (per _LANES.md w8 row); projection-pack fixture
  on disk.

Acceptance: w8 gate + end-to-end `--backend projection` run against the fixture pack
(`RESTART_HANDOFF.md` §3a).

### 2.8 Epoch courts extension

Sources: `epoch_watermark.ex` (default globs now `lib/**/*.ex`, `config/**/*.exs`,
`priv/repo/migrations/**/*.exs` — `epoch_watermark.ex:60`), `epoch_freshness.ex`,
`epoch_plan.ex`, `test/ggen_igniter_epoch_config_migrations_test.exs` (on disk).

- R2.8-1: watermark globs cover the three implementation planes; the epoch check refuses
  unattributed post-watermark edits in `config/` and `priv/repo/migrations/` (F2).
- R2.8-2: admission refuses epoch-illegal plans before bytes are written (two-layer
  binding, see ARD §5).

Acceptance: epoch-courts gate (`RESTART_HANDOFF.md` §3a).

## 3. Stage 0-7 architecture

Fixed registry (`landing_pipeline.ex:73-82`) preceded by stage 0 base integrity
(git `rev-parse --verify` of `--base`, worktree SHA, base receipt):

| # | stage | module | requirement |
|---|---|---|--- PRD table continued in ARD §4 |
| 0 | base_integrity | inline (`base_integrity/1`) | `--base` required; base ref resolves |
| 1 | epoch_check | `LandingPipeline.Stage.EpochCheck` | no unattributed implementation-plane edit |
| 2 | 2 risk_tier | `…Stage.RiskTier` | tier classifies; receipts carry risk fields |
| 3 | build_gate | `…Stage.BuildGate` | compile+test gate receipt |
| 4 | fanout_review | `…Stage.FanoutReview` | review findings tallied, blockers==0 |
| 5 | security_block | `…Stage.SecurityBlock` | no open security findings |
| 6 | convergence_cap | `…Stage.ConvergenceCap` | within convergence budget |
| 7 | incident_eval | `…Stage.IncidentEval` | eval corpus scored ≥ baseline |

All seven concrete stage modules are other lanes' files; until all land, a real run refuses
`stage_module_missing` at the first absent one — by design. **UNKNOWN** whether all seven
exist on disk today (registry cites the module names; per-stage file existence not probed
individually this pass — see ARD §6 residue).

## 4. Epoch two-layer binding

Per CLAUDE.md epoch boundary law: `Admit(f) ⟺ FreshEpoch(f)`. Layer 1 — admission refuses
known-illegal plans before any byte is written
(`semantic_jira.admit_candidates --epoch-manifest` applies `EpochPlan.check/2` to order
lines carrying `"epoch"`, typed refusals `REFUSED_EPOCH_*`). Layer 2 — `mix
ggen_igniter.epoch.check` proves the resulting bytes against the watermark. Both layers
required; a plan gate cannot see what a generator actually emits, and a tree check cannot
un-write an illegal byte it refuses. v26.10.20 extends the watermark globs to
`config/**/*.exs` + `priv/repo/migrations/**/*.exs` (`epoch_watermark.ex:60`).

## 5. Test architecture

Chicago-style: real collaborators, state-based assertions, no Mox/:meck/Mimic/Patch/mockall
(grep gate in CLAUDE.md). Real diffs, real stores (JSON/JSONL on disk), real subprocess
capture (`LandingPipeline.Stage.capture/2`), `opts[:stages]` injection seam for the landing
pipeline (real behaviour implementations, still short-circuiting). Per-lane build isolation
`MIX_BUILD_ROOT=_build-lane-<name>`; per-lane gate commands in `RESTART_HANDOFF.md` §3a.

## 6. Disclosed residue

- `test/fixtures/review_eval/` absent (declared in `_LANES.md` L6). UNKNOWN impact until
  the L6 gate runs.
- The seven concrete stage modules: existence not individually probed this pass — UNKNOWN;
  the pipeline's `stage_module_missing` refusal makes absence loud, not silent.
- All lane code uncommitted on `main`; zero wave commits.
- Coordinator artifacts (status.md rows, ADR-013 ontology individuals + regen, glossary,
  changelog) — RESTART_HANDOFF §2 lists ADR-013 as NOT-STARTED; note
  `docs/architecture/adr/ADR-013-landing-pipeline-staged-composition.md` now EXISTS on disk
  (verified 2026-10-20), so handoff §6.5 is partially stale; the ontology-individuals+regen
  leg is UNKNOWN.
- RESTART_HANDOFF §6.3 said the security receipt/gate tests were MISSING; all three
  security test files now exist on disk — handoff note superseded.

## 7. Falsifier register F1-F4

(from `RESTART_HANDOFF.md` §4; ledger rows opened in `docs/VERIFICATION_LEDGER.md`)

- **F1** — reference receipt replays with |Δ|=0; any mutated artifact that still admits
  violates F1. Command: see ledger.
- **F2** — post-watermark edit to `config/**/*.exs` or `priv/repo/migrations/**/*.exs`
  without attribution must refuse (REFUSED_*, exit ≠ 0); compiling in clean violates F2.
- **F3** — `mix ggen_igniter.review_eval.gate` must exit 1 with an open blocking finding in
  `docs/REVIEW_STATE.md`; passing with open blockers violates F3.
- **F4** — a diff with a planted secret must exit 5 SECURITY_BLOCKED via
  `mix ggen_igniter.security_review`; landing clean violates F4.

## 8. Triage: 11 failures + 20 invalid

The failure inventory itself is **UNKNOWN** — no persisted run output names the 11 failures
and 20 invalid outcomes on disk (checked `docs/jira/v26.10.20/`, `docs/VERIFICATION_LEDGER.md`,
no run receipt under `.ggen_igniter/receipts/` this pass). Structural triage only:

- The 20 "invalid" outcomes are consistent with the landing pipeline's
  `invalid_invocation` (exit 2) classification (`landing_pipeline.ex` `run/1` returns
  `{2, %{"status" => "invalid_invocation", ...}}` for missing `--base` / unresolvable
  base ref) — but which tests produced them is UNKNOWN until the suite rerun.
- The 11 failures: unattributed without a rerun. First action when the tree is green:
  rerun the full suite, paste output, open ledger rows per failure class.
- Run-when-green: `mix compile --warnings-as-errors && mix test` (full suite), then
  per-lane gates per `RESTART_HANDOFF.md` §3a.

Status vocabulary per repo law: no ALIVE claims in this PRD; everything is grounded to
on-disk artifacts (file citations) or marked UNKNOWN.

## 9. Part II — test-plane bifurcation charter

The test plane is split into two planes with different epoch standing. All claims below
re-verified on disk 2026-10-20 on `main` (HEAD `1a6e60d`).

### 9.1 Two planes

**Plane A — artisan / independent-falsifier plane. Epoch-exempt by design.**

The epoch law binds implementations, not knowledge or evidence. Per the root `CLAUDE.md`
epoch table and `epoch_watermark.ex`, the exempt planes are `test/**`, fixtures, and
receipts:

| plane | epoch-bound? |
|---|---|
| `test/**`, fixtures, receipts (falsifiers, evidence) | **no** — Plane A |
| `lib/**/*.ex` | yes — first court |
| `config/**/*.exs`, `priv/repo/migrations/**/*.exs` | yes — v26.10.20 extension (`epoch_watermark.ex:60`) |

Rationale (unchanged from CLAUDE.md): `Test_t(A_{t+1})` is an independent historical
falsifier — tests predate the new implementation on purpose, so the implementation phases
in while the court survives. Consequence: a test-plane file may be written, mutated, or
re-added at any time without an epoch attribution; the epoch courts
(`mix ggen_igniter.epoch.check`, `EpochPlan.check/2`) must never refuse on these paths.

**Plane B — mechanical projection plane.**

`test-suite-projection`: tests generated from the capability surface by a ggen pack
(Post-F1 target), rather than hand-written. Standing: **SPEC-ADMITTED / OPEN** — the pack
does not exist in `~/ggen-marketplace/packs/` (enumerated 2026-10-20; nearest
testing-adjacent pack is `fortune5-testing-bblock-pack`, which is not the named pack).
Until the pack lands, every test in this repo is Plane A by construction and no
projection-produced test exists. Note: this repo already self-hosts one pack family as
proof of the mechanism (`priv/ggen/adr-index-pack`, per CLAUDE.md), so the projection
plane's admission path is the existing ggen pack pipeline, not a new one.

### 9.2 TR-01..TR-05 requirement rows

Standing is per repo law: OPEN (pending a pasted-output gate run), WIRED (code on disk,
cited), or SPEC-ADMITTED/OPEN. No ALIVE without a pasted-output cite.

| id | requirement | verification criterion | standing | evidence |
|---|---|---|---|---|
| TR-01 | Full-suite gate clearance: `mix compile --warnings-as-errors && mix test` green | paste real full-suite output; zero failures, zero invalid; per §8 the current failure inventory (11 failures / 20 invalid) is unattributed | **OPEN** — pending full-suite green | §8; `.claude/skills/gate/SKILL.md` |
| TR-02 | Plane A exempt-plane law: epoch courts never refuse on `test/**`, fixtures, receipts | `mix ggen_igniter.epoch.check` on a tree with a fresh unattributed `test/**` edit exits 0 for those paths (ALIVE-side verdicts only for exempt paths); a mutation that makes an exempt path refuse violates this row | **OPEN** — not yet run this pass; court code on disk (`epoch_freshness.ex`, `epoch_plan.ex`) | `CLAUDE.md` epoch table; `epoch_watermark.ex:60` |
| TR-03 | Plane B projection source-of-truth: `test-suite-projection` pack exists in `~/ggen-marketplace/packs/` and projects a test suite deterministically | `ggen sync run` replay against a fixed ontology yields byte-identical suite output (C25-style determinism falsifier) | **SPEC-ADMITTED / OPEN** — no pack on disk | `~/ggen-marketplace/packs/` enumeration 2026-10-20 |
| TR-04 | Convergence critic wired into `mix ggen_igniter.review.convergence` | CLI task passes a critic-backed `reviewer` (non-empty findings on a real diff), not the deterministic empty pass | **WIRED (module) / OPEN (CLI integration)** — `convergence/critic.ex` on disk (C1 landed, 27 tests green per lane receipt); CLI task still injects its own empty reviewer — disclosed at `lib/mix/tasks/ggen_igniter.review.convergence.ex:18-21,51-59` | `lib/ggen_igniter/convergence/critic.ex` |
| TR-05 | Receipt integrity law: every receipt hash is sha256 via `Receipt.compute_receipt_hash/1` | grep for any non-sha256 hash family (e.g. BLAKE3) in `lib/**` + schema must return zero matches; receipts round-trip (`ggen_igniter_receipt_schema_test.exs`) | **WIRED** — sha256 confirmed (`receipt.ex:389-407`: `"sha256:" <> hex_sha256(...)`); no BLAKE3 anywhere in the receipt path | `lib/ggen_igniter/receipt.ex`, `priv/schema/receipt.schema.json` |

### 9.3 Standing corrections absorbed into repo law

- Receipts are **sha256 hash-chained** via `Receipt.compute_receipt_hash/1`
  (`lib/ggen_igniter/receipt.ex:389-407`). Never claim BLAKE3 for any receipt or ledger
  hash in this repo.
- **Never write ALIVE without a pasted-output cite.** Without one, use UNKNOWN or
  PARTIAL_ALIVE with the exact blocking hop named. This is the same rule PRD §0 already
  states; it now also governs the TR register above.
- TR-04 disclosure is preserved verbatim from the lane receipt: the CLI task's own
  module-doc scope note (`review.convergence.ex:18-21`) already states the default
  reviewer is a deterministic empty-finding pass; real critic integration lands with the
  reviewer contract, not by silently extending the task.
