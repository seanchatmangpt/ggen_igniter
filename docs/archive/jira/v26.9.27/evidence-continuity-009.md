<!-- manufactured by ggen_igniter --pack calver-ticket-day (public ns: oslc_cm + dcterms + prov + earl + aps)
     stage chain: 守→柲→算→除→偽→延→実  (APS OperatorGlyph — https://w3id.org/chatman/aps#) -->

# evidence-continuity-009: Evidence continuity across the boundary: receipts, OCEL, manifests
status: OPEN
created: v26.9.27

## Mission

Epoch check attributes files from .ggen_igniter/manifest.json and receipts/*.jsonl — verify what is tracked vs gitignored, what survives the epoch replacement, and record the out-of-subject receipts gap (exact-head ALIVE needs receipts outside the tree they certify). Product: evidence-continuity.md with tracked/ignored classification and the boundary procedure for evidence.

## Acceptance

evidence-continuity.md states for each evidence class (manifest, receipts, OCEL, qualification) whether it is git-tracked, where it lives at the boundary, and how v26.10.1 manufacture receipts will attribute fresh files

## History
- 2026-09-27T14:5xZ | ALIVE | feat/v26.9.27-epoch-prep | evidence classes classified tracked/ignored with boundary procedure; out-of-subject receipts gap (C21) recorded as open edge | evidence-continuity.md written
