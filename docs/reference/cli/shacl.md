# mix ggen_igniter.shacl

Standalone SHACL validation of any RDF data file against any shapes file (any format
`GgenIgniter.Ontology.load!/1` accepts), via `GgenIgniter.SemanticJira.Shacl.validate_file/2`.

```bash
mix ggen_igniter.shacl --data FILE --shapes FILE [--json] [--fail-on-unsupported]
```

## Flags

| Flag | Meaning |
|---|---|
| `--data FILE` | Data graph (required, must exist) |
| `--shapes FILE` | Shapes graph (required, must exist) |
| `--json` | One JSON object: `schema_version`, `conforms`, `exit_code`, `shapes_checked`, `focus_node_count`, `violations`, `unsupported` |
| `--fail-on-unsupported` | Exit 1 when unsupported constructs are present |

## Exit codes

- `0` conforms (unsupported constructs, if any, are still printed as `UNSUPPORTED` lines)
- `1` violations, or unsupported constructs with `--fail-on-unsupported`
- `2` invocation error (missing/unreadable file)

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
