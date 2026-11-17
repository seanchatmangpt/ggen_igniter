# Lane 18: native/ggen_graph_nif

Standing: UNVERIFIED

Read-only static exploration of the `native/ggen_graph_nif` crate and its Elixir binding. No
cargo build, `cargo test` or `mix test` was run this pass, so nothing here is a runtime
claim. The crate exposes two NIFs (`query_turtle/2`, `query_turtle_raw/2`), each building a
fresh in-memory oxigraph store per call. Error paths return `{:error, string}` tuples and a
grep found no `unwrap`, `expect`, `panic!`, `todo!` or `unsafe` in the sources. Two gaps
stand out: both NIFs run on the regular scheduler with no dirty-scheduler annotation, and
the crate has no Rust-side tests.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| N1 | Two NIFs: query_turtle, query_turtle_raw | READ | lib.rs:55-56,77-78 |
| N2 | No DirtyCpu schedule on either NIF | READ | lib.rs:55,77; grep Dirty empty |
| N3 | No unwrap/expect/panic!/todo!/unsafe in crate | READ | grep src: only comment word |
| N4 | Errors are {:error, String}; Elixir raises | READ | lib.rs:39,58,62; oxigraph.ex:140 |
| N5 | Panic behavior untested | UNVERIFIED | no test found |
| N6 | rustler 0.36.2, oxigraph 0.5.9 (rdf-12) | READ | Cargo.toml:12-13; Cargo.lock:317,618 |
| N7 | No #[test]; no cargo test in CI | READ | grep src, .github: none |
| N8 | Elixir tests: SELECT, errors, ASK, unicode | READ (not run) | engine_test.exs:17-328 |
| N9 | Only SELECT; ASK/CONSTRUCT NotSelectQuery | READ | oxigraph_engine.rs:129-131 |
| N10 | Literals lexical-only unless raw: true | READ | oxigraph_engine.rs:85-97 |
| N11 | Store and Turtle rebuilt on every call | READ | oxigraph_engine.rs:102-108 |
| N12 | Doc cites RemoteEngine todo!() not in crate | READ | lib.rs:5-8; grep todo! empty |
| N13 | Vendored; upstream path is /Users/sac/ggen | READ | oxigraph_engine.rs:5 |
| N14 | Loader uses Rustler; stubs call nif_error | READ | native/graph_nif.ex:9,23,38 |
| N15 | mix.exs packages crate; rustler ~> 0.36 | READ | mix.exs:144-145,202 |
| N16 | CI caches NIF cargo target; nif_compiles | READ (not run) | ci.yml:81,109-113 |
| N17 | priv/native absent; NIF not built here | READ | ls priv/native: no such file |

## Next

1. Measure N2: run a large-graph query under `:erlang.statistics` scheduler utilization,
   then decide whether `schedule = "DirtyCpu"` is warranted.
2. Add a Rust `#[cfg(test)]` module for `normalize_term` and `run_query` (N7), and wire
   `cargo test` into CI.
3. Add an Elixir test provoking a Rust panic path or confirm none is reachable (N5).
4. Fix the `lib.rs` header drift about `RemoteEngine` (N12), in a lane that owns the file.
5. Run `mix compile` and `mix test test/*oxigraph*` to turn N8 and N16 into receipts.
6. Consider a store-reuse or batched NIF if per-call reparse shows up in profiling (N11).

## See Also

- `native/CLAUDE.md`
- `docs/jira/v26.11.17/LANES.md`
- `docs/architecture/adr/0001-oxigraph-default-query-engine.md`
- `docs/jira/v26.11.17/02-engine-nif-vs-sparql.md`
