---
name: defect-round
description: One falsification-hardened defect-hunting round for ggen_igniter — failing test first, fix, mutate, disk-verify, receipt
---

Run one round per invocation. Refuse to advance a step on any failure — report and stop
rather than paper over it.

1. **SELECT**: name one unverified behavior in `ggen_igniter` (untested branch, error
   path, boundary condition, an ADR-disclosed gap in `docs/status.md`). State exactly
   why it's unverified with a `file:line` citation.
2. **FALSIFY-FIRST**: write a test that FAILS against current code. Run it
   (`mix test path/to/test.exs`) and paste the real failing output. If it passes,
   the hypothesis was wrong — discard and pick another target.
3. **FIX**: make the minimal real change (Chicago-style: real collaborators, no mocks).
4. **READ-BACK**: re-`Read` the edited file and quote the changed lines verbatim.
5. **MUTATE** (where feasible): hand-mutate the fix (flip a condition, off-by-one) and
   confirm the test you wrote now fails against the mutant — proves the test is
   load-bearing, not tautological. Revert the mutation.
6. **GATE**: run the `gate` skill in full. Paste real output.
7. **RECEIPT**: append a row to `docs/VERIFICATION_LEDGER.md` (create if absent):
   round | hypothesis | failing-output summary | mutant-killed (yes/no) | commit SHA.
8. **COMMIT**: `git commit -F <message-file>` (never inline `-m` for multi-line —
   see `~/.claude/rules/tools.md`), message names the round number.

If no genuine unverified behavior can be found, say "ROUND EXHAUSTED — no honest gap
found" and stop. Do not manufacture busywork to look productive.
