# SJIRA-261010-15 — praxis-core cutover dry-run (executable work order)

Date: 2026-10-09 · Lane: cutover-dryrun · Repo: /Users/sac/ggen (canonical checkout, read-only lane)

**Status (2026-10-09 refresh #3): WRITTEN — 7-step checklist complete.**
(2026-10-09 refresh #8): re-measured post-callsite-migration — **34 refs in
14 files**, comment-only residue in ggen-mcp/ggen-lsp/ggen-cheat-scanner;
praxis-core's only remaining consumer is the receipt_chain_seam (SJIRA-21
refuted the ggen-config exception). Migration-type coverage gaps →
SJIRA-261010-23, which blocks SJIRA-22's praxis-cutover gate.
Publish-blocker inventory tracked in SJIRA-261010-16 (in flight); FM-PACK-018
adjudication in flight. Seam rewire remains the GO-gate critical path.
Surprises surfaced: `examples/praxis-core-verify` default-features hard-links
`praxis-core` — must be removed before the workspace ladder; the differential
test's praxis oracle imports are deletable only in the cutover commit;
`ggen-mcp:222` has a user-visible string mentioning praxis. Measured: 101 refs
in 23 files; only real Cargo dep is ggen-engine.
(2026-10-09, SJIRA-261010-21): the ggen-config exception is REFUTED —
`receipt_impl.rs` contains zero praxis_core symbols; no praxis dep in its
Cargo.toml. The ggen-config row below is comment-only at most (and currently
zero matches); steps 5-6 need no ggen-config work item.

## 0. Measured inventory (as of this dry-run; seam flip in flight, owned by rewire lane)

`grep -rn "praxis_core|praxis-core" /Users/sac/ggen/crates --include='*.rs' | grep -v crates/praxis`:
**101 refs in 23 files**, partitioned:

| Class | Files | Action |
|---|---|---|
| Engine seam + call sites | `receipt_chain_seam.rs`, `sync.rs`, `verbs/handlers.rs` | rewire lane owns; dry-run assumes flipped |
| Engine tests (11) | `receipt_chain_differential_test.rs` (uses `praxis_core` as ORACLE — keep until go gate passes, then delete oracle half), `receipt_chain_e2e.rs`, `receipt_chain_seam_test.rs`, `receipt_chain_own_history_replay.rs`, `composed_packs_e2e.rs`, `constitution_obligation_e2e.rs`, `cross_pack_matrix.rs`, `framework_packs_e2e.rs`, `frontmatter_fields_e2e.rs`, `migration_receipt_persist.rs`, `receipt_epoch_e2e.rs`, `receipt_genesis_ceiling_e2e.rs`, `sync_e2e.rs`, `verify_pack_gate_sabotage_e2e.rs` | retarget imports to `receipt_chain_seam`; differential test deletes `use praxis_core::*` only after go gate |
| ggen-mcp | `src/lib.rs:222` (string literal in tool description), `src/tools/receipt_verify.rs:2` (doc comment), `tests/receipt_verify_test.rs:98` (comment) | 1-line description/comment edits; no code dep (ggen-mcp has no praxis Cargo dep) |
| ggen-config | REFUTED as a consumer (SJIRA-261010-21): `src/receipt/receipt_impl.rs` has zero praxis_core symbols; only `src/manifest/types.rs` mentions `praxis-graphlaw` in prose | no work item; nothing to sweep |
| ggen-cheat-scanner | `src/lib.rs:183` (comment) | edit or leave (comment-only); no code dep |
| ggen-lsp | `src/a2a_mcp/a2a/ggen_construct.rs:287` (comment) + `Cargo.toml:11,25` comments | edit comments; no code dep |

Cargo manifests referencing praxis (non-.rs):
- `crates/ggen-engine/Cargo.toml:98-99` — the only real path deps on `praxis-core`/`praxis-graphlaw`
- root `Cargo.toml:90-91` — workspace members; `:680` — publish-safety comment; `:69,71` — vendoring-history comments
- `examples/praxis-core-verify/` — standalone example crate, `praxis-core = { path = "../../crates/praxis-core", optional = true }` under default feature `praxis-core-live`

## 1. Ordered cutover checklist (each step: command → acceptance)

**GO GATE (step 1a) is the only gate: the differential court must be green on the graphlaw-backed seam before any deletion.**

### 1a. GO GATE — seam flipped, courts green
```
cargo test -p ggen-engine --test receipt_chain_e2e          # expect 25 passed, 0 failed
cargo test -p ggen-engine --test receipt_chain_differential_test  # expect 5 passed, 0 failed
cargo test -p ggen-engine --test receipt_chain_seam_test    # expect 4 passed, 0 failed
grep -n "graphlaw" crates/ggen-engine/src/receipt_chain_seam.rs | head -1  # confirm flip landed
```
Accept: all three counts exact, 0 failures. **Any failure → NO-GO; halt before step 1b.**

### 1b. Remove Cargo deps
Edit `crates/ggen-engine/Cargo.toml` (delete lines 98-99), root `Cargo.toml` members (lines 90-91),
and `workspace.dependencies` entry if present (grep first: `grep -n "praxis" Cargo.toml`).
```
cargo metadata --format-version 1 >/dev/null   # manifest parses
cargo tree -p ggen-engine -i praxis-core       # expect: nothing depends on praxis-core
```

### 1c. Delete vendored crates
```
git rm -r crates/praxis-core crates/praxis-graphlaw
```
Accept: clean `cargo metadata`; both dirs gone from `git ls-files`. Git-tracked → recoverable.

### 1d. Flip ggen-engine publish=true
Edit `crates/ggen-engine/Cargo.toml` `publish = false` → `publish = true`.
```
cargo publish --dry-run -p ggen-engine
```
Accept: success OR a NAMED remaining blocker (record verbatim in receipt — e.g. another path dep).
Unnamed/ambiguous failure → NO-GO on this step, block on named cause.

### 1e. Root Cargo.toml:680 comment + examples/praxis-core-verify
Update root `Cargo.toml:680` publish-safety comment (reason for `publish=false` on ggen is gone for
ggen-engine). Delete `examples/praxis-core-verify/` (its whole reason to exist is the real
praxis-core link; graphlaw replacement supersedes) — or, if retained, feature-off by flipping
`default = []`. **Decision: delete** (0 consumers of its bin outside verification docs).
```
grep -rn "praxis-core-verify" --include='*.rs' --include='*.toml' . | grep -v examples/praxis-core-verify
```
Accept: zero external references to the example.

### 1f. Full workspace test ladder
```
just pre-commit        # primary gate per repo rules
just check && just test
```
Accept: `just pre-commit` green; `just test` 0 failures. Andon: any CRITICAL stops the line.

### 1g. Doc/comment residue sweep (post-deletion, non-blocking for compile)
Edit the 6 comment/string-literal sites in the inventory table (ggen-mcp lib.rs:222 string,
receipt_verify.rs:2, receipt_verify_test.rs:98,
ggen-cheat-scanner lib.rs:183, ggen-lsp ggen_construct.rs:287 + its Cargo.toml comments,
root Cargo.toml:69,71). Change wording from "via praxis-core" to "via graphlaw::receipt_chain".
```
grep -rn "praxis_core\|praxis-core" crates examples --include='*.rs' --include='*.toml' | wc -l
```
Accept: count monotonically → 0 (or only intentional history mentions in docs/sjira).

## 2. Risk register

| Risk | Mitigation / coverage |
|---|---|
| Receipt bytes at rest diverge post-cutover (`.ggen-v2/receipt.json`, receipt-log) | Covered by the differential court (golden + 24 cases, every hash/verdict/error-class identical). Residual: at-rest files written pre-flip replayed post-flip — receipt_chain_e2e's own-history-replay test covers this; keep it green in 1f. |
| ggen-config `[law]` types doc-comments name `praxis_core::ReceiptRecord` | REFUTED (SJIRA-261010-21): no such comment exists; ggen-config has zero praxis_core references. Behavior unaffected; no sweep item. |
| ggen-lsp analyzer comment claims praxis-core receipt chaining | Comment-only; sweep in 1g. |
| ggen-mcp tool-description string says "via praxis-core" | String literal; user-visible only. 1g. |
| Differential test's oracle disappears with the crates | Sequence matters: keep `praxis-core` importable until 1a go gate passes; delete oracle imports only in the same commit as 1c. |
| examples/praxis-core-verify breaks workspace build after 1c | Its dep is `optional` under a default feature that hard-links praxis-core — MUST be deleted or feature-off in 1e before 1f, else `cargo test --workspace` fails. |
| `cargo publish --dry-run` surfaces a second path dep | Named-blocker protocol in 1d; do not guess. |

## 3. Constraints
- One canonical checkout; no worktrees; no git state mutations by this lane (dry-run doc only).
- Differential court green = GO; anything else = NO-GO, halt before deletion.
- All commands via `just` where a recipe exists; never bare `cargo make`.
- Every step records command + exit in the eventual receipt (law 7).

## 4. Falsifier for this dry-run
A cutover executed per this order that leaves any step without its acceptance command passing
(e.g. publish flipped with `--dry-run` never run) invalidates the checklist; amend the order.
