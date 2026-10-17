# SJIRA-261010-14 — port `token_replay` validator stage (POWL lifecycle replay) into graphlaw

- **Repo/base**: `/Users/sac/graphlaw`, branch `docs/doc-hdit-scaffold-gl`
  (uncommitted session changes are the base context; no worktrees, no clones).
- **Priority**: **P3 — dead surface**. Evidence: `grep -rn "token_replay\|token-replay\|replay_adapter" /Users/sac/ggen/crates/ggen-engine/src/` → 0 matches (exit 1, 2026-10-09). No ggen-engine consumer, so this is not on the praxis-retirement critical path (SJIRA-261010-01 step 6 does not require it). Re-check the grep before starting; if a consumer appears, promote to P1.
- **Status**: OPEN
- **Related**: SJIRA-261010-01 (validator+store port, 4-stage), tracks the gap
  documented in `graphlaw/src/receipt_chain.rs:1584` ("The praxis `token_replay`
  stage is intentionally absent").

## Scope found (praxis reference, git history only — file deleted from disk)

- `git -C /Users/sac/ggen show HEAD:crates/praxis-core/src/replay_adapter.rs`:
  fixed 3-node SEQ POWL model (`judge -> admit -> receipt`) replayed via
  `bcinr_powl_receipt::replay::PowlReplayVerifier`. Token bits
  `TOK_START/JUDGED/ADMITTED/DONE` (bits 0-3), node-identity bits
  `NODE_BIT_JUDGE/ADMIT/RECEIPT` (bits 8-10). `replay_lifecycle` returns
  `ConformanceMetrics` (fitness `0x0001_0000` = 1.0, Q16.16) or
  `ReplayViolation::TokenNotEnabled { node_id }` on out-of-order steps.
  `replay_receipt_lifecycle(&ReceiptRecord)` replays the canonical lawful
  3-step order for a record. Depends on crate `bcinr-powl-receipt`.
- `git show HEAD:crates/praxis-core/src/receipt_validator.rs`,
  `check_token_replay` (line ~265): stage 5 of the validator; empty ledger →
  `Skip("no records to replay")`; per record, `replay_receipt_lifecycle` must
  yield fitness `0x0001_0000`, else `Fail("record {i}: fitness {:#010x} != 1.0 (0x00010000)")`
  or `Fail("record {i}: replay violation {e:?}")`; otherwise `Pass`.

## Task

Port the `token_replay` stage into `graphlaw::receipt_chain::validator`
(`/Users/sac/graphlaw/src/receipt_chain.rs`, `pub mod validator`), extending the
4-stage validator (`schema`, `chain_recompute`, `chain_linkage`, `monotonic`)
to 5 stages. Port or re-implement the POWL replay verifier (via `bcinr-powl-receipt`
dependency or an in-crate equivalent with identical semantics), plus the
`lifecycle_frame` / `replay_receipt_lifecycle` surface from `replay_adapter.rs`.
Remove/replace the intentional-absence note at `receipt_chain.rs:1584` once landed.

## Acceptance (testable)

1. `token_replay` stage passes on a valid ledger whose records replay the
   canonical `Judged -> Admitted -> Receipted` order with fitness `0x0001_0000`.
2. Refuses on replay-after-tamper: a ledger record crafted to replay out of
   order (e.g. `Receipted` before `Admitted`) yields
   `Fail("record 0: replay violation TokenNotEnabled { node_id: N }")` — error
   text matching praxis `check_token_replay` byte-for-byte.
3. Empty ledger → `Skip("no records to replay")`, matching praxis.
4. The existing 4 stages' behavior and byte-parity are unregressed:
   existing golden/integration tests (`receipt_chain_golden`, FM-CHAIN-009/014
   class) still green.

## Constraints

- Lane ownership: `/Users/sac/graphlaw` worktree/branch per coordinator; this
  work order authored on the `ggen` checkout lane — implementation lane must be
  the graphlaw lane.
- Must not regress the 4-stage validator's byte-parity (stage names, ordering,
  `StageResult` shapes for the existing four stages unchanged; `token_replay`
  appended last, as in praxis).
- Frozen wire strings unchanged.
- Chicago TDD: real ledger JSONL on disk in tests; no mocks.

## See Also

SJIRA-261010-01 · `docs/v26_10_10_praxis_retirement_plan.md`
