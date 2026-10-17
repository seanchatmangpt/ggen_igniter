# SJIRA-261010-13 — Pack corpus dedup execution (WITHDRAWN: design falsified)

- **repo/base**: ggen @ branch spec-integration
- **status**: WITHDRAWN (2026-10-09) — SJIRA-261010-12 falsifier FIRED:
  census re-run found 64 consumer refs resolving to `/Users/sac/ggen/packs`
  vs 1 to `ggen-marketplace/packs` (direction REVERSED from the 45-vs-0
  premise). ggen/packs is live-consumed by the repo's own examples
  (`examples/cs2-projections/ggen.toml:10`,
  `examples/interview-assist/ggen.toml:8`); deletion would break them.
  Option c is dead. Still USER-GATED for any execution if ever revived.
- **Corpus data closure** (2026-10-09, purge-finisher lane): ~17 remaining
  prose-only pack dirs deleted (capability-ecology 16, affidavit-trust-plane
  4, zeroconfig→specimen, et al); contract-based keeps exceeded the court's
  list. Requires reconcile TRUE FINAL: 64 packs / 140 entries / 91 distinct
  URNs / 0 dangling (the earlier "37" was the 89-pack purge-lane scope
  artifact; 10-sample of the unenumerated 102 all contract-clean).
  6 bare-name requires normalized to URN form across 15 files; 5 packs'
  missing `description` fields added (they were being refused FM-PACK-003:
  automatic-autonomic-operations, certification-assist x2, ontostar-mustar,
  speedrun). `capability_corpus_test` fixed to stop leaking synthetic-clone
  capabilities: 3/0 deterministic.
- **design**: `/Users/sac/ggen/docs/pack_urn_namespace_proposal.md`
  (FALSIFIED section supersedes the option-c recommendation)

## Scope (execute only after explicit user approval)
1. Delete the 71 duplicated pack directories from `/Users/sac/ggen/packs/`
   (names = intersection measured 2026-10-09; re-derive at execution time —
   do not trust the stale list). For the 40 diverged and 22
   marketplace-newer pairs, verify marketplace copy `diff`s clean against
   nothing (they are sole copies post-deletion) and record the ggen-side
   content hash in the receipt before deletion for replay.
2. Grep `ggen/packs` internal references (justfile, tests, docs, ggen.toml)
   for the 71 names; redirect any in-repo consumer to
   `../ggen-marketplace/packs/<name>`.
3. Run `ggen sync run --dry-run` in 2–3 representative consumers
   (ash_a2a, xaas, ggen-marketplace) to confirm zero DuplicateCapability
   refusals and unchanged resolution.
4. Receipt: count of dirs deleted, hashes of diverged ggen-side copies,
   sync outputs pre/post.

## Falsifier
Any consumer sync fails to resolve a pack after deletion, or a deleted
ggen-side pack is byte-different from its marketplace copy in a way that
loses content (hash mismatch vs pre-deletion receipt not explained by the
marketplace-newer classification).

## Standing
BLOCKED[USER_APPROVAL] until operator approves deletion.
