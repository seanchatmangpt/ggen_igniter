# `mix ggen_igniter.review.convergence`

Source: `lib/mix/tasks/ggen_igniter.review.convergence.ex`
(`Mix.Tasks.GgenIgniter.Review.Convergence`). Status: **IMPLEMENTED** — every
flag below is verbatim from the task's `OptionParser.parse/2` `strict:` list
(line 34) and its aliases.

```
mix ggen_igniter.review.convergence --sha SHA [--diff PATH] [--max-rounds N] [--json]
```

Thin CLI over `GgenIgniter.Convergence.run/2`. Round state machine per
content-sha: `ROUND_RUNNING -> ROUND_PASSED | ROUND_FIXED_ADVANCES |
REVIEW_ESCALATED`; terminal states are final — no round 4 ever
(`--max-rounds` overrides the cap for tests only). Rounds persist to
`<base_dir>/.ggen_igniter/reviews/<sha>/rounds.jsonl` via
`GgenIgniter.ReviewStore`.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--sha SHA` | string | *(required)* | Content-sha the rounds are keyed on. Missing → exit 2. |
| `--diff PATH` | string | *(none)* | Read a diff from PATH and pass it to the reviewer. |
| `--max-rounds N` | integer | cap (3) | Overrides the bounded-round cap; must be `>= 1`. |
| `--json` | boolean | `false` | One JSON document (`sha`, `final_state`, `rounds`) on stdout. |

Aliases: `-s` (`--sha`), `-d` (`--diff`), `-m` (`--max-rounds`).

## Scope note (honest)

The library-level default reviewer behind `GgenIgniter.Convergence.run/2` is
now a real deterministic critic: `GgenIgniter.Convergence.Critic.review/1`
(`lib/ggen_igniter/convergence/critic.ex`) — three mechanical rules over each
hunk's ADDED lines (`:formatting` trailing whitespace, `:dead_code`
`IO.inspect`/`dbg(`, `:missing_doc` a `defmodule` with no earlier
`@moduledoc` in the same hunk; the hunk-local window is disclosed in the
module's moduledoc). An injected `reviewer:` fn still overrides it.

This CLI task itself currently injects its own structural empty pass
(`lib/mix/tasks/ggen_igniter.review.convergence.ex`, the `reviewer:` fn in
`run/1`), so a run through the task reviews empty regardless of the diff.
Wiring the task's reviewer to the critic (or to `GgenIgniter.Review`
perspectives) is the remaining step, tracked in `docs/status.md`'s
convergence row — not silently extended here.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Passed (`final_state != review_escalated`). |
| 1 | Escalated (`review_escalated`). |
| 2 | Bad invocation (missing `--sha`, unknown flag, `--max-rounds <= 0`, or `Convergence.run/2` error). |

## Example

```
mix ggen_igniter.review.convergence --sha abc123... --diff /tmp/landing.diff --json
```
