# 14 Chicago Test Audit

Standing: UNVERIFIED

Read-only audit of the Chicago-style invariant (`CLAUDE.md`, `test/CLAUDE.md`) over `test`,
`lib` and `native`, on branch `claude/kind-ptolemy-imv2b6` (remote
`seanchatmangpt/ggen_igniter`). Nothing was compiled and `mix test` was not run, so no
pass/fail claim is made. The CLAUDE.md mock grep returned three hits, all self-references
(a diff-fixture string, a moduledoc, a rules-doc note), not test doubles. `native` had no
mock-library hits. The census found 2339 `test "..."` macros in 320 test files. Skips and
exclusions are mostly environmental (`:integration` is excluded by default). Seven
`assert true` no-op branches exist, each commented as a "named skip". Fourteen
`assert_receive`/`assert_received` matches exist; the one I read carries real state.

## Findings

Details and sources for each id are in the Evidence section.

| id | finding | standing |
|---|---|---|
| F1 | Mock grep over `test lib native`: 3 hits, all self-references | ALIVE (run) |
| F2 | Hit 1 is `import Mox` inside a diff heredoc fixture | ALIVE (read) |
| F3 | Hits 2-3 are prose (moduledoc, `test/CLAUDE.md`) | ALIVE (read) |
| F4 | `lib` holds the enforcement regex (not hit by CLAUDE.md grep) | ALIVE (read) |
| F5 | Allowlist of the self-reference files is documented in a test | PARTIAL_ALIVE |
| F6 | Wider scan (mockall, `Mox.`, `Mimic.`) hits only F4's file | ALIVE (run) |
| F7 | Plain `mix test` excludes `:integration` unless `GGEN_TEST_FULL` | ALIVE (read) |
| F8 | `:integration` is the dominant tag, 76 tag lines | ALIVE (run) |
| F9 | Env-gated excludes: qlever, ash_r2rml, postgres | ALIVE (read) |
| F10 | Other tags: network 9, skip_schema 4, known_upstream_bug 4 | ALIVE (run) |
| F11 | Hard `skip:` tags exist at 7 sites (4 + 3 describetag) | ALIVE (grep) |
| F12 | `worked_example_test` skips when sibling checkout is absent | ALIVE (read) |
| F13 | 7 bare `assert true` no-op branches ("named skip") | ALIVE (grep, read) |
| F14 | F13 branches report green when env is absent, not skipped | PARTIAL_ALIVE |
| F15 | Drift guard: `:machine_absent` is `assert true`, drift flunks | ALIVE (read) |
| F16 | Case-variant property prints `[skip]` then `assert true` | ALIVE (read) |
| F17 | 14 receive-style asserts; the 1 read asserts on a struct field | PARTIAL_ALIVE |
| F18 | No `:meck`, call-count or `was_called` idiom found in tests | ALIVE (run) |
| F19 | Tests lacking a state assertion: heuristic unreliable | UNVERIFIED |
| F20 | No test file lacks every assert/refute/flunk/property token | ALIVE (run) |
| F21 | Exhaustive interaction-only / tautology audit not done | UNVERIFIED |

## Evidence

F1 (run from `/home/user/ggen_igniter`):

```bash
grep -rnE '(use|import) +(Mox|Mimic|Patch)\b|:meck\.' test lib native
```

```text
test/ggen_igniter_review_tally_test.exs:154:      +  import Mox
test/ggen_igniter_mock_discipline_test.exs:18:  heredoc line (`+  import Mox` inside a diff string)
test/CLAUDE.md:73:It still catches `use Mox`, `Mox.expect`, `:meck.new`, `use Patch`, `import
```

(Line 18 above is trimmed and re-indented to fit 100 columns.)

F2, F3: `test/ggen_igniter_review_tally_test.exs:154` sits inside a `diff = """` heredoc passed
to `Review.run/2` (lines 145-160 read). Lines 18 and 73 of the other two are prose.

F4, F6: `grep -rniE 'mockall|Mox\.|Mimic\.' test lib native --include=*.ex --include=*.exs
--include=*.rs --include=*.toml | head` returned two lines, both in
`lib/ggen_igniter/review/perspectives/chicago_tests.ex` (lines 6 and 20). A separate grep of
`native` for `Mox|Mimic|:meck|mockall` in `.rs`/`Cargo.toml` printed nothing.

F5: `test/ggen_igniter_mock_discipline_test.exs:12` begins an "Allowlist" paragraph naming the
three self-reference files. The test was not run, so whether it passes is UNVERIFIED.

F7: `test/test_helper.exs:151-152` adds `:integration` to excludes unless `GGEN_TEST_FULL`
is set (comment at 145).

F8, F10: `grep -rhoE '@(module)?tag +:[a-z_0-9]+' test | sed 's/@moduletag/@tag/' | sort |
uniq -c | sort -rn`. Top rows: 76 `:integration`, 9 `:requires_network`, 7 `:tmp_dir`,
5 `:requires_ash_r2rml`, 4 `:skip_schema`, 4 `:known_upstream_bug`.

F9: `test/test_helper.exs:109` (`:requires_qlever_server`), `:124` (`:requires_ash_r2rml`),
`:140` (`:postgres`). Each exclusion is decided by a real reachability or file probe.

F11: `receipts_schema_currency_test.exs:60,71,83,104` (`@tag skip: skip_reason`);
`ggen_igniter_ash_policies_enforce_test.exs:123`, `ggen_igniter_doctrine_hddl_pack_test.exs:404`
and `ggen_igniter_semantic_jira_pack_test.exs:633` (describetag skips; the last two are
conditional on `@ferroplan_skip`).

F12: `test/ggen_igniter/eds/worked_example_test.exs:44-50` sets `@moduletag skip:` with a
reason when the marketplace checkout is absent, else `skip: false`.

F13 sites (all `assert true`):

```text
test/ggen_igniter_semantic_jira_r_projection_test.exs:509,513
test/ggen_igniter_artifact_identity_properties_test.exs:295
test/ggen_igniter_fleet_receipt_conformance_test.exs:154,167,305,310
```

F14: the comments at those sites say the earlier `check/1` assertions "carry the law".
That claim was not verified by running. `receipts_schema_currency_test.exs:19` documents a
visible `@tag skip:` alternative.

F15: `fleet_receipt_conformance_test.exs:151-168`: `{:match, _}` and `:machine_absent`
both end in `assert true`; `{:drift, ..}` calls `flunk`.

F16: `artifact_identity_properties_test.exs:288-295`.

F17, F18: `grep -rnE 'assert_received|refute_received|assert_receive|call_count|
:erlang\.trace|:meck|was_called' test --include=*.exs | wc -l` gave 14. Every listed line
was an `assert_receive`/`assert_received`. Read: `ggen_igniter_sensor_sink_test.exs:60-69`
forwards a real event via a real callback and matches `%Event{activity: ...}`.

F19: an awk scan flagged 44 candidate tests with no assertion token. Two spot-checks
(`ggen_igniter_upstream_rename_blocker_test.exs:64` uses `assert_raise`;
`ggen_igniter_extension_schema_test.exs:333` uses a helper `refuse!/2`) were false
positives, so the count is not reported as a finding.

F20: a shell loop over `find test -name '*_test.exs'` printing files with no
`assert|refute|flunk|check all|property` token produced no output.

Counts: `find test -name '*_test.exs' | wc -l` gave 320; summed
`grep -rcE '^\s*test +"'` gave 2339.

## Next

1. Run `mix compile --warnings-as-errors` and `mix test` (the `gate` skill) and paste output.
2. Turn the seven `assert true` branches (F13) into visible ExUnit skips decided at compile
   time, so absent-environment runs report skipped rather than passed.
3. Replace the F19 awk scan with an AST pass (`Code.string_to_quoted`) counting tests whose
   body has no `assert`/`refute`/`flunk`/`assert_raise` or known assertion helper.
4. Read the other 13 receive-style sites to confirm each pairs with a state check.
5. Run once with `--include integration` and record executed versus excluded counts per tag.
6. Run the F1 grep in CI and assert the hit list equals the three allowlisted files.

## See Also

- `CLAUDE.md` (non-negotiable invariants)
- `test/CLAUDE.md`
- `docs/testing/chicago.md`
- `docs/jira/v26.11.17/LANES.md`
- `test/ggen_igniter_mock_discipline_test.exs`
