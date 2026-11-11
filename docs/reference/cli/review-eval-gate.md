# `mix ggen_igniter.review_eval.gate`

Source: `lib/mix/tasks/ggen_igniter.review_eval.gate.ex`
(`Mix.Tasks.GgenIgniter.ReviewEval.Gate`). Status: **IMPLEMENTED** — every
flag below is verbatim from the task's `OptionParser.parse!/2` `strict:` list
(lines 22–23).

```
mix ggen_igniter.review_eval.gate --seal --run-id ID
mix ggen_igniter.review_eval.gate --run-receipt PATH [--surface-tolerance N]
```

Seal or adjudicate against the incident-eval baseline
(`GgenIgniter.ReviewEval.Gate.seal/1` / `.admit/1`).

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--seal` | boolean | `false` | Seal mode: with `--run-id ID`, seals the baseline from run ID's receipt. |
| `--run-id ID` | string | *(none)* | The run receipt id to seal from (required with `--seal`). |
| `--run-receipt PATH` | string | *(none)* | Adjudicate mode: admit against the run receipt at PATH. |
| `--surface-tolerance N` | integer | `1` | Adjudicate mode only: allowed surface divergence before refusal. |

Modes are exclusive: `--seal --run-id` seals; `--run-receipt` adjudicates;
neither → usage error (exit 2).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Admit (seal succeeded, or `ADMITTED` with details). |
| 1 | Refuse (`REFUSED <reason>` from `Gate.admit/1` — e.g. digest mismatch, non-ancestor head). |
| 2 | Invocation/config error: missing baseline, missing run receipt, seal refusal, digest mismatch, non-ancestor head, or neither mode's flags given. |

## Example

```
mix ggen_igniter.review_eval.gate --run-receipt .ggen_igniter/review-evals/run-261020-abc1234/receipt.json
```
