# RECEIPT.md — v26.10.2 milestone manufacturing receipt

Manufacturing receipt per operating-doctrine law 7: exact subjects, commands + exits,
standing per hop, falsifiers, residues. Covers the v26.10.1-loop prior wave, ERRC
v26.10.2 phase 1 (9 lanes), and phase-2 F-lanes. Vocabulary:
ALIVE / PARTIAL_ALIVE / BLOCKED / REFUSED / UNKNOWN.

## Identity

| field | value |
|---|---|
| milestone | v26.10.2 (ERRC phase 1 + phase 2) |
| subject repo | ggen_igniter main, head ee10e7b (tag `v26.10.2` @ ee10e7b) |
| date | 2026-10-02 |
| lane map | `_LANES.md` (this directory); DoD ledger below (lane C10) |

## Cross-repo SHA ledger

| repo | branch | head | note |
|---|---|---|---|
| ggen_igniter | main | ee10e7b | tag `v26.10.2` @ ee10e7b; 26.10.1 **and** 26.10.2 on hex |
| xaas | feat | 4b848624 | `feat/sjira-v26-10-1-chicago-render`; main = merge 5fc56da2 |
| ash_a2a | main | f36e3e6 | code head; docs-only c8ee4c9 above it; **26.9.31 on hex** |
| ash_pplan | main | 5f7e875 | 26.10.2 committed; tag pending C9/B1; lock regen uncommitted |

ggen_igniter commit chain this wave (cd0898d → ee10e7b):

| SHA | subject (prefix) |
|---|---|
| 81df828 | feat(semantic-jira-pack): standing-transition event vocabulary, pack shapes, gate 055 |
| 134b35c | feat(schema): vendored fleet-R v2 schema with digest pin + conformance court |
| 513c6e7 | feat(verify): VerifyMutation — mutation catalog over the fail-closed verify surface |
| 67fcffa | docs(v26.10.2): milestone lanes, receipt, and ERRC cycle report |
| ee10e7b | release: v26.10.2 — symlink-boundary law + ERRC wave |

Full subjects on disk at the cited SHAs (`git log --format=%s` per SHA).
Cross-repo detail: xaas 7dc90027 is the F1 hex-floor output; 2517f626 is the live
SemanticJiraBridge seam; 4b848624 is the plan-next admit/2 seam. ash_a2a debdc1a and
75c386e carry the 26.9.31 prep chain; d58f99f is the fleet-R-v2 projection, 6abdb9f
the two-port graph-digest HILT work. ash_pplan b80ce69/f91fafe carry the 26.10.2
version identity; 1ebc817 the standing bridge + FOND closure.

## Command ledger (real commands, real exits)

| command | exit | outcome |
|---|---|---|
| bridge suite vs hex-published dep | 0 | **101/0 — decisive promote falsifier: ALIVE vs hex** |
| bridge suite (loop qualification, local subject) | 0 | 101/0 — loop ALIVE at qualification scale |
| `mix ggen_igniter.epoch.watermark` (re-stamp) | 0 | watermark re-stamped for epoch v26.10.2 |
| `admit_candidates` (targetPack) | 1 | `REFUSED:TARGET_PACK_MISMATCH` (reg 132) |
| `mix ggen_igniter.receipts check` | 0 | fleet-R v2 law + extension namespace enforced |
| fleet-R v2 schema conformance court | 0 | vendored schema + digest pin (priv/schema/, 134b35c) |
| `mix ash_a2a.chicago.mutate --require-killed` | 0 | wired into ash_a2a CI (debdc1a) |
| `mix compile --warnings-as-errors` + `mix test` | 0 | per-commit gate on landed commits |
| hex publish ggen_igniter 26.10.1 | 0 | package + docs live on hex, tag `v26.10.1` |
| hex publish ggen_igniter 26.10.2 | 0 | package + docs live on hex, tag `v26.10.2` @ ee10e7b |
| hex publish ash_a2a 26.9.31 | 0 | package + docs live on hex (aaed6a2→75c386e prep chain) |
| crown bind `:snapshot` | 0 | descriptor-rewrite hole closed; named ticket-dir error |
| xaas weekly semantic-crown CI job | 0 | machine evidence under the execute hop (bd7c0ad9) |

The non-zero exit is a typed refusal doing its job: admission refusing an illegal
plan before any byte is written. Not a failure.

## Standing per hop

Loop hops x repos. ggen = ggen_igniter. "—" = hop not on that repo's path.

| hop | ggen | xaas | ash_a2a | ash_pplan |
|---|---|---|---|---|
| admit | ALIVE — journaled; refusal at reg 132 | — | — | ALIVE — pilot consumes the refusal (F5) |
| order→pack | ALIVE — `sj:targetPack` gate (f0c6f92) | — | — | ALIVE — targetPack pilot (F5) |
| generate | ALIVE — pack shapes + gate 055 (81df828) | — | — | — |
| execute | ALIVE — local driver | ALIVE — fabric via bridge | ALIVE — HILT witnessed (B2) | — |
| verify | ALIVE — fleet-R v2; validator ADMITTED | — | ALIVE — `--require-killed` in CI | — |
| receipt | ALIVE — fleet-R v2 `receipts check/1` | — | PARTIAL_ALIVE — RProjection (d58f99f) | — |
| promote | ALIVE — bridge 101/0 vs hex dep | — | — | — |
| plan-next | ALIVE — candidate journaled | ALIVE — admit/2 seam, default-OFF (4b848624) | — | — |

xaas execute also carries the weekly semantic-crown CI job (bd7c0ad9) under the
execute hop. Lines per cell name the witness commit; full chains in the ledger.

Supporting rows:

| item | standing | why |
|---|---|---|
| two-port HILT (`utp:hilt`) | PARTIAL_ALIVE | opt-in (60e18bf); B2 witness; Hilt publish gates it |
| ash_a2a mutation court | PARTIAL_ALIVE | `--require-killed` in CI; 26.9.31 **on hex** (F3 done) |
| crown `:snapshot` binding | ALIVE (ggen) | hole closed; xaas subprocess residue, see below |
| v26.10.2 release (ggen_igniter) | ALIVE | on hex AND tagged `v26.10.2` @ ee10e7b (F2 done) |
| ash_pplan 2-pack | PARTIAL_ALIVE | symlink law in `PackLock` (B1); tag/publish await C9/B1 |

## Falsifiers run

| falsifier | result |
|---|---|
| bridge suite 101/0 against the **hex** dependency | passed — promote hop standing holds |
| bridge suite 101/0 on the loop subject (local) | passed — loop standing holds |
| targetPack mismatch admission | refused as designed — gate non-vacuous |
| receipts check vs fleet-R v2 + namespace | enforced — malformed receipts fail |
| vendored-schema conformance court | enforced — digest pin + schema shape (134b35c) |
| VerifyMutation catalog over the verify surface | mutants enumerated + killed (513c6e7) |
| mock-discipline gates (guard + MockScan) | executable, wired at gate/CI level |
| `chicago.mutate --require-killed` | surviving mutants fail the build |

## Residues (standing, not failures)

- **xaas subprocess crown `:no_ready_work`** — fails at `Lease.claim_next` equally on
  base; root-cause pass in flight (lane A8; F4 in `_LANES.md`'s phase-2 table).
  Candidate cause: `:ultracode_providers` empty fail-closed under test.
- **machine_experience 3 failures** — only with `GGEN_IGNITER_DIR` set; under
  reconciliation. Owner: F6.
- **ToolchainPin ggen test red off-pin** — by design; asdf shims off PATH is the
  machine-side root cause; PATH repair is the documented fix. Owner: operator.
- **ash_pplan 2-pack manufacture BLOCKED** — pending the 26.10.2 symlink-law publish
  (coordinator-gated). Owner: F5 / coordinator.
- **El3 scratch cleanup** — ~110 GB awaiting operator `rm` confirmation. Owner:
  operator.

## Parked items (8)

1. **xaas crown `:no_ready_work` repair** — root-cause in flight (A8/F4).
2. **machine_experience `GGEN_IGNITER_DIR`** — reproduces only under env set;
   reconciliation in progress (F6).
3. **ToolchainPin off-pin red** — machine-side PATH root; documented fix, awaiting
   PATH repair.
4. **El3 ~110 GB scratch cleanup** — irreversible; awaiting operator confirmation.
5. **schema repo promotion decision** — vendored pilot done (134b35c); promotion to a
   dedicated repo is the open call (F9 remainder).
6. **fleet-r pack** — phase-3, bundled with #5 (F9 remainder).
7. **protocol-court trio re-modelling** — phase-3, bundled with VerifyMutation
   follow-ons (F10 remainder).
8. **work_graph/3 generator + shared digest boundary doc** — phase-3, from the F-wave
   residues.

Replay: check out each repo at the ledger SHA above. The ggen_igniter commit chain,
command exits, and cited files are those on disk at ee10e7b (tag `v26.10.2` @
ee10e7b); the xaas merge is 5fc56da2, ash_a2a f36e3e6, ash_pplan 5f7e875.

## DoD verdict ledger (C-lanes)

Lane C10 (this file) records the cross-repo Definition-of-Done ledger. Verdicts fill
as lanes report; a lane still out is PENDING with its scope. B-wave witnesses already
recorded above: B1 (pplan symlink-law unblock) and B2 (a2a HILT behavioral witness).

| lane | scope | verdict | evidence |
|---|---|---|---|
| C1 | not yet reported to this ledger | PENDING | coordinator dispatch |
| C2 | not yet reported to this ledger | PENDING | coordinator dispatch |
| C3 | not yet reported to this ledger | PENDING | coordinator dispatch |
| C4 | not yet reported to this ledger | PENDING | coordinator dispatch |
| C5 | not yet reported to this ledger | PENDING | coordinator dispatch |
| C6 | not yet reported to this ledger | PENDING | coordinator dispatch |
| C7 | not yet reported to this ledger | PENDING | coordinator dispatch |
| C8 | not yet reported to this ledger | PENDING | coordinator dispatch |
| C9 | pplan tag/publish verdict (joint with B1) | PENDING | last tag `v26.10.1`; 26.10.2 landed |
| C10 | DoD ledger: version sweep, SHA refresh, matrix | DONE | this section + tables above |
