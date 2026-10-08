# Ticket 02: igniter/ash/spark version conformance (v26.9.10)

## Summary

Real evidence-backed resolution of the three DoD items in
`docs/jira/v26.9.10/02-IGNITER-ASH-SPARK-VERSION-CONFORMANCE.md`:

1. Decide whether to bump the `igniter` dependency.
2. Audit `Ash.Notifier` usage in this repo's docs/templates.
3. Compare `mix ash.set.domains` against this repo's own domain-generation logic.

The work was done as an A/B test-suite comparison at igniter 0.8.3 vs 0.8.4
(not a changelog read), a real `grep` sweep for `Ash.Notifier`, and a real
read of `deps/ash/lib/mix/tasks/ash.set.domains.ex` against
`lib/ggen_igniter/doctor_fixes.ex`. The merge commit lands the completed
ticket doc; no application code changed.

## Status

Done — already merged/committed (merge commit `895674c` into the target
branch; content commit `3cbe5e1`).

## Commits

- `895674c` merge: ticket 02 igniter/ash/spark version conformance (v26.9.10)
- `3cbe5e1` docs(jira): close 02-IGNITER-ASH-SPARK-VERSION-CONFORMANCE with real evidence

## Changes

- Updated `docs/jira/v26.9.10/02-IGNITER-ASH-SPARK-VERSION-CONFORMANCE.md`
  Status from "PLANNED / NOT STARTED" to "DONE" with the full evidence trail
  (101 insertions, 1 deletion) — this is the only file touched by either
  commit; no `mix.lock` diff was committed (lock is back to its prior state).
- **Version-bump decision: REFUSED, evidence-backed.** `mix deps.update igniter`
  resolved `0.8.3 => 0.8.4` (plus transitive `spitfire 0.4.0 => 0.4.1`,
  `mint 1.9.3 => 1.10.0`). `mix compile --warnings-as-errors` stayed clean at
  0.8.4, but a real A/B test run (full suite at 0.8.4 → `git checkout --
  mix.lock` back to 0.8.3 → re-run same files → forward to 0.8.4 again)
  isolated a reproducible regression: all 5 tests in
  `test/ggen_igniter_ash_gen_core_alignment_test.exs` that compose
  `ash.gen.base_resource` then `ash.gen.resource` in one `Igniter.Test` run
  raise `The base module <Mod> is not in the list of base resources` (via
  `Igniter.compose_task/4`, `ash 3.33.1` `ash.gen.resource.ex:153`) at 0.8.4,
  and pass clean at 0.8.3.
- Also noted, not acted on: `test/ggen_igniter_ash_task_coverage_test.exs`'s
  "version scope of the envelope" test fails at 0.8.4 because its own
  `@known_version_skew` list still expects `:igniter` to be skewed, but at
  0.8.4 the repo and its fixture resolve identically — a self-correcting
  signal, left unedited since the bump itself is refused.
- Also disclosed as unrelated environmental flakiness (explicitly not a
  version-bump finding): 3 `ExUnit.TimeoutError`s in
  `test/ggen_igniter_sync_inject_test.exs` on the first full-suite run, and
  one run's output clobbered by a concurrent unrelated process writing to
  shared `/tmp`; re-running that test file alone passed 9/9 in 66s.
- **Decision applied**: `mix.lock`'s `igniter` pin left at `0.8.3` (confirmed
  via `git checkout -- mix.lock && mix deps.get`, `grep -n '"igniter"'
  mix.lock` shows `0.8.3`); `mix.exs:99`'s `{:igniter, "~> 0.8"}` constraint
  unchanged.
- **Ash.Notifier audit: not applicable.** Real
  `grep -rn "Ash\.Notifier\|@behaviour Ash\.Notifier\|notify(\|requires_original_data?\|def load("`
  over `docs/integrations/ash/` and `priv/ggen/*/templates/*.ex.eex` returned
  zero matches (grep exit code 1) — no page or template in this repo
  implements or documents `Ash.Notifier` semantics.
- **`mix ash.set.domains` comparison: no gap found.** Real read of
  `deps/ash/lib/mix/tasks/ash.set.domains.ex` (its `igniter/2` calls
  `Ash.Mix.Tasks.Helpers.discover_domains/1` then
  `Igniter.Project.Config.configure(igniter, "config.exs", app_name,
  [:ash_domains], domains)`) against this repo's
  `lib/ggen_igniter/doctor_fixes.ex` (`ash_domains_rule/0`,
  `fix_ash_domains!/1`, `rewrite_ash_domains!/3`, lines ~558-767, using
  `Igniter.Project.Config.modify_config_code/4` on the same `[:ash_domains]`
  key path at `doctor_fixes.ex:756-761`). Both converge on the identical
  config-key mechanism; the domain-rendering template
  `test/fixtures/ash-lifecycle-pack/templates/domain.ex.eex` covers a
  disjoint concern (rendering `Ash.Domain` module bodies, not config
  registration). No follow-up ticket needed.

## Verification

As stated in commit `3cbe5e1`'s message (this session, real output):

- `mix compile --warnings-as-errors`: clean.
- `mix test`: 20 doctests / 42 properties / 868 tests; 7 pre-existing
  failures (rename/rewrite refactor tests, ash.set.domains/ash.install
  alignment, manufacture-pack idempotence) reproduced identically at both
  igniter 0.8.3 and 0.8.4, confirmed unrelated to this ticket's scope.
- `mix format --check-formatted`: flags 2 pre-existing unformatted files
  (`lib/mix/tasks/ggen_igniter.doctor.ex`,
  `test/mix/tasks/ggen_igniter.frontier_release_plan_test.exs`), neither
  touched this session.
- Mock-hygiene grep: zero matches.
- Only file changed across both commits:
  `docs/jira/v26.9.10/02-IGNITER-ASH-SPARK-VERSION-CONFORMANCE.md`; `mix.lock`
  confirmed back to its committed state (no diff).

## Related

- Closes DoD tracked in `docs/jira/v26.9.10/02-IGNITER-ASH-SPARK-VERSION-CONFORMANCE.md`.
- Commit `3cbe5e1` references `Claude-Session:
  https://claude.ai/code/session_01Q9CxAziKRC59z9Z1YVQ2NW`.
- No PR number stated in either commit subject.
