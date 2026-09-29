# mix ggen_igniter.shacl

Standalone SHACL validation of any RDF data file against any shapes file (`.ttl`, `.nt` or `.nq`; a
`.nq` dataset is merged into one graph before validation; other extensions are refused), via `GgenIgniter.SemanticJira.Shacl.validate_file/2`.

```bash
mix ggen_igniter.shacl --data FILE --shapes FILE [--json] [--allow-unsupported]
```

## Flags

| Flag | Meaning |
|---|---|
| `--data FILE` | Data graph (required, must exist) |
| `--shapes FILE` | Shapes graph (required, must exist) |
| `--json` | One JSON object: `schema_version`, `conforms`, `exit_code`, `shapes_checked`, `focus_node_count`, `violations`, `unsupported` |
| `--allow-unsupported` | Opt out of failing closed: unsupported constructs are still printed but exit stays 0 |
| `--fail-on-unsupported` | Deprecated no-op alias (failing closed is now the default); prints a stderr note; removed next release |

## Exit codes

- `0` conforms (or, with `--allow-unsupported`, only unsupported constructs were found)
- `1` violations, or unsupported constructs (default; stderr says `UNSUPPORTED ... failing closed`)
- `2` invocation error: missing file, unsupported extension, unloadable input, or
  `no SHACL shapes found in <path>` (empty shapes file, swapped `--data`/`--shapes`, no node shapes)

`exit_code` in `--json` always equals the process exit code. On exit 2 with `--json` the object is
`{"schema_version":1,"error":"...","exit_code":2,"conforms":false}`. When shapes exist but no focus
node matched, `0 focus nodes validated` is printed to stderr (exit stays 0).

## Supported subset

Only the subset documented in `GgenIgniter.SemanticJira.Shacl`: targets `sh:targetClass`,
`sh:targetNode`, `sh:targetSubjectsOf`, `sh:targetObjectsOf`; property constraints `sh:minCount`,
`sh:maxCount`, `sh:nodeKind`, `sh:datatype`, `sh:pattern` (flag `i`), `sh:minLength`,
`sh:maxLength`, `sh:hasValue`, `sh:class`; node-level `sh:closed`, `sh:ignoredProperties`,
`sh:property`, `sh:deactivated`; `sh:sparql` constraints.

Unsupported (always reported, never skipped): `sh:qualifiedValueShape` / `sh:qualifiedMinCount` /
`sh:qualifiedMaxCount`, `sh:node`, `sh:not`, `sh:and`, `sh:or`, `sh:xone`, `sh:in`,
`sh:languageIn`, `sh:uniqueLang`, non-`i` `sh:flags`, non-simple property paths. `sh:severity`,
`sh:name`, `sh:description`, `sh:order`, `sh:group` are tolerated annotations, not evaluated.

## See Also

- `docs/reference/cli/packs-list.md`
