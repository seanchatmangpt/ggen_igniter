# In-flight triage — ggen_igniter @ 1a6e60d — 2026-11-07 (Lane G8)

Standing: PARTIAL_ALIVE

- 98 dirty entries (40 modified, 58 untracked) on top of 1a6e60d. No git
  transitions executed by this lane (coordinator owns git).
- `mix compile --warnings-as-errors` — exit 0 (pre-verified by coordinator).
- Targeted tests over the modified modules: `mix test test/ggen_igniter_epoch_admission_test.exs test/ggen_igniter_task_contract_test.exs test/ggen_igniter_receipt_schema_test.exs test/ggen_igniter_semantic_jira_complete_test.exs test/mix_semantic_jira_execute_task_test.exs test/ggen_igniter_state_machine_conservation_test.exs`
  → **59 tests, 0 failures** (15 excluded), exit 0.
- Full suite run 1: 20 doctests, 41 properties, 1763 tests, **9 failures**, 5 skipped.
- Full suite run 2 (full log, `/tmp/g8_full_test.log`): 20 doctests, 41 properties,
  1763 tests, **10 failures**, 5 skipped, `mix test` exit 2 (925s / 1438s wall).
  Run-1→run-2 delta of +1 is the gall-ticket 300s test-timeout (#3 below) —
  load-sensitive timing, not an assertion change.

## Failure adjudication (all substrate-class, none attributable to in-flight diffs)

| # | Test | Class | Pre-existing? |
|---|---|---|---|
| 1 | ToolchainPinQualification — VM OTP 28.3.1 vs `.tool-versions` pin OTP 27.2.4 | environment | yes — machine is off-pin |
| 2 | FleetReceiptConformance — vendored `priv/schema/fleet-receipt.v2.json` sha256 ≠ machine `~/.claude/dfcm/receipt.schema.json` | external drift | yes — machine copy moved outside the tree |
| 3 | GallTicketTest "checkpoint capability lines lexicographically sorted" | flaky timeout | yes — 300s ExUnit timeout under load; passed run 1 |
| 4–5 | SyncVerify orchestrator ×2 | substrate moved | yes — `[FM-LAW-015]` EA admission gate in ggen CLI 26.11.4 on PATH |
| 6–10 | Fortune5ReadyTask ×5 (incl. case 3 negative test) | substrate moved | yes — same `[FM-LAW-015]`, tests predate the CLI gate |

All 7 FM-LAW-015 failures are the same root cause: the ggen CLI on PATH gained an
EA-admission requirement (`ea.graph.json` or `--skip-ea-admission`) after these tests
were written. Premise rot; fix is test/tooling-side (pass the opt-out or add a fixture
ea.graph.json), not a regression from the 98 dirty entries. The gall-ticket timeout is
the only load-sensitive one (run-to-run variance 9↔10).

## Per-file classification

### Modified (40)

Modified lib/ (11) — all compile clean, all covered by passing targeted tests:

| File | One-line change summary |
|---|---|
| lib/ggen_igniter/epoch_freshness.ex | freshness court judges three implementation planes (lib, config, priv/repo/migrations) with the same closed verdict set; pre-multi-plane watermarks fail closed with `UNKNOWN_PROVENANCE` plane standing |
| lib/ggen_igniter/epoch_watermark.ex | `stamp!/3` records identities for all three planes by default; a glob matching no files is stamped VACUOUSLY-EMPTY (loud recorded absence, never silent narrowing) |
| lib/ggen_igniter/reactors/reconcile_reactor.ex | reconcile events carry Review.RiskTier assessment + per-path risk_signals |
| lib/ggen_igniter/receipt.ex | receipt struct + JSON serialization gain optional pack_digest / risk_tier / risk_score / risk_approvals |
| lib/ggen_igniter/semantic_jira/complete.ex | completion loop routes an order refusal through Execute.run/1's `{1, verdict}` refused verdict and continues, instead of aborting the run |
| lib/ggen_igniter/semantic_jira/epoch_plan.ex | freshness matching honors the watermark's recorded glob set (multi-glob `implementation_globs` with legacy single-glob fallback) |
| lib/ggen_igniter/semantic_jira/execute.ex | adds a projection execution backend (`--pack-lock` + capability_id/target_path renders a guarded artifact + pack gates + projection receipt); documents a disclosed UNSUPPORTED replay-fence residue (sync-time pack stamp never persisted) |
| lib/ggen_igniter/task_contract.ex | adds exit code 5 `:security_blocked` (SECURITY_BLOCKED standing, distinct from drift's BLOCKED) |
| lib/ggen_igniter/telemetry/ocel_emitter.ex | new `emit_review_round/2` OCEL event under `[:ggen_igniter, :review, :round]`, pre-existing reconcile event untouched |
| lib/mix/tasks/semantic_jira.complete.ex | `--packs-root` multi-pack per-order `sj:targetPack` resolution backend, mutually exclusive with `--pack-dir` (exit 2 on ambiguity) |
| lib/mix/tasks/semantic_jira.execute.ex | `projection` backend flag wiring (`--pack-lock`, capability projection receipt surface) |
| mix.exs | adds `test.shard` and `review.eval` aliases |

## Commit grouping proposal (coordinator action)

1. **feat(review+risk-tier)** — review/landing-pipeline/convergence/security_review lib trees + 7 mix tasks + reconcile_reactor risk wiring + receipt risk fields + ocel_emitter review-round event + task_contract code 5 `:security_blocked` + priv/schema updates + `.claude/hooks`, `.claude/skills`, `.claude/receipts`, `.github/workflows/{machine-review,risk-tier}.yml`, CODEOWNERS, REVIEW_STATE/VERIFICATION_LEDGER docs. Core feature commit — the review/landing pipeline + security review subsystem.
2. **feat(epoch multi-plane)** — epoch_freshness.ex + epoch_watermark.ex + epoch_plan.ex + epoch_admission test + receipts/security/ + docs/jira/v26.10.20/ lane plans.
3. **feat(projection backend)** — semantic_jira/projection.ex + test/fixtures/projection-pack/ + execute.ex projection backend + mix task docs for `--packs-root`/`--pack-dir` backends + mix tasks complete/execute + projection tests.
4. **docs+changelog** — CHANGELOG.md, docs/glossary.md, docs/status.md, docs/reference/cli/* modified+untracked, ADR-013, adr README, ci.yml, mix.exs aliases.
5. **DELETE** — `tmp-bp-validation/` (24K scratch validation debris, 9 files; coordinator to delete, lane did not delete).

## Seal readiness — Lane B7 re-verification @ current tree, 2026-11-07

Standing: PARTIAL_ALIVE

### Re-run evidence (B7)

| Gate | Command | Result | vs G8 |
|---|---|---|---|
| compile | `mix compile --warnings-as-errors` | exit 0 | match |
| targeted | same 6-file test list (see above) | **59 tests, 0 failures** (15 excluded), exit 0, 22.6s | match |
| full suite | `mix test` (log: `/tmp/b7_full_test.log`) | 20 doctests, 41 properties, **1763 tests, 13 failures**, 5 skipped, exit 2 | G8 run-2 had 10; +3 delta (below) |

### Failure adjudication vs G8's list

All 10 of G8's failures reproduced with the same classes: ToolchainPinQualification
(environment, off-pin OTP), FleetReceiptConformance (external schema drift),
GallTicket sorted (this run: GRAPHLAW_WASM refusal, not G8's 300s timeout — same
environment family, different victim mechanism), SyncVerify ×2 + Fortune5 ×5
(FM-LAW-015 EA-admission premise rot, all 7 as before).

**+3 delta failures, single shared root cause** (NOT in G8's list):

- GallTicketTest "renders every required ticket section"
- GateVerifyTest "a healthy graph passes with and without the contract"
- SemanticJiraCompleteTest "drives two eligible orders to a complete frontier"
  (this test PASSED in the targeted 59/0 run minutes earlier — proving the
  failure is environmental, not diff-attributable)

Root cause: `test/ggen_igniter_graphlaw_engine_test.exs:53` sets
`Application.put_env(:ggen_igniter, :graphlaw_wasm_path, <bogus /tmp path>)`
globally (restored in an `after` block), while the suite runs async — other
processes executing graphlaw-dependent tests inside the leak window get
`REFUSED:GRAPHLAW_WASM_ARTIFACT_MISSING`. Pre-existing test-hygiene defect
(the file is not in the dirty set); victims vary run-to-run (G8: 10, B7: 13).
This explains the run-to-run failure-count variance class generally.

**Verdict: no failure is attributable to the 98 in-flight entries.** The
full-suite gate is NOT clean (never was on this machine), but the failure set
is fully adjudicated as pre-existing substrate/environment.

### FM-LAW-015 status (premise rot, 7 failures)

Still unresolved. No `ea.graph.json` fixture has landed (checked repo root,
`priv/`, `test/fixtures/`). `ggen sync run --help` (ggen 26.11.4 on PATH)
**does expose `--skip-ea-admission`** ("lawful only when the project
intentionally runs without architecture admission").

Recommended pre-seal action (NOT implemented by this lane): add
`--skip-ea-admission` to the ggen CLI invocations in the 7 affected tests
(SyncShellout orchestrator ×2, Fortune5ReadyTask ×5) — test-side, one flag per
invocation — OR vendor a fixture `ea.graph.json` and point the CLI at it.
Test-side flag is the minimal diff.

### FM-LAW-015 closure — Lane F3 (completing G9's stopped work), 2026-11-07

Standing: PASS

G9's disk state on stopping was already complete: both affected test files
(`test/ggen_igniter_sync_shellout_test.exs`,
`test/ggen_igniter_fortune5_ready_task_test_test.exs` path is
`test/ggen_igniter_fortune5_ready_task_test.exs`) define
`write_ea_graph_fixture!/1` and every project-fixture helper routes through
it. Note on method: G9 deviated from B7's flag recommendation with stated
cause — lib `SyncShellout.run/2` hardcodes `["sync", "run"]`, so the
`--skip-ea-admission` flag is unreachable test-side; the minimal, element-free
valid graph (schema `ggen.ea.graph.v1`, one strategy, empty element arrays)
satisfies the gate without changing what sync-mechanics tests verify. Per the
dispatch rule (fixture only when the test's purpose IS admission), these are
sync-mechanics tests, so the fixture is present to satisfy the CLI gate, not
to assert admission behavior. The 2 SyncVerify + 5 Fortune5 FM-LAW-015
failures are resolved.

Run evidence (F3):

| Run | Command | Result | exit |
|---|---|---|---|
| 7 affected tests (both files) | `mix test test/ggen_igniter_sync_shellout_test.exs test/ggen_igniter_fortune5_ready_task_test.exs` | 11 tests, **0 failures** (3 excluded) | 0 |
| full suite | `mix test` (log: `/tmp/f3_full_test.log`) | 20 doctests, 41 properties, **1763 tests, 2 failures**, 5 skipped (697 excluded) | 2 |

Delta vs B7's 13-failure baseline: **13 → 2** (all 7 FM-LAW-015 → 0; 3
async-leak failures did NOT reproduce this run — victims vary run-to-run per
the adjudication above; instead 2 environment/drift-class failures appeared:

1. `GgenIgniter.ToolchainPinQualificationTest` — running VM is Elixir 1.19.5
   (OTP 28) on Erlang/OTP 28.3.1; `.tool-versions` pins elixir 1.19.5-otp-27,
   erlang 27.2.4. Environment (off-pin run), same class as B7's adjudication.
2. `GgenIgniter.FleetReceiptConformanceTest` — vendored
   `priv/schema/fleet-receipt.v2.json` drifted from machine
   `~/.claude/dfcm/receipt.schema.json` (machine sha256 `a2c7510b…`, vendored
   `b513126e…`). External drift; fix is the test's own printed re-vendor
   `cp`. Outside this lane's scope (schema file not lane-owned) — left
   unfixed, named for the sealing lane.

**Seal readiness: G1 group gate now provable.** The 7 FM-LAW-015 failures
were the only premise-rot class in the adjudicated set; with them green, the
remaining failures are 2 environment/drift items external to the tree, plus a
run-to-run async-leak variance class (graphlaw_engine_test.exs:53 global
`put_env`, pre-existing hygiene defect, zero or flaky victims per run).

### Commit-group validation vs current tree (drift list)

Entry census: 99 dirty entries (G8: 98). The +1 is this triage notes file
itself (expected, self-referential).

- **Group 1 (review+risk-tier)**: all named files present. Drift (assign here,
  not named by G8): `.claude/skills/gate/SKILL.md` (M), `.claude/settings.json`
  (M), `.claude/agents/ggen-reviewer.md` (M); the 14 untracked
  review/security/convergence/landing-pipeline test files +
  `test/support/review_eval_fixture.ex` must ride with this group.
- **Group 2 (epoch multi-plane)**: all named files present. Drift: untracked
  `test/ggen_igniter_epoch_config_migrations_test.exs` belongs here.
- **Group 3 (projection backend)**: all named files present. No drift.
- **Group 4 (docs+changelog)**: all named files present; G8's `docs/reference/cli/*`
  covers the three additional modified cli docs; `docs/reference/refusals.md` (M)
  and `priv/ggen/adr-index-pack/ontology.ttl` (M) also need a home (G4 or G1).
- **Group 5 (DELETE)**: `tmp-bp-validation/` still present, 9 files, intact.
- **Unassigned**: ~10 modified test/support files (e2e/lifecycle, gall_ticket,
  mock_discipline, pack_marketplace_sync, actuation_dispatch_matrix properties,
  legacy_outputs, receipt_schema, state_machine_conservation, task_contract,
  mix_semantic_jira_execute_task, pack_compile, semantic_a2a_manufactured) are
  not named in any G8 group — assign each to its feature group before staging.

**Readiness verdict: READY TO SEAL with the drift assignments above.** Compile
and targeted gates green and reproducible; full-suite failures 100%
pre-existing-class; commit grouping sound, requires the explicit test-file and
settings/agents assignments listed before staging.
