# ERRC.md — v26.10.2 cycle report

ERRC (Eliminate / Reduce / Raise / Create) over the post-loop backlog, ranked.
Evidence pointers cite `RECEIPT.md` (this directory) by section (R# = RECEIPT
section). Cycle status: **phase 1 COMPLETE, phase 2 LANDED through the
post-ledger D-wave (final-state pass, ggen_igniter @ a404697) — remaining
gates are coordinator publishes (ash_pplan hex) and the D8 pin qualification;
phase 3 backlog slimmed by this wave.**

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
| F2 (v26.10.2 release propagation) | DONE — 26.10.1 and 26.10.2 on hex; tag `v26.10.2` @ ee10e7b | R# SHA ledger |
| F3 (26.9.31 hex publish, Hilt witness) | DONE — 26.9.31 on hex | head f36e3e6 → ccdb634; R# supporting rows |
| F4 (crown `:no_ready_work` repair) | DONE — subprocess crown completes the full loop | 117e4b64 (provider-claim fix) |
| F5 (lock regen) | UNBLOCKED — tag `v26.10.2` @ 2cad4cc landed (C9); hex publish state unchanged | R# supporting rows; 2cad4cc |
| F6 (machine_experience reconciliation) | BACKLOG | R# parked #2 |
| F7 (DOCS milestone receipt) | DONE — final-state pass folded the D-wave + C9/C11 in | 67fcffa, 04c5fcf, this pass |
| F8 (event-terms + gate 055) | DONE — landed early | 81df828 |
| F9 (schema promotion, fleet-r) | PARTIAL — pilot done; decision open | 134b35c; R# parked #5-6 |
| F10 (trio + VerifyMutation) | PARTIAL — catalog done; trio open | 513c6e7; R# parked #7 |

Post-ledger D-wave (after 04c5fcf, all on ggen_igniter main, verified
read-only): 67961c7 (canonical `REFUSED:<CODE>` emitters, legacy parse shapes
removed), 8e577a5 (`to_prd_status/1` removed — fleet-R v2 projection supersedes),
8ef0fea (TargetPack rendered from pack facts; HANDWRITTEN row 48 retires),
3c22220 (HILT binding DEFAULT ON — `utp:hilt false` is the compat escape),
b83d604 (strict-profile STOP witnesses), 3a154ae (legacy digest window SHRUNK,
removal milestone v26.11.1), c49c53f (shapes_checked assertion), a404697
(C11 credo zero). D8 pin move to `elixir 1.19.5-otp-27` / `erlang 27.2.4` is
on disk, uncommitted at a404697 — qualification in flight.

F5 detail (historical): the lock regen collided with upstream ggen_igniter pack
layout; the resolution was the v26.10.2 symlink law. The tag landed
(`v26.10.2` @ 2cad4cc, C9), unblocking manufacture; the ash_pplan hex publish
remains coordinator-gated.

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
7. HILT work-order binding in the generated constructor: opt-in at 60e18bf,
   now DEFAULT ON (3c22220) after the ash_a2a 26.9.31 Hilt publish; behavioral
   witness against the published subject (c021243, 9562548); `utp:hilt false`
   is the compat escape.
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
| 2 | F1..F10 | **LANDED** — F1/F2/F3/F4/F7/F8 DONE; F5 unblocked (tag @ 2cad4cc, publish gated); F6 backlog; F9/F10 partial by design |
| 3 | remainders | **BACKLOG (5)** — the list above |
