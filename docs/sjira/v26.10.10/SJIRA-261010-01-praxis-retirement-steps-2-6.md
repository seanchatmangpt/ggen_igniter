# SJIRA-261010-01 — praxis-core retirement steps 2-6 (receipt-chain port + rewiring)

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P0
- **Status** (2026-10-09 refresh #2): differential court COMPLETE — praxis vs
  graphlaw fully identical (golden + 24 generated cases + tamper classes +
  rolling chains). Validator+store port COMPLETE 405/0; graphlaw workspace
  re-verified 432/0 clean (change receipt:
  `docs/receipt-2026-10-09-*.md`, recommended 2-commit split). Seam rewire
  (step 6) IN FLIGHT. Cutover dry-run WRITTEN — see
  SJIRA-261010-15 (101 refs / 23 files; only real Cargo dep is ggen-engine).
  (2026-10-09 refresh #8, post-callsite-migration ~90%): re-measured **34 refs
  in 14 files**; residue is comment-only in ggen-mcp/ggen-lsp/
  ggen-cheat-scanner. praxis-core's only consumer is now the receipt_chain_seam
  itself — the ggen-config exception is refuted (SJIRA-21). Callsite coverage
  gaps (MigrationReceipt, ReceiptRecordV1Legacy, MIGRATION_LAW_1_TO_2) →
  SJIRA-261010-23 (blocks SJIRA-22 G7); ObligationCount already ported, seam
  re-export approved.
  Earlier: step 1 (`graphlaw::receipt_chain`) is COMPLETE —
  byte-exact golden proof, 428/0. Step 1 blocker cleared. Steps 4-5 (validator +
  JSONL store port) and step 6 (ggen-engine seam rewiring) are IN FLIGHT on
  separate lanes. Remaining: finish steps 2-3 chain-rule ports behind the
  golden gate, then retirement + `publish = true`. New fact: a receipt
  differential court (praxis vs graphlaw over 20+ generated chains) is in
  flight and must pass before praxis-core deletion. (2026-10-09, lane
  sjira-replay-gap): validator + JSONL store port COMPLETE; the praxis
  `token_replay` stage is intentionally absent from the graphlaw port and is
  tracked as SJIRA-261010-14 (P3 — zero ggen-engine consumers, grep evidence
  in that file). (2026-10-09, SJIRA-261010-21): the claimed ggen-config
  exception is REFUTED — `receipt_impl.rs` uses zero praxis_core symbols
  (ed25519_dalek/sha2/chrono/serde only; no praxis dep in its Cargo.toml;
  ggen-config praxis mentions are prose). Consequence: once the in-flight
  callsite migration lands, `receipt_chain_seam` is praxis-core's ONLY
  consumer — steps 5-6 shrink (no ggen-config work item; the cutover
  checklist's "ggen-config [law] types prose" item is comment-only).
- **Blocked-by**: none (step 1 landed)
- **Lane**: single lane; no worktrees, no clones — one canonical checkout

## Task

Execute steps 2-6 of `docs/v26_10_10_praxis_retirement_plan.md` (source of truth for
the design; do not re-derive):

1. **Step 2 — `graphlaw::receipt_chain` (L, critical path)**: port `ReceiptRecord`
   (all 17 fields, `RECEIPT_RECORD_VERSION = 1`), BLAKE3 chain via
   `build_admission_frame` / `chain_from_frame`. The 99-byte `OcelCausalFrame`
   hash bytes (crate `bcinr-powl-receipt`) must be reproduced byte-exactly.
2. **Step 3 — ChainRule / ChainStanding / ChainMonotonicity port (M)**. Wire
   discriminators `"praxis-chain/base"` and `"praxis-chain/v2-fold"` are FROZEN
   strings (appear in stored JSON) — must not change.
3. **Step 4 — `graphlaw::receipt_epoch` (L)**: `SCHEMA_V1`/`SCHEMA_V2`
   (`"ggen-receipt/v1"`/`"v2"`), `CeilingLevel` ordering
   `Red < LegacyObserved < Yellow < Green`, `EquivalenceMap` (8 fields,
   `deny_unknown_fields`), `AdmissionLedger` family.
   4b. **Step 4b — migration-boundary types port (S, gates the cut)**: port
   `MigrationReceipt` (8 fields), `ReceiptRecordV1Legacy` (14 fields),
   `MIGRATION_LAW_1_TO_2 = "M_1_to_2"` (frozen wire string) from praxis
   `receipt_epoch.rs` into graphlaw `receipt_chain.rs` epoch module, byte-exact;
   extend epoch tests + differential v1-legacy hash court. Full spec:
   `SJIRA-261010-23-graphlaw-migration-types-port.md` (BLOCKS SJIRA-22 G7).
4. **Step 5 — Validator + JSONL store port (M)**. Keep the JSONL ledger; graphlaw's
   content-addressed `receipt_store` is an optional non-blocking bridge — do not
   cutover.
5. **Step 6 — praxis-core retirement + ggen-engine rewiring (M)**: rewire
   `sync.rs` / `handlers.rs` (66 residual praxis refs across 14 files, all in
   ggen-engine) onto the graphlaw modules; delete praxis-core; flip ggen-engine
   `publish = true` (DoD #22).

Compatibility gate: golden tests **FM-CHAIN-009** (`receipt_record.rs:1076`, head
hashes `d04c6d08…` / `bebae299…`) and **FM-CHAIN-014** must pass as graphlaw
integration tests BEFORE any retirement. Dual-read, never hard cutover.

## Acceptance

- `cargo test -p praxis-graphlaw --test receipt_chain_golden` (or equivalent): FM-CHAIN-009 + FM-CHAIN-014 pass, byte-identical hashes.
- `grep -rn "praxis_core\|praxis-core" crates/ggen-engine/src | wc -l` → 0.
- `grep -n "publish" crates/ggen-engine/Cargo.toml` → `publish = true`.
- `cargo check --workspace` exit 0; `cargo test -p ggen-engine --test receipt_chain_e2e` green (was 25/0 pre-port).

## Constraints

- Chicago TDD; real JSONL ledger on disk in tests (`TempDir` OK).
- No edits to frozen wire discriminators.
- No `git reset --hard`; fix forward.
