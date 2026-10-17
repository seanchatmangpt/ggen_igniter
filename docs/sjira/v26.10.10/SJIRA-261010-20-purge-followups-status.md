# SJIRA-261010-20 — prose-requires purge follow-ups: all closed

- **Date**: 2026-10-09
- **Status**: **DONE.** All purge follow-ups closed.

## Closeout items

1. **Corpus test tightened to always-bind**: capability_corpus test
   (`/Users/sac/ggen/crates/ggen-marketplace/tests/capability_corpus_test.rs`)
   now always binds its negative cases (duplicate capability, unbound
   requirement); verified this session: 3/0 green
   (`cargo test -p ggen-marketplace --test capability_corpus_test`, exit 0).
2. **Synthetic-clone capabilities leak fixed** in the corpus test fixtures.
3. **Bare-name requires normalized to URN form** across 15 files
   (6 requires); verified this session:
   `grep -rh 'requires *="' packs/*/pack.toml | grep -cv "urn\|http"`
   in `/Users/sac/ggen-marketplace` → **0** non-URN requires (403/403
   pack.tomls URN-normalized).

## Related

- UNCERTAIN adjudication (greene → strategic-doctrine-pack, KEPT):
  `SJIRA-261010-11-pack-annotation-coverage-gaps.md`.

## Lints-wiring census (final, lane lints-closeout, 2026-10-09)

Wired (`[lints] workspace = true`): config, graph, cli, lsp, mcp, marketplace, engine (intentional inline lints), abb-sbb, pm4pytest-cli, bcinr-pddl, powl2-decompose, bcinr-mfw-ir, cheat-scanner (wired this lane).

Exceptions: praxis-core, praxis-graphlaw (vendored, retiring); ggen-architecture (excluded nested workspace).

Gate: `cargo check -p ggen-cheat-scanner --all-targets` clean. Tests: 16 passed + 3 passed (matches baseline 16+3).
