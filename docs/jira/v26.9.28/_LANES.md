# v26.9.28 Igniter ERRC wave 2 — lane map

One canonical checkout (`/Users/sac/ggen_igniter`, branch `main`). Agents never run git state
commands; the coordinator commits per lane. Per-lane `MIX_BUILD_ROOT=_build-lane<N>`; never
`mix deps.get`. Shared files (`mix.exs`, `HANDWRITTEN.md`, `CHANGELOG.md`, `docs/status.md`,
`docs/reference/cli/index.md`) are coordinator-owned: lanes REPORT the exact edit, never make it.

| lane | scope | owned files (create/edit) |
|---|---|---|
| L1 | thin Igniter installer (RA2/E1/C1-installer) | `lib/mix/tasks/ggen_igniter.install.ex`, `test/ggen_igniter_install_installer_test.exs`, `docs/reference/cli/install.md` |
| L2 | upgraders (C1) | `lib/mix/tasks/ggen_igniter.upgrade.ex`, `lib/ggen_igniter/upgrades/**`, `test/ggen_igniter_upgrade_test.exs`, `docs/reference/cli/upgrade.md` |
| L3 | idempotence harness (RA1/R3) | `test/support/igniter_idempotence.ex`, `test/ggen_igniter_igniter_idempotence_test.exs` |
| L4 | receipted Spark extension pack (C3) | `priv/ggen/receipted-extension-pack/**`, `test/fixtures/receipted-extension/**`, `test/ggen_igniter_receipted_extension_pack_test.exs` |
| L5 | Ash-Igniter-API pack (C2) | `priv/ggen/ash-igniter-api-pack/**`, `test/fixtures/ash-igniter-api/**`, `test/ggen_igniter_ash_igniter_api_pack_test.exs` |
| L6 | igniter-task-pack (RA3) | `priv/ggen/igniter-task-pack/**`, `test/fixtures/igniter-task/**`, `test/ggen_igniter_igniter_task_pack_test.exs` |
| L7 | usage-rules pack + manifest export (C4/C5) | `priv/ggen/usage-rules-pack/**`, `lib/ggen_igniter/manifest_export.ex`, `lib/mix/tasks/ggen_igniter.manifest.dump.ex`, `test/ggen_igniter_manifest_export_test.exs`, `test/ggen_igniter_usage_rules_pack_test.exs`, `docs/reference/cli/manifest.md` |
| L8 | doctor_fixes reduction + upstream issue drafts (R1/R2/R4) | `lib/ggen_igniter/doctor_fixes.ex`, `docs/jira/v26.9.28/upstream-igniter-issues.md` |
| L9 | repo hygiene (E3) | `.gitignore`, `docs/jira/v26.9.28/hygiene-report.md` |
| CI | tests/CI runtime ERRC (running) | `.github/workflows/ci.yml`, `test/test_helper.exs`, test `async:` lines, `docs/jira/v26.9.28/ci-runtime-errc.md` |

Already landed: `44c89aa` (TaskShell, install/rename docs). Untracked files from another
session (`docs/reference/cli/epoch.md`, `test/fixtures/ash_extension_receipted_consumer/`,
`test/ggen_igniter_ash_receipted_action_test.exs`) are not ours: do not touch.
