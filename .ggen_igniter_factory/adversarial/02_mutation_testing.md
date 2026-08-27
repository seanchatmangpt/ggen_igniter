# Adversarial Verification: Mutation Testing (Domain 02)

**Verifier**: independent adversarial subagent, no access to any builder reasoning/claims.
**Method**: real repository disk state + real commands executed by this verifier, right now.
**Repo**: `/Users/sac/ggen_igniter` (not a git checkout of a clean tag -- see baseline note below).

## Baseline / environment facts (measured, not assumed)

- `mix.exs` real declared version: `26.8.27` (project.version key). The task brief's
  stated release target "v26.7.27" does **not** match this value -- reporting the real
  value per instructions, not assuming the brief is right.
  Command: `head -50 mix.exs` -> `version: "26.8.27"`.
- `git rev-parse HEAD` = `767bccea32d03790a1f4975596a06ecd16df365f`
  ("Add hygen-parity frontmatter, mode:eval/inject actuation, oxigraph default engine,
  optional tesla/gno, doctor --fix, and full-lifecycle e2e tier").
- `git status --short` at session start showed **36 uncommitted changes** (23 modified
  tracked files + untracked new test files and fixtures) already sitting in the working
  tree before this verifier touched anything. This is the real, as-found disk state this
  report verifies against -- not the last commit. Full list captured in this verifier's
  transcript; not reproduced here since it is not this domain's finding.
- `mix compile` succeeds cleanly (one pre-existing deprecation warning about
  `:preferred_cli_env` in `mix.exs`, unrelated to test correctness).
- `find test -name '*.exs' | wc -l` = 39 test files in `test/`.

## Selection

8 test files selected across unit / property / integration, per instructions:

| # | File | Category | Lines |
|---|------|----------|-------|
| 1 | `test/frontmatter_test.exs` | unit (doctest wrapper) | 20 |
| 2 | `test/engine_test.exs` | unit (doctest wrapper) | 16 |
| 3 | `test/ggen_igniter_pack_test.exs` | unit, Chicago-style | 131 |
| 4 | `test/ggen_igniter_doctor_fixes_test.exs` | unit, Chicago-style | 407 |
| 5 | `test/ggen_igniter_frontmatter_properties_test.exs` | property (StreamData) | 217 |
| 6 | `test/ggen_igniter_actuate_properties_test.exs` | property (StreamData) | 175 |
| 7 | `test/ash_r2rml_gate_integration_test.exs` | integration (external, tagged skip) | 97 |
| 8 | `test/ggen_igniter_sync_task_test.exs` | integration (real subprocess) | 62 |

## Per-file read findings

1. **`frontmatter_test.exs`** -- pure doctest wrapper: `doctest GgenIgniter.Frontmatter` +
   `doctest GgenIgniter.Frontmatter.MatchSpec`. Real assertions come from the doc examples
   in `lib/ggen_igniter/frontmatter.ex`'s `@doc` blocks, executed by ExUnit's doctest
   machinery. Not itself hand-written assertions, but not a hardcoded pass either --
   doctest failures are real ExUnit failures. CONFIRMED as a real (if thin) test.

2. **`engine_test.exs`** -- same pattern: `doctest GgenIgniter.Engine`. CONFIRMED real.

3. **`ggen_igniter_pack_test.exs`** -- Chicago-style, real files under
   `test/fixtures/sample-pack/` and `test/fixtures/broken-pack/`, real `File.write!`/temp
   dirs for edge cases (ambiguous templates, empty dirs). No mocks. CONFIRMED real
   (mutation-tested below, #1).

4. **`ggen_igniter_doctor_fixes_test.exs`** -- Chicago-style, builds real throwaway
   `mix.exs`/`config/config.exs`/`lib/*.ex` fixtures per test via `File.write!`, calls the
   real `GgenIgniter.DoctorFixes` functions directly, asserts on real file content after
   the fix. Explicitly documents why one branch (`:gno`/`:dcatr` "not relevant") can't be
   forced without faking `Application` state, and honestly narrows scope there rather than
   faking it. No mocks anywhere in the file. CONFIRMED real (mutation-tested below, #2).

5. **`ggen_igniter_frontmatter_properties_test.exs`** -- real StreamData generators over
   `Frontmatter.from_map/1,2`, `Frontmatter.split_template/1`, `MatchRule.from_map/1`.
   Assertions are full round-trip/state assertions (every field checked, not just one).
   Moduledoc is unusually precise about the exact boundaries of what each property does
   and doesn't claim (e.g. explicitly flags that the `"mode"` gate is inert for
   `from_map/1` and says so rather than implying otherwise). CONFIRMED real.

6. **`ggen_igniter_actuate_properties_test.exs`** -- real StreamData properties against a
   real temp directory and real `File` reads/writes exercising `Actuate.write_file!/3`'s
   4-branch decision table (`unless_exists` / `skip_if` / `unchanged` / `written`),
   including a dedicated property asserting `dry_run` never calls `File.write!`/`mkdir_p!`
   even on the `:written`-computing branch. No mocks. CONFIRMED real (mutation-tested
   below, #3).

7. **`ash_r2rml_gate_integration_test.exs`** -- real cross-repo integration test loading
   an independently-authored external ontology (`~/ash_r2rml`) and running real SPARQL
   gate queries through `GgenIgniter.Ontology`/`GgenIgniter.Query`. Tagged
   `:requires_ash_r2rml` with a real, visible `setup`-driven exclude (not a silent
   mock-substitution) when `~/ash_r2rml` isn't present on the machine. Two of its three
   tests assert a real, reproducing `Protocol.UndefinedError` from `sparql` 0.3.12 against
   real SPARQL UNION/FILTER-NOT-EXISTS query shapes -- a documented, verified engine
   limitation, not a hidden failure. CONFIRMED real; UNVERIFIABLE at execution time
   on this machine (see Execution note below -- `~/ash_r2rml` presence not confirmed by
   this verifier, so these 3 tests could not be run, only read).

8. **`ggen_igniter_sync_task_test.exs`** -- real `System.cmd("mix", [...])` subprocess
   invocation of `mix ggen_igniter.sync` end-to-end, asserting on real exit code, real
   stdout, real written file's existence, real `Code.string_to_quoted!/1` syntax
   validity, and real generated-content substring checks. No mocks. Notably its own
   comment independently corroborates the `26.8.27` version fact above ("oxigraph (the
   default since v26.8.27)"). CONFIRMED real.

## Hardcoded-return-value grep sweep

Searched `lib/` for suspicious "function body is just a literal regardless of input"
patterns:

```
grep -rnE 'do:\s*(true|false|nil|"[^"]*"|:[a-z_]+|\d+)\s*($|,)' lib/ | grep -v "@moduledoc\|@doc\|#"
```

21 hits, all inspected individually. Every hit is a **multi-clause function dispatching
on a distinct literal argument pattern** (idiomatic Elixir pattern matching across
several `def`/`defp` clauses of the same name -- e.g. `parse_freeze_policy("never"), do:
:never` / `parse_freeze_policy("always"), do: :always` / `parse_freeze_policy("checksum"),
do: :checksum`, or `outcome_verb(:written), do: "wrote"` / `outcome_verb(:injected), do:
"injected"` / etc.), not a single-clause function that ignores its argument and always
returns one constant. REFUTED as a hardcoded-return-value concern -- no finding here.

A second sweep for a single `def` whose entire multi-line body is one bare literal
(`awk` scan over every `.ex` file in `lib/` for `def foo(...)` immediately followed by a
line matching `true|false|nil|:ok|:error|<int>` and nothing else) returned **zero
matches**. REFUTED.

Also checked `test/*.exs` for degenerate always-pass assertions (`assert true$`, `assert
1 == 1`) -- zero matches. REFUTED.

## Mutation checks (3 performed, all real: break -> run -> confirm fail -> restore -> confirm pass)

### Mutation 1 -- `GgenIgniter.Pack.query_name/1` (backs `discover_queries/1`, file #3)

- **Target**: `lib/ggen_igniter/pack.ex:96` -- `String.replace(~r/^\d+_/, "")`
  (strips a leading digit-prefix like `010_` from a gate query filename stem).
- **Baseline**: `mix test test/ggen_igniter_pack_test.exs` -> `12 tests, 0 failures`.
- **Mutation applied**: changed the regex to `~r/^ZZZ_NEVER_MATCHES_\d+_/` (never matches
  any real filename, so prefix-stripping silently becomes a no-op).
- **Re-run with mutation**: `12 tests, 2 failures` --
  - `discover_queries/1 finds every gates/*.rq file in the real sample pack, sorted,
    digit-prefix stripped` -- failed: got `{"010_spec", ...}` instead of `{"spec", ...}`.
  - `discover_queries/1 discovers even a syntactically invalid gate query file` -- failed:
    got `{"010_bad", ...}` instead of `{"bad", ...}`.
- **Verdict**: CONFIRMED -- these two tests genuinely exercise digit-prefix stripping and
  fail correctly when it's broken.
- **Restore**: reverted to `~r/^\d+_/` exactly; `diff` against a pre-mutation backup of
  the file showed byte-identical; re-run -> `12 tests, 0 failures`. Restore CONFIRMED.

### Mutation 2 -- `GgenIgniter.DoctorFixes.check_dep_only/2` (file #4)

- **Target**: `lib/ggen_igniter/doctor_fixes.ex:83` --
  `if Regex.match?(~r/\bonly:/, tuple_text) do`.
- **Baseline**: `mix test test/ggen_igniter_doctor_fixes_test.exs` ->
  `18 tests, 0 failures`.
- **Mutation applied**: negated the condition to
  `if not Regex.match?(~r/\bonly:/, tuple_text) do` (inverts the has-`only:`/no-`only:`
  branches).
- **Re-run with mutation**: `18 tests, 4 failures` --
  - "detects and relaxes a real `only: [:dev, :test]` restriction" -- expected
    `{:fixable, _}`, got `{:ok, "... has no :only restriction"}`.
  - "relaxes only: while preserving OTHER options ..." -- expected `{:fixed, _}`, got
    `{:ok, "... has no :only restriction"}`.
  - "is idempotent: fixing twice in a row is a no-op the second time" -- expected
    `{:fixed, _}`, got `{:ok, "... has no :only restriction"}`.
  - "check reports :ok and fix no-ops when the dependency has no :only restriction" --
    expected `{:ok, _}`, got `{:unrecognized, "... but its exact shape was not
    recognized: {:igniter, \"~> 0.8\"}"}`.
- **Verdict**: CONFIRMED -- 4 distinct tests genuinely depend on this branch condition
  and fail correctly, with the exact expected direction of failure (branches swapped).
- **Restore**: reverted the `not` removal exactly; `diff` against a pre-mutation backup
  showed byte-identical; re-run -> `18 tests, 0 failures`. Restore CONFIRMED.

### Mutation 3 -- `GgenIgniter.Actuate.write_file!/3` skip_if branch (file #6)

- **Target**: `lib/ggen_igniter/actuate.ex:87` --
  `exists and skip_if != nil and matches?(existing, skip_if) -> {:ok, :skipped_match}`.
- **Baseline**: `mix test test/ggen_igniter_actuate_properties_test.exs` ->
  `4 properties, 0 failures`.
- **Mutation applied**: prefixed the guard with `false and ...` so the `skip_if` branch
  can never fire (falls through to the `:unchanged`/`:written` branches instead).
- **Re-run with mutation**: `4 properties, 1 failure` -- the "skip_if precedence over the
  byte-comparison (:unchanged) branch" property failed immediately (StreamData shrank to
  a minimal counterexample: `marker = "a"`, `filler = ""`, `use_regex? = false`), expected
  `{:ok, :skipped_match}`, got `{:ok, :unchanged}`.
- **Verdict**: CONFIRMED -- this property genuinely exercises `skip_if` precedence and
  fails correctly, with StreamData's shrinker producing a clean minimal repro.
- **Restore**: reverted the `false and` prefix exactly; `diff` against a pre-mutation
  backup showed byte-identical; re-run -> `4 properties, 0 failures`. Restore CONFIRMED.

## Worthless-test findings

**None.** All 3 mutated behaviors were caught by the tests that claim to verify them, with
correct failure direction and no false negatives. No test in the 8 read files was found to
assert a hardcoded/tautological outcome independent of the code under test.

## Post-verification repo state check

`git status --short` after all 3 mutation/restore cycles is byte-for-byte identical to the
pre-verification state (checked via `diff` of each mutated file against a backup copy taken
immediately before mutating it, and via `git status --short` before/after comparison of the
full working tree) -- this verifier introduced zero net changes to the repository.
Temporary backup copies used for the diff check were deleted after use; nothing is left in
`.ggen_igniter_factory/adversarial/` except this report.

## Scope note (what this domain does NOT cover)

This report is scoped to test-genuineness/mutation-survivability and hardcoded-return
sweeps only, per this verifier's assigned domain. It does not assess overall test coverage
breadth, CI status, dialyzer/credo findings, or the other 34/39 test files not read in this
pass -- those are out of scope for this domain and not silently assumed passing.
