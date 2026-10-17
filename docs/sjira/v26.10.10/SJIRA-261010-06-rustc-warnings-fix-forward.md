# SJIRA-261010-06 — rustc warnings "allow" flip follow-through (inventory + fix-forward)

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P2
- **Status** (2026-10-09 refresh): DONE — workspace at 0 rustc warnings; root
  `Cargo.toml` flipped to `warnings = "warn"`; 1 unused-import fix landed;
  ggen-config verified 174/0. Residual per-crate clippy shrink of the blanket
  allow blocks (the clippy half of this order) remains open if still wanted.
- **Blocked-by**: none

## Task

DoD #17 is PARTIAL: the flip to `warnings = "allow"` was purchased with blanket
workspace-lint allows (root `Cargo.toml:305+`) and praxis-graphlaw's 22-lint
allow block. Inventory every crate currently covered by a blanket allow and
fix-forward to per-crate lints so the allow blocks shrink to genuinely-needed
entries.

1. Inventory: for each workspace crate, try `[lints] workspace = true` + targeted denies; record which warnings fire.
2. Fix-forward warnings per crate (starting with non-vendored crates; vendored crates praxis-graphlaw/praxis-core/bcinr-* last, smallest-diff fixes only).
3. Ensure bcinr-mfw-ir and any remaining vendored crate carry `[lints] workspace = true` (bcinr-pddl done in DoD #11).

## Acceptance

- `cargo clippy --workspace --all-targets` 0 warnings with the root allow list reduced vs the `Cargo.toml:305+` baseline; diff of the allow block included in the receipt.
- Each non-vendored crate compiles clean with `warnings = "warn"` locally (per-crate `RUSTFLAGS="-D warnings" cargo check -p <crate>` exit 0) or has an explicit documented exception.

## Constraints

- Vendored crates: minimal diff, do not restructure.
- No new blanket allows; fix forward only.
