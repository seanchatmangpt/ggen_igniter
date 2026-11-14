# 02-GAP-REGISTER

Standing: UNVERIFIED

Source: `00-OVERVIEW.md` gaps G1-G8 plus every "Known gaps" bullet in
`P/fragments/L*-NOTES.md` (`P` = `/Users/sac/ggen-marketplace/packs/ash-a2a-app-pack`),
deduped by theme. Statuses are as of authoring; none re-verified by execution.

## Overview gaps

- G1 (OPEN; L19 designed, unrun): igniter cannot drive the pack. Close: `ggen_igniter.sync
  --pack` output equals `ggen sync run` byte-for-byte. Owner L19. L19 found sync already parses
  frontmatter; the missing piece is a Tera renderer (`pack_sync` task, sibling).
- G2 (OPEN; L19 delivered template, unrun): `--skip-ea-admission` required. Close: sync exits 0
  without the flag. Owner L19.
- G3 (PARTIAL; igniter side authored): pack hash change forces `rm ggen.lock`. Close: ggen
  `sync run --relock`. Owner L19 (igniter `pack_sync --relock` exists; ggen CLI change not).
- G4 (OPEN): dev/test uses `:legacy_compat`. Close: `:strict` profile with durable stores/keys.
  Owner L17/L09 (unassigned).
- G5 (PARTIAL): missing hddl_operator, authority/hooks, argument_mapping, `get?`, relationships,
  non-ETS layers, multi-domain agents. Owners L17 (skill/authority/hooks), L02, L09, L10.
  Close: term + template branch + gate + fixture each, then rendered.
- G6 (PARTIAL): mutation court per template. Owner L20 (shim script authored). Close: each
  shim court flips (exit 0 PASS) on a real run.
- G7 (PARTIAL): unknown ashType/duplicates/agent-without-domain gates. Owner L20 (040-047).
  Close: gates return 0 rows on FULL fixture and refuse a mutated one.
- G8 (OPEN): generated test lacks dispatch round-trip. Owner L20. Close: test calls
  `AshA2A.Dispatcher.dispatch/6` per read skill and passes.

## Cross-lane gaps

- Fragment wiring: no lane edits `resource.ex.tmpl`/`domain.ex.tmpl`; every `fragments:` line
  is a coordinator edit, conditional on lane facts. Owner coordinator. Close: FULL fixture
  compiles with all fragments wired.
- Gate coverage of legacy edges: gates still read legacy `aap:action` only (L07_010, L07_030,
  L10_010/020, L14_010/020/030, L17_100/103/104/106/129, L20_042/045, L11_bridge_shape,
  L16_090, L05_validation_wellformed, L02_040) or legacy `aap:attribute` only (L20_040,
  L17_104, L11_bridge_shape, L02_030, L08_010, L04_030, L05 key/attr gates, L07_040, L03_030).
  Owner E2 follow-up. Close: each accepts the new edge kinds; FULL fixture yields 0 rows.
- Skills targeting manage actions (L02) pass gate 020 after E2; verify by run.
- Raw Elixir text unvalidated (defaults, filters, constraints, sorts, hook/run bodies,
  expressions: L01, L03, L04, L05, L06, L07, L10, L14, L18). Close: compile gate catches;
  optional parse gate. Owners per lane.
- Unescaped quotes in description/message text (L01, L04, L07, L05 gate only). Close:
  template escaping or gate on `"`. Owners L01, L04, L05, L07.
- Booleans are string literals "true"/"false" convention (L01, L04). Close: gate L01_060 run.
- Nothing compiled or run in any lane. Close: 03-VERIFY-LADDER passes.

## Per-lane gaps

- L01: `public?` always emitted; `{M,F,A}` defaults raw; embedded/union/struct types only via
  `aap:ashTypeModule` + raw constraints; atoms needing quotes in enums; PK-only attrSpec vs
  gate 010 (now handled by E2).
- L02: unmodeled options: validate_destination_attribute?, filterable?, sortable?, default_sort,
  manual, not_found_message, violation_message, relationship_context, temporal_keys,
  authorize_read_with, attribute_* flags, from_many?, could_be_related_at_creation?, domain,
  read_action_arguments, manage_relationship value_is_key/meta/ignore?/error_path; inline
  manage_relationship on base actions; aggregates/calculations over relationships; has_one
  identities. Composite join pk needs gate 010 relax. Domain must list both ends.
- L03: async?, authorize?, field?, multitenancy; `expression/2` callbacks; module calcs other
  than coalesce; builtins other than concat.
- L04: aggField unchecked for multi-hop/resource aggregates; >3 hops flagged only; aggregates
  not auto-exposed as skill outputs; nested aggregate refs; relies on L02 terms
  `aap:relationship [aap:name; aap:destination]` (rename if mismatched).
- L05: validation names order output (use numeric prefixes); byte_size and negation helpers
  only via `raw`; identity `where` raw; key gate fails for non-`aap:attribute` keys; action-local
  `validate` unreachable until an action fragment hook exists.
- L06: no `atomic?` option (modeled as require_atomic?/atomic_upgrade?); L06 vs `aap:action`
  name collision uncrosschecked; no validations, change `where` typing, `prepend?`, read
  pagination/`get?`, manual actions, `reactor(...)` run form; fixture references absent
  `watchers` relationship; generic-action arguments alphabetical.
- L07: custom Ash.Policy.Check modules and `{Mod, opts}` tuples unmodeled; single policy
  condition; nested policy_group unmodeled; gates 010/030 ignore group conditions; resources
  without policy emit no file; actor required on calls.
- L08: TaskStore.Ash is not tenant-aware (needs ash_a2a change; projection uses per-tenant
  namespace refs); tenant FK declared as both attribute and relationship duplicates; mounts
  for one domain from two lanes collide on `transport do`; no tenant-aware actions; gate 040
  cannot check mount-tenant uniqueness across mounts.
- L09: no ash_postgres/ash_sqlite source on this machine (options from memory, no file:line);
  unmodeled polymorphic?, migration_*, exclusion/foreign_key names, storage_types, concurrent
  indexes, prefix; `references` use free-string `aap:ofRelationship`; autoescape behavior of
  `.tmpl` unknown (`| safe` used); migrations come from `mix ash.codegen`, not ggen;
  mnesia/boot/supervision/.formatter wiring are coordinator actions.
- L10: `allow` mfa, `custom_inputs`, non-atom interface args, multi-namespace validation;
  `get_by` not checked against attributes; `validate_config_inclusion?` cannot live in a
  fragment (coordinator emits `use` option); domain `description` may clash across fragments;
  agents must compile before domain; `ash_domains` lists must agree with L10 config.
- L11: filter/transform are remote captures only; `requires_original_data?/2`, `load/2` not
  modeled; per-action `notifiers:` unmodeled; nested topic alternatives only raw; bridge payload
  minimal (resource/action/id); publication order by node IRI; simple_notifiers is a `use` opt.
- L12: enum value descriptions/labels; hand-written Ash.Type callbacks; Struct `instance_of`;
  embedded resources lack calculations/validations/changes/identities; verify_skills warns
  (not errors) for custom module types, silencing not modeled; gate 010 per-type not
  per-skill reachability.
- L13: `next_state`, Charts, `possible_next_states` into skills unmodeled; two transitions of one
  action with differing targets stack conflicting changes (no gate); `rejected`/`auth_required`
  producers are runtime-decided.
- L14: ETS data layer vs AshOban transactional expectations (needs L09 Postgres); triggered
  read actions need keyset pagination (no vocab, ungated); raw `where`/`sort`/`backoff`/
  `extra_args`; ash_oban verifiers unread; signals workers unmodeled; schedule `on_error`
  argument vocab missing; `AshOban.config` and `{Oban, config}` in application.ex are manual.
- L15: reactor `where`/`guard`; per-binding `inputs` transform; group/debug/recurse/template
  entities, Ash load/context sub-entities, change step; bulk undo contract ungated; Reactor
  description is moduledoc only; gate 030 treats any enclosing transaction as compensating;
  gate 040 cannot check external `stepImpl` modules; skill gate 020 ignores `aap:reactorSkill`
  (fragment action exists by construction).
- L16: obligations are pack-local (no ash_pplan DSL); FOND/HTN/POWL have no TTL surface;
  AshOban/AshStateMachine not generated here; `AshPPlan.Dsl` lacks `compensation:`; `:plan`
  authority admitted by gate 040 but not by the DSL verifier list; GROUP_CONCAT order engine-
  defined; adapter names not gated; custom capability families fail gate 040; unique `ppFile`
  per workflow/provider/pack required.
- L17: domain-level skills unmodeled; `aap:Skill` lacks extended options (use `aap:SkillSpec`);
  default-projected type warnings not mirrored; hook module bodies, grpc endpoint (501),
  `sign_with`/`force_ssl`/`serve_schemas`, `:execution`/`:require_authenticated_caller`
  app-env globals unmodeled; group ordering relies on Tera `group_by` key order. Not
  mirrorable: on_cancel existence, oauth single-flow validity, authorizer lease evaluation.
  Domain cannot mount an agent wrapping itself (compile-order deadlock; use gateway domain);
  `Ash.Policy.Authorizer` with no policies forbids all (needs L07).
- L18: no nested entities, singleton_entity_keys, top_level?, imports, deprecations, links,
  examples, auto_set_fields, transform, no_depend_modules, recursive_as, hide; no transformer
  ordering; Ash.Resource targets only; types raw; section-level instance options not
  instantiable; fixture lacks PK facts and may trip gate 010 when merged.
- L19: see G1-G3; no reconciliation manifest, receipt or `--on-stale` on the Tera path;
  unsupported frontmatter refuses (`REFUSED:UNSUPPORTED_FRONTMATTER`); Tera subset only;
  `mix ggen_igniter.sync` does not dispatch to `pack_sync` (needs `tera_pack?/1` hook in
  `run_sync/3`); ea graph never emits candidate_sbbs/qualifications/packs (digests need
  Rust), so nothing is admissible by `ggen ea admit --sbb`; live-pack golden compares 8 files.
- L20: transition court assumes pk `id`; policy court uses `Ash.can?` with `maybe_is: false`;
  reactor undo probe is a raw boolean; no courts for L03/L04/L08 vocab; ashType whitelist
  hand-curated; `validate_policy/4` arity unverified.

## See Also

[01-LANES-INDEX](01-LANES-INDEX.md) · [03-VERIFY-LADDER](03-VERIFY-LADDER.md) ·
[04-ASSUMPTIONS-TO-FALSIFY](04-ASSUMPTIONS-TO-FALSIFY.md)
