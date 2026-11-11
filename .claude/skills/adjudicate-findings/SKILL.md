---
name: adjudicate-findings
description: Triage open review findings from docs/REVIEW_STATE.md — fix them or close them with a typed resolution (WONTFIX/DUPLICATE/BY-DESIGN/NOT-A-BUG/TEST-GAP-ONLY), each citing an artifact; single escalation point NEEDS-HUMAN
---

# Adjudicate Findings

Triage pass over the open findings in `docs/REVIEW_STATE.md`. Every open
finding gets exactly one of two outcomes: **fixed** (a real diff closes it) or
**resolved** (a typed resolution closes it without a diff). Nothing else.

## Steps

1. **Confirm location** and read `docs/REVIEW_STATE.md`. List every
   `status=open` finding by id, severity, class.

2. **Partition: fix vs resolve.** A finding is a FIX candidate iff fixing it
   is a real code/doc change that the current work order owns. A finding is a
   RESOLVE candidate iff the behavior under review is correct and the finding
   mis-models it, or it duplicates another finding, or fixing it is out of
   this work order's scope. When in doubt, fix — a typed resolution is an
   admitted claim, not an exit hatch.

3. **Fix candidates**: apply the fix, then verify the finding is closed the
   Chicago way — re-read the changed code on disk and, where a test can
   witness it, run the test. Mark `closed` in REVIEW_STATE.md with the closing
   round and the verifying command/test name.

4. **Resolve candidates**: each resolution MUST be one of exactly five typed
   values, each citing an artifact (file:line, ADR section, commit, or receipt)
   that justifies it. An untyped or uncited resolution is invalid and the
   finding stays open:
   - `WONTFIX` — real but deliberately not addressed now; cite the tracker
     row/work order that records the debt.
   - `DUPLICATE` — same finding as another id; cite the surviving finding id.
   - `BY-DESIGN` — the flagged behavior is the specified behavior; cite the
     doc/ADR/README section specifying it.
   - `NOT-A-BUG` — the finding's factual premise is false in the current tree;
     cite the file:line that falsifies the premise.
   - `TEST-GAP-ONLY` — no production defect; the gap is the missing witness;
     cite the test added (or the existing test that already covers the path).

5. **Cross-check FIXED claims** — audit, don't trust: for every finding marked
   closed-by-fix, re-read the cited file/lines and confirm the flagged
   condition is actually gone. A FIXED claim that does not survive the audit
   reverts to `open` with a note; the round verdict then still counts it.

6. **Recompute the verdict** from the surviving open set:
   `VERDICT: <round>/3 | N blockers, M majors, K minors; PROCEED only if blockers==0`
   with N/M/K counted over OPEN findings only.

7. **Single escalation point**: the ONLY way an unresolved finding exits this
   skill's scope is `NEEDS-HUMAN`, reached when (a) the round cap (3) is hit
   with open findings, or (b) two consecutive rounds converge on an unchanged
   open set, or (c) a resolution requires an authority this skill does not
   hold (e.g. contradicting an ADR). Write `NEEDS-HUMAN: <finding ids>` in
   REVIEW_STATE.md and stop — do not silently drop the findings, do not run
   another round past the cap.

## Invariants

- This skill edits code/docs it owns plus `docs/REVIEW_STATE.md`; it never
  edits the reviewer agent or the review machinery.
- Resolutions are append-only history in REVIEW_STATE.md — a resolution may be
  overturned by new evidence, recorded as a new note, never erased.
- `blockers == 0` among open findings is the only PROCEED condition.
