# ADR-0001: Oxigraph as the Default SPARQL Query Engine

## Status

**Accepted.** Live since v26.8.27. `GgenIgniter.Engine.registry/0` maps
`"oxigraph" => GgenIgniter.Engine.Oxigraph`, and
`Mix.Tasks.GgenIgniter.Sync`'s `engine_name = opts[:engine] || "oxigraph"`
is the real, current default — confirmed both by reading the source and by
a real `mix ggen_igniter.sync` run with no `--engine` flag printing
`(engine: oxigraph, ...)`.

## Context

`ggen_igniter` supports three SPARQL query engines behind one behaviour
(`GgenIgniter.Engine`, `prepare!/2` + `run/2`): the pure-Elixir `sparql` hex
package, a real remote QLever HTTP endpoint, and a native oxigraph engine
(a Rustler NIF embedding the real Rust `ggen` project's own
`ggen-graph-wasm` `OxigraphEngine`). Before v26.8.27, `sparql` was the
default.

A real, empirically confirmed data-corruption bug drove the change: the
`sparql` hex package (v0.3.12) does not correctly honor `ORDER BY`. A
join-shaped query mirroring this project's own gate-query fixtures
(`?field ex:fieldOf ?entity ; ex:fieldOrder ?field_order . ... ORDER BY
?field_order` over 10 rows) came back in **reverse order** (`[9, 8, ..., 0]`
instead of the requested ascending `[0, 1, ..., 9]`). The identical query
run through oxigraph — a real, independent, spec-conformant SPARQL 1.1
engine — returned the correct ascending order. Silent row-order reversal is
a real corruption risk for any `--for-each` fan-out template that assumes
row order (positional joins, numbering).

## Decision

Make `oxigraph` the default `--engine` value. `sparql` and `qlever` remain
fully available, explicit choices — this is a default change, not a
deprecation of the other two engines.

## Consequences

- **A working Rust/`cargo` toolchain is now required to compile
  `ggen_igniter` at all**, regardless of which `--engine` is ever actually
  invoked at runtime — `lib/ggen_igniter/native/graph_nif.ex`'s `use
  Rustler` compiles `native/ggen_graph_nif` as part of that module's own
  compilation. This requirement predates the default change (the loader
  module was already unconditionally part of `lib/`); changing the
  *default string* added no *new* compile-time requirement.
- **Row-value shape differs from `sparql`, disclosed in source**: oxigraph's
  rows are documented as the raw, unprocessed N-Triples-style term strings
  oxigraph itself returns (angle-bracket IRIs, quoted/datatype-annotated
  literals) rather than bare values. This disclosed trade-off was
  independently probed against this repo's own real fixtures in a later
  documentation pass and **could not be reproduced** — the real generated
  output contained clean, bare Elixir values with no such wrapping. This ADR
  does not resolve that discrepancy; see `docs/tutorials/getting-started.md`
  and `docs/status.md` for the current, honestly-unresolved state.
- `mix ggen_igniter.doctor` check 3 still warns on `sparql <= 0.3.12` for
  callers who explicitly choose `--engine sparql`.
- This project's own `mix e2e` lifecycle test pins `--engine sparql`
  explicitly rather than relying on the new oxigraph default, for reasons
  documented in `docs/testing/e2e-lifecycle.md`.

## See also

- `docs/reference/cli/engines.md` — full engine comparison and choosing guidance
- `docs/status.md` — the disputed row-shape claim's current, unresolved status
