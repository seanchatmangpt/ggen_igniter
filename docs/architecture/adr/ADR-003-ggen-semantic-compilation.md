# ADR-003: ggen Semantic Compilation Integration

## Status
Accepted (`IMPLEMENTED`)

## Context
Code generation requires extracting structured entity definitions from semantic RDF graphs and Turtle ontologies using SPARQL queries.

## Decision
1. Ingest RDF ontologies into in-memory `%RDF.Graph{}` structs via `GgenIgniter.Ontology`.
2. Execute SPARQL queries using `GgenIgniter.Engine.Oxigraph` (native Rustler NIF) as the default engine, with `GgenIgniter.Engine.Sparql` and `GgenIgniter.Engine.Qlever` as alternative backends.
3. Implement `GgenIgniter.Frontmatter` as a 1:1 mirror of `ggen`'s YAML template headers.

## Rationale
Oxigraph fixes a proven `ORDER BY` reverse-ordering bug present in the pure-Elixir SPARQL package and provides spec-compliant SPARQL 1.1 execution.

## Consequences
- **Positive:** High performance, accurate SPARQL sorting, native multi-query support.
- **Trade-off:** Compiling the Oxigraph engine requires a working Rust toolchain via Rustler.
