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
- **Row-value shape is PLAIN by default, matching `sparql`'s shape**:
  verified by reading `lib/ggen_igniter/query/oxigraph.ex:112-142` — `run/2`
  and `run/3` (with no `raw: true`) call `GraphNif.query_turtle/2`, which
  returns oxigraph's terms normalized to plain, unwrapped values (no
  `<...>` IRI brackets, no `"..."^^<...>`/`@lang` literal wrapping), the
  same shape `GgenIgniter.Query.run/2` (the `sparql` hex engine) returns.
  This was a real, already-fixed bug (see `oxigraph.ex`'s moduledoc,
  "Term normalization: PLAIN values by default, raw as an explicit
  opt-in") — earlier versions of this engine returned raw N-Triples-style
  `Term::to_string()` serializations, fixed at the source in the Rust NIF
  itself (`native/ggen_graph_nif/src/oxigraph_engine.rs`'s
  `normalize_term/1`), not by post-processing in the Elixir wrapper. The
  raw, pre-fix shape remains available only via the explicit `raw: true`
  opt-in (`GraphNif.query_turtle_raw/2`), for callers that need a
  binding's datatype IRI or language tag. One disclosed, narrower scope
  limit survives: the plain default returns every literal's lexical
  string uniformly regardless of datatype (an `xsd:boolean` literal
  normalizes to the string `"true"`, not the Elixir boolean `true`),
  unlike `GgenIgniter.Query.run/2`'s per-datatype `elixir_mapping/2`
  coercion for `xsd:boolean`/`xsd:integer` specifically — see
  `docs/status.md` for this narrower, still-accurate caveat.
- `mix ggen_igniter.doctor` check 3 still warns on `sparql <= 0.3.12` for
  callers who explicitly choose `--engine sparql`.
- This project's own `mix e2e` lifecycle test pins `--engine sparql`
  explicitly rather than relying on the new oxigraph default, for reasons
  documented in `docs/testing/e2e-lifecycle.md`.

## See also

- `docs/reference/cli/engines.md` — full engine comparison and choosing guidance
- `docs/status.md` — the row-shape claim's current, verified status (plain
  by default; one narrower disclosed datatype-coercion caveat remains)
