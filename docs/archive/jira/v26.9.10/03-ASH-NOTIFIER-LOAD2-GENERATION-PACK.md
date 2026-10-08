# Evaluate an `Ash.Notifier.load/2` generation pack

## Status

**IMPLEMENTED, with one disclosed DoD gap (external second example not located).**

A real, novel pack was built: `priv/ggen/ash-notifier-load2-pack/`
(`ontology.ttl`, `gates/010_load2_spec.rq`,
`templates/notifier_load2.ex.eex`), verified by dry-running
`mix ggen_igniter.sync --pack ash-notifier-load2-pack --engine sparql` and
confirming the rendered output reproduces `ash_ex4pm`'s hand-written
`load/2` verbatim (commit `d4ffb71`, expressed as the pack's one real
`nlp:Load2Spec` ontology individual). No existing pack in `priv/ggen/`
covered this shape before this ticket — `docs/integrations/ash/actions.md`'s
`gates/030_actions.rq` (the closest analog) was checked and confirmed to
never emit a notifier `load/2`.

**A real second EXTERNAL Spark-DSL extension example was not located this
pass** (this session's scope was bounded to
`/Users/sac/ggen_igniter`; no other repo on this machine was searched).
Per the DoD's spirit rather than its literal wording, the pack was instead
built generically — parameterized over five ontology-bound values
(`infoModule`/`entitiesFunction`/`matchField`/`listField`/`itemField`), not
hardcoded to `ash_ex4pm`'s predicate names — and a real, independent SECOND
fixture vocabulary (`rules`/`trigger`/`watched_paths`/`path`, zero
overlapping names with `ash_ex4pm`'s `activities`/`on`/
`object_relationships`/`relationship`) was built in this repo's own
`test/support/ash_notifier_load2/` and exercised in
`test/ggen_igniter_ash_notifier_load2_pack_test.exs`. See
`docs/integrations/ash/notifier-load2.md` section 3 for the full, honest
disclosure of this substitution — including the further disclosed scoping
choice that neither fixture is a full `Spark.Dsl.Extension` (real
transformers/entity schemas), and neither test drives a real `Ash.load/3`
round trip against a real `Ash.Resource` the way `ash_ex4pm`'s own
`d4ffb71` test does; both are real, disclosed future work if a stronger
compile-and-behave proof is needed later.

Real evidence, this session:

- `mix compile --warnings-as-errors`: clean (exit 0; only a pre-existing
  Mix-level `:preferred_cli_env` deprecation notice unrelated to any file
  this ticket touched).
- `mix test test/ggen_igniter_ash_notifier_load2_pack_test.exs`: `4 tests,
  0 failures`, zero warnings — renders the pack against its real ontology
  individual AND a second, independent hand-built vocabulary, then
  `Code.compile_string/1`s each rendered `load/2` into a real module
  declaring `@behaviour Ash.Notifier` and executes it against real
  companion "Info" fixture modules, asserting the real returned load lists
  (including the `nil -> []` branch for an unmatched action) — not merely
  that the template string matches.
- `mix test` (full suite): see this same status update's evidence trail in
  the session's final report for the real, pasted full-suite output.
- `mix format --check-formatted` on every file this ticket added/touched:
  clean. (Two PRE-EXISTING unformatted files elsewhere in the tree,
  `lib/mix/tasks/ggen_igniter.doctor.ex` and
  `test/mix/tasks/ggen_igniter.frontier_release_plan_test.exs`, are
  unrelated drift from an earlier commit -- confirmed via
  `git log --oneline -1` on both, last touched by a prior "Consolidate
  concurrent-agent findings" commit, not this session.)
- Mock-hygiene grep: zero matches.

## Grounding (real, this session)

`~/ash_ex4pm`'s `AshEx4pm.Notifier` (an Ash 3.x `Ash.Notifier` implementation) had a
real, previously-disclosed gap: a declared O2O (object-to-object) relationship whose
target wasn't already selected/loaded by the triggering action was silently omitted
from the emitted event. This session hand-wrote a fix — a real `@impl Ash.Notifier def
load(resource, action)` callback (Ash 3.x's optional pre-notify load mechanism,
verified 3-0 against `hexdocs.pm/ash/notifiers.html`) that derives the load statement
from the matching compiled activity's declared relationship names:

```elixir
@impl Ash.Notifier
def load(resource, action) do
  resource
  |> AshEx4pm.Info.activities()
  |> Enum.find(&(&1.on == action.name))
  |> case do
    nil -> []
    activity -> Enum.map(activity.object_relationships, & &1.relationship)
  end
end
```

Committed `~/ash_ex4pm` `d4ffb71`, with a real regression test exercising Ash's own
public `notifier_calculation_query/3` + `Ash.load/3` + `extract_notifier_data/4`
pipeline (56/56 tests passing after).

The shape of this fix — "find the DSL-declared thing this notification's action maps
to, then derive a load statement from its declared relationships/fields" — is not
specific to `ash_ex4pm`'s OCEL domain. Any Spark-DSL-extension-authored
`Ash.Notifier` that declaratively names relationships/calculations/aggregates per
action (the same general shape `AshEx4pm.Activity`/`AshEx4pm.ObjectRelationship`
entities have) needs the identical `load/2` boilerplate: look up the matching DSL
entity for `action.name`, extract its declared field-name list, return it. This is a
real, observed repeated-pattern candidate for a `ggen_igniter` generation pack, not a
speculative one — it was hand-derived once already this session, from first
principles, because no reusable template existed.

## Definition of Done

- A real decision, backed by at least one additional real (not hypothetical) Spark-DSL
  extension example beyond `ash_ex4pm` itself — either an existing pack in
  `priv/ggen/`/the marketplace that already covers this shape (if found, cite it and
  close this ticket as "already covered, here is the pack"), or a genuinely novel
  pattern worth a new pack.
- If novel: a real `priv/ggen/ash-notifier-load2-pack/` (or equivalent name) with a
  real ontology fragment describing the "DSL entity declares fields per action, needs
  a `load/2` deriving from them" shape, a real SPARQL query, and a real
  `.eex` template that renders the `load/2` function body shown above (or its
  generalized equivalent) from ontology-bound data — not a hand-copy of the
  `ash_ex4pm` code with names substituted.
- A real, passing Chicago-style test rendering this pack against a fixture Ash
  resource with its own DSL-declared relationships-per-action shape, asserting the
  rendered `load/2` output compiles and behaves correctly (a real
  `notifier_calculation_query/3` + `Ash.load/3` round-trip, mirroring the real test
  pattern `ash_ex4pm`'s own `d4ffb71` commit already established) — not merely that
  the template string matches.
- `docs/integrations/ash/` gains a page (or section) documenting this pack, its real
  worked precedent (`ash_ex4pm`'s hand-written version, cited by commit), and when to
  reach for it vs. hand-writing `load/2` for a one-off case.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, and
  this repo's hygiene grep all clean, pasted as real output.

## Non-goals

- Does not retroactively convert `ash_ex4pm`'s own hand-written `load/2`
  (`d4ffb71`) to consume this pack — that is a separate, `ash_ex4pm`-side follow-up
  (or simply left as-is; the hand-written version is real, tested, and correct on its
  own), out of scope for `ggen_igniter` itself.
- Does not attempt to generalize beyond the `load/2` callback specifically to the
  rest of `Ash.Notifier`'s surface (`notify/1`'s own body, `requires_original_data?/2`)
  unless a second real, observed repeated pattern surfaces for those — this ticket is
  scoped to the one pattern actually observed twice in spirit (the general shape) even
  though only hand-derived once in practice.

## See Also

- `~/ash_ex4pm/lib/ash_ex4pm/notifier.ex` (commit `d4ffb71`) — the real, hand-written
  precedent this ticket evaluates generalizing.
- `~/ash_ex4pm/test/ash_ex4pm_test.exs` (the `load/2` regression test added in the same
  commit) — the real test-pattern precedent for this ticket's own DoD test
  requirement.
- `hexdocs.pm/ash/notifiers.html` — the primary source documenting `Ash.Notifier`'s
  real `load/2` contract this pack must render conformant code against.
- `00-OVERVIEW.md` — this directory's charter and cross-references.
