# ASH-IDIOM-AUDIT

Standing: PARTIAL

Audit of `priv/ggen/ash-*` packs against Ash best practices. Fixes touch ontology and
templates only; the coordinator regenerates and gates. Nothing here was compiled or run.

## Packs

| pack | role |
|---|---|
| ash-lifecycle-pack-inprocess-dispatch-test | fixture-shaped resource/domain renderer |
| ash-igniter-api-pack | Igniter task composing resources (idiomatic surface) |
| ash-manufacture-pack | Igniter task composing upstream `ash.gen.*` |
| ash-notifier-load2-pack | `Ash.Notifier.load/2` snippet |

## Fixed

| pack | file:line | rule | fix |
|---|---|---|---|
| lifecycle | templates/resource.ex.eex:42 | explicit accept lists | `default_accept(:*)` replaced by the declared attribute names plus `belongs_to` FK names |

Pinned-bytes check: no file under `test/` asserts `default_accept` (grep over `test/`;
the `test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex` copy is outside the owned
files and still carries `:*`). `test/e2e/lifecycle_test.ex:205-219` pins
`attribute_writable?(true)` and `source_attribute(:customer_id)`, both left unchanged.
The in-process dispatch test uses this pack through `@stem_pack_name`; it asserts no
accept text (UNVERIFIED by run).

## Unfixed

| pack | file:line | rule | reason |
|---|---|---|---|
| lifecycle | templates/resource.ex.eex:55 | named intent actions | `:archive` is an empty `update` block; the ontology has no change facts, so adding bodies means a new vocabulary |
| lifecycle | ontology.ttl:113-133 | actions-first | bare CRUD defaults are ontology facts the e2e lifecycle test depends on |
| lifecycle | resource.ex.eex (whole) | policies, `authorize?: true` | no policy vocabulary; the pack is a declared shape corpus (moduledoc), not Ash proof |
| lifecycle | domain.ex.eex:44-48 | code interfaces on the domain | no interface vocabulary; ash-igniter-api-pack owns `aia:CodeInterface` |
| lifecycle | ontology.ttl:79-109 | identities | no identity facts; Customer `email` has no uniqueness |
| api | ontology.ttl:339-341 | default-deny policies | read policy is `authorize_if always()`, pinned by `test/ggen_igniter_ash_igniter_api_pack_test.exs:109` |
| api | ontology.ttl:295-360 | policies on every resource | Book has a read policy only and no `policy` extension fact; Author has none; adding facts shifts pinned counts |
| api | ontology.ttl:326 | relationships, not raw FK | `author` is declared as a relationship; no raw FK attribute (conforming) |
| api | templates/api_task.ex.eex:354 | `ash.gen.resource` options | primary key fixed to `--uuid-primary-key id`; no ontology fact for other kinds |
| api | templates/api_task.ex.eex:136 | calculations as modules | calculation `expr(...)` is inline, which is the correct form for a one-line expression |
| manufacture | templates/manufacture.ex.eex:65-85 | policies, identities, actions | delegates to upstream generators (`--default-actions`); no policy or identity facts |
| notifier-load2 | templates/notifier_load2.ex.eex:5 | notifier over pubsub | already an `Ash.Notifier` callback; no loose pubsub or `Ash.Signals` present |
| all | gates/*.rq | atomic updates | none of the four packs emits an update change; no read-modify-write found |

## Conforming

- No `Ash.Signals` or loose PubSub in any template.
- api pack renders explicit `accept [...]` per action, `identity`, `calculate`, aggregates,
  `define :name, action: :a` interfaces and multitenancy `strategy` plus `attribute`.
- api pack validations render as `validate present/match/compare`, not anonymous functions.

## See Also

- `priv/ggen/CLAUDE.md`
- `test/ggen_igniter_ash_igniter_api_pack_test.exs`
- `test/ggen_igniter_sync_inprocess_dispatch_test.exs`
