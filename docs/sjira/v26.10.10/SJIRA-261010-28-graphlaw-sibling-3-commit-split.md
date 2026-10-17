# SJIRA-261010-28: graphlaw sibling repo 3-commit split — pending user gate

Date: 2026-10-10
Lane: sjira-refresh (docs)
Repo: /Users/sac/ggen (base c8846c7-equivalent); target sibling graphlaw repo
Status: OPEN — BLOCKED on user gate.

## Context

The praxis retirement plan (docs/v26_10_10_praxis_retirement_plan.md) and
repo-state report (§4.3) establish: the workspace has no `../graphlaw` path
dep today; the law engine is vendored `crates/praxis-graphlaw`. The retirement
path requires splitting the graphlaw foundation library into its own sibling
repo (3 commits prepared: extraction, API freeze at
`GraphEngine`/`Delta`/hook-receipt surface, and re-point scaffolding), after
which ggen-engine's three touchpoints swap over
(`law_engine.rs:61-63` `build_store`, `graph.rs:1157/1197/1324/1213-1214`,
`handlers.rs:256`).

The 3-commit split exists but landing it is an irreversible topology
transition — user-gated, not agent-gated.

## Work order (post-gate)

1. **[USER GATE]** Approve the 3-commit sequence and target repo location.
2. Land commits 1–3 in the sibling repo in order; verify each with the
   sibling's own test suite at the exact commit SHA.
3. Introduce the graphlaw dep into ggen (path first, registry per SJIRA-25
   publish policy), behind the existing `LawEngine` seam — seam already
   passes only N-Triples/N3 strings, no model types.
4. Swap the three touchpoints; keep `GraphEngine`/`Delta` API frozen.
5. Re-run G7 acceptance (SJIRA-23 port) and the retirement plan's verification
   ladder.

## Acceptance criteria (falsifiable)

1. `cargo tree -p ggen-engine -i praxis-graphlaw` → empty/error after swap.
2. `cargo test -p ggen-engine --test law_engine_bridge_e2e` and
   `--test reflexive_law_e2e` green against the sibling graphlaw dep.
3. Sibling repo: each of the 3 commits has its own green-suite receipt at its
   exact SHA.

## Constraints

- One canonical checkout per repo; no worktrees (topology guard).
- Nothing lands until the user gate; agents may prepare dry-run diffs only.
- oxrdf 0.3.4 quarantine must move with the split, not leak into the ggen
  workspace (version-conflict note, repo-state report §3.2).

## Priority

High — G7 and praxis retirement both route through this gate.

## Prep (2026-10-10)

Lane: graphlaw-split-prep. Read-only inventory of `/Users/sac/graphlaw`
working tree at HEAD `e1059f1` (branch `docs/doc-hdit-scaffold-gl`).
No writes, no staging.

### Dirty inventory (11 modified + 5 untracked)

Modified: `Cargo.toml` (+17: blake3/hex/serde deps, serde_json now required,
`abi = []` no-op feature), `Cargo.lock` (+3), `README.md` (+23: receipt-chain
+ refuse-hook sections), `src/lib.rs` (+2: `pub mod receipt_chain` +
re-exports), `src/hooks.rs` (+146/-29: Effect::Refuse), `wasm/src/lib.rs`
(fmt only), tests: `knowledge_hooks.rs` (+90), `op_differential.rs`,
`op_forward_compat.rs` (cfg `feature = "abi"` guards), `registry_limits.rs`
(fmt), `wasm_abi.rs` (+7 cfg guards).

Untracked: `src/receipt_chain.rs` (2083 lines), `tests/receipt_chain_golden_test.rs`,
`tests/receipt_chain_validator_test.rs`, `tests/receipt_epoch_migration_port_test.rs`,
`docs/receipt-2026-10-09-receipt-chain-and-refuse-hooks.md`.

Version check: `Cargo.toml` package `version = "26.10.5"` (line 3) is
**committed** — the dirty diff touches only dependency lines and features.

### Grouping (3 commits)

The planned 3-way split (receipt-chain / epoch port / refuse hooks) maps as:
epoch port is a submodule **inside** `src/receipt_chain.rs`, not separate
files, so commits 1 and 2 differ only by the epoch test file.

**Commit 1 — receipt-chain family + epoch port**
Files: `src/receipt_chain.rs`, `src/lib.rs`, `Cargo.toml`, `Cargo.lock`,
`tests/receipt_chain_golden_test.rs`, `tests/receipt_chain_validator_test.rs`,
`tests/receipt_epoch_migration_port_test.rs`, plus the serde_json-required
fallout: `tests/op_differential.rs`, `tests/op_forward_compat.rs`,
`tests/registry_limits.rs`, `tests/wasm_abi.rs`, `wasm/src/lib.rs`.
Message:
```
feat(receipt): port praxis-core receipt-chain family + migration epoch

Verbatim port of praxis-core's receipt-chain surface (ReceiptRecord v1,
frozen praxis-chain/* wire strings, byte-exact BLAKE3 frame/chain hashing,
4-stage ReceiptValidator, JSONL ReceiptStore) and the receipt_epoch
submodule (ReceiptRecordV1Legacy, MigrationReceipt, MIGRATION_LAW_1_TO_2).
crates.io bcinr-powl-receipt is infeasible on stable 1.96.0 (nightly-only
wasm4pm-compat), hence the port. serde_json becomes a required dep; abi
tests gain feature guards. Unblocks ggen praxis-core/praxis-graphlaw
retirement (SJIRA-15).

Gates: cargo test -p graphlaw (443 passed, 0 failed);
receipt_epoch_migration_port_test 4/4.
```

**Commit 2 — hooks refuse-effect**
Files: `src/hooks.rs`, `tests/knowledge_hooks.rs`, plus README/docs could go
either commit — recommend here.
Message:
```
feat(hooks): refuse-effect — kh:effect "refuse" emits no delta

New Effect enum (EmitDelta | Refuse), Verdict::Refuse(reason),
HookVerdict, Materialized::verdicts. Refuse is never an error at
materialize; the consumer decides. Backward-compatible: emit-delta packs
unchanged. Unblocks ggen-engine receipt_chain_seam refuse plumbing.
```

**Commit 3 — docs**
Files: `README.md`, `docs/receipt-2026-10-09-receipt-chain-and-refuse-hooks.md`.
Message: `docs: receipt-chain + refuse-hook reference sections, session receipt`.

### Verification gate (before every commit)

```
cd /Users/sac/graphlaw && cargo test -p graphlaw   # expect 443 passed, 0 failed
```

### Exact command sequence when the user lifts the gate

```
cd /Users/sac/graphlaw
git add Cargo.toml Cargo.lock src/lib.rs src/receipt_chain.rs \
  tests/receipt_chain_golden_test.rs tests/receipt_chain_validator_test.rs \
  tests/receipt_epoch_migration_port_test.rs tests/op_differential.rs \
  tests/op_forward_compat.rs tests/registry_limits.rs tests/wasm_abi.rs \
  wasm/src/lib.rs
cargo test -p graphlaw
git commit   # message 1 above

git add src/hooks.rs tests/knowledge_hooks.rs
cargo test -p graphlaw
git commit   # message 2 above

git add README.md docs/receipt-2026-10-09-receipt-chain-and-refuse-hooks.md
git commit   # message 3 above
```

### Notes / unexpected

- Repo docs themselves recommend a 2-commit split (receipt chain, hooks);
  this prep keeps 3 by carving docs out — epoch rides commit 1 since it
  lives in `receipt_chain.rs`.
- `tests/knowledge_hooks.rs` docstring says 11 tests; refuse tests are the
  +90-line addition — verify count at gate time.
- oxrdf quarantine note (§3.2 of repo-state report): no oxrdf version
  changes appear in the dirty diff — nothing leaks into the ggen workspace.
- README "Session changes uncommitted" section becomes stale after the
  split; consider dropping that subsection in commit 3.

## Re-baseline (2026-10-10, coordinator, post graphlaw-verify lane)

The 443/0 baseline was invocation-dependent. Measured at e1059f1+dirty:
- `cargo test -p graphlaw` → 145 passed / 0 failed / 1 ignored
- `cargo test -p graphlaw --all-features` → **412 passed / 0 failed** (use this as the split gate)
- `cargo test -p graphlaw --all-targets` → 118 passed / 0 failed

Zero failures under all three. API surface confirmed intact (all ggen-consumed symbols exported). Dirty set unchanged vs prep inventory. Update commit-gate commands to `cargo test -p graphlaw --all-features`.
