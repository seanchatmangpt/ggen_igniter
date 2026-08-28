# ADR-007: Compensation Restores State While Preserving Evidence

## Status
Accepted (`IMPLEMENTED`)

## Context
When generated code fails build verification (`mix compile`), restoring previous files is essential. However, erasing the fact that an attempt occurred destroys vital debugging and audit information.

## Decision
1. When verification fails, trigger Reactor `undo/3` to restore pre-run file bytes.
2. Emit OCEL events (`ACTUATION_STARTED`, `FILES_CHANGED`, `COMPENSATION_STARTED`, `FILES_RESTORED`).
3. Always append a durable receipt (`.ggen_igniter/receipts/YYYY-MM-DD.jsonl`) with standing `:compensated` or `:build_broken` containing `pre_run_hash` and `post_run_hash`.

## Rationale
A failed actuation is a consequential physical event. Preserving the cryptographic hash and failure reason provides complete operational transparency.

## Consequences
- **Positive:** Disk state is restored to pre-run integrity ($\text{pre\_hash} == \text{post\_hash}$) while the historical audit trail is preserved.
- **Trade-off:** Receipt log grows monotonically over time.
