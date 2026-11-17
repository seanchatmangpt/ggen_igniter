# Lane 02: Engine.run/2, oxigraph NIF vs sparql engine divergence

Standing: UNVERIFIED

Read-only exploration, v26.11.17. No `mix` binary is on PATH and `_build/` is absent in this
checkout (`which mix` printed nothing; `ls _build` -> "No such file or directory"), so no test
or compile was run. Every finding below is from reading source and grepping, not from a run.
The lane premise (CLAUDE.md line 7: the NIF is the default `--engine`, the `sparql` engine has
`FILTER NOT EXISTS`/`UNION` limits) is stale in the pipeline: since 2026-10-17 the engine is
fixed to graphlaw (wasm), and the NIF and the `--engine` surface are gone from the sync path.
The divergence still exists in three residual places: the `Query.run/2` facade over oxigraph,
the SHACL/prose paths that call the `sparql` hex package directly, and stale docs. There is also
no `Engine.run/2` function; `run/2` is a behaviour callback on each engine module.

## Findings

[E] = `lib/ggen_igniter/engine.ex`; other paths relative to `lib/ggen_igniter/` or as named.

| id | finding | standing | evidence |
|---|---|---|---|
| F01 | Engine fixed to `"graphlaw"`; `fetch!/1` raises otherwise | UNVERIFIED | [E]:29-33,74-82 |
| F02 | No `Engine.run/2` function; only a `@callback run/2` | UNVERIFIED | [E]:26-27 |
| F03 | CLAUDE.md:7 says NIF is default `--engine`; stale | UNVERIFIED | CLAUDE.md:7 vs [E]:9-23 |
| F04 | sync `strict:` list has no `--engine` switch | UNVERIFIED | grep of `strict:` block: empty |
| F05 | status.md:73-77 lists removed engines | UNVERIFIED | status.md:73-77; [E]:11-17 |
| F06 | engines.md lists 4 engines, obsolete error text | UNVERIFIED | engines.md:1,21; [E]:80 |
| F07 | status.md:139 cites Engine.Qlever at engine.ex:137 | UNVERIFIED | `wc -l [E]` -> 84 lines |
| F08 | NIF still used by Query.run/2, doctor | UNVERIFIED | query.ex:14; doctor.ex:918 |
| F09 | Query.run/2=oxigraph, pipeline=graphlaw; no diff test | UNVERIFIED | query.ex:3-9; [E]:11 |
| F10 | sparql hex still runs in SHACL/prose paths | UNVERIFIED | shacl.ex:644; prose.ex:729 |
| F11 | 050_frontier.rq dodges NOT EXISTS; 5 use it | UNVERIFIED | 050_frontier.rq:2-4; grep |
| F12 | No graphlaw NOT EXISTS/UNION test; no receipt | UNVERIFIED | grep empty; [E]:20-23 |
| F13 | Graphlaw SELECT-only; CONSTRUCT untested | UNVERIFIED | graphlaw.ex:51-56; test:110-116 |
| F14 | oxigraph moduledoc cites a nonexistent test file | UNVERIFIED | `ls test`: file absent |
| F15 | wasm present; sha256 equals pinned constant | UNVERIFIED | `sha256sum`; graphlaw.ex:73 |
| F16 | Third wasm fallback is a `~/graphlaw` author-machine path | UNVERIFIED | graphlaw.ex:67 |
| F17 | Graph re-serialized to Turtle per prepare!/2 | UNVERIFIED | graphlaw.ex:75-78 |
| F18 | Plain-lexical literals; no bool/int coercion | UNVERIFIED | status.md:90; graphlaw.ex:10 |
| F19 | run_all kept for legacy; agreement vacuous | UNVERIFIED | engine_registry.ex:47-74 |
| F20 | resolve accepts only all/graphlaw | UNVERIFIED | engine_registry.ex:28-44 |

## Next

1. Run `mix compile --warnings-as-errors` and `mix test` where a toolchain exists; promote or
   refute F01-F20 with real output.
2. Run `FILTER NOT EXISTS` and `UNION` probes (the five `.rq` files in F11) against graphlaw and
   against `Query.Oxigraph`; record the row diff. This is the only way to settle F09 and F12.
3. Correct CLAUDE.md:7, `docs/status.md:73-77,139` and `docs/reference/cli/engines.md`
   (lanes 15, 16, 19 own those; hand off F03, F05, F06, F07).
4. Decide whether `Query.run/2` should route to graphlaw (one engine) or keep oxigraph; add a
   differential test if both stay (F08, F09).
5. Add a CONSTRUCT refusal test for graphlaw and restore or retarget the missing
   ASK/CONSTRUCT divergence test cited by the oxigraph moduledoc (F13, F14).
6. Audit SHACL and prose `SPARQL.execute_query` call sites for the NOT EXISTS crash class (F10).

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/jira/v26.11.17/18-native-nif.md` (NIF crate, lane 18)
- `docs/jira/v26.11.17/11-gate-non-vacuity.md` (gate coverage, lane 11)
- `lib/ggen_igniter/engine.ex`, `lib/ggen_igniter/engine/graphlaw.ex`
