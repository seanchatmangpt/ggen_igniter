# Engine selection: `--engine oxigraph|sparql|qlever`

Source: `lib/ggen_igniter/engine.ex` (`GgenIgniter.Engine` behaviour +
`GgenIgniter.Engine.{Sparql,Qlever,Oxigraph}` adapters), dispatched from
`Mix.Tasks.GgenIgniter.Sync`. Status: **IMPLEMENTED** for all three engines.

`GgenIgniter.Engine.registry/0` is the single source of truth for valid
`--engine` values:

```elixir
%{
  "sparql"   => GgenIgniter.Engine.Sparql,
  "qlever"   => GgenIgniter.Engine.Qlever,
  "oxigraph" => GgenIgniter.Engine.Oxigraph
}
```

An unrecognized `--engine` value raises immediately via `Engine.fetch!/1`:
`"invalid --engine \"nope\", must be one of: oxigraph, qlever, sparql"`.

Every engine module implements two callbacks: `prepare!/2` (graph + raw CLI
opts → whatever context `run/2` needs; runs once per `sync` invocation) and
`run/2` (context + one query string → `[map()]` rows; runs once per named
query). Adding a new engine means adding a module + one registry entry, not
editing `sync`'s dispatch logic.

## `--engine oxigraph` — the default (since v26.8.27)

Runs every query in-process against the loaded `%RDF.Graph{}` via a real,
native oxigraph engine: a Rustler NIF over `native/ggen_graph_nif`
(`ggen_graph_nif` crate, wrapping `~/ggen/crates/ggen-graph-wasm`'s
`OxigraphEngine`), exposed as `GgenIgniter.Query.Oxigraph.run/2`.

**Why it became the default**: a real, empirically confirmed data-corruption
bug in the previous default. `GgenIgniter.Query.run/2` (the `sparql` hex
package, v0.3.12) does not correctly honor `ORDER BY` — a join-shaped query
mirroring the real gate fixtures (`?field ex:fieldOf ?entity ; ex:fieldOrder
?field_order . ?entity ex:entityStruct ?entity_struct .` with `ORDER BY
?field_order` over 10 rows) came back in reverse order (`[9, 8, ..., 0]`
instead of the requested ascending `[0, 1, ..., 9]`). The same query run
through oxigraph (a real, independent, spec-conformant SPARQL 1.1 engine)
returned the correct ascending order. Silent row-order reversal is a real
corruption risk for any `--for-each` fan-out template that assumes row order
(numbering, positional joins) — hence the switch.

Two real, disclosed trade-offs of this default, neither hidden:

- **Row-value shape differs from `sparql`.** `oxigraph`'s rows are the raw,
  unprocessed N-Triples-style term strings oxigraph itself returns — IRIs
  come back angle-bracket-wrapped (`<https://example.org/...>`) and
  literals come back quoted (with datatype/language tags when applicable,
  e.g. `"42"^^<http://www.w3.org/2001/XMLSchema#integer>`), not bare values.
  A template rendering a query column directly (`<%= module_name %>`) will
  see this shape difference if switched from `sparql` to `oxigraph`.
- **A working Rust toolchain is required to compile this library at all**,
  regardless of which `--engine` is ever actually invoked at runtime.
  `lib/ggen_igniter/native/graph_nif.ex`'s `use Rustler` compiles
  `native/ggen_graph_nif` via a real `cargo` subprocess as part of that
  module's own compilation — there is no separate `mix compilers:` entry
  gating this; it runs whenever `graph_nif.ex` is compiled. This requirement
  predates the default change (the loader module has been unconditionally
  part of `lib/` since `oxigraph` was first added as an opt-in engine) —
  changing the *default* string is a runtime-only behavior change, adding no
  new compile-time requirement beyond what already existed.

## `--engine sparql` — the pure-Elixir fallback

Runs every query in-process against the loaded `%RDF.Graph{}` via
`GgenIgniter.Query.run/2` (the `sparql` hex package). Still available and
useful for a query shape known to depend on `sparql` hex's specific
(non-`ORDER BY`-correct) behavior, or to A/B a result against the new
default. `mix ggen_igniter.doctor` (check #3) warns if the loaded `:sparql`
version is `<= 0.3.12`, since that version additionally has a known `FILTER
NOT EXISTS` + `BIND` inside `UNION` bug (raises
`Protocol.UndefinedError`) — recommending `--engine qlever` for gate queries
with that shape.

## `--engine qlever` — real remote SPARQL endpoint

Sends every query instead to a real, **already-running** QLever SPARQL
endpoint via `GgenIgniter.Query.Qlever.run/2` (`gno` + real HTTP — no
in-process SPARQL evaluation at all). `--ontology` is still loaded as a
`%RDF.Graph{}` via the same `Ontology.load!/1`, but only to look up the
`gnoa:Qlever`-typed store resource named by `--store-id` — the query text
itself never touches this graph's data; it runs entirely on the remote
QLever store. **`--store-id` is required** when `--engine qlever` is given
(`ArgumentError` if omitted).

`GgenIgniter.Engine.Qlever` guards two optional deps (`:gno` and `:tesla`,
both `optional: true` in `mix.exs`) with real `Code.ensure_loaded?/1`
runtime checks in `prepare!/2`, so a consumer missing either gets a clear,
actionable `RuntimeError` (naming exactly which dep to add) instead of a
raw `MatchError` deep in `Application.ensure_all_started(:tesla)`. It also
idempotently starts the `:tesla` application and a `GgenIgniter.Finch`
process (registered under that name, checked via `Process.whereis/1`)
before use, since Igniter tasks operate on ASTs and don't boot the full OTP
application tree on their own.

`mix ggen_igniter.doctor --engine qlever --store-id ID` (check #8) verifies
real reachability via a real `ASK { ?s ?p ?o }` query — requires a pack
ontology to resolve `--store-id` against (`--pack`/`--pack-dir`).

## Choosing an engine

| Need | Engine |
|---|---|
| Default; correct `ORDER BY`; in-process, no external service | `oxigraph` |
| A query shape specifically depends on `sparql` hex's own (non-`ORDER BY`-correct) evaluation, or you want to A/B against oxigraph | `sparql` |
| Gate queries use `FILTER NOT EXISTS` + `BIND` inside `UNION` (triggers the `sparql` 0.3.12 bug) | `qlever` |
| Data already lives in a real, running QLever store rather than a local `.ttl` file | `qlever` |
| No Rust toolchain available to compile `native/ggen_graph_nif` at all | Not solvable by switching `--engine` — see the compile-time note above; the NIF module compiles regardless of which engine is used at runtime. |

## Examples

```
# default (oxigraph)
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex

# sparql
mix ggen_igniter.sync \
  --engine sparql \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --query sections=test/fixtures/sections.rq \
  --query entities=test/fixtures/entities.rq \
  --query fields=test/fixtures/fields.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex

# qlever
mix ggen_igniter.sync \
  --engine qlever \
  --ontology config/gno/test/store.ttl \
  --store-id http://example.com/Qlever \
  --query spec=priv/ggen/some-pack/gates/010.rq \
  --template priv/ggen/some-pack/templates/out.ex.eex \
  --out lib/generated.ex
```
