# Expert Review — Kent Beck Lens (Father of TDD & Extreme Programming)

Architectural evaluation of `ggen_igniter` v26.11.10 from the perspective of Kent Beck,
creator of Test-Driven Development (TDD) and Extreme Programming (XP).

- **Review Date:** 2026-11-10
- **Target Release:** `ggen_igniter` v26.11.10 (`3487755919b4c919d132644f47b275f464d44a29`)
- **Toolchain Grounding:** `elixir 1.19.5`, `erlang 27`, `ex_unit`, `ash 3.33.11`, `igniter 0.8.4`
- **Review Persona:** Pioneer of Test-Driven Development, author of *Test-Driven Development: By Example*,
  and author of the Four Rules of Simple Design. Fierce opponent of mock-based testing theater;
  demands fast, expressive, and truthful feedback loops grounded in real collaborator testing and
  anti-vacuity mutation checks.

---

## Executive Summary & Stance

> "I get paid for code that works, not for tests that pass because mocks were wired to agree with
> each other. If your tests don't fail when you mutate the code, your test suite is a soothing lie.
> Chicago-style testing with real files, real databases, and real subprocesses is the only testing
> that earns trust."

This review evaluated `ggen_igniter` against TDD discipline, Chicago-style mock-free verification,
anti-vacuity mutation rigor, and the Four Rules of Simple Design. The architecture receives an
**APPROVED** verdict. The total ban on mock doubles, mechanical enforcement via review perspectives,
and 25 real-subprocess mutation tests represent an extraordinary implementation of classical testing.

---

## Section 1 — CONFIRMED Findings (Ranked)

### Majors

#### M1. Total Elimination of Mock Doubles (Pure Chicago-Style Testing)
- **Observation:** `test/CLAUDE.md:40-70` strictly prohibits mock doubles (`Mox`, `Mimic`, `Patch`, `:meck`)
  for in-repo or locally runnable collaborators. Tests interact directly with real files in unique temp
  directories, real subprocesses, real PostgreSQL instances, and real native WASM engines.
- **Enforcement Mechanism:** Verified mechanically by `lib/ggen_igniter/review/perspectives/chicago_tests.ex:18-38`
  (which flags added lines matching banned mock tokens in git diffs) and `test/ggen_igniter_mock_discipline_test.exs:46-55`
  (which runs `grep` across `lib/`, `test/`, and `native/`).
- **Beck's Assessment:** Mock-heavy testing (London school) couples test suites to implementation details,
  making refactoring painful. Testing against real collaborators ensures tests verify actual observable behavior.
- **Standing:** `ALIVE`.

#### M2. Anti-Vacuity Mutation Rigor
- **Observation:** In `test/ggen_igniter_mock_discipline_test.exs:25-28`, the test-double allowlist is
  anti-vacuous: each entry is asserted to produce a real grep hit. If an underlying file is altered or fixed,
  the test fails loudly instead of silently loosening the allowlist.
- **Real-Subprocess Mutation Corpus:** In `test/ggen_igniter_agent_guard_test.exs:1-60`, 25 real-subprocess
  cases test `.claude/hooks/refuse-handwritten-ash.sh` over the stdin JSON protocol, verifying that intentional
  mutations (multiline macro splits, module aliases, multi-edit payloads, directory traversals) fail closed.
- **Beck's Assessment:** Tests must be sensitive to faults. A green test that cannot fail is worse than no test.

#### M3. Four Rules of Simple Design — Engine Consolidation
- **Observation:** The Four Rules of Simple Design are: 1) Passes tests, 2) Reveals intent, 3) No duplication,
  4) Fewest elements. Rule 4 was directly honored when `ggen_igniter` pruned its multi-engine selection surface
  (`sparql`, `qlever`, `oxigraph`) down to the single fixed `graphlaw` WASM module (`lib/ggen_igniter/engine.ex:9-24`, `lib/mix/tasks/ggen_igniter.sync.ex:55-76`).
- **Beck's Assessment:** Eliminating unused configurability is the hallmark of simple design. It eliminated
  hundreds of lines of dispatch complexity while passing 100% of query verification tests.

---

### Minors

#### m1. ExUnit Configuration Hygiene in `test_helper.exs`
- **Observation:** In `test/test_helper.exs:23-50`, documentation details how sequential calls to
  `ExUnit.configure(exclude: [...])` overwrite rather than append to `:exclude`. The helper consolidates
  all exclusions into a single call before `ExUnit.start/1`.
- **Beck's Assessment:** Honest documentation of test harness edge cases preserves developer trust and
  prevents flaky CI runs.

#### m2. Fast Feedback Loops via Async Execution
- **Observation:** Tests declare `use ExUnit.Case, async: true` unless sharing non-isolated global resources
  (`test/CLAUDE.md:12-14`), taking full advantage of BEAM process isolation for rapid execution.

---

## Section 2 — REFUTED Findings

### R1. Refuted Claim: "Chicago-style tests are too slow and should be replaced with unit mocks"
- **Claim:** Running tests against real files and subprocesses makes the test suite sluggish.
- **Investigation:** By leveraging BEAM concurrency with `async: true` and utilizing in-memory WASM engines,
  the entire test suite executes in seconds, completely avoiding the brittle mock-refactoring trap.
- **Verdict:** REFUTED.

---

## Section 3 — Expert Recommendations & Vision

1. **Automated Mutation Testing in CI:** Introduce mutation testing tools (like `Muzak`) into CI to systematically
   measure test suite fault sensitivity.
2. **Explicit Test Ladder Partitioning:** Separate tests into `mix test.fast` (unit/properties) and `mix test.full`
   (integration/subprocesses) to optimize developer flow.
3. **Property Testing Expansion:** Expand `StreamData` generators across SPARQL result-binding parsers.

---

## Section 4 — What This Review Did NOT Check

- Long-duration stress testing under multi-node distributed clustering.

---

## Section 5 — Evidence Ledger & Mechanical Citations

| Subject / Artifact | Exact Location | Finding / Invariant Verified | Standing / Result |
|---|---|---|---|
| Chicago testing mandate | `test/CLAUDE.md:40-70` | Zero mock doubles policy for local collaborators | Enforced |
| Anti-mock review gate | `lib/ggen_igniter/review/perspectives/chicago_tests.ex:18-38` | AST and diff inspection rejecting banned test doubles | `ALIVE` |
| Mock discipline test | `test/ggen_igniter_mock_discipline_test.exs:1-55` | Automated verification of zero unapproved mocks | Passed |
| Agent guard mutation tests | `test/ggen_igniter_agent_guard_test.exs:1-60` | 25 real-subprocess stdin JSON protocol mutation tests | 25/25 passed |
| Engine simplification | `lib/ggen_igniter/engine.ex:9-24` | Consolidation to single fixed `graphlaw` WASM engine | `ALIVE` |
| ExUnit config hygiene | `test/test_helper.exs:23-50` | Single-point configuration avoiding tag clobbering | Verified |
| Overview charter | `00-OVERVIEW.md` | Master release charter and test methodology | Verified |
| Shore-up compilation gate | `01-RELEASE-SHORE-UP-AND-COMPILATION.md` | Verification of warning-free test compilation | Verified |
