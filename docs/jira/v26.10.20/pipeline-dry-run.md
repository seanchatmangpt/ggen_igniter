# Pipeline Dry Run — v26.10.20 (lane C16)

Date: 2026-10-20. Read-mostly lane; only this file written. No git mutations, no mocks.

## Run

```
pwd && git rev-parse --abbrev-ref HEAD
# /Users/sac/ggen_igniter, main

MIX_BUILD_ROOT=_build-lane-c16 mix compile          # exit 0
MIX_BUILD_ROOT=_build-lane-c16 mix ggen_igniter.review.pipeline \
  --base b514bf510196190040a391bf749fe6da5ec12ae3 \
  --epoch v26.10.20-c16-dryrun
```

Base = `b514bf5` (`git merge-base origin/main main`), HEAD = `1a6e60d` at run time.

## Outcome

**Status: BLOCKED at stage 1 `:epoch_check`.**

- Stage 0 `:base_integrity` — **pass** (real git: `rev-parse --verify` exit 0,
  `merge-base --is-ancestor` exit 0, HEAD `1a6e60d6fed9c2adb06a2c097bbc83e8529f007e`).
- Stage 1 `:epoch_check` — **refused**, typed reason:

```
first_block: epoch_check ["epoch_check_error", ["refused_epoch_check",
  {"code": "watermark_not_found",
   "detail": "no watermark stamped for epoch v26.10.20-c16-dryrun; run
              mix ggen_igniter.epoch.watermark --epoch v26.10.20-c16-dryrun
              at the boundary"}]]
```

An earlier invocation without `--epoch` refused at the same stage with
`["no_epoch", "opts[:epoch] must be a non-empty binary epoch id"]` — invocation
guard fired before the watermark lookup. Stages 2-7 (`risk_tier`, `build_gate`,
`fanout_review`, `security_block`, `convergence_cap`, `incident_eval`) never ran;
short-circuit on first refusal is confirmed working.

Note: the task process exited 0 despite status BLOCKED (documented CLI
`--json` contract says exit 1 on BLOCKED; observed exit code of the piped
shell was 0). Flagging as an observed divergence between the moduledoc exit
law and the human-output path — UNVERIFIED whether this is intended.

## Receipts on disk

`.ggen_igniter/receipts/pipeline/pl-1792521618-8899/`:
`landing-receipt.json`, `stage-0-base_integrity.json`, `stage-0-epoch_check.json`.

## Current pipeline standing

ALIVE through stage 1; BLOCKED at `:epoch_check` on
`refused_epoch_check/watermark_not_found` — the epoch watermark for this epoch
label has not been stamped (remediation named in the refusal: run
`mix ggen_igniter.epoch.watermark --epoch <label>` at the boundary). This is
the expected concurrent-landing BLOCK, not a pipeline defect.

## landing-receipt.json

```json
{
  "epoch": "v26.10.20-c16-dryrun",
  "first_block": {
    "reason": [
      "epoch_check_error",
      [
        "refused_epoch_check",
        {
          "code": "watermark_not_found",
          "detail": "no watermark stamped for epoch v26.10.20-c16-dryrun; run mix ggen_igniter.epoch.watermark --epoch v26.10.20-c16-dryrun at the boundary"
        }
      ]
    ],
    "stage": "epoch_check"
  },
  "run_id": "pl-1792521618-8899",
  "receipts_dir": "/Users/sac/ggen_igniter/.ggen_igniter/receipts/pipeline/pl-1792521618-8899",
  "stages": [
    {
      "base_sha": "b514bf510196190040a391bf749fe6da5ec12ae3",
      "finished_at": "2026-10-20T18:40:18Z",
      "order": 0,
      "output": {
        "commands": [
          {"command": "git rev-parse --verify b514bf510196190040a391bf749fe6da5ec12ae3", "duration_ms": 13, "exit": 0, "stdout_tail": "b514bf510196190040a391bf749fe6da5ec12ae3\n"},
          {"command": "git merge-base --is-ancestor b514bf510196190040a391bf749fe6da5ec12ae3 HEAD", "duration_ms": 14, "exit": 0, "stdout_tail": ""},
          {"command": "git rev-parse HEAD", "duration_ms": 15, "exit": 0, "stdout_tail": "1a6e60d6fed9c2adb06a2c097bbc83e8529f007e\n"}
        ]
      },
      "reason": null,
      "stage": "base_integrity",
      "status": "pass",
      "worktree_sha": "1a6e60d6fed9c2adb06a2c097bbc83e8529f007e"
    },
    {
      "finished_at": "2026-10-20T18:40:18Z",
      "order": 0,
      "output": null,
      "reason": [
        "epoch_check_error",
        [
          "refused_epoch_check",
          {
            "code": "watermark_not_found",
            "detail": "no watermark stamped for epoch v26.10.20-c16-dryrun; run mix ggen_igniter.epoch.watermark --epoch v26.10.20-c16-dryrun at the boundary"
          }
        ]
      ],
      "stage": "epoch_check",
      "status": "refused"
    }
  ],
  "status": "BLOCKED"
}
```

## See Also

- `lib/ggen_igniter/landing_pipeline.ex`, `lib/ggen_igniter/landing_pipeline/stage.ex`
- `docs/architecture/adr/ADR-013-landing-pipeline-staged-composition.md`
