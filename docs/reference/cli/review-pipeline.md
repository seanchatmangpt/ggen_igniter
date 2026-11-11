# `mix ggen_igniter.review.pipeline`

Source: `lib/mix/tasks/ggen_igniter.review.pipeline.ex`
(`Mix.Tasks.GgenIgniter.Review.Pipeline`). Status: **IMPLEMENTED** — every
flag below is verbatim from the task's `OptionParser.parse/2` `strict:` list
(line 51) and the usage text.

```
mix ggen_igniter.review.pipeline --base REF [--epoch LABEL]
                                 [--out PATH] [--json] [--help]
```

CLI entry over `GgenIgniter.LandingPipeline.run/1` (delegates 100% —
flag-parsing only, zero business logic in the task). Runs stage 0
`:base_integrity` (real git: `rev-parse --verify`, `merge-base
--is-ancestor`, worktree-drift check) and then the FIXED ordered stage
registry — 1 `:epoch_check`, 2 `:risk_tier`, 3 `:build_gate`, 4
`:fanout_review`, 5 `:security_block`, 6 `:convergence_cap`, 7
`:incident_eval` — short-circuiting on the first block/refusal. The fixed
order is load-bearing: risk tier precedes fan-out width. Per-stage receipts
land in `.ggen_igniter/receipts/pipeline/<run_id>/stage-<order>-<name>.json`
plus `landing-receipt.json`.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--base REF` | string | *(required)* | The git base the landing is judged against. Missing → exit 2. |
| `--epoch LABEL` | string | *(none)* | Optional epoch label recorded in the report/receipt. |
| `--out PATH` | string | *(none)* | The final landing receipt is also written there. |
| `--json` | boolean | `false` | Exactly one JSON document on stdout (no trailing prose; halts directly). |
| `--help` | boolean | `false` | Usage text, exit 0. |

## Exit codes

The `mix ggen_igniter.epoch.check` exit law:

| Code | Meaning |
|---|---|
| 0 | Every stage passed with real embedded output (status ALIVE). |
| 1 | BLOCKED: base drift / first-stage block or refusal (typed JSON as the last line of stderr, and `landing-receipt.json` on disk). |
| 2 | Invalid invocation (e.g. missing `--base`, unknown flag; report JSON on stderr). |

## Example

```
mix ggen_igniter.review.pipeline --base main --epoch v26.10.20 --out /tmp/landing-receipt.json --json
```
