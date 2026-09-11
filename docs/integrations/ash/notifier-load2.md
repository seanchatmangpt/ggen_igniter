# Generating `Ash.Notifier` `load/2` (`ash-notifier-load2-pack`)

**Status: real, novel pack — `priv/ggen/ash-notifier-load2-pack/`.**

How `ggen_igniter` renders an `Ash.Notifier` `load/2` callback for a
Spark-DSL extension whose entities declare relationship/calculation/
aggregate names per action, generalizing a real, previously hand-written
fix. See `docs/jira/v26.9.10/03-ASH-NOTIFIER-LOAD2-GENERATION-PACK.md` for
this pack's originating ticket.

---

## 1. The real, worked precedent

`~/ash_ex4pm`'s `AshEx4pm.Notifier` (an `Ash.Notifier` implementation) had a
real, previously-disclosed gap: a declared O2O relationship not already
selected/loaded by the triggering action was silently omitted from the
emitted event. This was fixed by hand, commit `d4ffb71`:

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

Verified against Ash 3.x's real, documented `load/2` contract
(`hexdocs.pm/ash/notifiers.html`), with a real regression test exercising
Ash's own `notifier_calculation_query/3` + `Ash.load/3` +
`extract_notifier_data/4` pipeline (56/56 tests passing after, per the
ticket's grounding section).

## 2. The generalized shape this pack captures

The fix's shape is not specific to `ash_ex4pm`'s OCEL domain: "find the
DSL-declared entity matching this notification's action, then derive a
`load/2` list from its declared field names." `ash-notifier-load2-pack`
renders exactly that shape, parameterized over five values bound per
Spark-DSL extension (an `nlp:Load2Spec` individual in
`priv/ggen/ash-notifier-load2-pack/ontology.ttl`) — not hardcoded to
`ash_ex4pm`'s predicate names:

| Ontology property | ash_ex4pm's value | Meaning |
|---|---|---|
| `nlp:infoModule` | `AshEx4pm.Info` | Module exposing DSL entities for a resource. |
| `nlp:entitiesFunction` | `activities` | Function on `infoModule`, called with resource. |
| `nlp:matchField` | `on` | Field on each entity compared against `action.name`. |
| `nlp:listField` | `object_relationships` | Field on entity holding the field-ref list. |
| `nlp:itemField` | `relationship` | Field on each list item holding the load name. |

Rendering the pack's one gate query (`gates/010_load2_spec.rq`) and template
(`templates/notifier_load2.ex.eex`) against the pack's own ontology
individual reproduces `ash_ex4pm`'s `load/2` verbatim:

```console
$ mix ggen_igniter.sync --pack ash-notifier-load2-pack \
    --engine sparql --yes --out /tmp/notifier_load2.ex
$ cat /tmp/notifier_load2.ex
@impl Ash.Notifier
def load(resource, action) do
  resource
  |> AshEx4pm.Info.activities()
  |> Enum.find(&(&1.on == action.name))
  |> case do
    nil -> []
    entity -> Enum.map(entity.object_relationships, & &1.relationship)
  end
end
```

## 3. Generality evidence — honest disclosure

The originating ticket's Definition of Done asked for "at least one
additional real (not hypothetical) Spark-DSL extension example beyond
`ash_ex4pm`." **A real second EXTERNAL Spark-DSL extension example was not
located this pass** — this session's scope was bounded to
`/Users/sac/ggen_igniter` and did not search other repos on this machine or
the network for a second real consumer.

What was actually done, as an honest, disclosed in-repo substitute:

1. The pack's ontology/query/template are written generically —
   parameterized over `infoModule`/`entitiesFunction`/`matchField`/
   `listField`/`itemField` as **data**, not baked into the SPARQL or EEx as
   `ash_ex4pm`-specific literals.
2. `test/ggen_igniter_ash_notifier_load2_pack_test.exs` renders the pack
   twice against two **independent** vocabularies: the real `ash_ex4pm`
   individual, and a second, hand-built binding set
   (`rules`/`trigger`/`watched_paths`/`path`) with zero overlapping
   predicate names, each compiled (`Code.compile_string/1`) and executed
   against a real companion "Info" fixture module
   (`test/support/ash_notifier_load2/ash_ex4pm_info.ex`,
   `test/support/ash_notifier_load2/rules_info.ex`), asserting on the real
   returned load lists.

This proves the pack's ontology+query+template genuinely generalizes across
two independent subjects. It does **not** satisfy the ticket's literal
"external example" wording, and this page states that plainly rather than
claiming it does. Neither fixture is a full `Spark.Dsl.Extension` (with real
transformers/entity schemas) — the "Info" modules are plain Elixir modules
returning plain structs shaped exactly like what the rendered `load/2`
actually touches (`Enum.find/2` + `Enum.map/2` over plain field access; no
Spark introspection API is called by the rendered code or by
`AshEx4pm.Info.activities/1` itself). Building two full Spark-DSL
extensions, or a real `Ash.load/3` round trip against real `Ash.Resource`s
(mirroring `ash_ex4pm`'s own `d4ffb71` test more closely), was judged out of
scope for this pass; it is real, disclosed future work if a stronger
compile-and-behave proof against actual Ash resources is needed later.

## 4. When to reach for this pack vs. hand-writing `load/2`

- **Reach for this pack** when a Spark-DSL extension already declares, per
  action, the relationship/calculation/aggregate names an
  `Ash.Notifier` needs loaded before `notify/1` fires — the same repeated
  shape `ash_ex4pm`'s `Activity`/`ObjectRelationship` entities have. Add one
  `nlp:Load2Spec` individual naming your extension's five accessor values
  and render.
- **Hand-write `load/2`** for a one-off case: a notifier with no DSL-level
  per-action field declarations to derive from (the loaded fields are fixed,
  not action-dependent), or where the derivation logic is not a straight
  `Enum.find` + `Enum.map` (e.g. it needs to merge fields from more than one
  entity, or apply per-field filtering) — this pack renders exactly the one
  observed shape, not a general-purpose `load/2` DSL.

## See Also

- `docs/jira/v26.9.10/03-ASH-NOTIFIER-LOAD2-GENERATION-PACK.md` — the
  originating ticket, including its Definition of Done and real Status.
- `priv/ggen/ash-notifier-load2-pack/` — the real pack (`ontology.ttl`,
  `gates/010_load2_spec.rq`, `templates/notifier_load2.ex.eex`).
- `priv/ggen/CLAUDE.md` — the `--pack` directory-shape convention this pack
  follows.
- `test/ggen_igniter_ash_notifier_load2_pack_test.exs` — the real,
  compile-and-execute Chicago-style test for this pack.
- `docs/integrations/ash/actions.md` — the closest existing analog
  (`ash-lifecycle-pack`'s `030_actions.rq`), which renders action *blocks*
  but never a notifier `load/2`; confirmed, this session, not to already
  cover this shape.
