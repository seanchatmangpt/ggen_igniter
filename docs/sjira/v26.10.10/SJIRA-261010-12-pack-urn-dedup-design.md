# SJIRA-261010-12 — Pack URN duplicate-capability design + measurement

- **repo/base**: ggen @ branch spec-integration (design-only; no behavior diff)
- **status**: ADMITTED (design + measurement receipt, 2026-10-09 refresh:
  proposal written at `docs/pack_urn_namespace_proposal.md`; FINAL court
  deterministic-clean 401/401 parse, 0 duplicate [capabilities], 0 shape
  deviations; collision census 71 = 9 identical / 22 marketplace-newer / 40
  diverged; live corpus = marketplace, 45 consumer refs vs 0). (2026-10-09
  refresh #2: the 71 cross-corpus dup URNs are USER-GATED via
  SJIRA-261010-13 execution order — do not execute without approval.)
  (2026-10-09 refresh #3: FALSIFIER FIRED. Census re-run: 64 consumer refs
  resolve to ggen/packs vs 1 to ggen-marketplace — direction REVERSED
  (falsifying lines: examples/cs2-projections/ggen.toml:10,
  examples/interview-assist/ggen.toml:8). "Marketplace is the live corpus"
  premise dead; option c re-adjudicated and rejected; proposal revised to
  DEFER with mirror-collapse (e) as the design-if-needed.)
  (2026-10-09 refresh #4 canonical census: 403 pack.toml total — 95 ggen +
  308 marketplace — 331 unique names, 72 mirror pairs. Recommendation:
  DEFER; revisit on a real cross-corpus consumer.)
- **proposal**: `/Users/sac/ggen/docs/pack_urn_namespace_proposal.md`

## Acceptance
- [x] 71 colliding name pairs enumerated and classified: 9 identical,
      22 marketplace-newer, 40 diverged, 0 ggen-newer
      (method: `comm -12` of `ls packs/`, per-pair `diff -rq`, `[pack]` version compare)
- [x] Live-consumed corpus measured: 45 consumer `ggen.toml` references to
      `ggen-marketplace/packs`, 0 to `ggen/packs`, 3 to local `mfact/packs`
- [x] Options a–d evaluated with trade-offs; recommendation = option c
      (dedup to marketplace corpus), interim composer precedence (b) if
      execution is delayed
- [x] Falsifier: if any project's `ggen.toml` is later found resolving packs
      from `ggen/packs`, the "marketplace is the live corpus" premise and the
      dedup order (SJIRA-261010-13) must be re-adjudicated
      — **FIRED 2026-10-09**: 64 refs resolve to `ggen/packs`, 1 to
      `ggen-marketplace/packs`. Premise reversed; order re-adjudicated and
      withdrawn (see refresh #3 and proposal FALSIFIED section).

## Standing
PARTIAL_ALIVE — design falsified, recommendation revised (defer; mirror-
collapse (e) if a cross-corpus consumer appears). Any execution remains
USER-GATED.

## Canonical Pack-Corpus Census (lane corpus-census, 2026-10-09)

Method: `find <repo>/packs -maxdepth 2 -name pack.toml` + `[pack].name` parse.
Run twice, byte-identical results.

| metric | value |
|---|---|
| ggen/packs dirs | 97 (95 with pack.toml, 2 manifest-less) |
| ggen-marketplace/packs dirs | 309 (308 with pack.toml, 1 manifest-less) |
| total dirs | 406 |
| total pack.toml files | 403 |
| unique [pack].name | 331 |
| unique dir names | 332 |
| cross-repo mirror pairs (same [pack].name in both repos) | 72 (144 files) |

### Circulating numbers explained
- **401** = pack.toml file count at an earlier time (34 fewer manifests than now).
- **437** = later pack.toml count, still 34 short of current 403; superseded.
- **332** = unique *dir names* (capability_corpus_test's injection dedups by dir
  name, hence 332 not 331).
- **475** = dir count at an earlier time incl. manifest-less/ghost dirs
  (SJIRA-261010-13 territory); current total dirs = 406.

### Which number each consumer uses
- **Composer / capability injection**: unique `[pack].name` = **331** (or 332 if
  keying by dir name — pick one and document).
- **Guides / per-repo docs**: per-repo pack.toml counts = 95 (ggen), 308
  (ggen-marketplace).
- **Urn-dedup design (this doc)**: mirror pairs = **72**. Of the 144 files in
  duplicated names, 72 are removable duplicates (403 - 331 = 72 surplus); each
  pair keeps exactly one canonical manifest.

## Census re-count (lane census-recount, 2026-10-09) — supersedes the numbers above

Method: full `find <repo>/packs -name pack.toml` (no maxdepth) + `[pack].name`
parse, both keyings; run twice, byte-identical (diff-clean). Ghost-dir/manifest-less
dirs unchanged from the census above (2 ggen, 1 marketplace).

| metric | full-tree | top-level only (prior census scope) |
|---|---|---|
| total pack.toml | **439** | 403 |
| ggen/packs | 95 | 95 |
| ggen-marketplace/packs | 344 | 308 |
| unique [pack].name | **338** (30 nested manifests have no [pack].name) | 332 |
| unique dir names | 368 | 332 |
| cross-repo mirror pairs | 71 | 71 |
| requires entries | 105 | — |
| dangling requires | 2 (both in `ggen-marketplace/packs/chatman-ecosystem-v26-9-1-release-gate/pack.toml`: `canonical-pipeline`, `authority-separation`) | 0 |

What grew 403 → 439: +36 nested manifests, all under
`ggen-marketplace/packs/` (9 `dfcm-pack/families/*` application manifests,
21 `ggen-pack-spec-pack/qualification/{positive,negative}/*` fixture
manifests, 6 others) — ghost-dir applications plus marketplace additions,
not new top-level packs (top-level totals unchanged: 95 + 308).

Canonical numbers going forward: **439 manifests / 338 unique
[pack].name / 368 unique dir names / 71 mirror pairs**; top-level-only
scope remains **403 / 332 / 332 / 71**. Mirror-pair figure 72 (and the
derived "72 removable duplicates") is stale in favor of 71.

## Census re-count (lane census-post-strata, 2026-10-10) — supersedes the 2026-10-09 re-count above

Method: full recursive walk of `ggen/packs` + `ggen-marketplace/packs` (no depth
limit), `[pack].name` parse (fallback: dir basename — zero manifests needed the
fallback); two runs, diff-clean (deterministic). Requires counted at top level
only (pre-first-`[[` table), i.e. `[capabilities].requires`, excluding gate-local
`[[gate]].requires`.

| metric | value (was 2026-10-09) |
|---|---|
| total pack.toml | **444** (439) |
| ggen/packs | 95 (95) |
| ggen-marketplace/packs | **349** (344) |
| top-level manifests | **408** (403) — +5 strata packs; nested unchanged at 36 |
| unique `[pack].name` | **373** (338) |
| unique dir basenames | **373** (368) |
| cross-repo mirror pairs | 71 (71) |
| manifests without `[pack].name` | **0** (30) |
| top-level requires entries | **104**, **71 distinct URNs**, **0 dangling** (105 entries / 2 dangling) |

Growth 439 → 444: the 5 new `strata-{protocol,temprun,cas,signer,stratus}-pack`
manifests (top-level, ggen-marketplace). The 14 `dfcm-pack/families/*` manifests
now all carry `[pack].name` (prior count reported 30 nested manifests nameless;
0 today). Prior "2 dangling" (`canonical-pipeline`,
`authority-separation` in `chatman-ecosystem-v26-9-1-release-gate`) are
`[[gate]].requires` bare capability references, not pack-level URN requires —
excluded by scope; pack-level dangling is 0.

Strata capability chain compose-verified: `strata-protocol` provides only;
`strata-temprun`/`strata-cas`/`strata-signer` each require
`urn:ggen:pack:strata-protocol-pack`; `strata-stratus` requires temprun +
protocol. All 5 edges resolve against the corpus (0 dangling).

Canonical numbers going forward: **444 manifests / 373 unique names / 373 unique
dir basenames / 71 mirror pairs / 104 requires (0 dangling)**. The 2026-10-09
figures (439/338/368/71) and the original 439/332/71 header figures are both
superseded.
