# mix ggen_igniter.packs

Pack discovery over `priv/ggen` (and optionally an extra pack root), replacing `ls priv/ggen`.
Read-only. Implemented by `GgenIgniter.PackCatalog`, which calls `Pack.parse_manifest/1`,
`Pack.discover_queries/1` and `Pack.discover_templates/1`.

```bash
mix ggen_igniter.packs [--json] [--pack-dir DIR] [--name NAME]
```

## Flags

| Flag | Meaning |
|---|---|
| `--json` | One JSON document: `{"schema_version": 1, "packs": [...]}`, keys sorted, packs sorted by `dir` |
| `--pack-dir DIR` | Also list packs under `DIR` (each child directory), or `DIR` itself when it holds an `ontology.ttl` |
| `--name NAME` | Only the pack whose name (or directory basename) is `NAME` |
| `--help` | Usage, exit 0 |

## Fields per pack

`name`, `version`, `description` (from `pack.toml`; `null` when the pack has none),
`metadata_source` (`manifest` / `inferred` / `invalid_manifest`), `manifest_error`, `dir`,
`ontology` (path or `null`), `gates` (`{name, path}`), `templates` (`{stem, path, to, for_each}`,
`to`/`for_each` from template frontmatter), `required_flags`, `origin` (`priv_ggen` / `pack_dir`),
`hex_shipped`.

`hex_shipped` mirrors `mix.exs` `shipped_packs/0`: `priv/ggen/*` minus any path containing `ash`;
always `false` for `--pack-dir` packs.

## Exit codes

- `0` listed
- `2` unknown `--name` or bad invocation

## See Also

- `docs/reference/cli/shacl.md`
- `docs/reference/cli/sync.md`
