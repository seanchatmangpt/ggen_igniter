# Release notes — ggen_igniter v26.10.2

Tag: `v26.10.2` @ ee10e7b (26.10.1 and 26.10.2 both live on hex). This wave:
the v26.10.1-loop closes with the symlink-boundary law and the ERRC v26.10.2
wave across ggen_igniter, xaas, ash_a2a and ash_pplan; main has advanced to
a404697 (credo zero) on top of the tag. Evidence: `docs/jira/v26.10.2/RECEIPT.md`.

## What ships in 26.10.2

- Symlink-boundary law in the pack lock
  (`GgenIgniter.PackLock`, released ee10e7b): a canonical symlink whose
  target stays inside the pack's enclosing git toplevel is a lawful pack
  member (content-hashed, tag `"L"`); a target outside the toplevel, any
  directory symlink, and any loop/dangling link refuse
  `REFUSED:PACK_SYMLINK_ESCAPE` (never a hang). Outside a git repo the pack
  root is the boundary. Definition: `docs/glossary.md` "symlink boundary".
- ERRC wave (9 phase-1 lanes + 10 phase-2 F-lanes; outcome tables in
  `docs/jira/v26.10.2/ERRC.md`): fixture hygiene, executable mock gates,
  `sj:targetPack` execute gate, fleet-R v2 receipts law, crown `:snapshot`
  binding, `--require-killed` mutation court in ash_a2a CI.
- Receipts law (fleet-R v2): `mix ggen_igniter.receipts check/1` enforces the
  fleet-R v2 schema and the extension namespace (2cac19d); the projection
  `GgenIgniter.SemanticJira.RProjection` (89d7839); the vendored schema with
  digest pin + conformance court (134b35c).
- Gate 055 + standing-transition event vocabulary in the semantic-jira pack
  (81df828).
- `mix semantic_jira.execute` consumes `sj:targetPack` (f0c6f92); TargetPack
  is now rendered from pack facts — HANDWRITTEN row 48 retired (8ef0fea).
- Two-port HILT binding DEFAULT ON in the generated constructor
  (opt-in at 60e18bf, default-on at 3c22220; `utp:hilt false` is the compat
  escape).
- Refusal emitters emit the canonical `REFUSED:<CODE>` form; the legacy
  `REFUSED(code)` / bare-`REFUSED_<CODE>` parse shapes are removed
  (67961c7).
- `to_prd_status/1` removed — superseded by the fleet-R v2 projection
  (8e577a5).

## Post-tag main (ee10e7b → a404697)

- Credo zero: 15 behavior-preserving fixes + 7 law-commented exemptions
  (a404697); shapes_checked assertion (c49c53f).
- Legacy digest window SHRUNK, removal milestone v26.11.1 (3a154ae): only the
  three committed xaas ledgers that verify solely under the legacy rule are
  blockers (HANDWRITTEN row 46 D1 census). xaas side mirrors the shrink with
  a runtime probe of the legacy export (93784aed).
- Strict-profile STOP witnesses (b83d604): the durable block is ready, the
  profile itself is not flipped.
- Toolchain pin moves to `elixir 1.19.5-otp-27` / `erlang 27.2.4`
  (D8; .tool-versions edit on disk, qualification in flight — not yet
  committed at a404697).

## Honest residues

- Legacy digest window is a window, not a removal: removal milestone
  v26.11.1 (3a154ae; blockers named in HANDWRITTEN row 46).
- Strict profile remains STOP: witnesses exist, the profile flip does not
  (b83d604).
- HANDWRITTEN rows 47 (optional_target_pack kernel clause) and 49 (reactor
  pack stamp) remain open; row 48 retired at 8ef0fea.
- Known pre-existing environmental failure class: `ToolchainPin` tests are
  red off-pin by design; pass under the pin (as CI does).

## Verification record

- Per-commit gate on every landed commit:
  `mix compile --warnings-as-errors` + `mix test` → exit 0
  (`docs/jira/v26.10.2/RECEIPT.md`, command ledger).
- Bridge suite 101/0 against the hex-published dependency (promote hop).
- `admit_candidates` targetPack mismatch → exit 1 with the typed refusal
  `REFUSED:TARGET_PACK_MISMATCH` (registry entry 132) — a refusal doing its
  job, not a failure.
- Hex: 26.10.1 and 26.10.2 packages + docs live on hex; tag `v26.10.2` @
  ee10e7b. ash_a2a 26.9.31 live on hex.

## Replay

```
git checkout v26.10.2            # ee10e7b
MIX_BUILD_ROOT=_build-p2 mix test
```

Cross-repo replay heads (verified 2026-10-02): xaas de15fd14 (feat branch),
ash_a2a ccdb634, ash_pplan 2cad4cc (`v26.10.2`), ggen-marketplace 6b43b654.
