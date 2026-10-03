# ERRC.md — v26.10.2 cycle report

ERRC (Eliminate / Reduce / Raise / Create) over the post-loop backlog, ranked.
Evidence pointers cite `RECEIPT.md` (this directory) by section (R# = RECEIPT
section). Cycle status: **phase 1 COMPLETE, phase 2 mostly landed — three lanes
gated on coordinator publishes, phase 3 backlog slimmed by this wave.**

## Quadrant table (ranked)

| rank | quad | item | evidence |
|---|---|---|---|
| 1 | Eliminate | El1: fixture-deleting `on_exit` removed | R# commit list (b64a746) |
| 2 | Reduce | mock leakage → executable gates (ggen + ash_a2a) | R# falsifiers |
| 3 | Reduce | pack mismatch → `sj:targetPack` refusal | R# command ledger (typed refusal) |
| 4 | Raise | receipts law: fleet-R v2 + namespace + validator ADMITTED | R# command ledger |
| 5 | Raise | crown descriptor-rewrite hole closed (`:snapshot`) | R# command ledger |
| 6 | Raise | mutation-court vacuity: `--require-killed` in CI | R# falsifiers |
| 7 | Create | two-port HILT binding (`utp:hilt`, opt-in) | R# supporting standing (PARTIAL_ALIVE) |
| 8 | Create | vendored fleet-R v2 schema: digest pin + court | R# command ledger (134b35c) |
| 9 | Create | VerifyMutation catalog over the verify surface | R# falsifiers (513c6e7) |
| 10 | Create | Cr5: milestone receipt (this directory) | R# identity; F7 DONE in `_LANES.md` |
| 11 | Eliminate | El3: ~110 GB scratch deletion proposed | R# parked #4 |

## Phase 1 — COMPLETE (9 lanes, outcomes)

| lane | outcome | evidence |
|---|---|---|
| P1-G1 (fixture hygiene + mock gate) | landed | b64a746 |
| P1-G2 (epoch re-stamp, digest law doc, status pass) | landed | 2cac19d |
| P1-G3 (`sj:targetPack` execute gate) | landed | f0c6f92 |
| P1-G4 (fleet-R v2 receipts law, release + tag) | landed | 2cac19d, cd0898d, tag `v26.10.1` |
| P1-X1 (xaas env-honest tests) | landed | eb5928eb |
| P1-X2 (crown `:no_ready_work` diagnosis) | landed (ticket-only by design) | see R# residues |
| P1-A1 (MockScan mock gate) | landed | debdc1a |
| P1-A2 (`--require-killed` in CI, 26.9.31 prep) | landed | debdc1a, aaed6a2 |
| P1-P1 (bin/gate re-sync, lock regen) | landed | 5f7e875 |

Phase-1 RESOLUTIONS held: El1 on_exit scoping (b64a746), targetPack refusal
registry-132 seam consumed (not redefined) by the receipts law, fleet-R v2
append-only registry, `utp:hilt` opt-in (60e18bf) awaiting Hilt publish.

## Phase 2 — F-lane outcomes

| lane | outcome | evidence |
|---|---|---|
| F1 (xaas hex floor bump) | DONE — merged to main | 7dc90027, merge 5fc56da2 (XA-3004) |
| F2 (v26.10.2 release propagation) | IN FLIGHT — pending coordinator publish | R# SHA ledger |
| F3 (26.9.31 hex publish, Hilt witness) | PENDING publish | aaed6a2 prep committed; head f36e3e6 |
| F4 (crown `:no_ready_work` repair) | IN FLIGHT — root-cause pass (lane A8) | R# residues |
| F5 (lock regen) | BLOCKED — collision; awaits symlink-law publish | R# residues; 5f7e875 |
| F6 (machine_experience reconciliation) | BACKLOG | R# parked #2 |
| F7 (DOCS milestone receipt) | DONE | 67fcffa; three files on disk in this directory |
| F8 (event-terms + gate 055) | DONE — landed early | 81df828 |
| F9 (schema promotion, fleet-r) | PARTIAL — pilot done; decision open | 134b35c; R# parked #5-6 |
| F10 (trio + VerifyMutation) | PARTIAL — catalog done; trio open | 513c6e7; R# parked #7 |

F5 detail: the lock regen collided with upstream ggen_igniter pack layout; the
resolution is the v26.10.2 symlink law, so manufacture is BLOCKED pending the
coordinator publish, not re-partitioned onto another lane.

## Phase 3 — remaining backlog (5)

Closed by this wave and removed from the backlog: fleet schema vendoring pilot
(134b35c), VerifyMutation catalog (513c6e7), mock-discipline gates (b64a746 +
debdc1a), crown-CI job (bd7c0ad9). Remaining:

1. **schema repo promotion decision** — vendored pilot exists; promote-to-repo is
   the open call (F9 remainder).
2. **fleet-r pack** — bundled with #1 (F9 remainder).
3. **protocol-court trio re-modelling** — VerifyMutation follow-on (F10 remainder).
4. **work_graph/3 generator** — new, from F-wave residues.
5. **shared digest boundary doc** — new, from F-wave residues.

Dispatch after the phase-2 gate: every F-lane has an integration commit or a typed
REFUSED/BLOCKED receipt.

## Quadrant actions (ranked rows above)

1. Tests `on_exit`-delete only paths they minted; the tracked fixture pack survives
   (b64a746).
2. Prose replaced by executable checks: settings guard + gate-skill regex (ggen,
   b64a746), MockScan AST scanner (ash_a2a, debdc1a).
3. `execute` refuses `target_pack_mismatch` before any byte is written (f0c6f92).
4. `receipts check/1` enforces fleet-R v2 and the extension namespace (2cac19d);
   validator ADMITTED (R# standing per hop).
5. Crown binds `:snapshot`; named ticket-dir error added.
6. Surviving mutants fail the ash_a2a build.
7. Opt-in HILT work-order binding in the generated constructor (60e18bf); activation
   gated on ash_a2a hex publishing Hilt.
8. Identity by blob sha, not blame; schema vendored with a digest pin and a
   conformance court (134b35c).
9. Mutation catalog over the verify surface: mutants enumerated, killed, and gated
   (513c6e7).
10. `_LANES.md` + `RECEIPT.md` + this file (67fcffa).
11. Awaiting operator confirmation before any deletion.

Status-truth pass: `docs/status.md` corrected and re-verified against real evidence
(2cac19d).

## Three-phase status

| phase | lanes | status |
|---|---|---|
| 1 | P1-G1..G4, P1-X1..X2, P1-A1..A2, P1-P1 | **COMPLETE** — all 9 lane outputs landed |
| 2 | F1..F10 | **MOSTLY LANDED** — F1/F7/F8 DONE; F2/F3/F5 gated; F4 in flight; F6 backlog |
| 3 | remainders | **BACKLOG (5)** — the list above |
