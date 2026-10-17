# SJIRA-261010-11 — close pack annotation coverage gaps (114/401)

- **Repo/base**: `/Users/sac/ggen` + `/Users/sac/ggen-marketplace`
- **Priority**: P2
- **Status** (2026-10-09 refresh #4): **DONE.** Prose-requires purge
  COMPLETE: 297→37 requires (260 prose-only deleted, contract-evidenced
  keeps; 1 UNCERTAIN flagged: greene→strategic-doctrine-pack). All six
  capability suites green deterministic (43/0): capability_corpus 3/0,
  pack_composition_e2e 11/0, packfile_from_dir 6/0, packfile_capabilities
  9/0, packfile unit 10/0, namespace 4/0. SJIRA-10 part 2 VERIFIED
  (capabilities-aware arbitration live). Earlier refreshes:
  annotation receipt RECORDED; dangling requires = 0 (7 deleted);
  ~76% of sampled requires were PROSE-ONLY.
- **Adjudication** (2026-10-09): the one UNCERTAIN require is adjudicated
  **KEPT** with class-d evidence. greene-licensing-case-pack →
  strategic-doctrine-pack is an executable falsifier, not prose:
  `packs/greene-licensing-case-pack/ontology/greene-case.ttl:144,166`
  (`glc:r4` and `glc:f05`) pin
  `git -C ggen-marketplace show c0f27e5bed97b164ac267f86d8d9d989982319e8:packs/strategic-doctrine-pack/generated/catalog.json | shasum -a 256`.
  Sibling pack and `generated/catalog.json` both exist; command ran clean,
  digest `d279700226af68fd41fa6223359000333c351bec8bf75ca8625ffebf3991af44`.
  By design the digest pins a historical commit, so drift of the sibling's
  working tree does not break the falsifier — the require is load-bearing.
- **Blocked-by**: none
  (independent of SJIRA-261010-10 parser wiring; both must
  land before the composer corpus test can bind at full coverage)

## Task

Refresh census (2026-10-09): 287/401 pack.tomls carry `[capabilities]` —
93/93 in ggen `packs/`, but only 194/308 in ggen-marketplace `packs/`. The
114 unannotated packs are all in the ggen-marketplace corpus. Annotate them
(consumes/provides derived from each pack's actual template/schema surface,
same method as the original fan-out).

Also verify owner execute bits while touching pack dirs: several had lost
`u+x` (restored 2026-10-09 via `chmod u+x`); re-check with
`find packs -maxdepth 1 -type d ! -perm -u+x` and fix forward.

## Acceptance

- `grep -L "\[capabilities\]" packs/*/pack.toml` → 0 in both repos.
- Execute-bit sweep: zero non-executable pack dirs in either corpus.
- Spot check: 5 annotated packs' capabilities match their actual
  provides/consumes (no boilerplate-only annotation).

## Constraints

- Mechanical annotation only where the surface is unambiguous; ambiguous
  packs get an explicit TODO comment, not guessed capabilities.
- No worktrees; do not touch pack contents beyond pack.toml + bits.

## Reconciliation appendix (lane requires-reconcile, 2026-10-09)

The "297→37" purge figure is a **scope artifact**, not a contradiction of the
final census. Fresh single-script recount over both corpora
(`/Users/sac/ggen/packs` 95 packs + `/Users/sac/ggen-marketplace/packs` 308):

- **Final true number: 64 packs with non-empty `requires`, 140 require
  entries, 91 distinct URNs, 0 dangling, split 12 ggen / 52 marketplace.**
  (Census's "63/139" differed by one pack/entry — a snapshot-timing delta,
  not a method difference; both agree on 0 dangling, 0 bare.)
- The purge lane's own snapshot (`/tmp/requires_pairs.txt`) enumerated only
  **89 packs** of the 403-pack corpus. Within that scope, 30 packs / 80
  entries remain; the purge's 37 class-evidenced keeps were correct *for its
  scope at its time*. The remaining entries in scope (80 − 37 = 43) plus the
  29 packs / 60 entries entirely outside its scope were added by later lanes
  (f-g/no/p/qr dedup waves) that postdated the purge's enumeration.
- **Sample verdict (10 extra packs, 26 URN edges): all contract-clean.**
  Every target exists in-corpus (0 dangling corpus-wide); every sampled
  requiring pack carries non-`pack.toml` artifact evidence of the dependency
  (ontology.ttl prefix-binding, qualification/consumer.ttl imports,
  templates/*.tmpl path-loads, runners/*.py script loads) — e.g.
  agent-harness-recompilation-pack → 17 URNs, all bound in its ontology.ttl.
- **Verdict: no re-purge needed.** The extra keeps are lane-authored,
  contract-evidenced dependencies, not purge misses. The 37 figure should be
  read as "37 kept within the purge lane's 89-pack scope", superseded by the
  corpus-wide 64-pack / 140-entry census.
