# `mix ggen_igniter.review`

Source: `lib/mix/tasks/ggen_igniter.review.ex` (`Mix.Tasks.GgenIgniter.Review`).
Status: **IMPLEMENTED** — every flag below is verbatim from the task's
`OptionParser.parse/2` `strict:` list (lines 46–55) and the moduledoc.

```
mix ggen_igniter.review --base REF [--head REF] [--verifiers N]
                        [--round N] [--review-id ID] [--json] [--help]
```

Runs one review round (L2 review core) over the diff between `--base` and
`--head`, delegating 100% to `GgenIgniter.Review`. The Mix task is parsing and
envelope only — no review logic lives here.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--base REF` | string | `HEAD` | Git ref to diff against. Without `--head`, runs `git diff --unified=3 REF` (working tree). |
| `--head REF` | string | *(none)* | Optional second ref; with it the task runs `git diff --unified=3 base head`. |
| `--verifiers N` | integer | `3` | Verifier count M; the core pads with neutral abstainers, so with no injected verifiers every finding is rejected (fail closed). Must be `>= 1`. |
| `--round N` | integer | `1` | Review round number; drives cross-round repeat suppression and `rounds.jsonl` history. |
| `--review-id ID` | string | `current` | Persistence key under `.ggen_igniter/reviews/<ID>/`. |
| `--json` | boolean | `false` | The round doc as one JSON document on stdout. |
| `--help` | boolean | `false` | Print usage (alias `-h`). |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Round completed with no POSTED findings (clean, or all suppressed). |
| 1 | Round completed but posted findings remain — or a typed refusal (`GIT_DIFF_FAILED`: bad diff refs). |
| 2 | Bad flags or unresolvable input (`--verifiers < 1`, unknown flag). |

## Example

```
mix ggen_igniter.review --base main --head HEAD --round 2 --review-id my-feature
```
