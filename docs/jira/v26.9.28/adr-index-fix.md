# ADR Index Fix (v26.9.28, lane w6)

Fixes hygiene-report section (c). `priv/ggen/adr-index-pack/ontology.ttl` gained 11
`adr:Decision` individuals: `0009`, `ADR-001`..`ADR-005`, `ADR-006a`, `ADR-006b`,
`ADR-007`..`ADR-009`. Titles and statuses are copied from each file's H1 and Status text.

The two `ADR-006-*` files keep their filenames; the index ids are `ADR-006a`
(actuation-single-boundary) and `ADR-006b` (generational-resilience-manufacture).

Row count: 11 before, 22 after (all 22 ADR files, once each).
README regenerated with:

```bash
mix ggen_igniter.sync --pack adr-index-pack --engine sparql --out docs/architecture/adr/README.md
```

New ADRs take the next free prefixed number, `ADR-013`.
