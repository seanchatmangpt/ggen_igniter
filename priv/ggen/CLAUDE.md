# `priv/ggen/` — the `--pack` convention

Fixed shape per pack, matched by `mix ggen_igniter.sync --pack <name>`'s
default resolution — don't deviate from these exact subpath names or the
pack-derived defaults silently stop resolving:

```
priv/ggen/<pack-name>/
  ontology.ttl              # the RDF/Turtle graph this pack queries
  gates/*.rq                # named SPARQL queries — filename convention below
  templates/*.eex           # EEx templates rendered against query results
```

## Naming

- Gate files: `NNN_name.rq` (zero-padded 3-digit prefix, e.g.
  `010_adrs.rq`) when a pack has an implied ordering across gates; a
  single-query pack (like `adr-index-pack`) still gets one numbered file
  rather than a bare `name.rq`, for consistency with multi-gate packs.
- Template files: `<output-shape>.<ext>.eex` where `<ext>` is the real
  extension of the file being generated (`readme.md.eex` renders a
  `.md`, `extension.ex.eex` renders a `.ex`) — never a bare `.eex` with no
  target extension embedded.
- SPARQL style: `PREFIX` declarations at the top using this pack's own
  ontology IRI (see `adr-index-pack`'s `adr:` prefix bound to
  `https://ggen-igniter.dev/ontology/adr-index#`), `SELECT DISTINCT` unless
  duplicates are actually wanted, one triple pattern per line.

## Adding a new pack

1. Write `ontology.ttl` first — model the real domain concepts as classes/
   properties under a pack-scoped IRI, don't reuse another pack's namespace.
2. Write gate queries against it and verify each with a real
   `mix ggen_igniter.sync --pack <name> --dry-run` run before wiring a
   template — confirms the query actually returns the expected row shape
   before spending effort on the render side.
3. Write the template last, using the query's real result columns (check
   `--dry-run` output or a real run's rendered content, don't guess column
   names from the ontology alone — a `SELECT` can rename/compute columns).
4. If the pack is meant for external reuse via `github:`/`hex:` fetch
   (`GgenIgniter.Pack.fetch_pack!/2`), document it in
   `docs/reference/cli/sync.md`'s pack section.
