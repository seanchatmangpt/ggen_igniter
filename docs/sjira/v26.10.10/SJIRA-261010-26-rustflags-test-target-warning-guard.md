# SJIRA-261010-26: standing CI guard — RUSTFLAGS test-target warning inventory

Date: 2026-10-10
Lane: sjira-refresh (docs)
Repo: /Users/sac/ggen (base c8846c7-equivalent)
Status: OPEN — guard proposal; lane for the immediate RUSTFLAGS rerun is in
flight.

## Context

Phase-1 receipt (v26_10_10_phase1_receipt.md, item 17 / rustc-warn flip row)
recorded the methodology: a 14-crate `RUSTFLAGS="-W warnings"` inventory gave
0 warnings, but cargo caches warnings — stale `target/` state can silently
suppress re-emission (a trailing `-W warnings` cargo arg errors silently;
touching `.rs` files forces re-emission). Warnings in `#[cfg(test)]` /
`--all-targets` code are not covered by the default `just check` path and
currently have no standing gate, so the inventory will drift.

## Work order — proposal

Add a CI (or `justfile` gate) check that re-runs the warning inventory on
test targets deterministically:

1. New recipe, e.g. `just warn-inventory`:
   `RUSTFLAGS="-W warnings" cargo check --workspace --all-targets 2>&1` with
   the known cargo-arg trap avoided (flag via RUSTFLAGS env, never a trailing
   cargo arg).
2. Gate condition: zero `warning:` lines in output (fail-closed, not a
   warning-about-warnings).
3. Cache-robustness: the recipe must force warning re-emission — either
   `cargo clean -p` for changed crates first, or run under a
   `CARGO_TARGET_DIR` unique to the gate run (deleted on exit, per lane
   build-root cleanup law).
4. Wire into `just pre-commit` or CI; follow the existing gate-count
   governance test convention if added to pre-commit.

## Acceptance criteria (falsifiable)

1. `just warn-inventory` exits 0 on current main with output containing zero
   `warning:` lines.
2. Injecting a deliberate `#[allow]`-bypassable warning into a test module
   makes the gate exit non-zero (mutation/negativity check).
3. Running the gate twice back-to-back (second run fully cached or with fresh
   target dir) yields the same verdict.

## Constraints

- Chicago: real cargo invocation, assert on real output, no stubs.
- Gate must be fail-closed; a timeout or tool error is a failure, not a pass.

## Priority

Medium — prevents recurrence class; not a release blocker itself but protects
G3/G4 standing.
