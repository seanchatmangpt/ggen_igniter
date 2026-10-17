# SJIRA-261010-08 — pack capability adoption: post-annotation composer integration test + surfacing

- **Repo/base**: `/Users/sac/ggen`, branch `spec-integration`
- **Priority**: P1
- **Status** (2026-10-09 refresh #6): CLI pack capabilities verb LANDED;
  MCP capabilities surfacing DONE (19/19 tools + 7/7 resources);
  FINAL corpus court deterministic-clean 401/401; changelog 26.10.10 section
  drafted. Composer part 2 (SJIRA-10 part 2) VERIFIED — capabilities-aware
  arbitration 11/0 via pack_composition_e2e; landed semantics documented in
  the guide (provides = packages ∪ capabilities.provides; requires =
  dependencies ∪ capabilities.requires; DuplicateCapability cross-corpus
  tripwire; `PackCapabilitySurface::from_pack`). Earlier:
  PARTIAL — composer corpus test IN FLIGHT.
  Annotation fan-out is ~complete: 287/401 pack.tomls carry `[capabilities]`
  (93/93 in ggen, 194/308 in ggen-marketplace) — the ≥50% binding threshold is
  MET. 114 packs remain unannotated (all in ggen-marketplace; see
  SJIRA-261010-11). NOTE: any lane touching marketplace pack files must verify
  owner execute bits — several pack dirs had lost `u+x` (restored via
  `chmod u+x`); if a corpus test fails with permission errors, check bits
  first. Also see SJIRA-261010-10: `[capabilities]` is NOT yet read by
  `PackFile` parsing — the corpus test must exercise real parsed annotations,
  not just file presence.
- **Blocked-by**: none (SJIRA-261010-10 part 2 unblocked — mkt-fmt lane
  released composer.rs; composer merge in flight)

## Task

The composer revival (DoD #15, 4-refusal taxonomy, marketplace lib 436/0) landed
against unit fixtures. Two follow-ups against the real corpus (401 annotated
packs):

1. **Post-annotation composer integration test**: run composer resolution over
   the real annotated pack corpus and exercise the `DuplicateCapability` /
   `UnboundRequirement` arbitration paths against real metadata (not synthetic
   fixtures). Assert typed refusal behavior and correct winner selection on
   known-duplicate cases.
2. **CLI/composer surfacing**: expose composer resolution results (arbitration
   decisions, refusals) through the CLI so a user can see why a pack set
   resolved or refused — currently the taxonomy is library-visible only.

## Acceptance

- `cargo test -p ggen-marketplace --test composer_corpus_integration` (new): runs over the real corpus, exercises both refusal variants, green.
- A CLI verb (existing or new noun/verb) prints composer arbitration/refusal detail; verified by running it against a fixture manifest that triggers `DuplicateCapability` and capturing real output.
- No regression: `cargo test -p ggen-marketplace` stays ≥ 436/0.

## Constraints

- Chicago TDD: real corpus files, real CLI subprocess (ggen_bin() fallback pattern per `cli_boundary.rs`).
- No worktrees; lane owns composer + the new test/CLI surface.
