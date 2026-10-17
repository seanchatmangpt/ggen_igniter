# SJIRA-261010-09 — documentation drift sweep at v26.10.10 close

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P2
- **Blocked-by**: SJIRA-261010-01 … 08 landing (sweep must run last, at close)

## Task

The audit report (`docs/v26_10_10_repo_state_and_library_usage_report.md`) and
phase-1 receipt (`docs/v26_10_10_phase1_receipt.md`) contain counts/statuses that
go stale as the work orders land (§7 delta already shows the pattern: "28 sites"
superseded, grep recount PENDING, engine tally PENDING). At loop close:

1. Re-derive every count in both docs from disk (praxis ref census, star-toml residual grep, DoD table statuses, lint-allow inventory) — same discipline as `source-of-truth-check`.
2. Correct or supersede stale claims in place; mark as-of-date anything left unverified.
3. Check the stale cosmetic item: `config_schema.rs` doc text "only 1 of 6 dispatches" (code already correct — open cosmetic item in phase-1 receipt).

## Acceptance

- Every numeric claim in both docs re-derived with a command recorded next to it; zero claims older than the close date without an as-of marker.
- `grep -n "1 of 6" crates/ggen-config/src/config_schema.rs` → 0 matches (doc text corrected).
- Parity/governance gates re-run green: `cargo test -p ggen-config system_crate_map_parity_test` 2/2, governance gate 4/4.

## Constraints

- Docs only; no code changes in this order beyond the one doc-comment fix.
- No worktrees; run after all other orders' receipts exist.
