# Ticket 03: ash-notifier-load2-pack (v26.9.10)

## Summary

Adds `priv/ggen/ash-notifier-load2-pack/`, an ontology-driven ggen generation
pack that generalizes ash_ex4pm's hand-written `Ash.Notifier` `load/2` fix
(commit `d4ffb71`) -- "find the DSL-declared entity matching this
notification's action, then derive a `load/2` list from its declared field
names" -- into a reusable, parameterized generator. Merged into the target
branch via merge commit `16ab254`.

## Status

Done - already merged/committed.

## Commits

- `16ab254` merge: ticket 03 ash-notifier-load2-pack (v26.9.10)
- `958e12a` feat(pack): add ash-notifier-load2-pack (Ash.Notifier load/2 generation)

## Changes

- `priv/ggen/ash-notifier-load2-pack/ontology.ttl` -- one real
  `nlp:Load2Spec` individual expressing ash_ex4pm's precedent as data.
- `priv/ggen/ash-notifier-load2-pack/gates/010_load2_spec.rq` -- SPARQL gate
  validating the spec individual.
- `priv/ggen/ash-notifier-load2-pack/templates/notifier_load2.ex.eex` --
  EEx template parameterized over five ontology-bound values
  (`infoModule`/`entitiesFunction`/`matchField`/`listField`/`itemField`),
  not hardcoded to ash_ex4pm's predicate names.
- `docs/integrations/ash/notifier-load2.md` (144 lines added) -- the real
  worked precedent, the generalized shape, and an explicit disclosure that a
  second, independent EXTERNAL Spark-DSL extension example was not located
  in that session (scope was bounded to this repo) and what was substituted
  for it instead.
- `docs/jira/v26.9.10/03-ASH-NOTIFIER-LOAD2-GENERATION-PACK.md` (57 lines
  added) -- ticket's Status section updated with real evidence and the same
  disclosure.
- `test/ggen_igniter_ash_notifier_load2_pack_test.exs` (176 lines) --
  Chicago-style test: renders the pack against its real ontology individual
  AND a second, independent hand-built vocabulary
  (`rules`/`trigger`/`watched_paths`/`path`), then
  `Code.compile_string/1`s each rendered `load/2` into a real module
  declaring `@behaviour Ash.Notifier` and executes it against real
  companion "Info" fixture modules, asserting on the real returned load
  lists rather than on template-string matching.
- `test/support/ash_notifier_load2/ash_ex4pm_info_fixture.ex` (59 lines) --
  real Info fixture module mirroring ash_ex4pm's DSL-declared entity shape.
- `test/support/ash_notifier_load2/rules_info.ex` (39 lines) -- second,
  independent Info fixture module used to prove the pack isn't hardcoded to
  ash_ex4pm's naming.
- 8 files changed, 562 insertions(+), 1 deletion(-) total across the merge.

## Verification

Per the `958e12a` commit message (this session's stated evidence):

- `mix ggen_igniter.doctor --pack ash-notifier-load2-pack` -- all checks
  pass.
- A real dry-run/sync reproducing ash_ex4pm's `load/2` verbatim.
- `mix test test/ggen_igniter_ash_notifier_load2_pack_test.exs` -- 4 tests,
  0 failures, 0 warnings.
- `mix compile --warnings-as-errors` -- clean.
- Full `mix test` suite -- 875 tests, 7 pre-existing failures, all in
  `test/ggen_igniter_ash_manufacture_pack_test.exs`,
  `test/ggen_igniter_upstream_rename_blocker_test.exs`,
  `test/ggen_igniter_agent_guard_test.exs`,
  `test/ggen_igniter_base_refactors_test.exs`,
  `test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs` --
  stated as none touching this ticket's new files.
- `mix format --check-formatted` -- clean on every file this ticket added.
- Mock-hygiene grep -- zero matches (stated in commit message).

No CI evidence is stated in the commit messages; all verification above is
local/session-stated.

## Related

- Ticket doc: `docs/jira/v26.9.10/03-ASH-NOTIFIER-LOAD2-GENERATION-PACK.md`
- Prior precedent commit referenced: `d4ffb71` (ash_ex4pm hand-written fix)
- Session: `https://claude.ai/code/session_01Q9CxAziKRC59z9Z1YVQ2NW` (from
  `958e12a` commit message)
- Merge parents: `895674c` (base), `958e12a` (feature branch tip)
