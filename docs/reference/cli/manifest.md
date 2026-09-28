# `mix ggen_igniter.manifest.dump`

v26.9.28. Emits a stable, sorted JSON export of a project's reconciliation state for
third-party replay, modeled on `mix ash.manifest.dump`. Read-only.

## Usage

```bash
mix ggen_igniter.manifest.dump [--path DIR] [--out FILE]
```

| Flag | Meaning |
|---|---|
| `--path DIR` | Directory holding `.ggen_igniter/` (default `.`) |
| `--out FILE` | Write the export to FILE instead of stdout |
| `--help`, `-h` | Print usage, exit 0 |

## Inputs

- `<DIR>/.ggen_igniter/manifest.json` (see `docs/reference/reconciliation/manifest.md`)
- `<DIR>/.ggen_igniter/receipts/*.jsonl` (one `GgenIgniter.Receipt` JSON object per line)

## Output shape

```json
{
  "format": "ggen_igniter.manifest_export/1",
  "manifest": {"entries": {}, "schema_version": "1", "version": 1},
  "manifest_sha256": "sha256:<hex of the raw manifest.json bytes>",
  "receipts": []
}
```

Object keys are sorted at every depth; receipts are ordered by
`{started_at, id, file, line}`; no absolute paths or wall-clock values are added, so
identical input yields byte-identical output from any directory.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Exported |
| `1` | Typed refusal on stderr: `REFUSED:MISSING_MANIFEST`, `REFUSED:CORRUPT_MANIFEST`, `REFUSED:CORRUPT_RECEIPT` |
| `2` | Invalid invocation (unknown flag, stray positional, unwritable `--out`) |

Library entry point: `GgenIgniter.ManifestExport.dump/1`.

## See Also

- `docs/reference/reconciliation/manifest.md`
- `docs/reference/cli/replay.md`
