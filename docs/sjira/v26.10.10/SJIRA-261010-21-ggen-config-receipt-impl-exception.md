# SJIRA-261010-21: ggen-config receipt_impl praxis_core exception — PREMISE REFUTED

Date: 2026-10-09
Lane: config-receipt-spec
Repo: /Users/sac/ggen (branch spec-integration)
Status: RESOLVED — the documented exception does not exist in the code.

## Claim investigated

Callsite-migration context asserted: "ggen-config's `receipt_impl.rs` is the
documented exception — it cannot dev-dep ggen-engine (circular), so it still
imports praxis_core directly, blocking full praxis-core retirement."

## Evidence (measured, not recalled)

`crates/ggen-config/src/receipt/receipt_impl.rs` (382 lines):
- Imports: `crate::error`, `chrono`, `ed25519_dalek` (Signature, Signer,
  SigningKey, Verifier, VerifyingKey), `serde`, `sha2` (Sha256).
- Zero `praxis_core` symbols. Its own doc comment explicitly distinguishes it
  from `ggen_engine::receipt_chain_seam::ReceiptRecord` (Ed25519/SHA-256
  one-shot install receipt vs chained-BLAKE3 sync ledger — different
  lifecycles, deliberately coexisting, neither replaces the other).

`crates/ggen-config/Cargo.toml`: no praxis_core/praxis-graphlaw dependency.
Workspace grep: zero `praxis_core` occurrences in any ggen-config `.rs` or
TOML; only doc-comment mentions of `praxis-graphlaw` in
`src/manifest/types.rs` (the `[law]` manifest schema, prose only).

Remaining `praxis_core` consumers workspace-wide: `praxis-graphlaw` itself
(internal) and `ggen-engine`'s `receipt_chain_seam` — which is the seam the
migration routes through. No ggen-config exception exists to migrate.

## Options (as posed, now moot)

- (a) ggen-config deps graphlaw directly: N/A — nothing to replace.
- (b) Move receipt_impl into ggen-engine: rejected on consumers alone —
  `ggen_config::receipt::*` has 10+ production consumers across
  ggen-marketplace (pki.rs, install.rs, composition_receipt.rs, error.rs,
  security.rs, agent/receipt.rs) and ggen-cli (receipt_manager.rs,
  cmds/receipt.rs). Moving it inverts a clean dependency for no gain.
- (c) Keep praxis-core for ggen-config: unnecessary — ggen-config already
  does not use it.
- (d) Duplicate logic in graphlaw::receipt_chain: rejected — drift risk with
  zero motivating call.

## Resolution

No code task. The praxis-core retirement blocker attributed to ggen-config is
already closed (or never existed). The only remaining praxis_core surface is
inside praxis-graphlaw and the receipt_chain_seam itself.

## Acceptance criteria (testable, for the refutation)

1. `grep -rn "praxis_core" crates/ggen-config/` → zero matches (doc comments
   excepted for `praxis-graphlaw` schema prose).
2. `grep -n "praxis" crates/ggen-config/Cargo.toml` → zero matches.
3. `cargo build -p ggen-config` and `cargo test -p ggen-marketplace` green
   with no praxis_core in ggen-config's dependency closure
   (`cargo tree -p ggen-config -i praxis-core` → empty/error).

## Priority

None (informational). If praxis-core retirement is still tracked as blocked
by ggen-config anywhere, that record should be corrected against this
receipt. Next real question, out of scope here: whether praxis-graphlaw's
internal praxis_core usage justifies keeping the crate at all.
