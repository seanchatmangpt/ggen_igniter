# SJIRA-261010-05 — engine all-targets quiet-machine rerun + byte-identity failure classification

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P1
- **Status** (2026-10-09 refresh #3): graphlaw workspace re-verified clean
  (hooks refuse-effect 432/0); engine/CLI regression gates still IN FLIGHT
  on a lane. Disk emergency RESOLVED (2026-10-09: ~500GB lane build roots
  purged via oclnr) — lanes must re-request/rebuild targets before the
  quiet-machine rerun.
- **Blocked-by**: preferably SJIRA-261010-04 (stale ambient binary removed) to keep the machine quiet; not strictly required

## Task

DoD #19: the contention-run tally was **710 passed / 32 load-flavored / 3 stable
byte-identity failures** and needs a quiet-machine rerun and classification of
the 3 stable failures (class: book_gap `ocel.json` / `receipts.jsonl` drift —
suspected stale-fixture drift, not logic).

1. `TMPDIR=/tmp cargo test -p ggen-engine --all-targets` on a quiet machine; full tally.
2. For each of the 3 byte-identity failures: diff expected vs actual `ocel.json`/`receipts.jsonl`, classify (fixture drift vs real nondeterminism vs stale binary), and either regenerate the fixture with a receipted command or file a defect.
3. Update the DoD table (`docs/v26_10_10_phase1_receipt.md` item 19) with the quiet-machine numbers and per-failure classification.

## Acceptance

- Quiet-machine run recorded with pass/fail counts; 0 unclassified failures.
- Each of the 3 failures has a written classification + resolution (regenerated fixture commit or defect order).
- Re-run is reproducible: second consecutive run yields identical counts.

## Constraints

- `TMPDIR=/tmp` required (see phase-1 receipt environmental finding).
- No test skips/`--ignored` filtering to manufacture a green tally.
