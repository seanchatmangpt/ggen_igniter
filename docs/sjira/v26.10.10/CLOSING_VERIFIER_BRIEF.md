# CLOSING_VERIFIER_BRIEF — v26.10.10 session (REFRESHED 2026-10-10, closeout re-verification)

Executable checklist for the independent verifier. Refreshed after the V-wave
gate consolidation (V1–V20), the V14 closure (tripwire/parser courts,
swallowed-requires repair), the census recount, and the FM-PACK-018 fix. All
commands run from `/Users/sac/ggen` on branch `spec-integration` unless noted.
Statuses sourced from `docs/sjira/v26.10.10/INDEX.md` (refresh #8) and
`/Users/sac/ggen/docs/v26_10_10_phase1_receipt.md` (V-wave + V14 closure
sections).

Legend: **[PASS-1]** = already verified in pass 1 (re-run optional, cheap
confirm); **[PASS-2]** = must be run by the closing verifier; **[PENDING]**
= in-flight/user-gated, record status only, do not block.

## Section A — Test-gate claims

| # | Claim (source) | Status | Command | Expected |
|---|---|---|---|---|
| A1 | receipt_chain_e2e 25/0 (SJIRA-01; V11) | [PASS-1] | `cargo test -p ggen-engine --test receipt_chain_e2e` | 25 passed, 0 failed |
| A2 | law_engine 4/0 (phase1; V11) | [PASS-1] | `cargo test -p ggen-engine --test law_engine_test` | 4 passed, 0 failed |
| A3 | receipt-chain seam 4/0 (V11) | [PASS-1] | seam test target per seam lane receipt | 4 passed, 0 failed |
| A4 | Differential court 428/0 praxis-vs-graphlaw (SJIRA-01) | [PENDING] — court pending its background run per V11; independent re-run pending | differential-court test in `docs/receipt-2026-10-09-*.md` (~/graphlaw) | 428/0; golden byte-exact |
| A5 | Validator+store port 405/0; graphlaw workspace 432/0 (SJIRA-01) | [PASS-1] | from `~/graphlaw`: workspace `cargo test` | 405/0 validator; 432/0 workspace |
| A6 | Capability six-suite set 43/0 — capability_corpus tightened to 3/0 (always-bind), pack_composition 11/0 (V2) | [PASS-1] | `cargo test -p ggen-marketplace capability_corpus` (3/0); `pack_composition_e2e` (11/0); `packfile_from_dir` (6/0); `packfile_capabilities` (9/0); packfile unit (10/0); namespace (4/0) | each matches; sum 43/0 |
| A7 | Parser differential court 5/0 (V14; `crates/ggen-engine/tests/pack_capabilities_parser_diff_test.rs`) — supersedes B-item "2 documented divergences" | [PASS-1] | `cargo test -p ggen-engine --test pack_capabilities_parser_diff_test` | 5 passed, 0 failed |
| A8 | Composer arbitration 11/0 (V2 confirms) | [PASS-1] | `cargo test -p ggen-marketplace --test pack_composition_e2e` | 11 passed, 0 failed |
| A9 | Composer corpus court deterministic-clean (SJIRA-08) | [PASS-1] | corpus court test per SJIRA-08 receipt | deterministic-clean; no nondeterminism reruns |
| A10 | Corpus engine smoke 403 manifests / 0 refusals (SJIRA-18) | [PASS-2] | `cargo test -p ggen-engine --test pack_corpus_engine_smoke` | parses all 403 top-level pack.toml, 0 refusals |
| A11 | generation_rules_e2e 28/0 (SJIRA-03) | [PASS-2] | `cargo test -p ggen-engine --test generation_rules_e2e` | 28 passed, 0 failed |
| A12 | cross_pack 6/0, typed_causes 8/0, rules_n3 4/0 (SJIRA-03) | [PASS-2] | corresponding test targets | 6/0, 8/0, 4/0 |
| A13 | Callsite migration (G1): `build_tera_with_packs` at generation_rules.rs:528 (plus sync.rs:1009, :1063) | [PASS-2] | `grep -n "build_tera_with_packs" crates/ggen-engine/src/generation_rules.rs` | hit at line 528 |
| A14 | Refuse-consumer closure (G5, SJIRA-02) | [PASS-2] | `cargo test -p ggen-engine --test law_engine_bridge_e2e`; `--test reflexive_law_e2e`; `grep -rn "load_hook_pack" crates/ggen-engine/src` | suites green; no fallback shim in grep |
| A15 | ggen-config 178/0 (V1 superseded the brief's 174/0) | [PASS-1] | `cargo test -p ggen-config` | 178 passed, 0 failed |
| A16 | Workspace check + clippy (G3): marketplace clippy src-clean; lints wiring COMPLETE incl. cheat-scanner + mcp | [PASS-2] | `just check` + clippy per justfile | 0 errors, 0 warnings |
| A17 | Engine all-targets quiet rerun (G4); V13 determinism 19/0 quiet-machine VERIFIED; V19 engine coverage lane still IN FLIGHT | [PASS-2] / [PENDING for V19] | clean `cargo test -p ggen-engine --all-targets` | green; byte-identity classification matches receipt |
| A18 | Version alignment (G6): V16 VERIFIED — single 26.10.x across tree; publish dry-run receipts landed (dirty-tree-refusal only) | [PASS-1]; dry-run post-rebuild [PASS-2] | workspace version grep; `cargo publish --dry-run` per SJIRA-16/19 order | aligned; dry-run passes (ggen-engine last) |
| A19 | rustc warnings 0 (SJIRA-06 DONE) | [PASS-1] | `RUSTFLAGS="-W warnings" cargo check --workspace` | 0 warnings |
| A20 | abb-sbb 59/0 (V7) | [PASS-1] | `cargo test -p ggen-abb-sbb` | 59 passed, 0 failed |
| A21 | cheat-scanner 19/0 after lints wiring (V7) | [PASS-1] | `cargo test -p ggen-cheat-scanner` | 19 passed, 0 failed |
| A22 | Vendored trio 91/28/37, 0 failed (V8) | [PASS-1] | bcinr-pddl lib + schedule-related + third target per V8 row | 91/0, 28/0, 37/0 |
| A23 | Cross-corpus tripwire 2/0 (`crates/ggen-marketplace/tests/cross_corpus_tripwire_test.rs`) — FALSIFIED composer refusal claim (V14) | [PASS-1] | `cargo test -p ggen-marketplace --test cross_corpus_tripwire_test` | 2 passed, 0 failed |
| A24 | Annotated pack sync smoke 2/0 (`crates/ggen-engine/tests/annotated_pack_sync_smoke.rs`) | [PASS-2] | `cargo test -p ggen-engine --test annotated_pack_sync_smoke` | 2 passed, 0 failed |
| A25 | Compose verb 5/0 + order-determinism fix (post-brief lane) | [PASS-2] | compose-verb test target per lane receipt | 5 passed, 0 failed |
| A26 | MCP capability surfacing 19/19 tools + 7/7 resources (V2/lane) | [PASS-1] | MCP capabilities test targets per lane receipt | 19/19 and 7/7 |

## Section B — Static claims (grep/inspect)

| # | Claim | Status | Command | Expected |
|---|---|---|---|---|
| B1 | GraphLawStore repoint (DoD 5) | [PASS-2] | `grep -rn "praxis_graphlaw::TripleStore" crates/ggen-engine/src/graph.rs` | 0 hits |
| B2 | ggen-config zero praxis_core (SJIRA-21 REFUTED-exception settled) | [PASS-2] | `grep -rn "praxis_core" crates/ggen-config --include='*.rs'; grep -n "praxis" crates/ggen-config/Cargo.toml` | 0 code occurrences; no dep |
| B3 | star-toml raw-site count — 5 stray sites FIXED in corrective wave (V17 finding 1 closed); 9-documented-exception invariant restored | [PASS-2] | `grep -rn "toml::from_str" crates --include='*.rs' \| grep -v star_toml` | 9 documented exceptions + `ggen-config/tests/pack_corpus_schema_test.rs:32,102` only |
| B4 | Corpus invariants — CANONICAL census (SJIRA-12 recount): **439 full-tree manifests** (95 packs + 344 marketplace incl. 36 nested) / 338 unique [pack].name / 71 mirror pairs; top-level scope = 403 / 332 / 71 (V18: 332/71 canonical). Requires (V18 authority chain, supersedes 64/140/91): **49 packs / 104 entries / 74 distinct URNs / 0 dangling / 0 bare / 0 swallowed** (post 154-file swallowed-requires repair) | [PASS-2] | census per SJIRA-12 + V18 method | figures above |
| B5 | PackFile parses [capabilities] (SJIRA-10) | [PASS-1] | `grep -n capabilities crates/ggen-marketplace/src/packs_registry/types.rs` | `capabilities` field with serde default |
| B6 | Guide spot-checks (SJIRA-14a) + composer docstring CORRECTED for mirror-collapse (tripwire finding: same-named mirrors dedupe by id, cross-corpus compose merge-collapses 403→332 silently; docstring no longer claims refusal) | [PASS-2] | read `docs/pack_capabilities_guide.md` + composer docstring | FM-PACK-018 credited to `validate_capability_requirements`; CLI shows `pack capabilities` verb (~pack.rs:1004); URN count 71; docstring claims dedupe/merge-collapse, NOT refusal |
| B7 | UNCERTAIN require adjudicated KEPT (SJIRA-11) | [PASS-2] | pinned shasum at `packs/greene-licensing-case-pack/ontology/greene-case.ttl:144,166` vs c0f27e5 | digest `d27970...f44`; load-bearing |
| B8 | Changelog 26.10.10 section | [PASS-2] | `grep -n "26.10.10" CHANGELOG.md` | section present |
| B9 | FM-PACK-018 two-tier rule LANDED (H2 fix): `crates/ggen-engine/src/pack.rs:454-528` + guide section | [PASS-2] | read pack.rs:454-528 + guide | two-tier validate present; guide documents it |
| B10 | Swallowed-requires repair 154 files landed (V14 item 3) | [PASS-2] | sample sweep: no top-level/docstring `requires` lines in [capabilities]-bearing packs | 0 swallowed |

## Section C — Go/no-go: praxis cutover (SJIRA-15/22)

1. A1–A5 green (receipt chain + seam + differential court) — seam rewire is
   praxis-core's only consumer post-SJIRA-21. A4 court background run pending.
2. `reflexive_law_e2e` green (A14).
3. FM-PACK-018 adjudication LANDED (B9); publish-safety inventory final.
4. SJIRA-23 port (MigrationReceipt etc.) NOT STARTED — G7 blocker, [PENDING].
5. Cutover dry-run checklist (SJIRA-15) executed; `publish = true` flip per SJIRA-16.

## Section D — Release-cut gates G1–G7 (SJIRA-22)

| Gate | Definition | Verify via |
|---|---|---|
| G1 | Callsite migration landed; receipt gates green | A13, A1–A3, A11 |
| G2 | FM-PACK-018 adjudication landed; publish inventory final | B9 |
| G3 | Workspace check + clippy green (incl. SJIRA-06 clippy half) | A16, A19 |
| G4 | Engine gates green on quiet machine; disk cleared | A17 (V19 lane still in flight) |
| G5 | Refuse-consumer closure green | A14 |
| G6 | Version-align gates; publish dry-run post-rebuild | A18 |
| G7 | SJIRA-23 graphlaw receipt types ported | [PENDING] — not started |

Falsifier: any gate red at cut time → ABORT, fix-forward, re-run, re-present.

## Section E — Known-acceptable exceptions (do NOT re-litigate)

1. 9 documented `toml::from_str` exceptions (+ 2 test-side sites) — B3; stray-site corrective wave closed V17 finding 1.
2. Parser divergences: RESOLVED by the 5/0 differential court (A7) — the former "2 documented divergences" exception RETIRES.
3. cli `outdated_warning` 1 pre-existing failure — receipted, not a session regression.
4. praxis `token_replay` not ported — SJIRA-14b (P3, OPEN).
5. ggen-config receipt_impl "praxis exception" — REFUTED (SJIRA-21); distinct install receipt by design.
6. Cross-corpus compose silent merge-collapse 403→332 — now DOCUMENTED DESIGN (tripwire 2/0 + docstring correction), not a defect.
7. Remaining unannotated marketplace packs — ≥50% binding threshold met (SJIRA-11 DONE).

## Section F — User-gated / in-flight items to EXCLUDE from pass 2

- **Callsite-migration receipt gates (90/0 claimed)**: independent re-run
  PENDING — record, do not block pass 2 (A1–A3/A11 cover the suites).
- **SJIRA-23 graphlaw port**: G7 blocker, not started.
- **Release cut itself (tag/push/publish)**: user-gated (SJIRA-22).
- **SJIRA-04 ambient reinstall, SJIRA-07 abb-sbb deletions, SJIRA-13a ghost-dir deletion, graphlaw 2-commit split**: user-run post-cut.
- **SJIRA-13b corpus dedup**: WITHDRAWN (falsifier FIRED).
- **V19/V20/V10/V12 coverage lanes**: IN FLIGHT — record status only.

## Pass-2 blockers (what actually gates the closing verifier)

**SUPERSEDED 2026-10-10** — all four resolved; see Section G below. Content
preserved as the pass-2-era record.

1. A4 differential court background run completion.
2. V19 engine all-targets quiet rerun landing (G4).
3. A14 refuse-consumer `reflexive_law_e2e` confirmation.
4. Everything else is PASS-1-verified or user-gated.

---

# Section G — 2026-10-10 closeout re-verification (AUTHORITATIVE; supersedes rows marked SUPERSEDED above)

Re-verified 2026-10-10 against ggen `main` HEAD `39e35b406` (later), verified
on disk: commits `dcbf33333` (abb-sbb publish lift), `5c9da7a3e` (G4 root
cause + `sync_closure_golden_test.rs` golden locks, 195 lines), workspace
version `26.10.10` confirmed in ggen-engine and ggen-abb-sbb Cargo.tomls,
star-toml raw-site sweep = 3 in-code exceptions, and the in-flight test
files present in the tree (receipt_verb_e2e, verbs_handlers_test,
transition_receipt_test, init_mine_library_test, tera_analyzer_codes_test,
tools_surface_parity_test, write_apply_confirm_test).

## G.1 CLOSED (pass-3 blockers, all green)

| Claim | Evidence |
|---|---|
| Two-tier property court 3/0 — prior failure was a fixture bug (undeclared pack name), fixed in `3cd294466` | commit `3cd294466`; pass-3 run 3/0 |
| Version 26.10.10 aligned across all surfaces | `grep ^version crates/*/Cargo.toml` — engine/abb-sbb confirmed 26.10.10 |
| abb-sbb `publish = false` lifted | commit `dcbf33333`, 1-line deletion in `crates/ggen-abb-sbb/Cargo.toml` |
| star-toml: stray sites reduced to 3 in-code exceptions | `grep -rn "toml::from_str" crates --include='*.rs' \| grep -v star_toml` → 3 hits (supersedes B3's 9-exception invariant) |
| Pack corpus court 6/0 over the 314-pack marketplace | corpus court run, pass 3 |
| G4 root cause fixed + golden locks | commit `5c9da7a3e` (`sync.rs` project-relative closure keys + golden test) |

## G.2 CLOSED (today's additional courts — all pass, 0 fail)

compose e2e 8/0 · two-tier 6/0 · epoch property 6/0 · OTEL 2/0 · LSP parity
8/0 · composer arbitration 17/0 (supersedes A8's 11/0) · MCP 6/0 · graph
determinism 5/0 (commit `39e35b406`) · cheat precision 20/0 · drift advisory
6/0 (commit `12933b648`) · ambient guard 4/0 · gates closure 5/0.

## G.3 IN FLIGHT / LANDED (honest status — test files on disk, receipts not yet re-witnessed this session)

receipt-verb e2e · doctor · sync-surface · tera analyzer codes ·
write-apply confirm · graph transition receipt · handlers · init-mine
library. Files present at `crates/ggen-engine/tests/{receipt_verb_e2e,
verbs_handlers_test}.rs`, `crates/ggen-graph/tests/transition_receipt_test.rs`,
`crates/ggen-lsp/tests/{init_mine_library_test,tera_analyzer_codes_test}.rs`,
`crates/ggen-mcp/tests/{tools_surface_parity_test,write_apply_confirm_test}.rs`
(currently untracked — commit pending). Mark IN FLIGHT until CI or a
witnessed run lands.

## G.4 CLOSED (strata, `~/strata` at `a365cf7` ≥ `443d52c`)

waves 1-3 · protocol court 114/0 · stratus 58/0 · temprun golden vectors ·
soak 10x PASS (Cp mean 6.72) · CLI binary shipped.

## G.5 CLOSED (marketplace, `~/ggen-marketplace` past `efea25462`, HEAD `aeca8a5a2`)

hdit-v2-structs landed: annotations, strata packs
(drift-corrected in `62f547b7e` — signer algo, valve refusal atoms),
README.

## G.6 USER-GATED (remaining; do not block close)

1. Publish chain (cargo publish, ggen-engine last per SJIRA-16/19).
2. Graphlaw 3-commit split (SJIRA-28; prep doc ready).
3. Tag/push of the release.
4. SJIRA-04 ambient ggen reinstall.

## Correction log (prior claims that turned out wrong or moved)

- A8 composer 11/0 → now 17/0 (expanded suite).
- B3 star-toml 9-exception invariant → 3 in-code exceptions after purge
  (stray corrective waves further shrank the set).
- A4 "court pending background run" → differential court resolved; not a
  blocker.
- V19 G4 "still in flight" → root cause found (`5c9da7a3e`), golden-locked,
  closed.
- B10/claims-era corpus figures (403/439 manifests) → superseded by the
  314-pack marketplace court baseline for closeout purposes.

Claim status counts (Section G): CLOSED 6 (G.1) + 12 (G.2) + 6 (G.4) + 1
family (G.5) = 25 closed items; IN FLIGHT 8 suites (G.3); USER-GATED 4
(G.6).
