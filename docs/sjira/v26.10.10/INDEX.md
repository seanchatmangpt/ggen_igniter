# SJIRA v26.10.10 Index

| id | title | status | priority | blocked-by |
|---|---|---|---|---|
| 01 | praxis-core retirement steps 2-6 (receipt-chain port + rewiring) | COMPLETE (differential court 428/0; steps 4-5 remain) | P0 | none (step 1 landed) |
| 02 | refuse-effect hook consumer rewiring (ggen) | DONE (consumer gates green; adjudicated green at HEAD a303d16f6) | P0 | none |
| 03 | generation_rules.rs:528 build_tera -> build_tera_with_packs | DONE (wired at :528; 28/0) | P1 | none |
| 04 | ambient ggen 26.9.28 stale install hazard (USER-RUN) | PENDING (user action) | P1 | none |
| 05 | engine all-targets quiet-machine rerun + byte-identity classification | DONE (verifier pass 4 GO: zero red suites, 0 warnings, versions 26.10.10) | P1 | none |
| 06 | rustc warnings "allow" flip follow-through | DONE (0 warnings; clippy half open) | P2 | none |
| 07 | ggen-abb-sbb Cargo.lock + target/ deletion (USER-RUN) | PENDING (permission-denied to agents) | P2 | none |
| 08 | pack capability adoption: composer integration test + surfacing | LANDED (court 401/401; MCP surfacing 19/19+7/7) | P1 | none |
| 09 | documentation drift sweep at v26.10.10 close | PENDING | P2 | 01..08 (run last) |
| 10 | wire [capabilities] into packs_registry PackFile parsing | DONE (both parts VERIFIED; parser diff court landed, drift fixed) | P0 | none |
| 11 | close pack annotation coverage gaps (114/401) | DONE | P2 | none |
| 12 | Pack URN duplicate-capability design + measurement | ADMITTED (design + measurement receipt) | — | none |
| 13a | ghost dirs verdict (packs/ without pack.toml) | COMPLETE (2 dirs classified DEAD) | — | user approval |
| 13b | Pack corpus dedup execution | WITHDRAWN (falsifier FIRED); corpus closure done: 64/140/91/0 requires, ~17 prose-only purged | — | — |
| 14a | capability guide fact-check closeout | COMPLETE | P2 | none |
| 14b | port token_replay validator stage into graphlaw | OPEN (dead surface) | P3 | none |
| 15 | praxis-core cutover dry-run (executable work order) | WRITTEN (7-step checklist complete) | — | 16 (inventory) |
| 16 | ggen-engine publish=false cutover: blocker inventory | DONE (all pass-3 blockers closed; corpus 6/0, property 3/0, versions 1/0, falsifiers 40/0, sparql_refusals 5/0, marketplace_fixture 1/0 at a303d16f6; remaining = USER-GATED publish chain 25) | — | user gate (publish) |
| 17 | nested test targets (ggen-cli/tests): classification + deletion order | PROPOSED (user gate required) | — | user gate |
| 18 | engine strict-parse smoke over pack corpus | RECEIPT (done) | — | none |
| 19 | intra-workspace version skew audit (follow-up to 16) | DONE (versions court 1/0 at a303d16f6; all 26.10.10) | P2 | none |
| 20 | prose-requires purge follow-ups | DONE (all closed: corpus test always-bind 3/0, leak fixed, 0 non-URN requires / 403 tomls) | P2 | none |
| 21 | ggen-config receipt_impl praxis_core exception | RESOLVED (premise REFUTED — zero praxis symbols; post-migration praxis-core's only consumer is the seam itself; 34 refs/14 files re-measured, comment-only residue in mcp/lsp/cheat-scanner) | P2 | none |
| 22 | v26.10.10 release-cut checklist (USER-gated) | WRITTEN (checklist complete; cut awaits gates + user approval; praxis-cutover G7 blocked-by 23) | P0 | G1-G7 (see file); G7←23 |
| 23 | port MigrationReceipt/ReceiptRecordV1Legacy/MIGRATION_LAW_1_TO_2 into graphlaw receipt_epoch | WRITTEN (P1 cutover prerequisite; not started; ObligationCount already ported, seam re-export approved) | P1 | none |
| 24 | G4 follow-up — fortune5 shape-closure regression hardening | ROOT CAUSE FIXED (5c9da7a3e: shape closure keys project-relative + golden lock); test-hardening half remains OPEN | P0 | none |
| 25 | G6 abb-sbb publish sequence (user-gated) | PREP LANDED (dcbf33333: publish=false lifted); real crates.io publish still USER GATED | P1 | user gate |
| 26 | standing CI guard — RUSTFLAGS test-target warning inventory | PARTIAL (b177c4b24: 8-crate property/e2e courts + test-target warning cleanup landed; standing guard not yet wired) | P2 | none |
| 27 | G-gate definitions G1-G7 reference doc | WRITTEN (definitions doc complete; gate statuses re-verified 2026-10-10 refresh) | — | none |
| 28 | graphlaw sibling repo 3-commit split | BLOCKED[USER GATE] (prep written; irreversible topology transition) | P1 | user gate |
| 29 | FM-PACK-018 two-tier unit court | DONE (two-tier landed; court adjudicated green at HEAD a303d16f6) | P1 | none |
| 30 | CLI `--packs` repeat flag | DONE (landed ~39e35b406..a303d16f6 court wave) | P2 | none |
| 31 | generation.rules dotted-table parsing | DONE (landed in pass-3 court wave; adjudicated green at HEAD) | P2 | none |
| 32 | lsp-max E0011 (CONSTRUCT/SELECT missing ORDER BY) | DONE (lsp-max generators + readme_region.md.tera template fix in a303d16f6) | P2 | none |
| 33 | strata Ash tier FR-4 | OPEN (unimplemented by design — scope: FR-4 Ash tier not yet built in /Users/sac/strata; wave-2 2cbc5d7 landed courts/fuzz/valve 38/0/soak Cp 6.1-6.7, FR-4 excluded) | P2 | none |

## Cross-repo evidence (2026-10-10)

- /Users/sac/ggen main @ a303d16f6 (2026-10-10 final convergence): verifier
  pass 4 GO — zero red suites, 0 warnings, versions 26.10.10. ~25 new courts
  landed today: 39e35b406 (README gate pointer + graph determinism),
  2364663b8 (five courts — MCP surface 12-vs-9 tool count fixed in repo-facts
  + regenerated), d9dee86b1 (seven courts + sparql_refusals fixture fix),
  a303d16f6 (README gate-count root cause in readme_region.md.tera, lsp-max
  generators, bench -p — slo-check Phase 1 no longer vacuous, receipt verb e2e).
  Prior wave: 5c9da7a3e (G4 root cause), d2790b206 (docs regen),
  b177c4b24 (8-crate courts + warning cleanup), a5c80671b (justfile
  lsp-max-new + docs closeout), 03ebdaee4 (corpus self-IRI invariant, strata
  family 5→6 packs), dcbf33333 (abb-sbb publish lift), 37958ed93 (conflict
  markers + dep pins 26.10.10).
- /Users/sac/strata: 2cbc5d7 wave-2 — CAS bugs fixed, valve 38/0, soak ALIVE
  Cp 6.1-6.7.

## Legend

- DONE/COMPLETE = landed with receipt; PARTIAL/LANDED-steps = in-file wording kept as stated.
- PENDING = not started or awaiting user action; IN FLIGHT = actively owned by a lane.
- BLOCKED[reason] = gating external fact; WITHDRAWN = falsified/retired (13b).
- Statuses transcribed from file headers; final convergence refresh 2026-10-10
  against ggen main a303d16f6 (verifier pass 4 GO). All prior IN FLIGHT rows
  (02/05/16/19/29/30/31/32) marked with landing commit or final tally; file
  headers predate this refresh.
- Remaining OPEN = USER-GATED only: 04 (ambient reinstall), 07 (lock/target
  deletion), 22 (release cut), 25 (crates.io publish, abb-sbb → engine chain),
  28 (graphlaw 3-commit split), 17 (user approval); plus by-design items 13a
  (user approval), 14b (dead surface), 33 (FR-4 unbuilt by scope).
