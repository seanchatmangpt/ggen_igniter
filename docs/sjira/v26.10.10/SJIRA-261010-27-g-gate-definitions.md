# SJIRA-261010-27: G-gate definitions (G1–G7) — reference document

Date: 2026-10-10
Lane: sjira-refresh (docs)
Repo: /Users/sac/ggen (base c8846c7-equivalent)
Status: OPEN — the brief (CLOSING_VERIFIER_BRIEF.md Section D) names G1–G7
but the tree lacked a definitions document with concrete pass criteria. This
file is that document.

Each gate: definition, pass criteria as real commands, and dependent
evidence rows from the brief. A gate is ALIVE only when every command exits 0
at the recorded HEAD — gate status claimed without the command output is not
standing.

## G1 — Callsite migration landed; receipt gates green

- Definition: generation-rules callsites route through `build_tera_with_packs`
  (generation_rules.rs:528; sync.rs:1009, :1063); receipt-side gates pass.
- Pass criteria:
  - `grep -n "build_tera_with_packs" crates/ggen-engine/src/generation_rules.rs`
    → hit at line 528.
  - `cargo test -p ggen-engine` green (receipt-gate suites included).
- Evidence: brief A13, A1–A3, A11. [PASS-2 as of brief]

## G2 — FM-PACK-018 adjudication landed; publish inventory final

- Definition: the two-tier FM-PACK-018 re-apply has landed and the publish
  inventory (which crates publish, in what order) is adjudicated and frozen.
- Pass criteria:
  - FM-PACK-018 corpus/gate suites green (capability_corpus, cross_corpus
    gates per phase-1 receipt — currently 3/0 and 2/0 post-fixture fix).
  - Publish inventory table in SJIRA-16/19 matches live
    `cargo publish --dry-run` behavior per crate.
- Evidence: brief B9.

## G3 — Workspace check + clippy green

- Definition: `just check` (cargo check --workspace) and clippy per justfile
  clean; lints wiring complete incl. cheat-scanner + mcp.
- Pass criteria:
  - `just check` exit 0.
  - Clippy scoped per justfile (root package lint recipe + the SJIRA-06
    closeout residue) exit 0.
- Evidence: brief A16, A19. [PASS-2]

## G4 — Engine gates green on quiet machine; disk cleared

- Definition: `cargo test -p ggen-engine --all-targets` green on a quiet
  (non-contended) machine, V13 determinism holds, lane build roots deleted.
  Hardened by SJIRA-24 (fortune5 shape-closure regression must be
  standalone-deterministic).
- Pass criteria:
  - `cargo test -p ggen-engine --all-targets` exit 0, quiet output.
  - SJIRA-24 acceptance (mutation check: revert G4 fix → red).
  - No `_build-*`/lane target dirs left behind.
- Evidence: brief A17 (V19 lane in flight). [PARTIAL — V19 PENDING]

## G5 — Refuse-consumer closure green

- Definition: refuse-effect hook consumer rewiring complete; no fallback shim
  reachable.
- Pass criteria:
  - `cargo test -p ggen-engine --test law_engine_bridge_e2e` exit 0.
  - `cargo test -p ggen-engine --test reflexive_law_e2e` exit 0.
  - `grep -rn "load_hook_pack" crates/ggen-engine/src` → no fallback-shim
    hits.
- Evidence: brief A14. [PASS-2]

## G6 — Version-align gates; publish dry-run post-rebuild

- Definition: single 26.10.x version across the tree; abb-sbb publish chain
  resolved (SJIRA-25); per-crate `cargo publish --dry-run` green post-rebuild,
  ggen-engine last.
- Pass criteria:
  - Workspace version grep → one 26.10.x line.
  - `cargo publish -p ggen-abb-sbb --dry-run` exit 0 (clean tree).
  - `cargo publish --dry-run` per remaining crate in dependency order, exit 0.
- Evidence: brief A18; SJIRA-16, -19, -25.

## G7 — SJIRA-23 graphlaw receipt types ported

- Definition: MigrationReceipt et al. ported to the sibling graphlaw crate
  per SJIRA-261010-23; praxis-core/praxis-graphlaw retirement path unblocked
  (see docs/v26_10_10_praxis_retirement_plan.md).
- Pass criteria:
  - SJIRA-23 acceptance commands green (port tests).
  - `cargo tree -p ggen-engine -i praxis-core` reflects the post-port closure
    asserted by the retirement plan.
- Evidence: brief A-row for SJIRA-23. [PENDING — not started]

## Gate dependency note

G6 depends on G2 (frozen inventory) and SJIRA-25 (abb-sbb sequence). G4
closes only with SJIRA-24 hardening landed. G7 is independent of G1–G6 but
blocks overall release close.
