# v26.9.30 Wave A (DfLSS gap register, plan ok-i-want-you-abundant-valley) — lane map

One canonical checkout (`/Users/sac/ggen_igniter`, branch `main`). Agents never run git state
commands; coordinator commits per lane. Per-lane `MIX_BUILD_ROOT=_build-<lane>`; never `deps.get`.
Coordinator-owned (lanes REPORT edits): `mix.exs`, `HANDWRITTEN.md`, `CHANGELOG.md`,
`docs/status.md`, `docs/reference/cli/index.md`, `.github/workflows/ci.yml`, `README.md`.

| lane | gap items | owned files |
|---|---|---|
| WA1 | refusal vocabulary (Orion G2, Sam G3) | `priv/schema/refusals.schema.json`, `lib/ggen_igniter/refusals.ex`, `test/ggen_igniter_refusals_test.exs`, `docs/reference/refusals.md`, `docs/glossary.md` |
| WA2 | `sync --check` + uniform `--json`/exit contract (Kenji G1/G4, Orion G3) | `lib/mix/tasks/ggen_igniter.sync.ex`, `.plan.ex`, `.verify.ex`, `lib/ggen_igniter/task_contract.ex`, `lib/ggen_igniter/task_shell.ex`, `test/ggen_igniter_task_contract_test.exs`, `test/ggen_igniter_sync_check_test.exs`, `docs/reference/cli/exit-codes.md`, `docs/reference/cli/sync.md`, `docs/reference/cli/plan.md` |
| WA3 | pack lockfile + receipt pack_digest (Priya G1, Ines G3) | `lib/ggen_igniter/pack_lock.ex`, `lib/mix/tasks/ggen_igniter.pack.lock.ex`, `lib/mix/tasks/ggen_igniter.pack.fetch.ex`, `lib/ggen_igniter/receipt.ex`, `priv/schema/receipt.schema.json`, `test/ggen_igniter_pack_lock_test.exs`, `docs/reference/cli/pack-lock.md` |
| WA4 | contributor kit (Sam G1/G5/G6, Ines G7) | `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE/**`, `.github/PULL_REQUEST_TEMPLATE.md`, `docs/contributing/dev-setup.md`, `docs/tutorials/first-pack.md` |
| WA5 | `packs` discovery + standalone `shacl` (Orion G4, Marcus G1) | `lib/mix/tasks/ggen_igniter.packs.ex`, `lib/mix/tasks/ggen_igniter.shacl.ex`, `lib/ggen_igniter/pack_catalog.ex`, `test/ggen_igniter_packs_task_test.exs`, `test/ggen_igniter_shacl_task_test.exs`, `docs/reference/cli/packs-list.md`, `docs/reference/cli/shacl.md` |

Seam contract WA2<->WA3: `GgenIgniter.PackLock.check(pack_dir :: String.t(), lock_path :: String.t()) ::
:ok | {:error, {:pack_digest_mismatch, %{pack: name, expected: hex, actual: hex}}} | {:error, {:lock_missing, path}}`
and `GgenIgniter.PackLock.digest(pack_dir) :: String.t()` (sha256 hex over a sorted, path-relative content walk).
WA2 wires it behind `--lock PATH` in sync (refusal = typed, exit 1); WA3 owns the module.
Seam contract WA1<->all: refusal codes are `{code_atom, detail}`; text form `REFUSED:<CODE> <detail>`.

Not touched: other session's uncommitted `docs/reference/cli/packs.md`, `docs/reference/cli/epoch.md`,
`test/fixtures/ash_extension_receipted_consumer/`, `test/ggen_igniter_ash_receipted_action_test.exs`.
