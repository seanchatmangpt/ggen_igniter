# SJIRA-261010-03 — generation_rules.rs:528 build_tera → build_tera_with_packs

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P1
- **Status** (2026-10-09 refresh): rewiring at `generation_rules.rs:528` is IN
  FLIGHT on a lane. Note: the grep-count exception ledger is back to exactly 9
  documented exceptions — any new bare `build_tera` found during this order
  must either be fixed or added to the ledger with justification.
- **Blocked-by**: none

## Task

The last unwired template site: `crates/ggen-engine/src/generation_rules.rs:528`
still calls `build_tera` instead of `build_tera_with_packs`. DoD #18 covered
`sync.rs` packs wiring; this site was left. Rewire it so rules-rendered templates
get the same pack-function environment as the sync path.

## Acceptance

- `grep -n "build_tera" crates/ggen-engine/src/generation_rules.rs` → only `build_tera_with_packs` (0 bare call sites).
- A test rendering a rules template that uses a pack-provided function succeeds (real pack fixture, `[rules]` + `[pack_sources]` schema sections).
- `cargo test -p ggen-engine` green; byte-identical output for templates that use no pack functions.

## Constraints

- No worktrees; lane owns `generation_rules.rs` + its tests.
- Chicago TDD: assert on rendered output state, not call counts.
