# Adversarial Verification — Domain: Process Exit Codes & Real Subprocess Correctness

Repo: `/Users/sac/ggen_igniter`
Verifier: independent, no prior builder reasoning read. All commands run live, right now, from repo root unless noted.

**Note on stated release target**: task framing said "v26.7.27, formerly stated as such". Real value from `mix.exs` (`version:` key, read directly): **`26.8.27`**. This does not match "v26.7.27" — reporting the real value as instructed, not assuming either number is correct.

---

## 1. `mix compile --warnings-as-errors`

**Command:** `mix compile --warnings-as-errors`
**Exit code:** `0`
**Verdict: CONFIRMED** — compiles clean under `--warnings-as-errors`.

Real output (full, verbatim — only content produced was a benign upstream Mix deprecation notice, not a warning from this codebase's own source):

```
warning: setting :preferred_cli_env in your mix.exs "def project" is deprecated, set it inside "def cli" instead:

    def cli do
      [preferred_envs: [coveralls: :test, "coveralls.detail": :test, "coveralls.html": :test]]
    end

  (mix 1.19.5) lib/mix/cli.ex:187: Mix.CLI.preferred_cli_env/3
  (mix 1.19.5) lib/mix/cli.ex:170: Mix.CLI.maybe_change_env_and_target/2
  (mix 1.19.5) lib/mix/cli.ex:59: Mix.CLI.proceed/2
  /opt/homebrew/bin/mix:7: (file)
  (elixir 1.19.5) src/elixir_compiler.erl:81: :elixir_compiler.dispatch/4
  (elixir 1.19.5) src/elixir_compiler.erl:56: :elixir_compiler.compile/4
```

This is a Mix-tooling deprecation warning about `mix.exs`'s own `:preferred_cli_env` key (not gated by `--warnings-as-errors`, which only governs compiler warnings), and it did not fail the build. Exit code `0` confirmed real, no compiler warnings-as-errors were triggered.

---

## 2. `mix test` (full suite, default seed) — REFUTED as unconditionally green; confirmed FLAKY

**Command:** `mix test`
**Exit code:** `2`
**Real final summary line:** `12 doctests, 21 properties, 207 tests, 2 failures`

**Verdict: REFUTED** for any claim that `mix test` passes cleanly / exits 0 on a default run. Two real, distinct failures at seed `93665` (the seed Mix picked for this run):

**Failure 1** — `test/ggen_igniter_sync_pack_test.exs:12` (`GgenIgniter.SyncPackTaskTest` — "mix ggen_igniter.sync --pack-dir resolves ontology/queries/template from the pack and writes a real file"):
```
error: undefined variable "entities"
└─ nofile:9:19

** (CompileError) nofile: cannot compile file (errors have been logged)

code: assert exit_code == 0, "mix ggen_igniter.sync --pack-dir failed:\n#{output}"
stacktrace:
  test/ggen_igniter_sync_pack_test.exs:42: (test)
```
The `mix ggen_igniter.sync` subprocess spawned by this test failed to compile a generated/rendered template (undefined variable `entities` at the rendered source's line 9, column 19), causing the assertion `exit_code == 0` to fail.

**Failure 2** — `test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs:278` (`GgenIgniter.ActuationDispatchMatrixPropertiesTest`, the engine x mode x for_each x dry_run x inject x guard_variant property):
```
Failed with generated values (after 1 successful run):
    * Clause:    combo <- combo_gen()
      Generated: %{mode: :file, engine: "sparql", for_each: false, dry_run: false, inject: false, guard_variant: :skip_if}

Assertion with =~ failed
code:  assert output =~ "skipped (skip_if matched): #{path}"
right: "skipped (skip_if matched): /Users/sac/.cache/tmp/ggen_igniter_dispatch_case_12034/Agent6.Single.ex"
stacktrace:
  test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs:513: anonymous fn/6 in GgenIgniter.ActuationDispatchMatrixPropertiesTest.run_case!/3
  ...
  (stream_data 1.4.0) lib/stream_data.ex:2545: StreamData.check_all/7
```
For the `guard_variant: :skip_if` combo, the real CLI subprocess output did not contain the expected `"skipped (skip_if matched): ..."` string — the actual captured `output` left-hand value shows only Mix's deprecation-warning noise plus a "wrote ...Agent6.Single.ex" notice, i.e. the file was written instead of being skipped by the `skip_if` guard.

### Flakiness re-check: `mix test --seed 777`

**Command:** `mix test --seed 777`
**Exit code:** `0`
**Real final summary line:** `12 doctests, 21 properties, 207 tests, 0 failures`

**Verdict: CONFIRMED FLAKY.** Same suite, same working tree, different seed → 0 failures instead of 2. This is real, reproduced nondeterminism, not a fluke of my reading: exit code flipped from `2` (default random seed `93665`) to `0` (`--seed 777`) across two consecutive real runs with no code changes between them. Any claim that "mix test passes" is true only for some seeds and false for others — report both facts, do not average them into "mostly passes."

At minimum, Failure 2 (the property test) is seed-sensitive by construction (StreamData property test — the failing generated combo `%{mode: :file, engine: "sparql", for_each: false, dry_run: false, inject: false, guard_variant: :skip_if}` may or may not be generated depending on seed). Failure 1 (the `SyncPackTaskTest` compile error) not recurring under `--seed 777` suggests it may also depend on generation/ordering of some shared fixture, template-cache, or ETS/tmp-dir state across the two runs — this was not root-caused further; only the fact of its disappearance under a different seed is confirmed.

---

## 3. `mix format --check-formatted`

**Command:** `mix format --check-formatted`
**Exit code:** `1`
**Verdict: REFUTED** for any claim that the codebase is fully `mix format`-clean. Real output names two unformatted files:

```
** (Mix) mix format failed due to --check-formatted.
The following files are not formatted:

/Users/sac/ggen_igniter/test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs
/Users/sac/ggen_igniter/test/ggen_igniter_sparql_engine_test.exs
```

Diff excerpts (verbatim from real tool output) — `test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs` needs 3 `if/do/else` expressions reformatted onto multiple lines (lines ~327-329, ~356-358, ~423-425 pre-diff); `test/ggen_igniter_sparql_engine_test.exs` needs one `RDF.Description.add(...)` call collapsed to a single line (lines ~114-119 pre-diff). Both are test files, not `lib/`.

---

## 4. Mock-usage grep — `grep -rnE "Mock|mock\(|patch\(|monkeypatch" test lib native`

**Command:** `grep -rnE "Mock|mock\(|patch\(|monkeypatch" test lib native | wc -l`
**Exit code:** `0` (grep found 0 matches; `wc -l` reports the count)
**Real output:** `0`
**Verdict: CONFIRMED** — zero occurrences of `Mock`/`mock(`/`patch(`/`monkeypatch` across `test/`, `lib/`, `native/`. Consistent with the Chicago-school (real-collaborator) testing discipline; no interaction-mocking pattern detected by this literal scan.

---

## 5. `mix hex.build`

**Command:** `mix hex.build`
**Exit code:** `0`
**Verdict: CONFIRMED** — package builds successfully.

Real summary from output:
```
Building ggen_igniter 26.8.27
...
Package checksum: 26b72525a324e20ef9270d046321837787db624ceab88ba11166f864a92ec35b
Saved to ggen_igniter-26.8.27.tar
```
Confirms the real on-disk version is `26.8.27` (matches `mix.exs`), not `26.7.27`.

---

## 6. `native/ggen_graph_nif` — `cargo tree` path-dependency check

**Command (from `native/ggen_graph_nif`):** `cargo tree | grep -c "path = \"" || true`
**`cargo tree` exit code:** `0`
**`grep -c` exit code:** `1` (grep's own exit code when count is zero — expected/normal grep behavior, not a failure; the `|| true` in the original command exists precisely to absorb this)
**Real count of `path = "` occurrences:** `0`

**Verdict: CONFIRMED** — 0 external path dependencies in the Rust NIF crate's dependency tree; the claim "no `path = \"...\"` deps in `cargo tree`" holds for real, current `Cargo.lock`/`cargo tree` output.

---

## Summary Table

| # | Command | Exit code | Verdict |
|---|---|---|---|
| 1 | `mix compile --warnings-as-errors` | 0 | CONFIRMED |
| 2a | `mix test` (default seed 93665) | 2 | REFUTED (2 real failures) |
| 2b | `mix test --seed 777` | 0 | CONFIRMED for this seed only — **suite is FLAKY across seeds** |
| 3 | `mix format --check-formatted` | 1 | REFUTED (2 unformatted test files) |
| 4 | mock-usage grep | 0 (count=0) | CONFIRMED (0 mock occurrences) |
| 5 | `mix hex.build` | 0 | CONFIRMED |
| 6 | `cargo tree` path-dep check | 0 (count=0) | CONFIRMED (0 path deps) |

**Bottom line:** compile, mock-discipline, hex.build, and cargo-tree path-dep checks are real and clean. `mix test` is NOT unconditionally green — it fails with exit 2 and 2 concrete failures at the default random seed (93665), and passes with exit 0 at `--seed 777`, confirming real flakiness rather than a one-off fluke. `mix format --check-formatted` fails (exit 1) on 2 test files. Stated release version in the task prompt ("v26.7.27") does not match the real `mix.exs`/`hex.build` version (`26.8.27`) — reporting as instructed, not resolving the discrepancy.
