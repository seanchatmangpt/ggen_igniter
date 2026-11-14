# 04-ASSUMPTIONS-TO-FALSIFY

Standing: UNVERIFIED

Every assumption below was flagged by a lane and not executed. `W` = scratch project from
`03-VERIFY-LADDER.md`; `P` = `/Users/sac/ggen-marketplace/packs/ash-a2a-app-pack`.
Format: assumption; lane; falsifying command; falsified if.

## Tera constructs (ggen 26.11.5 engine)

- `filter(attribute=..., value=...)` on rows from OPTIONAL columns treats unbound as absent;
  L05, L12, L13, L18, base resource template. Run `ggen sync run` in W and inspect the
  generated fragment. Falsified if sync errors or lines render empty or wrong.
- `default` plus `!=` precedence and `| default | split`; L04, L10, L14. Same run; inspect
  `_l04.ex`, `_l10.ex`, `_l14_oban.ex`. Falsified if guarded clauses render for absent values.
- Unbound OPTIONAL columns yield undefined keys, not empty strings (or both are handled);
  L13, L14, L19. Same run on a fixture lacking the optional fact.
- Macro `self::ref` and `self::step` recursion; L07, L15. Sync the L07 and L15 fixtures.
  Falsified if the engine rejects it; fallback is per-kind if/elif or depth-2 loops.
- Tests `is starting_with`, `containing`; filters `trim_start_matches`, `split`, indexed
  `p[0]`; L07, L10, L17. Sync; falsified on an `unsupported` or template error.
- `group_by` key order is alphabetical; `json_encode`; L17 security_requirements. Sync the L17
  fixture twice and diff. Falsified if order or JSON differs from expectation.
- `set_global` inside for loops; L18. Sync the L18 fixture; falsified on error or stale value.
- `.tmpl` autoescape is off and `| safe` suffices for SQL; L09. Sync L09, then grep generated
  files for `&quot;` or `&#`. Falsified if any HTML entity appears.
- GROUP_CONCAT ordering is stable (identity keys, pplan after/outcomes); L05, L16. Replay rung 8
  (diff of two syncs). Falsified by a non-empty diff.

## Fragment-supplied extensions and options

- Spark fragments accept `extensions:` (L13 AshStateMachine, L14 AshOban, L15 and L17 AshA2A,
  L18) and `authorizers:` (L07, L17): `mix compile --warnings-as-errors` in W. Falsified if
  Spark rejects them; fallback: list them in the resource `use` options.
- `data_layer:` inside a fragment (L09): same compile with an L09 resource. Falsified by a
  single-extension-kind conflict; fallback documented in `L09-NOTES.md`.
- `of: Ash.Domain, extensions: [AshA2A]` domain fragment (L08, L10, L17): same compile.
- `where: [action_is/1]` in a resource-level `changes` block (L13): compile, then `mix test`.
- `validate_policy/4` arity and `Ash.can?` with `maybe_is: false` (L20): `mix test` courts.
- `simple_notifiers` works only as a `use` option (L11): compile; falsified if a fragment-borne
  notifier also works.

## Spark merging

- Duplicate `transport do` blocks from L08 mounts and the L17 domain fragment merge instead of
  colliding: compile a domain carrying both. Falsified by a Spark duplicate-section error.
- Duplicate `domain do` blocks across L10 and other fragments merge: same compile.
- Plain `resource(X)` merges with `resources do resource X do define` via `DedupResources`
  (L10): compile; falsified by a duplicate-resource error.
- Multiple L18 instances of one entity render one `section do` each and Spark merges them.

## Other behavior

- FM-LAW-015 accepts an ABB/contract set with zero candidate SBBs (L19): run `ggen sync run`
  without `--skip-ea-admission` with `fixtures/L19-ea.ttl` appended (`aap:eaDeclare "true"`).
  Falsified if refused; then leave `eaDeclare` unset and use the default `ggen init` shape.
- Default ea graph equals the `ggen init` graph and passes without the skip flag (L19): same
  run without `eaDeclare`.
- Fragment ordering is compile-deadlock-free across L01-L18: `mix compile` on the FULL fixture.
- E2-widened gates 010/020/030 accept L01/L02/L06/L15 edges: `ggen graph validate` on a fixture
  whose PK and action come only from those edges; expect 0 rows.
- L04 gates match L02 term names (`aap:relationship [aap:name; aap:destination]`): validate
  `L04-aggregates.ttl` plus `L02-relationships.ttl`; falsified if L04_020 flags valid paths.
- L18 fixture lacks PK facts and trips gate 010 when merged: validate the FULL fixture.
- L20 gate 040 ashType whitelist rejects no builtin type used by the L01 fixture: validate.
- ash_postgres and ash_sqlite DSL options match AshPostgres 2.x / AshSqlite 0.2 (L09): compile
  with those deps fetched. Falsified by unknown-option errors.
- igniter Tera handles omitted or empty unbound columns (L19): `mix test` for `tera_test.exs`
  in `/Users/sac/ggen_igniter`.
- `lease_required?` skills see an authorizer contributed via fragments (L07, L17,
  verify_skills refused_lease_required_no_authorizer): compile a leased skill; if refused,
  declare `authorizers:` on the resource `use`.

## See Also

[03-VERIFY-LADDER](03-VERIFY-LADDER.md) · [02-GAP-REGISTER](02-GAP-REGISTER.md) ·
[01-LANES-INDEX](01-LANES-INDEX.md)
