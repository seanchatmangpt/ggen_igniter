# SJIRA-261010-24: G4 follow-up — fortune5 shape-closure regression test hardening

Date: 2026-10-10
Lane: sjira-refresh (docs)
Repo: /Users/sac/ggen (base c8846c7-equivalent; see repo HEAD at execution)
Status: OPEN — follow-up order for the G4 lane currently in flight.

## Context

Pass-3 verifier surfaced a fortune5 shape-closure regression that was
intermittently masked by environment variance: when the test ran against a
tempdir fixture or a shared `target/` directory with stale pack state, the
closure check could pass against cached/stale capability data rather than the
real shape graph. The in-flight G4 lane owns the fix; this order owns making
the regression **non-maskable**.

## Work order

Harden the regression test so environment variance cannot hide a recurrence:

1. The regression test MUST run standalone against its own deterministic
   fixture, never a pre-existing shared target state or ambient
   `.ggen/packs.lock`.
2. Isolation requirement: either `CARGO_TARGET_DIR` unique-per-run (with
   `on_exit` cleanup per same-checkout-fanout cleanup law) or an explicit
   fixture bootstrap that provably rebuilds closure state from the repo tree
   on every run.
3. Assert on observable closure output (the shape-closure verdict / refusal
   set), not on absence of error.

## Acceptance criteria (falsifiable)

1. `cargo test -p <fortune5-closure-test-target> -- --exact` passes on a clean
   machine AND fails when the original regression is reintroduced
   (mutation check: revert the G4 fix, test must go red).
2. Running the test twice in a row with a polluted shared `target/` between
   runs produces identical verdicts (determinism check).
3. `grep` of the test source shows no reliance on ambient
   `.ggen/` or workspace `target/` state — fixture is self-contained.

## Constraints

- Do not touch the G4 fix itself (other lane owns it) — test hardening only.
- Chicago style: real fixture, real file I/O, no mocks.

## Priority

High — gates G4 sign-off; without hardening the regression class can recur
silently.
