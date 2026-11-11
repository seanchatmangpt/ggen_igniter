# F2 Leg A — Unattributed config-plane edit (extended epoch court)

- Repo: /Users/sac/ggen_igniter (branch main @ 1a6e60d; scratch from `git archive HEAD` = f59433af56a5870ab1f0b4bd4978499959dbf140)
- Scratch tree: `/tmp/epoch-f2-scratch-1792519751` (git-inited + committed inside the extraction — the court requires a git work tree; the checkout was never mutated)
- Executing code: working-tree `lib/ggen_igniter/epoch_freshness.ex` (multi-plane extension, uncommitted)
- Build root: `MIX_BUILD_ROOT=_build-lane-c15`
- Date: 2026-10-20

## Commands + output

```
# stamp (one watermark for all legs)
MIX_BUILD_ROOT=_build-lane-c15 mix ggen_igniter.epoch.watermark --epoch f2-falsifier --base-dir /tmp/epoch-f2-scratch-1792519751
# → exit 0; 174 files; implementation_globs:
#   ["lib/**/*.ex", "config/**/*.exs", "priv/repo/migrations/**/*.exs"]

printf '# F2-FALSIFIER unattributed post-epoch edit\n' >> /tmp/epoch-f2-scratch-1792519751/config/config.exs

MIX_BUILD_ROOT=_build-lane-c15 mix ggen_igniter.epoch.check --epoch f2-falsifier \
  --base-dir /tmp/epoch-f2-scratch-1792519751 --report /tmp/f2-legA-report.json
```

Exit code: **1** (designed refusal).

```
config/config.exs  →  "verdict": "REFUSED_LEGACY_EDIT"
config plane: {"counts":{"admitted_generated":0,"admitted_residue":0,"refused":3,"total":3},
               "glob":"config/**/*.exs","standing":"REFUSED","watermarked":true}
whole-tree: standing=REFUSED admitted_generated=0 admitted_residue=0 refused=174
```

## Verdict

**FALSIFIER CONFIRMED AS PASS (court refuses)** — the extended court binds the
config plane: a post-watermark config edit with no receipt/residue attribution
is refused `REFUSED_LEGACY_EDIT`, exit 1. Before the multi-plane law this path
was invisible (first court glob was `lib/**/*.ex` only). The migrations plane
(stamped, 0 files) reports standing ALIVE — a stamped empty plane does not
poison the tree.
