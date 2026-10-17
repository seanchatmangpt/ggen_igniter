# SJIRA-261010-17 — Nested test targets (ggen-cli/tests): classification + user-gated deletion order

Date: 2026-10-09 · Lane: sjira-notes-2 · Status: PROPOSED (user gate required)

## Verdicts

| Target | Size | cargo_bin sites | Verdict |
|---|---|---|---|
| archive/ + marketplace integration pair | 541+434 LOC | 55 | **ARCHIVE** (intentionally dormant) |
| generated/cli_proof_tests.rs | 608 LOC | 18 | **DEAD-known-gap** — untracked; `[[test]]` deliberately removed 2026-07-19; wired only after `.specify/cli-proof-tests.ttl` generation runs |
| integration/testcontainers_readiness.rs | 605 LOC | 21 | **DEAD** — testcontainers 0.14-era API; dep absent since 2026-06-02 |

## User-gated options for testcontainers_readiness.rs

1. **Delete** — target has been uncompilable for >4 months; no consumer.
2. **Rewrite** against current testcontainers API if readiness coverage is still wanted.

## Harness migration receipt

261 in-scope cargo_bin sites across 56 files migrated to `ggen_bin()` pattern.
6 targets fixed by the migration alone.
