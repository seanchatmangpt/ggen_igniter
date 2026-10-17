# SJIRA-261010-25: G6 abb-sbb publish sequence (user-gated)

Date: 2026-10-10
Lane: sjira-refresh (docs)
Repo: /Users/sac/ggen (base c8846c7-equivalent)
Status: OPEN — publish-sequence order for the abb-sbb lane in flight.

## Context

G6 (version-align + publish dry-run) requires the abb-sbb crate to join the
publish chain.abb-sbb is currently consumed as a path dep by ggen-engine
(`Cargo.toml:97`) and must publish before (or with) the rest of the tree.
Dry-run receipts already landed showing only dirty-tree refusal; the real
sequence has not run.

## Work order

Execute the publish sequence in dependency order, with user gates:

1. **[USER GATE]** Confirm abb-sbb `Cargo.toml` final state (the workspace
   currently shows local modification to `crates/ggen-abb-sbb/Cargo.toml` —
   user must adjudicate before any publish).
2. Preflight (no gate): `cargo publish -p ggen-abb-sbb --dry-run` from a clean
   tree; must exit 0.
3. **[USER GATE]** Approval to run the real `cargo publish -p ggen-abb-sbb`.
4. Post-publish: `cargo update -p ggen-abb-sbb` registry resolution, then
   re-point ggen-engine's dep or confirm dual path/registry policy per
   SJIRA-19 version-skew ruling.
5. Then continue the existing G6 chain: workspace version grep →
   `cargo publish --dry-run` for each crate in dependency order, ggen-engine
   last (per A18).

## Acceptance criteria (falsifiable)

1. `cargo publish -p ggen-abb-sbb --dry-run` exit 0 on a clean tree at the
   exact HEAD recorded in the receipt.
2. Post-publish: `cargo search ggen-abb-sbb` (or registry check) shows the
   published 26.10.x version.
3. `cargo tree -p ggen-engine -i ggen-abb-sbb` resolves without path-only
   failure after the sequence.

## Constraints

- Every real `cargo publish` invocation is user-gated; agents may run dry-runs
  freely.
- No publish from a dirty tree (existing dry-run refusal is the guard).

## Priority

High — G6 blocker.
