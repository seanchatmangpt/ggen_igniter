# GGEN-2601: `EphemeralProjection.verify/2` does not bind attested bytes to the receipt's `post_run_hash`

- **Status**: Closed — implemented + Chicago-validated (2026-09-15)
- **Severity**: High
- **Standing**: ALIVE for this fix (ephemeral suites 11/11; full suite 935 tests green with resolved TMPDIR, `fix/v26.9.15-ephemeral-attestation` @ 9cb4a92, worktree `wt-v26915/ggen_igniter`)
- **Closure evidence**: `EphemeralManufacture.attest_receipt/2` reads each receipted file from disk exactly ONCE, proves `H(current receipted file-set) == receipt.post_run_hash` via the same `Receipt.hash_entries/1` primitive that built the hash, and manufactures every projection from those same in-memory bytes (no second read between verification and attestation — the TOCTOU window is closed, not narrowed). Missing `post_run_hash` is refused up front; a mismatch is a typed refusal naming both digests. Chicago falsifiers (single-file tamper, multi-file tamper, missing hash) all pass.
- **Found by**: 14-hour cross-repo code review, window 2026-09-14 9:40 PM → 2026-09-15 11:40 AM PDT (inspection, not execution)

## Evidence

`EphemeralManufacture.attest_receipt/2` (`lib/ggen_igniter/ephemeral_manufacture.ex:61-62`) takes an already-created `:alive` receipt, iterates `receipt.files`, and calls `File.read(path)` **after** reconciliation has completed, then hashes those current bytes.

The receipt itself contains a `post_run_hash` over the exact touched-file set (`lib/ggen_igniter/receipt.ex`), so the necessary evidence exists.

But `EphemeralProjection.verify/2` (`lib/ggen_igniter/ephemeral_projection.ex:121`) does not compare the newly calculated artifact digest against that receipt-bound state. It only checks whether `receipt_hash` is syntactically a valid `sha256:<64 hex>` value and then changes status from `:manufactured` to `:verified`.

So:

```
receipt t0 → mutate output t1 → attest_receipt t2
```

can produce:

```
artifact_digest(bytes@t1) + verification_receipt_hash(receipt@t0) + status = :verified
```

That is a genuine provenance misbinding / TOCTOU problem.

## Impact

A verification receipt computed over post-receipt-modified bytes can be presented as binding the receipted state. Any SLSA/provenance claim downstream of `:verified` inherits the misbinding. Ranked #2 in the cross-repo closure order.

## Fix

The minimal closure is **not** more prose or another provenance field. Reconstruct/verify the receipt's committed output identity before emitting SLSA — prove:

$$H(\text{current receipted file-set}) = receipt.post\_run\_hash$$

before any projection receives `:verified`.

## Falsifier (acceptance)

Get a real `:alive` receipt, mutate one receipted output before `attest_receipt/2`, then attest. It must return REFUSED. The current implementation appears capable of returning a verified projection.
