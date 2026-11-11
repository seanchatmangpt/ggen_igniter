# ARD — v26.10.20 no-human review pipeline — Architecture Requirements & Design

Companion to `docs/jira/v26.10.20/PRD.md` (requirements) and
`docs/jira/v26.10.20/_LANES.md` (lane ownership). Same grounding law as the PRD:
on-disk citations or UNKNOWN; no ALIVE claims without a pasted run receipt.

## 1. Subsystem map

| subsystem | root module | owned surface (on-disk 2026-10-20) |
|---|---|---|
| review core (L2) | `GgenIgniter.Review` (`lib/ggen_igniter/review.ex`) | `review/{finding,perspective,verifier,tally,filter,store}.ex`, `review/perspectives/{correctness,chicago_tests,epoch_law,invariants}.ex`, `mix ggen_igniter.review` |
| risk tier (L3) | `GgenIgniter.Review.RiskTier` | `review/risk_tier.ex`, additive `receipt.ex` risk fields, `reconcile_reactor.ex` Receipt.new sites |
| convergence (L4) | `GgenIgniter.Convergence` | `convergence/{hunks,classes}.ex`, `review_store.ex` (rounds.jsonl), `mix ggen_igniter.review.convergence`, OCEL emitter event |
| security (L5) | `GgenIgniter.SecurityReview` | `security_review/{receipt,diff_source}.ex`, `security_review/checks/*` (5 checks), `mix ggen_igniter.security_review`, exit 5 in `task_contract.ex:57-59` |
| review-eval (L6) | `GgenIgniter.ReviewEval` | `review_eval/{corpus,scorer,gate,case_runner,receipt,seed}.ex`, `mix ggen_igniter.review_eval.{seed,run,gate}`, alias `review.eval` (`mix.exs:125`) |
| landing pipeline (L7) | `GgenIgniter.LandingPipeline` | `landing_pipeline.ex`, `landing_pipeline/stage.ex`, `mix ggen_igniter.review.pipeline` |
| W8 projection | `GgenIgniter.SemanticJira.Projection` | `semantic_jira/projection.ex`, additive `semantic_jira/execute.ex` |
| epoch courts | `GgenIgniter.EpochWatermark` / `EpochFreshness` / `SemanticJira.EpochPlan` | watermark globs incl. `config/**/*.exs`, `priv/repo/migrations/**/*.exs` (`epoch_watermark.ex:60`) |

## 2. Stage 0-7 architecture (LandingPipeline)

Source: `landing_pipeline.ex`, registry at lines 73-82; stage 0 base integrity inline
(`run/1` → `base_integrity/1`).

| # | stage | module | refuses when |
|---|---|---|---|
| 0 | base_integrity | inline (`base_integrity/1`) | missing `--base`, unresolvable base ref → exit 2 `invalid_invocation` or BLOCKED base receipt |
| 1 | epoch_check | `LandingPipeline.Stage.EpochCheck` | unattributed implementation-plane edit (REFUSED_*) |
| 2 | risk_tier | `LandingPipeline.Stage.RiskTier` | tier above threshold without approvals |
| 3 | build_gate | `LandingPipeline.Stage.BuildGate` | compile/test gate fails |
| 4 | fanout_review | `LandingPipeline.Stage.FanoutReview` | review tally: blockers > 0 |
| 5 | security_block | `LandingPipeline.Stage.SecurityBlock` | open security findings (exit-5 standing) |
| 6 | convergence_cap | `LandingPipeline.Stage.ConvergenceCap` | findings-by-class exceed budget |
| 7 | incident_eval | `LandingPipeline.Stage.IncidentEval` | eval corpus scores below baseline |

Laws: strict order 1→7, short-circuit — later stages never run once an earlier gate refuses
(`landing_pipeline.ex:15`); final status "ALIVE" only when EVERY stage passes
(`landing_pipeline.ex:42`); a missing stage module refuses typed
`{:refused, {:stage_module_missing, name}}` — never a silent skip; stage receipts under
`.ggen_igniter/receipts/pipeline` (`landing_pipeline.ex:84`). `opts[:stages]` is the test
injection seam (real behaviour implementations, still short-circuiting); production callers
pass nothing. Existence of the seven concrete stage modules beyond `stage.ex` is UNKNOWN
(not individually probed; absence refuses loudly by design).

## 3. Epoch two-layer binding

`Admit(f) ⟺ FreshEpoch(f)` for implementation-plane files. Layer 1 (admission):
`semantic_jira.admit_candidates --epoch-manifest <watermark.json>` applies
`EpochPlan.check/2` to order lines carrying `"epoch"`; typed refusals
`REFUSED_EPOCH_LEGACY_EDIT`, `REFUSED_EPOCH_UNATTRIBUTED_IMPLEMENTATION`,
`REFUSED_EPOCH_PLAN_REUSES_PRE_WATERMARK_ARTIFACT`, `REFUSED_EPOCH_WATERMARK_UNAVAILABLE`;
a missing/unreadable manifest with epoch lines present refuses every epoch line (fail
closed); lines without `"epoch"` pass byte-identical. Layer 2 (proof):
`mix ggen_igniter.epoch.check` proves emitted bytes against the watermark (closed verdict
set; ALIVE iff verdict name starts `ALIVE_`). v26.10.20 extends watermark globs to
`config/**/*.exs` + `priv/repo/migrations/**/*.exs` (`epoch_watermark.ex:60`).

## 4. State and stores

| store | owner | format | notes |
|---|---|---|---|
| review findings | L2 `review/store.ex` | findings ledger | REVIEW_STATE-schema findings; filter dedup/suppression |
| rounds.jsonl | L4 `review_store.ex` | append-only JSONL | distinct module from L2's store (per `_LANES.md` shared-file resolutions) |
| review-eval receipts | L6 `review_eval/receipt.ex` | JSON receipts | corpus run + gate receipts |
| security receipts | L5 `security_review/receipt.ex` | JSON receipts | feeds `complete.ex` security pre-step |
| pipeline receipts | L7 | per-stage JSON | `.ggen_igniter/receipts/pipeline` (`landing_pipeline.ex:84`) |
| REVIEW_STATE.md | L1/reviewer | markdown ledger | round cap 3; append-only findings + verdict log |
| receipt chain | `receipt.ex` | JSON receipts under base_dir | sha256 hash-chain: `"sha256:" <> hex` digests (`receipt.ex:389-496`), chain-linking via `new/2` (`receipt.ex:291-302`) — sha256, NOT BLAKE3 (zero `blake` matches in `receipt.ex`) |

## 4b. Receipt risk fields (L3)

`risk_tier` / `risk_score` / `risk_approvals` (`receipt.ex:204-206`, defaults `:255-257`,
JSON projection via `put_optional` at `:465-467`); classification reproducible from fields
the receipt already carries (`risk_tier.ex:11-15`); deterministic thresholds and floors per
PRD §2.2 (`risk_tier.ex:27-36`).

## 4c. Review perspectives (L2)

Four perspectives on disk: `correctness`, `chicago_tests`, `epoch_law`, `invariants`
(`lib/ggen_igniter/review/perspectives/`, listed 2026-10-20).

## 5. Test architecture (Chicago)

Real collaborators everywhere: real diffs from git, real JSON/JSONL stores on disk, real
subprocess capture (`Stage.capture/2`), real receipt chains. State-based assertions; no
Mox/:meck/Mimic/Patch/mockall (CLAUDE.md grep gate). `opts[:stages]` is the only injection
seam — real behaviour implementations replacing the fixed registry, still short-circuiting
(`landing_pipeline.ex:64-70`). Per-lane build isolation `MIX_BUILD_ROOT=_build-lane-<name>`;
per-lane gate commands: `RESTART_HANDOFF.md` §3a.

## 6. Disclosed residue (architecture-relevant)

- The seven concrete stage modules: cited in the fixed registry (`landing_pipeline.ex:73-82`)
  but not individually probed this pass — UNKNOWN beyond `landing_pipeline/stage.ex` (only
  `stage.ex` listed under that dir on disk). Absence refuses loudly (`stage_module_missing`).
- `test/fixtures/review_eval/` absent (declared in `_LANES.md` L6) — UNKNOWN impact until
  the L6 gate runs.
- All lane code uncommitted on `main`; zero wave commits.
- RESTART_HANDOFF §6.3's "security receipt/gate tests MISSING" note is superseded: all three
  security test files exist on disk (verified 2026-10-20).

## 7. Falsifier register F1-F4

Same register as PRD §7; ledger rows opened in `docs/VERIFICATION_LEDGER.md`.

- **F1** — reference receipt replays with |Δ|=0; a mutated artifact that still admits
  violates F1. Probe: `mix ggen_igniter.replay`.
- **F2** — post-watermark unattributed edit to `config/**/*.exs` or
  `priv/repo/migrations/**/*.exs` must refuse (REFUSED_*, exit ≠ 0); compiling in clean
  violates F2.
- **F3** — `mix ggen_igniter.review_eval.gate` exits 1 with an open blocking finding in
  `docs/REVIEW_STATE.md`; passing with open blockers violates F3.
- **F4** — a diff with a planted secret exits 5 SECURITY_BLOCKED via
  `mix ggen_igniter.security_review`; landing clean violates F4.

## 8. Triage: 11 failures + 20 invalid

The failure inventory is **UNKNOWN** — no persisted run output on disk names them (checked
`docs/jira/v26.10.20/`, `docs/VERIFICATION_LEDGER.md` this pass; no run receipt naming them).
Structural triage:

- The 20 "invalid" outcomes are consistent with the landing pipeline's
  `invalid_invocation` (exit 2) classification (`run/1` returns
  `{2, %{"status" => "invalid_invocation", ...}}` for missing `--base` / unresolvable base
  ref) — but attribution to specific tests is UNKNOWN without a suite rerun.
- The 11 failures: unattributed without a rerun. First action when green: full rerun, paste
  output, open ledger rows per failure class.
- Run-when-green: `mix compile --warnings-as-errors && mix test`; per-lane gates per
  `RESTART_HANDOFF.md` §3a.

## 10. Test-plane architecture (ADR-TEST-01..03)

### ADR-TEST-01 — `test/**` epoch exemption (grounded, EXEMPT)

The exemption is real, not aspirational. Three mutually consistent sources:

1. **Plane table (CLAUDE.md, "Exempt planes" table, epoch-law section)**: rows
   `config, migrations` (named courts, not yet bound) and
   "knowledge plane: `.ttl`, `.rq`, `.eex`, `pack.toml`, docs, markdown — no";
   final row: "tests, falsifiers, evidence: `test/**`, fixtures, receipts — no"
   (epoch-bound = no). `test/**` is explicitly outside the law's scope.
2. **Watermark globs (`epoch_watermark.ex:60`)**: `@default_globs
   ["lib/**/*.ex", "config/**/*.exs", "priv/repo/migrations/**/*.exs"]` — no
   `test/**` glob exists in the default stamp set (first-class lib glob at
   `epoch_watermark.ex:59`). Files outside the globs are never judged.
3. **Freshness verdict set (`epoch_freshness.ex:72-74`, `:118-120`)**: the
   closed verdict set (`ALIVE_GENERATED`, `ALIVE_FRESH_RESIDUE`, `REFUSED_*`,
   `UNKNOWN_PROVENANCE`) is applied only to implementation-plane files surfaced
   by the watermark globs; `alive?/1` (`epoch_freshness.ex:120`) is defined per
   judged file. No glob → no judgment → no refusal path exists for `test/**`.

Consequence: `Test_t(A_{t+1})` is an independent historical falsifier — tests
predate the implementation on purpose and the epoch court never refuses them.

### ADR-TEST-02 — mechanical vs semantic split (mechanical pack SPEC-ADMITTED)

The split: semantic claims (review verdicts, security findings, convergence
tallies) stay hand-produced; the mechanical class (projection of the test
plane's own coverage/identity artifacts) routes through a ggen projection pack.

Status: **SPEC-ADMITTED — nothing on disk.** No test-plane projection pack
exists under `priv/ggen/` (directory listing 2026-10-20: 28 packs, none
test-projection; `priv/ggen/CLAUDE.md` only). The `Projection` module
(`lib/ggen_igniter/semantic_jira/projection.ex`, wired via the `--pack-lock`
projection backend, `semantic_jira/execute.ex:244-257`) is the intended
execution path but carries no test-plane pack binding.

**Falsifier**: fixed-point re-projection byte-identity — re-running the pack
against its own emitted output must produce byte-identical artifacts (|Δ| = 0);
any second-run diff is a refusal. Until the pack lands, the falsifier is
unrunnable, which is the definition of SPEC-ADMITTED (admitted by spec, zero
standing until a witnessed run).

### ADR-TEST-03 — C2 dual-sided fix: LANDED (actual state, not the assumed defect)

The C2 defect ("security_review task does not return exit 5 via TaskContract")
is **already closed on disk** — the C2 lane landed. Actual state:

- TaskContract table carries code 5 `:security_blocked` standing
  SECURITY_BLOCKED (`task_contract.ex:57-59`; table at `:40-62`, type at
  `:64`).
- `mix ggen_igniter.security_review` halts 5 on the blocked outcome:
  `case outcome do :ok -> halt(0); :security_blocked -> halt(5) end`
  (`lib/mix/tasks/ggen_igniter.security_review.ex:107-108`), envelope built via
  `TaskContract.envelope/3` (`:90-101`), REFUSED exit 1 at `:77-80`.
- The task's own moduledoc pins the contract (exit 0/1/5, `System.halt/1` on
  every real exit path, `:1-25`).

No remaining defect. Any open REVIEW_STATE row asserting otherwise is stale and
should be closed with evidence of this section.

## 9. Cross-links

PRD §2 per-subsystem requirements ↔ ARD §1 subsystem map; PRD §3 stage table ↔ ARD §2;
PRD §4 / ARD §3 epoch two-layer binding; PRD §7 / ARD §7 falsifiers ↔
`docs/VERIFICATION_LEDGER.md`; PRD §8 / ARD §8 triage. Lane ownership: `_LANES.md`.
Handoff: `RESTART_HANDOFF.md`.
