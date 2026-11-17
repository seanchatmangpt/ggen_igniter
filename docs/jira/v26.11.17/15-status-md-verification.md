# Lane 15: docs/status.md claims vs code and tests

Standing: UNVERIFIED

Lane 15 of v26.11.17 sampled 40 claims in `docs/status.md` against the tree.
Only existence and `file:line` checks ran; no `mix test` or `mix compile` was
executed, so every "passing" claim stays UNVERIFIED here. Result: 21 resolve,
19 are stale, missing, or contradicted. The worst: engine rows still describe
a multi-engine world that `engine.ex` says was removed; `to_prd_status/1` is
IMPLEMENTED at row 114 yet PLANNED at line 270, and grep supports neither;
one named test file does not exist. Many line cites have drifted.
Short paths: `lib/ggen_igniter` is written `gi/`, `lib/mix/tasks` is `mt/`.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| F01 | rows 73-77: multi-engine IMPLEMENTED | CONTRADICTED | `gi/engine.ex:10-18,31-33` |
| F02 | `EngineRegistry`, `EngineComparisonReport` still on disk | STALE rows | `ls gi/engine_registry.ex` present |
| F03 | row 114: `to_prd_status/1` at receipt.ex:492 | CONTRADICTED | grep lib: comment only, :399 |
| F04 | row 114: test at receipt_test.exs:324-339 | CONTRADICTED | grep `to_prd` in that test: none |
| F05 | line 270 says PLANNED; row 114 says IMPLEMENTED | SELF-CONFLICT | status.md:114 vs :270 |
| F06 | rows 71,247: `lock_node_restart_pid_reuse_test` | MISSING | `ls test/ggen_igniter_lock_node*` fails |
| F07 | lock.ex cites `acquire` 105, `release` 157 | ALIVE | `gi/lock.ex:105`, `:157` |
| F08 | lock.ex `stale_lock?` 151, `holder_pid_status` 189 | STALE | now `:196`, `:263` |
| F09 | `ReconcileReactor.plan/1` at :921 (rows 69,247,255) | STALE | `grep "def plan"` -> `:1062` |
| F10 | sync.ex `inject_content!` call at 852 | STALE | grep: mentions only 185-322 |
| F11 | doctor dry-run guard cites :621,636 | STALE | `mt/ggen_igniter.doctor.ex:642,678` |
| F12 | `max_retries(0)` cited reactor.ex:679-702 | STALE | now `reconcile_reactor.ex:708,742` |
| F13 | refusals: 132 codes, 24 wrapped | STALE | python3 over schema -> `147 24` |
| F14 | StreamData in 16 test files | STALE | `grep -rl StreamData test` -> 15 |
| F15 | 108 `System.cmd("mix"` sites | STALE | grep count -> 128 |
| F16 | zero matches for Mock/patch grep | CONTRADICTED | same grep -> 33 lines |
| F17 | CLAUDE.md-form mock grep clean | PARTIAL | 3 hits, fixture strings/docs |
| F18 | row 157 path `docs/jira/v26.9.28/...` | STALE | file is under `docs/archive/jira/` |
| F19 | row 170: ash deps at `mix.exs:176-177` | STALE line | actual `mix.exs:251-252` |
| F20 | row 170: `:ash_phoenix` absent from mix.exs | ALIVE | grep -> no match |
| F21 | row 66: `ensure_all_started(:reactor)` fix | ALIVE | `reconcile_reactor.ex:870` |
| F22 | row 67: doctor has 19 checks | ALIVE | grep -cE doctor.md -> `19` |
| F23 | rows 195/206: 13 gates, 21 caps, 5 compose | ALIVE | ls/grep -> 13, 21, 5 |
| F24 | row 171: `use Ash.*` at line 21 and 44 | ALIVE | `resource.ex.eex:21`, `domain.ex.eex:44` |
| F25 | row 210: hook allowlist at `:99` | STALE | `refuse-handwritten-ash.sh:181` |
| F26 | row 113: manifest schema version, `persist!` | ALIVE | `manifest.ex:161,255,348,361` |
| F27 | row 112: `Receipt.append!` near 498-530 | ALIVE | `receipt.ex:528` |
| F28 | row 226: receipt risk fields 204-206; `put_optional` | ALIVE | `receipt.ex:204,466`; `landing_pipeline.ex:328` |
| F29 | rows 218-225: 11 of 16 cited line numbers | ALIVE | risk_tier 112, review 47, tally 23, etc. |
| F30 | rows 218-225: 5 line cites drifted | STALE | convergence.ex :118,:220; review_store.ex :114,:140; security_review.ex :109 |
| F31 | row 223: all stage modules exist | ALIVE | 8 files in `gi/landing_pipeline/` |
| F32 | row 208: `Ocel2Export` `document` :70, `write!` :123 | STALE | `ocel2_export.ex:82`, `:138` |
| F33 | rows 285-286: RecurrenceDetector/Claim line cites | ALIVE | scan 41, new 45, execute 68, verify 87 |
| F34 | row 290: five EDS test files exist | ALIVE | `ls test/ggen_igniter/eds/` |
| F35 | row 219: pipeline test at :90 is `no_epoch` | PARTIAL | matches; red state unrun |
| F36 | row 220: convergence CLI stub :19-21 | ALIVE | `mt/ggen_igniter.review.convergence.ex` |
| F37 | row 160: PackLock symlink law at :87 | ALIVE | `gi/pack_lock.ex:87` |
| F38 | row 162: CHANGELOG `## v26.9.31` | ALIVE | `CHANGELOG.md:292` |
| F39 | count pins tied to HEAD `90c1da4`/`ea7a15e4` | UNVERIFIED | current HEAD `df4c9f0`; no rerun |
| F40 | See-also: findings.jsonl has 118 records | ALIVE | `wc -l` -> `118` |

## Next

1. Rewrite rows 73-77 to the single-engine fact; decide on dead registry code.
2. Resolve `to_prd_status/1`: implement it, or fix row 114 and line 270.
3. Fix or drop the `lock_node_restart_pid_reuse` test citation.
4. Re-pin drifted line numbers (F08-F12, F19, F25, F30, F32) or use greps.
5. Update counts (refusals, StreamData, `System.cmd("mix"`) and the mock grep.
6. Run `mix compile --warnings-as-errors` and `mix test`; replace HEAD pins.
7. Fix the archive path in row 157.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/status.md`
- `docs/CLAUDE.md`
