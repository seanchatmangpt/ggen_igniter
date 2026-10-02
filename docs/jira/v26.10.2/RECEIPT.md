# RECEIPT.md — v26.10.2 milestone manufacturing receipt

Manufacturing receipt per operating-doctrine law 7: exact subjects, commands + exits,
standing per hop, falsifiers, residues. All work below was executed this session
(v26.10.1-loop prior wave + ERRC v26.10.2 phase 1 this wave). Vocabulary:
ALIVE / PARTIAL_ALIVE / BLOCKED / REFUSED / UNKNOWN.

## Identity

| field | value |
|---|---|
| milestone | v26.10.2 (ERRC phase 1) |
| subject repo | ggen_igniter main, head cd0898d, tag v26.10.1 |
| date | 2026-10-02 |
| lane map | `_LANES.md` (this directory) |

## Cross-repo SHA ledger

| repo | branch | head | note |
|---|---|---|---|
| ggen (ggen_igniter) | main | cd0898d | tag v26.10.1; 26.10.1 PUBLISHED to hex |
| xaas | feat | eb5928eb | hex floor bump in flight (lane F1) |
| ash_a2a | main | debdc1a | 26.9.31 release-prep committed (aaed6a2) |
| ash_pplan | main | 5f7e875 | lock regen + targetPack pilot in flight (lane F5) |

## Prior wave — v26.10.1-loop

10 commits across ggen/xaas/ash_a2a/ash_pplan closing the
sjira→pack→execute→receipt→promote→plan-next loop. Verification: bridge suite 101/0
(0 failures). Standing: **the loop is ALIVE at qualification scale** — observed
execution of every hop on the admitted subject, not a plan or inspection.

## This wave — commit list (ggen_igniter main)

| SHA | subject (prefix) |
|---|---|
| b64a746 | fix(test): fixture pack preserved; mock-discipline gate |
| f0c6f92 | feat(semantic-jira): execute consumes sj:targetPack |
| 60e18bf | feat(two-port-pack): opt-in HILT work-order binding |
| 2cac19d | feat(semantic-jira): receipts fleet-R v2 law; status pass |
| cd0898d | release: v26.10.1 (calver-correction re-release of v26.9.31) |

Full subjects are on disk at the cited SHAs (`git log --format=%s` per SHA).
Cross-repo: ash_a2a aaed6a2 (26.9.31 release-prep); xaas eb5928eb and ash_pplan
5f7e875 carry the env-honest tests and gate/lock work respectively.

## Command ledger (real commands, real exits)

| command | exit | outcome |
|---|---|---|
| bridge suite (loop qualification) | 0 | 101/0 — loop ALIVE at qualification scale |
| `mix ggen_igniter.epoch.watermark` (re-stamp) | 0 | watermark re-stamped for epoch v26.10.2 |
| `mix semantic_jira.admit_candidates` (targetPack) | 1 | `REFUSED:TARGET_PACK_MISMATCH` (reg 132) |
| `mix ggen_igniter.receipts check` | 0 | fleet-R v2 law + extension namespace enforced |
| `mix ash_a2a.chicago.mutate --require-killed` | 0 | wired into ash_a2a CI (P1-A2) |
| `mix compile --warnings-as-errors` + `mix test` | 0 | per-commit gate on landed commits |
| hex publish ggen_igniter 26.10.1 | 0 | package + docs live on hex, tag v26.10.1 |
| crown bind `:snapshot` | 0 | descriptor-rewrite hole closed; named ticket-dir error |

The non-zero exit is a typed refusal doing its job: admission refusing an illegal
plan before any byte is written. Not a failure.

## Standing per hop

| hop | standing | why |
|---|---|---|
| sjira→pack→execute→receipt→promote→plan-next | ALIVE | bridge suite 101/0 on subject |
| execute `sj:targetPack` gate | ALIVE | refusal witnessed (`REFUSED:TARGET_PACK_MISMATCH`) |
| receipts fleet-R v2 law | ALIVE | `receipts check/1` enforces law + namespace |
| epoch watermark v26.10.2 | ALIVE | re-stamped this wave; `epoch.check` is the witness |
| two-port HILT binding (`utp:hilt`) | PARTIAL_ALIVE | opt-in in (60e18bf); gated on Hilt publish |
| ash_a2a mutation court | PARTIAL_ALIVE | `--require-killed` in CI; publish pending (F3) |
| crown `:snapshot` binding | ALIVE (ggen) | hole closed; xaas side BLOCKED, see residues |
| xaas hex floor bump | BLOCKED | in flight, lane F1, no receipt yet |
| ash_pplan pilot | BLOCKED | in flight, lane F5, no receipt yet |

## Falsifiers run

| falsifier | result |
|---|---|
| bridge suite 101/0 on the loop subject | passed — loop standing holds |
| targetPack mismatch admission | refused as designed — gate non-vacuous |
| receipts check vs fleet-R v2 + namespace | enforced — malformed receipts fail |
| mock-discipline gates (guard + MockScan) | executable, wired at gate/CI level |
| `chicago.mutate --require-killed` | surviving mutants fail the build |

## Residues (standing, not failures)

- **xaas crown `:no_ready_work`** — fails at `Lease.claim_next` equally on base;
  candidate cause: `:ultracode_providers` empty fail-closed under test. Owner: F4.
- **machine_experience 3 failures** — only with `GGEN_IGNITER_DIR` set; under
  reconciliation. Owner: F6.
- **ToolchainPin ggen test red off-pin** — by design; asdf shims off PATH is the
  machine-side root; PATH repair documented as the fix. Owner: operator.
- **El3 scratch cleanup** — ~110 GB awaiting operator confirmation. Owner: operator.

## Parked items (8)

1. **xaas crown `:no_ready_work` repair** — root-cause candidate named; needs a
   failing-test-first pass (F4).
2. **machine_experience `GGEN_IGNITER_DIR`** — reproduces only under env set;
   reconciliation in progress (F6).
3. **ToolchainPin off-pin red** — machine-side PATH root; documented fix, awaiting
   PATH repair.
4. **El3 ~110 GB scratch cleanup** — irreversible; awaiting operator confirmation.
5. **event-terms + gate 055** — phase-3; depends on targetPack receipts settling (F8).
6. **fleet schema repo promotion** — phase-3; needs fleet-r pack consumer first (F9).
7. **fleet-r pack** — phase-3, bundled with #6 (F9).
8. **protocol-court trio re-modelling** — phase-3, bundled with the ggen
   VerifyMutation catalog (F10).

Replay: check out each repo at the ledger SHA above; the ggen_igniter commits, command
exits, and files cited are those on disk at cd0898d / tag v26.10.1.
