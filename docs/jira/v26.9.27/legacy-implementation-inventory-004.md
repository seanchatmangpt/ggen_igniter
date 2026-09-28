<!-- manufactured by ggen_igniter --pack calver-ticket-day (public ns: oslc_cm + dcterms + prov + earl + aps)
     stage chain: 守→柲→算→除→偽→延→実  (APS OperatorGlyph — https://w3id.org/chatman/aps#) -->

# legacy-implementation-inventory-004: Inventory the pre-epoch implementation set and classify the planes
status: OPEN
created: v26.9.27

## Mission

Enumerate lib/**/*.ex at the boundary candidate tree; classify each file knowledge-plane vs implementation-plane per the epoch law (lib is implementation; config and migrations are named future courts); record counts and the exact per-file list as the day's inventory.md. This inventory is what epoch-005 extracts from and what v26.10.1 must replace.

## Acceptance

inventory.md lists every tracked lib/**/*.ex file with its classification and totals that sum to the enumerated count; count matches git ls-files output

## History
- 2026-09-27T14:5xZ | ALIVE | feat/v26.9.27-epoch-prep | 104 tracked lib/**/*.ex enumerated; counts cross-checked 3 ways (ls-files = stamp = rollup) | inventory.md written; untracked-at-stamp note recorded
