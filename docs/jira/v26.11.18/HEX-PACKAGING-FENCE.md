# Hex packaging / Ash-must-not-ship fence (v26.11.18 finish lane)

Standing: PASS (test-enforced; Hex publish still operator-gated)

## Fence (two halves)

1. **Deps** — every `:ash*` Hex dependency in `mix.exs` is `only: [:dev, :test]`
   so consumers never inherit Ash as a runtime requirement.
2. **Packs** — `shipped_packs/0` / `ash_shipped?/1` ship `priv/ggen/*` except
   basenames containing `"ash"`, with one exception: `ash-manufacture-pack`.

## Courts

| Test | What it proves |
|---|---|
| `test/ws5_contracts/21_ash_dev_test_scope_test.exs` | Source: every `:ash*` dep is `only: [:dev, :test]` |
| `test/ggen_igniter_shipped_packs_fence_test.exs` | Fast: `Mix.Project` package files + PackCatalog mirror + anti-vacuity reject set |
| `test/ggen_igniter_package_ash_free_test.exs` | Chicago: real `mix hex.build --unpack` (no ash* requirements, no ash pack roots except manufacture, no `use Ash.*` in shipped lib) |

## Runbook

`docs/jira/v26.11.10/10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md` (version-agnostic; publish still operator).

## Open (operator)

- Hex publish of the current CalVer (`mix.exs` `version:`) — not executed by this lane.
- Refresh `docs/jira/v26.11.10/evidence/hex_package_manifest.txt` on the next publish.
