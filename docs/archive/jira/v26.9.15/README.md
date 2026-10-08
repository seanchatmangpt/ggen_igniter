# v26.9.15 — ggen_igniter: bind ephemeral artifact identity to the receipted post-state

- **Date**: 2026-09-15
- **Source**: 14-hour cross-repo code review, window Sep 14 9:40 PM PDT → Sep 15 11:40 AM PDT.
- **Method**: inspection of commits, PR heads, and exact source files. No code executed, nothing changed by the reviewer.

## Result

**Closure (2026-09-15)**: GGEN-2601 implemented and Chicago-validated on `fix/v26.9.15-ephemeral-attestation` (worktree `wt-v26915/ggen_igniter`); ephemeral suites 11/11, full suite green with resolved TMPDIR. See the ticket file for evidence.

The new ephemeral-manufacturing path has the desired architecture:

`graph → reconciliation → ALIVE receipt → ephemeral artifact → provenance → retirement intent`

and retirement remains intent-only rather than acquiring DO authority — that part is correct.

But receipt identity does not actually bind the ephemeral artifact. `EphemeralManufacture.attest_receipt/2` reads and hashes the receipted files **after** reconciliation has completed, and `EphemeralProjection.verify/2` only checks that `receipt_hash` is syntactically a valid `sha256:<64 hex>` before flipping status to `:verified` — it never compares the freshly computed artifact digest against the receipt-bound `post_run_hash`. That is a provenance misbinding / TOCTOU defect. Standing: **BLOCKED for the verified-provenance claim**.

## Tickets

| ID                                                                            | Title                                                                                        | Severity | Closure order |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | -------- | ------------- |
| [GGEN-2601](./GGEN-2601-ephemeral-attestation-hash-binding.md)                | `EphemeralProjection.verify/2` does not bind attested bytes to the receipt's `post_run_hash` | High     | #2            |
