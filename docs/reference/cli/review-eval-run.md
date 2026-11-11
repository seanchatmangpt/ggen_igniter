# `mix ggen_igniter.review_eval.run`

Source: `lib/mix/tasks/ggen_igniter.review_eval.run.ex`
(`Mix.Tasks.GgenIgniter.ReviewEval.Run`). Status: **IMPLEMENTED** — the
task's `OptionParser.parse!/2` `strict:` list is EMPTY (line 20): it accepts
no flags of its own; the moduledoc's `--reviewer-cmd` shape is passed
through to the `CaseRunner` adapter unvalidated.

```
mix ggen_igniter.review_eval.run [--reviewer-cmd "claude"]
```

Run the incident-eval corpus against the reviewer. Uses the default
`claude -p` adapter unless overridden via `--reviewer-cmd` (passed through
to `GgenIgniter.ReviewEval.CaseRunner`). Writes a run receipt under
`.ggen_igniter/review-evals/run-<ts>-<head7>/receipt.json` — always, even on
REGRESSED. The reviewer prompt sha is computed from the real
`.claude/agents/ggen-reviewer.md` content (sha256, hex) and recorded in the
receipt.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--reviewer-cmd` | string | *(none — default `claude -p` adapter)* | Passed through unvalidated by this task's (empty) strict list to the `CaseRunner` adapter. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Run completed and a run receipt was written (verdict may be REGRESSED — the receipt records it either way). |
| 1 | Corpus failed to load (`Corpus.load/1` error falls through the `with`, terminating the task). |

## Example

```
mix ggen_igniter.review_eval.run
```
