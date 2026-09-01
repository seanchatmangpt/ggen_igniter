# ggen/ggen_igniter Sync-Receipt Parity Note

Field-for-field comparison of the real Rust ggen sync pipeline's IR/receipt structs
(`~/ggen/crates/ggen-engine/src/sync.rs`'s `PendingWrite`/`SyncReport`/`SyncReceipt`/
`ReceiptPayload`, and `~/ggen/crates/praxis-core/src/receipt_record.rs`'s
`ReceiptRecord` chain) against ggen_igniter's own `lib/ggen_igniter/pending_actuation.ex`
and `lib/ggen_igniter/receipt.ex`. Full field table: `.ggen_igniter_factory/ggen-parity.json`.

## Headline findings

- **PendingWrite -> PendingActuation**: good parity. igniter's struct is deliberately
  richer (identity/hash/ownership/compensation fields ggen splits across
  `PendingWrite` + `write.rs`'s `plan_write` + its own undo needs) — a real, documented
  design choice, not a gap.
- **`graph_hash` naming overclaim**: ggen's `graph_hash_hex` hashes the post-Enrich
  canonical graph state (after construct-query enrichment); igniter's
  `metadata["graph_hash"]` (`reconcile_reactor.ex` ~line 1439) is a plain sha256 of the
  raw ontology file bytes — there is no enrichment stage to hash the output of yet.
  Recommend renaming to `ontology_file_hash` to stop implying parity that doesn't exist.
- **Missing `skipped`/`decisions` maps**: ggen's `SyncReport` names every skipped path
  and every output's write decision; igniter computes the same information per-result
  (`outcome` atoms) but never aggregates it into the receipt. Low-risk aggregation fix.
- **Per-file hash dropped**: ggen's `ReceiptPayload.outputs` is `path -> hash`; igniter's
  `Receipt.files` is a bare path list even though the hash is already computed locally
  in `finalize_evidence/1`.
- **No cryptographic chain hash**: ggen's `ReceiptRecord` chains
  `payload_hash_hex`/`prev_chain_hash_hex`/`chain_hash_hex` over the receipt record
  itself. igniter's `reconstruct_standing/2` only checks file-content continuity
  (`pre_run_hash == prior post_run_hash`) — a hand-edited receipt line with unchanged
  file hashes but an altered `standing`/`reason` would pass undetected today. This is
  the single most consequential real gap found; not a one-line fix, recorded as a
  recommendation only per this task's scope.
- No equivalent to ggen's `packs` (per-pack content hash) or `closure` (full governing-
  input hash map) exists in igniter today — both are real, valuable, but not low-risk
  one-liners.

See `.ggen_igniter_factory/ggen-parity.json` for the complete field-by-field table
(yes/no/partial per field) and the full recommendation list.
