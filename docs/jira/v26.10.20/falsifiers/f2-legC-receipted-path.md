# F2 Leg C — Receipted path (extended epoch court, must-pass leg)

- Repo: /Users/sac/ggen_igniter (main @ 1a6e60d; scratch f59433af56a5870ab1f0b4bd4978499959dbf140)
- Scratch tree: `/tmp/epoch-f2-scratch-1792519751`; lib file restored before this leg
- Build root: `MIX_BUILD_ROOT=_build-lane-c15`
- Date: 2026-10-20

## Commands + output

```
git -C /tmp/epoch-f2-scratch-1792519751 checkout -- lib/ggen_igniter/task_contract.ex
mkdir -p /tmp/epoch-f2-scratch-1792519751/.ggen_igniter/receipts
jq -nc --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{id:"f2-receipted-leg-c", files:["lib/ggen_igniter/task_contract.ex"], standing:"alive", finished_at:$now}' \
  > /tmp/epoch-f2-scratch-1792519751/.ggen_igniter/receipts/f2-legC.jsonl

MIX_BUILD_ROOT=_build-lane-c15 mix ggen_igniter.epoch.check --epoch f2-falsifier \
  --base-dir /tmp/epoch-f2-scratch-1792519751 --report /tmp/f2-legC-report.json
```

Exit code: **1** (see "Overall standing" below).

```
lib/ggen_igniter/task_contract.ex → {"path": "...", "verdict": "ALIVE_GENERATED",
                                     "manufacture_receipt": "f2-receipted-leg-c"}
whole-tree: standing=REFUSED admitted_generated=1 admitted_residue=0 refused=173
```

## Verdict

**RECEIPTED PATH PASSES**: the post-watermark alive receipt flips the judged
file from `REFUSED_LEGACY_EDIT` to `ALIVE_GENERATED` with
`manufacture_receipt=f2-receipted-leg-c`; `admitted_generated` went 0 → 1.
The receipt-admission clause of the precedence chain works end to end on the
extended courts.

**Overall standing is still REFUSED (exit 1)** because the remaining 173
watermarked paths carry no post-epoch attribution — this is the court's
fail-closed design (every implementation byte must be attributed after the
boundary), not a leg failure. The leg's "must pass" criterion is the per-file
verdict on the receipted path, which is `ALIVE_GENERATED`. A whole-tree
ALIVE run would require receipts covering all 174 files.
