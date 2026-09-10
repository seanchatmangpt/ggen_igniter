# Evaluate an `Ash.Notifier.load/2` generation pack

## Status

PLANNED / NOT STARTED.

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
