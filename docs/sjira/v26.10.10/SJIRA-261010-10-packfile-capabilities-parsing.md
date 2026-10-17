# SJIRA-261010-10 — wire [capabilities] into packs_registry PackFile parsing (P0)

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P0
- **Status** (2026-10-09 refresh #6): **DONE — both parts VERIFIED.**
  Parser differential court landed (`pack_capabilities_parser_diff_test`) —
  ggen parser vs marketplace parser; caught real drift (identity-field
  injection asymmetry + 5 missing-description refusals), both fixed.
  Part 1 (PackFile parsing) LANDED + VERIFIED; `pack_file_from_dir` 6/0.
  Part 2 (capabilities-aware arbitration) VERIFIED 11/0 via
  pack_composition_e2e. Landed semantics, documented VERIFIED in the guide's
  composition section (`docs/pack_capabilities_guide.md`): provides =
  packages ∪ capabilities.provides; requires = dependencies ∪
  capabilities.requires; DuplicateCapability tripwire on cross-corpus mirrors;
  widened UnboundRequirement binding; source `PackCapabilitySurface::from_pack`
  in `composer.rs`. Guide evidence-contract section landed. All six capability
  suites green deterministic (43/0, see SJIRA-261010-11 refresh #4).
- **Blocked-by**: none

## Task

Found on 2026-10-09 backlog refresh: the pack annotation fan-out wrote
`[capabilities]` into 287/401 pack.tomls, but the annotations are INERT DATA —
nothing parses them.

- `crates/ggen-marketplace/src/packs_registry/types.rs:102`:
  `pub struct PackFile { pub pack: Pack }` — no capabilities field. TOML
  deserialization drops the `[capabilities]` table silently.
- `crates/ggen-marketplace/src/packs_registry/composer.rs` (~line 24-27)
  derives provided capabilities from `packages` entries and comments that
  requires-sets "live on ggen-engine's `PackToml`" — it never reads the
  annotations.

Wire it:

1. Add a `capabilities` section (consumes/provides) to `PackFile`/`Pack`
   (serde default for unannotated packs — 114 exist).
2. Merge composer capability derivation: parsed `[capabilities]` provides/
   consumes take precedence, `packages`-inferred provides remain as fallback;
   feed consumes into `UnboundRequirement` arbitration.
3. Round-trip test: parse an annotated real pack.toml, assert the
   capabilities struct is populated (currently zero coverage = the inertness).

## Acceptance

- `cargo test -p ggen-marketplace` green, ≥ 436/0 baseline.
- New test: `star_toml::from_str::<PackFile>` on a real annotated corpus
  pack.toml yields non-empty capabilities (red today).
- Composer `DuplicateCapability`/`UnboundRequirement` fire from parsed
  annotations on real corpus metadata, not just `packages` inference.

## Constraints

- Chicago TDD: real corpus files; no fixture fakes.
- No worktrees; lane owns packs_registry types + composer merge point.
- Serde must NOT use `deny_unknown_fields` silently dropping annotations —
  assert the field is read, not just tolerated.
