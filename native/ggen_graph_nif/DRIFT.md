# ggen_graph_nif — graphlaw / oxigraph / upstream drift ledger

Standing: documented 2026-11-18 (finish lane 7). Keep this file inside
`native/ggen_graph_nif/` so Mix packaging / sync-spine lanes do not own it.

## Upstream vendor source (CLOSED path → OWNED copy)

| Claim (historical) | Reality (2026-11-18) |
|---|---|
| Vendored from `~/ggen/crates/ggen-graph-wasm/src/{lib,oxigraph_engine}.rs` | That crate **no longer exists** under `~/ggen/crates/`. ggen's SPARQL/oxigraph surface now lives in `ggen-graph` / `ggen-engine` (`DeterministicGraph`, `SparqlEvaluator`). |
| NIF is a thin wrapper over a path dep | Hex-publish law forbids path deps; `src/query_engine.rs` + `src/oxigraph_engine.rs` are the **owned** engine copy. Do not reintroduce a `path =` dependency on ggen. |

Owned wrappers (`src/*.rs`, `lib/ggen_igniter/native/graph_nif.ex`,
`lib/ggen_igniter/query/oxigraph.ex`) name the removed crate only as
provenance history and point here — not a live sync edge.

## oxigraph crate pin

| Surface | Version |
|---|---|
| `native/ggen_graph_nif/Cargo.toml` | **`=0.5.11`** (exact) |
| `Cargo.lock` resolution (this tree) | **0.5.11** |
| `~/ggen` workspace / lock | **0.5.11** (`features = ["rdf-12"]`) |
| Prior NIF pin | 0.5.9 (closed this lane) |

API note: both `Store::load_from_reader` and `Store::load_from_slice` exist on
0.5.11. This crate uses `load_from_reader` with `RdfParser::from_format`
(Turtle); ggen-engine prefers `load_from_slice`. Behavior for the NIF's
one-shot Turtle→SELECT path is equivalent; not a correctness drift.

## graphlaw ↔ oxigraph (runtime engines)

| Axis | Status | Evidence |
|---|---|---|
| Fixed sync engine | **graphlaw** (`GgenIgniter.Engine.fixed/0`) | `lib/ggen_igniter/engine.ex` |
| Oxigraph role | Reference / differential / `Query.Oxigraph` | NIF still built; not the fixed CLI engine |
| Row-shape PLAIN contract | **Aligned** | IRIs bare; literals lexical strings; bnodes `_:label` |
| Differential SELECT | **Green** | `test/ggen_igniter_graphlaw_engine_test.exs` vs `Query.Oxigraph.run/2` |
| Typed-literal → native Elixir (`true`/`42`) | **Disclosed non-goal** | Both engines return lexical strings; RDF.ex `elixir_mapping/2` coercion is out of scope for the NIF |
| ASK / CONSTRUCT | Both refuse (SELECT-only) with clear errors | Oxigraph: `NotSelectQuery`; graphlaw: RuntimeError |

## Rebuild / doctor

```sh
cd native/ggen_graph_nif && cargo build --release
# or: mix compile  # Rustler copies target → priv/native/ggen_graph_nif.so
mix test test/ggen_igniter_oxigraph_engine_test.exs \
         test/ggen_igniter_graphlaw_engine_test.exs
```

Doctor checks 14–15 assert `.so` freshness and a functional smoke query.
