# ERRC.md — v26.10.2 cycle report

ERRC (Eliminate / Reduce / Raise / Create) over the post-loop backlog, ranked.
Evidence pointers cite `RECEIPT.md` (this directory) by section. Cycle status:
**phase 1 complete, phase 2 in flight, phase 3 backlog.**

## Quadrant table (ranked)

| rank | quad | item | evidence |
|---|---|---|---|
| 1 | Eliminate | El1: fixture-deleting `on_exit` removed | R# commit list (b64a746) |
| 2 | Reduce | mock leakage → executable gates (ggen + ash_a2a) | R# commands; R# standing |
| 3 | Reduce | pack mismatch → `sj:targetPack` refusal | R# commands (typed refusal) |
| 4 | Raise | receipts law strength: fleet-R v2 + namespace | R# commands (receipts check exit 0) |
| 5 | Raise | crown descriptor-rewrite hole closed (`:snapshot`) | R# commands; R# standing |
| 6 | Raise | mutation-court vacuity: `--require-killed` in CI | R# falsifiers |
| 7 | Create | two-port HILT binding (`utp:hilt`, opt-in) | R# standing (PARTIAL_ALIVE) |
| 8 | Create | digest boundary law documented from schema patterns | R# commit list (2cac19d) |
| 9 | Create | Cr5: milestone receipt (this directory) | R# identity; F7 DONE in `_LANES.md` |
| 10 | Eliminate | El3: ~110 GB scratch deletion proposed | R# parked #4 |

Actions behind the ranks:

1. Tests now `on_exit`-delete only paths they minted; the tracked fixture pack
   survives (b64a746).
2. Prose replaced by executable checks: settings guard + gate-skill regex (ggen),
   MockScan AST scanner (ash_a2a).
3. `execute` refuses `target_pack_mismatch` before any byte is written (f0c6f92).
4. `receipts check/1` enforces fleet-R v2 and the extension namespace (2cac19d).
5. Crown binds `:snapshot`; named ticket-dir error added.
6. Surviving mutants fail the ash_a2a build.
7. Opt-in HILT work-order binding in the generated constructor (60e18bf); activation
   gated on ash_a2a hex publishing Hilt.
8. Identity by blob sha, not blame; digest boundary law written down.
9. `_LANES.md` + `RECEIPT.md` + this file.
10. Awaiting operator confirmation before any deletion.

Status-truth pass: `docs/status.md` corrected, 4 rows re-verified against real
evidence (2cac19d).

## Parked list (8, with reasons)

1. **xaas crown `:no_ready_work`** — fails at `Lease.claim_next` equally on base;
   candidate cause `:ultracode_providers` empty fail-closed under test. Parked until
   a failing-test-first repair pass (lane F4).
2. **machine_experience 3 failures** — reproduce only with `GGEN_IGNITER_DIR` set;
   under reconciliation (lane F6).
3. **ToolchainPin ggen test red off-pin** — by design; asdf shims off PATH is the
   machine-side root; PATH repair is the documented fix.
4. **El3 ~110 GB scratch cleanup** — irreversible; awaiting operator confirmation.
5. **event-terms + gate 055** — phase-3; depends on targetPack receipts settling (F8).
6. **fleet schema repo promotion** — phase-3; needs a fleet-r pack consumer first (F9).
7. **fleet-r pack** — phase-3, bundled with #6 (F9).
8. **protocol-court trio re-modelling** — phase-3, bundled with the ggen
   VerifyMutation catalog (F10).

## Three-phase execution plan and status

| phase | lanes | status |
|---|---|---|
| 1 | P1-G1..G4, P1-X1..X2, P1-A1..A2, P1-P1 | **COMPLETE** — all lane outputs landed |
| 2 | F1..F7 | **IN FLIGHT** — F1, F5 running; F7 DONE; rest queued |
| 3 | F8..F10 | **BACKLOG** — parked items 5-8 |

- **Phase 1 — ERRC execution (4 repos)**: El1, epoch re-stamp, targetPack,
  fleet-R v2, HILT opt-in, crown `:snapshot`, env-honest tests, mock gates,
  mutation court, gate re-sync, releases. Complete — see RECEIPT.md commit list.
- **Phase 2 — propagation**: hex publishes + floors, crown repair,
  machine_experience reconciliation, milestone receipt (F7).
- **Phase 3 — backlog**: event-terms + gate 055, fleet schema repo promotion,
  fleet-r pack, protocol-court trio, ggen VerifyMutation catalog. Dispatch after
  the phase-2 gate.

Phase gate: phase 2 closes when every F-lane has an integration commit or a typed
REFUSED/BLOCKED receipt; phase 3 dispatches only after that gate (orthogonal-ownership
rule in `_LANES.md`).
