# _LANES.md — v26.10.2 ERRC wave, lane contracts (ggen_igniter @ cd0898d)

Milestone: close the v26.10.1-loop (sjira→pack→execute→receipt→promote→plan-next, ALIVE
at qualification scale, bridge suite 101/0) and run ERRC v26.10.2 phase 1 across four
repos. Two phases, disjoint file ownership per phase, one canonical checkout per repo,
coordinator owns every git transition. Lanes never run git state commands.

## Phase 1 — ERRC execution lanes (9)

| lane | repo | owns (create/edit, nothing else) |
|---|---|---|
| P1-G1 | ggen_igniter | fixture hygiene (El1 on_exit removal), mock-discipline guard, gate regex |
| P1-G2 | ggen_igniter | epoch re-stamp v26.10.2, digest boundary law doc, status.md truth pass |
| P1-G3 | ggen_igniter | execute `sj:targetPack` gate (registry 132), ontology.ttl (additive) |
| P1-G4 | ggen_igniter | receipts fleet-R v2 law, release commit + `v26.10.1` tag |
| P1-X1 | xaas | env-honest tests (ERTS mirror + cargo skips) |
| P1-X2 | xaas | crown `:no_ready_work` diagnosis (read-only + ticket, no behavior change) |
| P1-A1 | ash_a2a | mock-discipline gate via its own MockScan AST scanner |
| P1-A2 | ash_a2a | `chicago.mutate --require-killed` in CI, 26.9.31 release-prep |
| P1-P1 | ash_pplan | `bin/gate` re-sync to CI, lock regen, targetPack pilot |

Forbidden per lane (anything not in the lane's owns cell):

| lane | forbidden |
|---|---|
| P1-G1 | `lib/**`, `docs/**` |
| P1-G2 | `lib/**`, `test/**` |
| P1-G3 | receipts law, P1-G1's tests |
| P1-G4 | ontology.ttl, epoch files |
| P1-X1 | xaas crown/lease code |
| P1-X2 | P1-X1's test env files |
| P1-A1 | CI workflow, mix.exs version |
| P1-A2 | MockScan scanner |
| P1-P1 | anything outside `bin/` + lock |

### RESOLUTIONS (shared seams, phase 1)

- **El1 (P1-G1)**: a test that mints a unique-per-run fixture path `on_exit`-deletes
  only paths it created; the tracked inprocess-dispatch fixture pack is never deleted.
  Evidence: commit b64a746.
- **targetPack (P1-G3)**: `execute` refuses `target_pack_mismatch` when the order's
  `sj:targetPack` does not match the pack being executed; refusal registered at
  registry entry 132. P1-G4's receipts law consumes but does not define it.
- **fleet-R v2 (P1-G4)**: `receipts check/1` enforces the fleet-R v2 law and the
  extension namespace; P1-G3's targetPack receipts must satisfy it. Seam: the
  refusal-code registry is append-only — both lanes read it, only P1-G3 appends.
- **utp:hilt (two-port pack)**: opt-in HILT work-order binding in the generated
  constructor, gated on ash_a2a hex publishing Hilt. ggen-side commit 60e18bf lands
  the opt-in; activation waits on P1-A2's publish. Evidence: commit 60e18bf.
- **crown `:snapshot`**: crown binds `:snapshot` — descriptor-rewrite hole closed —
  plus named ticket-dir error. Cross-repo seam; xaas P1-X2 consumes the diagnosis.

## Phase 2 — F-lanes (10)

Orthogonal-ownership rule: each F-lane takes exactly one phase-1 lane's output as its
input and owns files disjoint from every concurrently-running F-lane. Where two
F-lanes would touch one file, the later lane serializes behind the earlier lane's
integration commit — no co-editing, no re-partition after dispatch.

| lane | repo | input | owns | status |
|---|---|---|---|---|
| F1 | xaas | P1-X1 | hex floor bump | IN FLIGHT |
| F2 | ggen_igniter | P1-G4 | v26.10.2 release propagation | BACKLOG |
| F3 | ash_a2a | P1-A2 | 26.9.31 hex publish; Hilt witness for utp:hilt | BACKLOG |
| F4 | xaas | P1-X2 | crown `:no_ready_work` repair | BACKLOG |
| F5 | ash_pplan | P1-P1 | lock regen + targetPack pilot | IN FLIGHT |
| F6 | ggen_igniter | P1-G2 | machine_experience reconciliation | BACKLOG |
| F7 | ggen_igniter | all | DOCS: milestone receipt (this directory) | DONE |
| F8 | ggen_igniter | P1-G3 | event-terms + gate 055 | BACKLOG |
| F9 | ggen_igniter | P1-G4 | fleet schema repo promotion + fleet-r pack | BACKLOG |
| F10 | ggen_igniter | P1-G4 | protocol-court trio + VerifyMutation catalog | BACKLOG |

F4 detail: candidate cause is `:ultracode_providers` empty fail-closed under test.
F6 detail: 3 failures reproduce only with `GGEN_IGNITER_DIR` set.

F7 is this directory. Its completion evidence is the three files on disk at
`docs/jira/v26.10.2/` — no code, no mix runs, no git transitions (docs-only lane).
