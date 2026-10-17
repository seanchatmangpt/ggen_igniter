# SJIRA-261010-14 — capability guide fact-check closeout

- **Repo/base**: `/Users/sac/ggen` (+ `/Users/sac/ggen-marketplace`)
- **Priority**: P2
- **Status**: **COMPLETE** (2026-10-09). Guide at `/Users/sac/ggen/docs/pack_capabilities_guide.md`.
  All three fact-check corrections verified on disk:
  1. FM-PACK-018 attribution fixed — guide credits `validate_capability_requirements`
     (`crates/ggen-engine/src/pack.rs`), "reached from both `resolve` and
     `resolve_read_only`".
  2. CLI section rewritten for the `pack capabilities` verb — verb exists at
     `crates/ggen-cli/src/cmds/pack.rs` (`#[verb] pub fn capabilities`, ~line 1004).
  3. URN count corrected to 71 ("71 cross-repo duplicate `provides` URNs as of
     the v26.10.10 phase-1 annotation") with pointer to
     `docs/pack_urn_namespace_proposal.md`.
  **Forward link (RESOLVED)**: SJIRA-261010-10 part 2 VERIFIED (11/0 via
  pack_composition_e2e) — the guide's composition section now documents the
  landed capabilities-aware arbitration semantics; evidence-contract section
  landed.

## Task

Structural gap surfaced by the 2026-10-09 refresh: no order owns folding the
capability-guide fact-check results back into the close state.

1. When the fact-check lane reports: adjudicate each finding (fix the guide,
   or receipt the guide as correct).
2. Cross-check guide claims against the live corpus state (401 pack.tomls,
   annotation coverage census in SJIRA-261010-11, parser status in
   SJIRA-261010-10) — any guide claim contradicted by parser/corpus reality
   is a defect to fix forward.
3. If smoke tests over the guide surface defects, file child orders rather
   than expanding this one.

## Acceptance

- Every guide claim either verified against disk or corrected; findings
  receipted; no claim citing stale counts (as-of markers required).
