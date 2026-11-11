# `mix ggen_igniter.review_eval.seed`

Source: `lib/mix/tasks/ggen_igniter.review_eval.seed.ex`
(`Mix.Tasks.GgenIgniter.ReviewEval.Seed`). Status: **IMPLEMENTED** — every
flag below is verbatim from the task's `OptionParser.parse!/2` `strict:` list
(line 22).

```
mix ggen_igniter.review_eval.seed [--force] [--min-conf F] [--max N]
```

Seed the incident-eval corpus from git history (fix/revert mining).
Deterministic for a given HEAD; refuses to overwrite an existing corpus
without `--force`. Writes a seed receipt under
`.ggen_igniter/review-evals/seeds/`.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--force` | boolean | `false` | Overwrite an existing corpus (without it, an existing corpus is refused). |
| `--min-conf F` | float | `0.5` | Minimum confidence for mined cases. |
| `--max N` | integer | `50` | Maximum cases mined. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Corpus seeded (receipt counts + corpus digest printed). |
| 1 | Corpus already exists and `--force` was not given (`Mix.raise`: "corpus already exists at ... (use --force to overwrite)"). |
| 2 | Bad flag (OptionParser `parse!` — unknown flag raises). |

## Example

```
mix ggen_igniter.review_eval.seed --force --min-conf 0.7 --max 25
```
