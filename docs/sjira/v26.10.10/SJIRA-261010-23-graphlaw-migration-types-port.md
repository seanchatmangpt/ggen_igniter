# SJIRA-261010-23 — port MigrationReceipt / ReceiptRecordV1Legacy / MIGRATION_LAW_1_TO_2 into graphlaw receipt_epoch

- **Repo/base**: `/Users/sac/graphlaw`, uncommitted session base (same session
  as SJIRA-01 steps 2-5; no worktrees, one canonical checkout)
- **Priority**: P1 — cutover prerequisite
- **Blocked-by graph**: SJIRA-261010-22's praxis-cutover release-cut gate is
  blocked-by THIS order. Cuts cannot present GREEN until the three migration
  types verify through graphlaw.
- **Status** (2026-10-09): WRITTEN — not started.

## Task

Port the three migration-boundary items from praxis-core
`receipt_epoch.rs` into `/Users/sac/graphlaw/src/receipt_chain.rs`
(`pub mod epoch`, ~line 885 region), byte-exact per the established port
discipline: same serde attrs, same field names, same ordering — wire-compatible.
Extend the existing epoch tests in place.

## Scope (enumerated from praxis originals, `git -C /Users/sac/ggen show HEAD:crates/praxis-core/src/receipt_epoch.rs`)

1. **`ReceiptRecordV1Legacy`** (praxis ~L758) — struct, 14 fields, `deny_unknown_fields`:
   `version: u32`, `instruction_id: u64`, `activity_idx: u16`,
   `activity: Option<String>` (`default`, `skip_serializing_if`), `node_kind: u8`,
   `ts_ns: u64`, `duration_ms: Option<u64>` (`default`, `skip_serializing_if`),
   `payload_hash_hex: String`, `prev_chain_hash_hex: String`,
   `chain_hash_hex: String`, `andon: Andon`, `obligation_count: u32`,
   `object_ids: Vec<String>` (`default`), `signature_hex: Option<String>`
   (`default`, `skip_serializing_if`). Models an old v1-only reader:
   deserializing a genuine v2 receipt JSON into it MUST fail (`schema`/`v2`
   keys unknown to it) — that behavior is the checkable half of "old code
   refuses new receipts" and must be asserted in tests.
2. **`MIGRATION_LAW_1_TO_2: &str = "M_1_to_2"`** (praxis ~L798) — frozen wire
   string; must not change.
3. **`MigrationReceipt`** (praxis ~L805) — struct, 8 fields, `deny_unknown_fields`:
   `migration_law`, `from_schema`, `to_schema`, `final_v1_chain_hash_hex`,
   `first_v2_chain_hash_hex`, `carries_forward: Vec<String>`,
   `becomes_unknown: Vec<String>`, `resulting_ceiling: CeilingLevel`. Plus
   `MigrationReceipt::new(final_v1, first_v2)` with no ceiling argument —
   `resulting_ceiling` is always `CeilingLevel::LegacyObserved`, and
   `carries_forward`/`becomes_unknown` carry their fixed literal vectors
   (`chain_hash_lineage`/`object_ids`/`instruction_id_sequence`;
   `admission`/`equivalence`/`obligation_count`).

Dependencies already present in graphlaw `epoch` module: `SCHEMA_V1`/`SCHEMA_V2`
(receipt_chain.rs ~640), `CeilingLevel` with `LegacyObserved` (~670), `Andon`
(~340). `ObligationCount` (the enum) is already ported (~885) — do not re-port.
The 1-line `receipt_chain_seam.rs` re-export addition is separately approved
(seam lane) and is NOT this order's diff.

## Acceptance criteria

1. Epoch tests extended: all three types round-trip (serialize → deserialize →
   assert equality) through graphlaw.
2. Negative path: v2 receipt JSON into `ReceiptRecordV1Legacy` fails
   (deny_unknown_fields) — the old-reader-refuses-new-receipts behavior holds.
3. `MigrationReceipt::new` invariants: fixed law/schema strings, fixed
   carries/becomes vectors, ceiling pinned to `LegacyObserved` — asserted, not
   commented.
4. **Differential court extension**: a v1-legacy record hashes (BLAKE3 chain
   hash) identically through praxis-core and graphlaw — byte-identical
   `chain_hash_hex` both sides.
5. `cargo test -p graphlaw` green (real test run, receipt cited in commit).

## Constraints

- Repo `/Users/sac/graphlaw` only; uncommitted session base — no git state
  commands (coordinator owns transitions/commits).
- Byte-exact port: same serde attrs, field names, field order, doc-comment
  intent; frozen strings (`"M_1_to_2"`, `"ggen-receipt/v1"`, `"ggen-receipt/v2"`)
  must not change.
- Chicago TDD: real serialization round-trips, no mocks/doubles.

## Falsifier

A v1-legacy receipt that verifies via praxis-core but fails via graphlaw
(hash mismatch, serde rejection, or ceiling/field drift) = port defective;
the order is not done until the differential court is identical.

## See Also

- `SJIRA-261010-01-praxis-retirement-steps-2-6.md` (parent port order)
- `SJIRA-261010-22-release-cut-checklist.md` (blocked consumer gate)
- `/Users/sac/ggen/crates/ggen-engine/src/receipt_chain_seam.rs` (epoch re-export list)
