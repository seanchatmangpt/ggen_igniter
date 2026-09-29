# mix ggen_igniter.upgrade

Runs ggen_igniter's version-keyed consumer upgraders. `mix igniter.upgrade ggen_igniter`
invokes it as `ggen_igniter.upgrade FROM TO`.

## Usage

```bash
mix ggen_igniter.upgrade 26.9.24 26.9.28
```

An upgrader registered for version `V` runs when `FROM < V <= TO`, ascending. Registry:
`GgenIgniter.Upgrades.registry/0` (`lib/ggen_igniter/upgrades.ex`).

## Upgraders

| version | module | effect |
|---|---|---|
| 26.9.28 | `GgenIgniter.Upgrades.V260928` | adds `import_deps: [:ggen_igniter]` to `.formatter.exs` (idempotent) |

## Refusals

- `REFUSED:UPGRADE_DOWNGRADE FROM -> TO` when `TO < FROM`
- `REFUSED:UPGRADE_INVALID_VERSION V` when a version is not parseable

Both are Igniter issues; nothing is written. `FROM == TO` is a no-op.

## See Also

- `docs/reference/cli/install.md`
- `lib/ggen_igniter/upgrades.ex`
