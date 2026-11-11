# RECEIPT.md — v26.10.2 milestone manufacturing receipt

Manufacturing receipt per operating-doctrine law 7: exact subjects, commands + exits,
standing per hop, falsifiers, residues. Covers the v26.10.1-loop prior wave, ERRC
v26.10.2 phase 1 (9 lanes), and phase-2 F-lanes. Vocabulary:
ALIVE / PARTIAL_ALIVE / BLOCKED / REFUSED / UNKNOWN.

## Identity

| field | value |
|---|---|
| milestone | v26.10.2 (ERRC phase 1 + phase 2 + final-state pass) |
| subject repo | ggen_igniter main, head ee10e7b (tag `v26.10.2` @ ee10e7b); main now at a404697 |
| date | 2026-10-02 |
| lane map | `_LANES.md` (this directory); DoD ledger below (lane C10) |

Final-state pass (F1 DOCS, 2026-10-02): authored on the working tree at
a404697; every SHA below re-verified with read-only `git log` in its own
repo before citation. The D-wave (67961c7 → a404697) landed after the DoD
ledger commit 04c5fcf and is folded in below.

## Cross-repo SHA ledger

| repo | branch | head | note |
|---|---|---|---|
| ggen_igniter | main | a404697 | tag `v26.10.2` @ ee10e7b; 26.10.1 **and** 26.10.2 on hex; credo-zero head |
| xaas | feat | de15fd14 | `feat/sjira-v26-10-1-chicago-render`; main = merge 5fc56da2; crown loop closed (117e4b64), digest window shrunk (93784aed) |
| ash_a2a | main | ccdb634 | code head above f36e3e6; 26.10.2 ERRC wave (4297fb0, e0fd26b, 619bbb3, 7c13f1e, eb7608d); **26.9.31 on hex** |
| ash_pplan | main | 2cad4cc | **tag `v26.10.2` @ 2cad4cc (C9 landed)**; standing-pack harness fix on top of 5f7e875 |
| ggen-marketplace | main | 6b43b654 | lifecycle trio entries (render-verified generalizations, IRI-diverged, review intent) |
| ash_affidavit | main | 300350e | 26.10.1 release commit 3d024ea pushed; EKV/PROV validity chain above it |
| ash_graphlaw | main | e990be4 | parity lineage R2 gained in 2ed5eea (wasm/ABI lineage map, E6); 26.10.1 version bump above it |
| ash_r2rml | fix/v26.9.29-from-source-head | c5ccb25 | R2RML loop map (E5): edge audit vs a2a/xaas/marketplace, ranked closure backlog |

ggen_igniter commit chain this wave (cd0898d → ee10e7b → a404697):

| SHA | subject (prefix) |
|---|---|
| 81df828 | feat(semantic-jira-pack): standing-transition event vocabulary, pack shapes, gate 055 |
| 134b35c | feat(schema): vendored fleet-R v2 schema with digest pin + conformance court |
| 513c6e7 | feat(verify): VerifyMutation — mutation catalog over the fail-closed verify surface |
| 67fcffa | docs(v26.10.2): milestone lanes, receipt, and ERRC cycle report |
| ee10e7b | release: v26.10.2 — symlink-boundary law + ERRC wave |
| c021243 | test(two-port): behavioral witness — stale_graph_identity against published ash_a2a 26.9.31 |
| 2b1dade | test: ash_a2a 26.9.31 / ash 3.33.11 migration — expectations re-pinned with laws |
| bde5584 | docs: DoD truth pass — status rows, execute targetPack CLI entry, glossary |
| 9562548 | test(two-port): behavioral stale_graph_identity witness + ash 26.9.31 relock |
| 04c5fcf | docs(v26.10.2): DoD ledger — standing matrix, publishes, C-lane verdicts |
| 67961c7 | refactor(refusals): all emitters emit the canonical REFUSED:<CODE> form; legacy parse shapes removed |
| 8e577a5 | refactor(receipt): remove to_prd_status/1 — superseded by the fleet-R v2 projection |
| 8ef0fea | feat(semantic-jira-pack): TargetPack rendered from pack facts — HANDWRITTEN row 48 retires |
| 3c22220 | feat(two-port-pack): HILT binding DEFAULT ON — utp:hilt false is the compat escape |
| b83d604 | chore(config): strict-profile STOP witnesses — the durable block is ready, the profile is not |
| 3a154ae | chore(semantic-jira): legacy digest window SHRUNK — removal milestone v26.11.1 |
| c49c53f | test(prov): assert the report names the pack shapes checked (shapes_checked) |
| a404697 | refactor: credo zero — 15 behavior-preserving fixes + 7 law-commented exemptions |

Full subjects on disk at the cited SHAs (`git log --format=%s` per SHA).
Cross-repo detail: xaas 7dc90027 is the F1 hex-floor output; 2517f626 is the live
SemanticJiraBridge seam; 4b848624 is the plan-next admit/2 seam; 117e4b64 closes
the subprocess-crown loop (provider-claim fix), 93784aed shrinks the legacy
digest window, de15fd14 makes the xaas ci job admittable (pinned sibling
checkouts). ash_a2a debdc1a and
75c386e carry the 26.9.31 prep chain; d58f99f is the fleet-R-v2 projection, 6abdb9f
the two-port graph-digest HILT work; above f36e3e6 the 26.10.2 ERRC wave —
c8ee4c9 (ARD/PRD), 4297fb0 + e0fd26b (docs-courts ERRC + v26.10.2 docs
release), 1d7dc2e (wasmtime 49.0.2, RUSTSEC-2026-0327), 619bbb3 (three vacuous
courts killed), 7c13f1e (RD1 allowlist shrink, 36 execution oracles), eb7608d
(cycle-2 receipt), 0bdc6b7 (Memory stores → real EKV), ccdb634 (5-tier Chicago
case study + pre-DO anchor receipts). ash_pplan b80ce69/f91fafe carry the 26.10.2
version identity; 1ebc817 the standing bridge + FOND closure; 2cad4cc/5baba1f
the standing-pack harness fix under tag `v26.10.2`. ggen-marketplace 6b43b654
is the lifecycle trio (render-verified generalizations, IRI-diverged, review
intent); ash_affidavit 3d024ea is the 26.10.1 release push; ash_graphlaw
2ed5eea adds parity check-id R2 + the wasm/ABI lineage map (E6); ash_r2rml
c5ccb25 is the R2RML loop map (E5).

## Command ledger (real commands, real exits)

| command | exit | outcome |
|---|---|---|
| bridge suite vs hex-published dep | 0 | **101/0 — decisive promote falsifier: ALIVE vs hex** |
| bridge suite (loop qualification, local subject) | 0 | 101/0 — loop ALIVE at qualification scale |
| `mix ggen_igniter.epoch.watermark` (re-stamp) | 0 | watermark re-stamped for epoch v26.10.2 |
| `admit_candidates` (targetPack) | 1 | `REFUSED:TARGET_PACK_MISMATCH` (reg 132) |
| `Bootstrap.Receipts.check/1 (in-repo executable form of the vendored fleet-R v2 law; no mix task)` | 0 | fleet-R v2 law + extension namespace enforced |
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
| two-port HILT (`utp:hilt`) | ALIVE | binding DEFAULT ON (3c22220; `utp:hilt false` = compat escape); behavioral witness vs published ash_a2a 26.9.31 (c021243, 9562548); opt-in origin 60e18bf |
| ash_a2a mutation court | PARTIAL_ALIVE | `--require-killed` in CI; 26.9.31 **on hex** (F3 done) |
| crown `:snapshot` binding | ALIVE (ggen + xaas) | hole closed; xaas subprocess crown completes the full loop (117e4b64 provider-claim fix) |
| v26.10.2 release (ggen_igniter) | ALIVE | on hex AND tagged `v26.10.2` @ ee10e7b (F2 done) |
| ash_pplan 2-pack | PARTIAL_ALIVE | symlink law in `PackLock` (B1); tag `v26.10.2` @ 2cad4cc landed (C9); hex publish state unchanged |

## Falsifiers run

| falsifier | result |
|---|---|
| bridge suite 101/0 against the **hex** dependency | passed — promote hop standing holds |
| bridge suite 101/0 on the loop subject (local) | passed — loop standing holds |
| targetPack mismatch admission | refused as designed — gate non-vacuous |
| receipts check vs fleet-R v2 + namespace | enforced — malformed receipts fail |
| vendored-schema conformance court | enforced — digest pin + schema shape (134b35c) |
| VerifyMutation catalog over the verify surface | mutants enumerated + killed (513c6e7) |
| behavioral stale_graph_identity vs published ash_a2a 26.9.31 | passed (c021243, 9562548) — two-port HILT default-on holds against the hex subject |
| mock-discipline gates (guard + MockScan) | executable, wired at gate/CI level |
| `chicago.mutate --require-killed` | surviving mutants fail the build |

## Residues (standing, not failures)

- **Legacy digest window** — a window, not a removal: removal milestone
  v26.11.1 (3a154ae ggen_igniter; xaas 93784aed runtime probe). Blockers: the
  three committed xaas ledgers that verify only under the legacy rule
  (HANDWRITTEN row 46 D1 census).
- **Strict profile remains STOP** — the durable block is ready; the profile
  flip is not (b83d604).
- **HANDWRITTEN rows 47/49 open** — kernel `optional_target_pack/1` clause and
  reactor pack-stamp clause; row 48 retired at 8ef0fea.
- **machine_experience 3 failures** — only with `GGEN_IGNITER_DIR` set; under
  reconciliation. Owner: F6.
- **ToolchainPin red off-pin** — by design; D8 moves the pin to
  `elixir 1.19.5-otp-27` / `erlang 27.2.4` (edit on disk, uncommitted at
  a404697); qualification in flight.
- **El3 scratch cleanup** — ~110 GB awaiting operator `rm` confirmation. Owner:
  operator.
- **RESOLVED this wave: xaas subprocess crown `:no_ready_work`** — completed
  the full loop after the provider-claim fix (117e4b64); formerly lane A8/F4's
  root-cause pass.

## Parked items (8 → 7)

1. ~~**xaas crown `:no_ready_work` repair**~~ — CLOSED: subprocess crown
   completes the full loop (117e4b64 provider-claim fix).
2. **machine_experience `GGEN_IGNITER_DIR`** — reproduces only under env set;
   reconciliation in progress (F6).
3. **ToolchainPin off-pin red** — D8 pin move to 1.19.5-otp-27 on disk;
   qualification in flight (D8).
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
ee10e7b), extended through a404697 by the final-state pass; the xaas merge is
5fc56da2 (feat head de15fd14), ash_a2a ccdb634, ash_pplan 2cad4cc
(tag `v26.10.2`).

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
| C9 | pplan tag/publish verdict (joint with B1) | DONE | tag `v26.10.2` @ 2cad4cc (verified `git rev-parse v26.10.2`); standing-pack harness fix 2cad4cc + 5baba1f; hex publish state unchanged |
| C10 | DoD ledger: version sweep, SHA refresh, matrix | DONE | this section + tables above |
| C11 | credo zero (ggen_igniter) | DONE | a404697 — 15 behavior-preserving fixes + 7 law-commented exemptions |
