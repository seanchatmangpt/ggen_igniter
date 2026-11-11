# ADR-013: Landing Pipeline — Staged Composition Behind a Behaviour

Status: Accepted (2026-10-20). Order family `docs/jira/v26.10.20/`, branch
`main`. Evidence citations are to `lib/ggen_igniter/landing_pipeline.ex` and
`test/ggen_igniter_landing_pipeline_test.exs` as they exist on disk this
date.

## Context

Review in this repository is currently ad-hoc and advisory. The last
formal review receipt dates to 2026-08-27; since then every review pass
(`docs/reviews/`, the ggen-reviewer agent, `review-round`) has produced
findings without a machine-checkable receipt tying the finding corpus to a
landing decision. Meanwhile the gates — `GgenIgniter.GateVerify` and the
`gate` skill — verify that compile/test/receipt checks ran, but verify is
not review: a diff can pass every gate while carrying defects the gates
were never designed to look for (security surface, convergence budget,
incident regressions, unclassified risk).

The raw material for a real review pipeline already exists as independent
modules and workflows: risk-tier classification (`risk-tier.yml`,
`GgenIgniter.Review`), fan-out adversarial review (`ggen-reviewer`,
`review-round`), security review (`GgenIgniter.SecurityReview`),
convergence capping (`GgenIgniter.Convergence`), and incident/eval
corpus scoring (`GgenIgniter.ReviewEval`). What is missing is not any one
layer but the composition: nothing forces a candidate landing through all
of them in a fixed order with a receipt per layer.

## Decision (IMPLEMENTED — pipeline; PARTIAL_ALIVE — stage modules)

Five review layers compose as `GgenIgniter.LandingPipeline.Stage`
implementations under a fixed order 0–7 owned by `GgenIgniter.LandingPipeline.run/1`
(`lib/ggen_igniter/landing_pipeline.ex:71-79` for the registry, `:84-96`
for `run/1`):

| order | stage |
|---|---|
| 0 | `base_integrity` (implemented in `landing_pipeline.ex:100-150`, not a stage module) |
| 1 | `EpochCheck` |
| 2 | `RiskTier` |
| 3 | `BuildGate` |
| 4 | `FanoutReview` |
| 5 | `SecurityBlock` |
| 6 | `ConvergenceCap` |
| 7 | `IncidentEval` |

1. **Behaviour, not convention.** Each stage implements
   `GgenIgniter.LandingPipeline.Stage` (`name/0`, `order/0`, `run/1`) and
   returns one of exactly three typed results: `{:pass, receipt}`,
   `{:block, reason, receipt}`, or `{:refused, reason}` — anything else is
   `{:bad_stage_return, other}` (`landing_pipeline.ex:219-220`). No
   boolean-or-raise convention; the result is the contract.
2. **Fixed, load-bearing order.** The registry order is not a scheduling
   convenience. **Risk tier (order 2) precedes fan-out review (order 4)**:
   the review width is chosen only after the change has been classified, so
   a high-risk diff can never select its own reviewers
   (`landing_pipeline.ex:10-13`). `Enum.reduce_while/3` short-circuits on
   the first `:block`/`:refused` (`:167-175`) — later stages never run once
   an earlier gate refuses.
3. **Fail-closed stage resolution.** Every registry module atom goes
   through `Code.ensure_loaded/1`; a module that does not exist is the
   typed refusal `{:refused, {:stage_module_missing, name}}`
   (`landing_pipeline.ex:195-202`) — never a silent skip. A missing stage
   is a verdict, not a crash.
4. **Receipts at every stage.** Per-stage receipts are written to
   `<receipts_dir>/<run_id>/stage-<order>-<name>.json` and the final report
   to `landing-receipt.json` (`landing_pipeline.ex:277-303`). The final
   status is `"ALIVE"` only when EVERY stage — including stage 0 — passed
   AND every embedded output is real (`Stage.capture/3` shape: non-empty
   `command`, integer `exit`, binary `stdout_tail`, non-negative
   `duration_ms`, `landing_pipeline.ex:251-267`). A `:pass` with empty
   embedded output is invalid and BLOCKS (`{:invalid_stage_output, name}`)
   — a vacuous pass can never mint ALIVE (`:207-211`). Exit law mirrors
   `mix ggen_igniter.epoch.check`: `{0, "ALIVE"}`, `{1, "BLOCKED"}`,
   `{2, invalid_invocation}` (`:54-58`, `:304`).
5. **Injection seam, not a config escape.** `opts[:stages]` replaces the
   fixed registry with real behaviour implementations — still sorted by
   `order/0`, still short-circuiting (`:155-158`). Production callers pass
   nothing and get the fixed registry.

## Consequences

- **Honest standing: PARTIAL_ALIVE until every stage module lands.** The
  seven concrete stage modules (`EpochCheck`, `RiskTier`, `BuildGate`,
  `FanoutReview`, `SecurityBlock`, `ConvergenceCap`, `IncidentEval`) are
  other lanes' files. Until they land, real runs refuse
  `stage_module_missing` at the first absent one — by design, not
  defect. The pipeline is complete when its own tests pass; a missing
  stage is a verdict, never a skip.
- **The fixed order constrains future stages.** Any new review layer must
  declare its place in the 0–7 order and accept the precedence it implies;
  inserting a stage between risk tier and fan-out review changes who
  reviews what, so registry edits are decisions, not refactors.
- **Review becomes receipted.** A landing either carries a per-stage
  receipt chain proving every layer ran with real output, or it carries a
  typed refusal naming the first missing/blocked layer. The 2026-08-27
  receipt-gap class is closed structurally.
- Gates keep their role: stage 3 (`BuildGate`) composes the existing
  verification gates into the pipeline; it does not replace or weaken
  them.

## Falsifier suite

`test/ggen_igniter_landing_pipeline_test.exs` drives the real pipeline over
injected real stage modules (Chicago: real modules, real `System.cmd` git
calls, real receipt files on disk): ALIVE requires all passes with real
embedded output; the first block short-circuits later stages; a pass with
empty embedded output blocks as `{:invalid_stage_output, _}`; a missing
stage module refuses `{:stage_module_missing, _}`; base drift / non-ancestor
base / missing base each produce the typed stage-0 refusal; the exit-code
law (0/1/2) is asserted on real return tuples.

## Evidence

`lib/ggen_igniter/landing_pipeline.ex` (registry `:71-79`, `run/1` `:84-96`,
base integrity `:100-150`, stage drive `:154-223`, realness law `:251-267`,
final receipt `:271-306`),
`lib/ggen_igniter/landing_pipeline/stage.ex`,
`test/ggen_igniter_landing_pipeline_test.exs`.

Real test run (this date):

```
$ MIX_BUILD_ROOT=_build-int-docs mix test test/ggen_igniter_landing_pipeline_test.exs
Running ExUnit with seed: 508646, max_cases: 32
Excluding tags: [:integration, :requires_qlever_server]

........
Finished in 0.3 seconds (0.3s async, 0.00s sync)
8 tests, 0 failures
```
