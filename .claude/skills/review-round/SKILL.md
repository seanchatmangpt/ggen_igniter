---
name: review-round
description: One bounded adversarial review round (cap 3) of the current diff via the ggen-reviewer agent — findings persisted to docs/REVIEW_STATE.md with severity, invariant citation, and required bug-class; dedup against prior rounds
---

# Review Round

Run ONE bounded review round per invocation. Never run more than one round
inside a single invocation — the cap is on rounds, not on effort within a round.

## Steps

1. **Confirm location**: `pwd && git remote -v && git rev-parse --abbrev-ref HEAD`.
   Must be `ggen_igniter`. Never assume cwd.

2. **Load round state**: read `docs/REVIEW_STATE.md` if it exists. It carries
   the current round number, open findings (id, severity, class, file:line,
   invariant, status), and the round cap (3). Missing file = round 1, no prior
   findings.

3. **Determine round mode**:
   - Round 1: full review — the agent reviews the complete diff
     (`git diff` + staged) across the 6 surfaces in
     `.claude/agents/ggen-reviewer.md`.
   - Rounds 2-3: diff-only — the agent reviews ONLY hunks changed since the
     previous round, plus a carried-finding regression check: for every open
     finding, re-verify against the new diff and mark `closed` (verified by
     reading the changed code) or keep `open` (still reproduces).

4. **Dispatch the reviewer**: invoke the `ggen-reviewer` agent with the round
   number, the round mode, and the list of open finding ids to regression-check.
   It is read-only by contract; it never edits.

5. **Enforce the finding schema** on every finding before persisting. A finding
   missing any field is not a finding:
   - `id` `R<round>-<seq>`
   - `severity`: `blocker|major|minor`
   - `bug-class` (REQUIRED): one of `correctness|concurrency|resource-leak|error-handling|security|api-misuse|data-loss|type-soundness|test-gap|style`.
     A finding with no bug-class is rejected — the class is what makes dedup
     and adjudication mechanical.
   - `invariant`: cited surface (1-6) or doc/ADR/README section
   - `file:line`, `status` (`open|closed`)

6. **Dedup against prior rounds**: a new finding that matches an existing
   (non-closed) finding on BOTH bug-class AND file with line within ±3 is the
   SAME finding — keep the original id, do not emit a duplicate. A match on
   only one axis is a new finding.

7. **Persist state**: rewrite `docs/REVIEW_STATE.md` with the new round number,
   the merged finding list (prior open + closed-this-round + new), and the
   reviewer's VERDICT line verbatim:
   `VERDICT: <round>/3 | N blockers, M majors, K minors; PROCEED only if blockers==0`

8. **Stop conditions** (check in order; first match wins):
   - `blockers == 0` AND the dispatching loop's fix/adjudicate pass has closed
     every open finding or adjudicated it → round loop ends, PROCEED.
   - Any blocker open after the fix pass → next round (if round < 3).
   - Round 3 completed and open findings remain → **NEEDS-HUMAN**: stop the
     automated loop; unresolved findings require human adjudication via the
     `adjudicate-findings` skill (which is the single escalation point).
   - Two consecutive rounds produce zero NEW findings and the open set is
     unchanged → **NEEDS-HUMAN**: the loop is not converging; more rounds
     would churn, not converge.

## Invariants

- The reviewer agent stays read-only (its `tools:` line). This skill writes
  only `docs/REVIEW_STATE.md`.
- One round per invocation. An invocation that runs rounds 1 and 2 has
  violated the cap.
- Findings are never deleted from REVIEW_STATE.md — closed ones stay as
  history with their closing round.
