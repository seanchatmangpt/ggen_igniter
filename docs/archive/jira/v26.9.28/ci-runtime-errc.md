# CI and test-suite runtime: ERRC

v26.9.28, 2026-09-28. Scope: `.github/workflows/ci.yml`, `test/test_helper.exs`, `mix.exs`
aliases, and `async:` / `@moduletag` lines of existing test files. Measurements are from a
16-core dev machine under variable load (load average 4 to 100 from other lanes), not from a
hosted runner; every hosted-runner number below is labelled as an extrapolation.

## Measured baseline

- `mix test --slowest 40` implies `--trace`, i.e. `max_cases: 1` (fully serial). It was
  killed by its own 50-minute bound at 1615 of ~1700 tests; per-test times summed to
  2668 s (44.5 min).
- One file, `test/ggen_igniter_semantic_jira_pack_test.exs`, is 1566 s of that (59%, 67
  tests; eight tests take 85 to 250 s each). Top 40 files are 98% of the time.
- 40 files were already `@moduletag :integration` (2160 s of 2668 s) but nothing excluded
  the tag, so `mix test` always paid for them. 80 of 260 test files were `async: false`.
- Hosted CI (from `ci.yml` history): ~14 min cold pre-test + ~42 min suite = ~56 min in one job.

## ERRC

| | Item | Where | Result |
|---|---|---|---|
| Eliminate | Single 90-minute job running everything serially with cold compile inside the timed test job | `ci.yml` (`build` line 19, `test` line 208, `test-heavy` line 309) | replaced by build + 6 shards + 5 heavy groups |
| Eliminate | Default `mix test` paying for 480 subprocess/integration tests | `test/test_helper.exs` (GGEN_TEST_FULL block) | fast lane 83 s (was serial minutes) |
| Eliminate | Vestigial `async: false` on 5 pure files | `lock_non_eexist_error`, `lock_path_canonicalization`, `engine_parity`, `semantic_jira_pack_health`, `semantic_jira_shacl` tests | now `async: true`; 5 seeds green |
| Reduce | Longest serial file (967 s idle, 1566 s loaded) | `ci.yml:309` matrix over ExUnit `describe` tags | 5 groups, max 185 s |
| Reduce | Untagged heavy subprocess files (7) | `@moduletag :integration` on `ultracode_two_port`, `doctor_inprocess`, `pack_fetch_task`, `cli_tasks_quirks`, `semantic_jira_observe_court_map`, `semantic_jira_bootstrap`, `process_discovery_pack` | moved out of fast lane |
| Reduce | Timeout budget | `ci.yml:27,216,317` (35 / 25 / 20 min) | replaces 90; extrapolated, see comments |
| Raise | Undocumented `async: false` reasons | one-line `# async: false -- <reason>` above 59 `use ExUnit.Case` lines | reason is machine-classified (cwd / env / Mix.shell / subprocess / global state / UNCLASSIFIED) |
| Raise | `test_helper.exs` overwrote CLI `--only`/`--exclude` | `test_helper.exs` merge with `Application.get_env(:ex_unit, :exclude)` | `--only` now keeps its `:test` exclusion |
| Create | Local lanes | `mix.exs:94-99` `test.fast`, `test.full`, `test.shard` | `mix test` = fast; `mix test.full` = all |
| Create | Compile-once handoff | `ci.yml` build job saves an exact-SHA cache (`actions/cache/save`); shards and heavy groups restore it with `fail-on-cache-miss: true` | shards never pay the ~14 min NIF compile |
| Create | Heavy-file split without touching the file | `ci.yml` group 5 is the complement (`--exclude` of every named describe) | a renamed or new describe still runs |

## Findings that changed the design

- `--include integration` beats `--exclude heavy` on a test carrying both tags (measured:
  an 8-partition run with both flags still ran the 67-test file). CI therefore uses
  `GGEN_TEST_FULL=1`, which stops the default exclusion instead of overriding it.
- Flipping the 10 files that run `ReconcileReactor` to `async: true` failed
  (`ArgumentError: the table identifier does not refer to an existing ETS table`,
  `:ggen_igniter_compensation_counters`, from `CompensationTelemetryMiddleware`). They were
  reverted with the reason as a comment; the global counter is the real reason they are serial.
- `reconcile_reactor_format_test.exs` flaked once in 9 concurrent trials (real `mix compile`
  verify subprocess); reverted to `async: false` with a comment.
- `ExUnit --partitions` splits by file, so a single file is a hard floor. That is why the
  heavy file needed a `describe`-level split.

## Test-count conservation (all counts are ExUnit doctests + properties + tests)

- All registered tests: `mix test --exclude test` = **1839 excluded** (0 run).
- Partition sums: `--partitions 8` = 240+237+189+235+208+166+287+277 = 1839; `--partitions 6`
  with `GGEN_TEST_FULL=1` ran 5d+4p+272t, 8d+9p+312t, 7p+188t, 3p+287t, 3d+5p+436t, 4d+14p+206t
  plus excluded 3, 1, 70 (67 heavy + 3), 2, 4 skipped, 1 skipped.
- Fast lane: 20 doctests + 41 properties + 1298 tests = 1359 run, 5 skipped, **480 excluded**
  (integration + `requires_qlever_server`; `requires_ash_r2rml` is included locally because
  `~/ash_r2rml` exists).
- Heavy groups on the 67-test file: 44+6+7+5+5 = **67**.
- Union argument: shards run everything except `:heavy`; heavy groups run the whole `:heavy`
  file (group 5 is the complement); the fast lane is the full set minus `:integration`.
  Exclusions that also applied to the old single job (`requires_qlever_server` via `CI=true`,
  `requires_ash_r2rml` absent on runners) still apply in every shard through `test_helper.exs`.

## Numbers

| Lane | Measured (dev machine) | Hosted extrapolation |
|---|---|---|
| Old: serial `--trace` run | 2668 s summed (aborted at 1615 tests) | ~56 min job (`ci.yml` history) |
| Fast lane `mix test` | 83 to 104 s | not run in CI |
| Shards 1..6 | 184, 136, 55, 329, 192, 231 s | max ~11 min at 2x |
| Heavy groups 1..5 | 185, 152, 181, 121, 3 s | max ~6 min at 2x |
| Whole file, one process | 967 s idle | replaced |

Extrapolated hosted wall-clock: build ~21 min (cold) + ~3 min restore + max(shard ~11,
heavy ~6) = ~35 min cold; warm builds skip most of the 14 min compile. UNVERIFIED until the
first hosted run; replace the budget comments in `ci.yml` with those numbers.

## Failures seen locally (pre-existing, not introduced here)

- `test running VM ... is the .tool-versions pin`: local Elixir 1.19.5 / OTP 28.3.1 vs the
  1.18.4 / 27.2.4 pin (environmental; CI installs the pin). The CI-pin assertion passes.
- `test mix.exs version: follows CalVer ... agrees with CHANGELOG.md`, and
  `doctor's check_version_policy`: `mix.exs` is 26.9.28, CHANGELOG top entry is 26.9.25.
- One `--engine qlever real end-to-end` failure when run with `--include integration` on a
  machine where a QLever server answers on 7020 (excluded under `CI=true`).
- `mix format --check-formatted` on the whole tree lists files this change did not touch
  (for example `test/ggen_igniter_upgrade_test.exs`); the touched files pass.

## Not done, closest thing

- Splitting `semantic_jira_pack_test.exs` into files (not in scope: another lane's file,
  logic edits). The `describe` matrix is the closest equivalent; splitting the file would
  let `--partitions` balance it and remove the describe-name list from `ci.yml`.
- `test/ggen_igniter_task_shell_test.exs` (139 s, another lane's new file) is untagged; it
  should get `@moduletag :integration` when that lane lands.
- No hosted run was possible here; timeouts are extrapolations, flagged in `ci.yml`.
