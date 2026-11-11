# F2 Leg B — Lib-plane control (extended epoch court)

- Repo: /Users/sac/ggen_igniter (main @ 1a6e60d; scratch f59433af56a5870ab1f0b4bd4978499959dbf140)
- Scratch tree: `/tmp/epoch-f2-scratch-1792519751`; config.exs restored via `git -C <scratch> checkout --` before this leg
- Build root: `MIX_BUILD_ROOT=_build-lane-c15`
- Date: 2026-10-20

## Commands + output

```
git -C /tmp/epoch-f2-scratch-1792519751 checkout -- config/config.exs
printf '# F2-FALSIFIER unattributed post-epoch lib edit\n' >> /tmp/epoch-f2-scratch-1792519751/lib/ggen_igniter/task_contract.ex

MIX_BUILD_ROOT=_build-lane-c15 mix ggen_igniter.epoch.check --epoch f2-falsifier \
  --base-dir /tmp/epoch-f2-scratch-1792519751 --report /tmp/f2-legB-report.json
```

Exit code: **1**.

```
lib/ggen_igniter/task_contract.ex  →  "verdict": "REFUSED_LEGACY_EDIT"
whole-tree: standing=REFUSED admitted_generated=0 admitted_residue=0 refused=174
```

## Verdict

**CONTROL CONFIRMED (court refuses)** — the same edit class on the lib plane
is refused identically (`REFUSED_LEGACY_EDIT`, exit 1). Leg A is not a
loosening: the extended courts are strictly more refusal surface than the
legacy single-glob court, same verdict class both planes.

Note (one leg B execution detail, disclosed): the first leg B attempt ran
`mix` from inside the scratch dir and died on missing deps before the court
executed (Mix "Can't continue due to errors on dependencies", no report
produced); it was rerun from the checkout cwd with `--base-dir` pointing at
the scratch — that rerun is the recorded result.
