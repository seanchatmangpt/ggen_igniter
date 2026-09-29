# v26.9.31 Wave B1 (DfLSS register #2: Ash/Reactor/Igniter community avatars) — lane map

One canonical checkout, branch `main`; agents never run git state commands; coordinator commits per
lane. Per-lane `MIX_BUILD_ROOT=_build-<lane>`; never `deps.get`. Coordinator-owned (lanes REPORT
edits): `mix.exs`, `HANDWRITTEN.md`, `CHANGELOG.md`, `docs/status.md`, `docs/reference/cli/index.md`,
`README.md`, `.github/workflows/ci.yml`, `test/test_helper.exs`, `docker-compose*.yml`.

Foundation (Wave B0, landed): `GgenIgniter.Test.PackCompile` (`render!/2`, `render/2`, `compile/2`,
`compile!/2`, `purge/1`, `with_compiled/3`, `tmp_project!/1`, `cleanup/1`) and
`GgenIgniter.Test.PostgresCase` in `test/support/`; guide `docs/contributing/chicago-pack-testing.md`.
Test-only deps declared: ash_json_api, ash_ai, ash_state_machine, ash_oban, oban.

| lane | avatar / register items | owned files |
|---|---|---|
| B1a | A1 Ash resource surface (action args/changes/validations, aggregates, code interfaces, bypass/field policies, resource config) | `priv/ggen/ash-igniter-api-pack/**`, `test/ggen_igniter_ash_action_surface_test.exs`, `test/ggen_igniter_ash_aggregates_interfaces_test.exs`, `test/ggen_igniter_ash_policies_enforce_test.exs`, existing `test/ggen_igniter_ash_igniter_api_pack_test.exs` (must keep passing; edit only if a fixture shape change forces it) |
| B1b | A8 state machine -> AshStateMachine + conservation/reachability gate | `priv/ggen/state-machine-pack/**` (new), `test/ggen_igniter_state_machine_pack_test.exs`, `test/ggen_igniter_state_machine_conservation_test.exs`, `test/fixtures/state-machine/**` |
| B1c | A2 Spark DSL schema-as-data, transformers, formatter export | `priv/ggen/receipted-extension-pack/**`, `test/ggen_igniter_extension_schema_test.exs`, `test/ggen_igniter_extension_transformer_test.exs`, `test/ggen_igniter_extension_formatter_test.exs`, `test/fixtures/receipted-extension/**`, existing `test/ggen_igniter_receipted_extension_pack_test.exs` (must keep passing) |
| B1d | A3 Reactor edges + Ash.Reactor steps + saga proofs | `priv/ggen/reactor-scaffold-pack/**`, `test/ggen_igniter_reactor_edges_test.exs`, `test/ggen_igniter_ash_reactor_pack_test.exs`, `test/ggen_igniter_reactor_saga_order_test.exs`, `test/ggen_igniter_reactor_halt_resume_test.exs`, `test/fixtures/reactor-pack/**`, existing expense_approval reactor tests must keep passing |
| B1e | A4 installer/upgrader generator + dry-run/--yes contract + upstream canaries | `priv/ggen/igniter-installer-pack/**` (new), `test/ggen_igniter_installer_pack_test.exs`, `test/ggen_igniter_upgrader_chain_test.exs`, `test/ggen_igniter_dry_run_yes_test.exs`, `test/ggen_igniter_upstream_canaries_test.exs`, `test/fixtures/installer-pack/**` |

Not touched: other session's `docs/reference/cli/packs.md`, `docs/reference/cli/epoch.md`,
`test/fixtures/ash_extension_receipted_consumer/`, `test/ggen_igniter_ash_receipted_action_test.exs`.
Pack paths containing "ash" are excluded from the hex package by `shipped_packs/0` (intended).
