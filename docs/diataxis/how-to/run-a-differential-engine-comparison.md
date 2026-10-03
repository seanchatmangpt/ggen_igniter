# How to: run a differential engine comparison

Run the same SPARQL query through two or more independent SPARQL engine
identities and refuse the run when they disagree. This is the
`--engine oxigraph,graphlaw` / `--engine all` comparison mode of
`mix ggen_igniter.sync` (ADR-0008).

## When to use this

- You want evidence that a gate query's row set does not depend on which
  engine happens to be on the hot path.
- You are qualifying a new engine identity (e.g. graphlaw) against the
  current default (oxigraph).

## The four engines

Valid `--engine` names are exactly the keys of
`GgenIgniter.Engine.registry/0`
(`lib/ggen_igniter/engine.ex`): `graphlaw`, `oxigraph`, `qlever`, `sparql`.

| name | what runs the query | notes |
|---|---|---|
| `oxigraph` | native oxigraph Rustler NIF in-process (**default**) | rows come back as unprocessed N-Triples-style term strings (IRIs angle-bracket-wrapped, literals quoted); a Rust toolchain is needed to compile the library at all |
| `sparql` | pure-Elixir `sparql` hex package in-process | known `ORDER BY` row-reversal bug at v0.3.12; known `FILTER NOT EXISTS`/`UNION` limitations |
| `qlever` | a real, already-running QLever HTTP endpoint | `--store-id` required; the `--ontology` graph is only read to look up the `gnoa:Qlever`-typed store resource |
| `graphlaw` | graphlaw WebAssembly module (PurRDF) hosted in-process by `wasmex` | artifact ships at `priv/graphlaw_wasm.wasm`; same plain row normalization as oxigraph |

## Compare two engines

```
mix ggen_igniter.sync \
  --engine oxigraph,graphlaw \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex
```

Behavior (`lib/ggen_igniter/engine_registry.ex`,
`lib/mix/tasks/ggen_igniter.sync.ex` comparison-mode section):

- The **first** named engine is the primary: its rows are what get
  rendered/actuated.
- Every resolved engine's `prepare!/2`/`run/2` (`GgenIgniter.Engine`
  behaviour, `lib/ggen_igniter/engine.ex`) is fanned out concurrently via
  `Task.async_stream/3`, each timed with `System.monotonic_time(:microsecond)`.
- One engine crashing becomes a `%CandidateResult{status: :error}` entry,
  never aborting the others; a task exceeding the timeout (default
  `30_000` ms) is killed and recorded as `:timeout`.
- When engines disagree on row-set, the run **refuses** (nonzero exit)
  rather than rendering from either side.

## Inspect the report

Without `--engine-report`, a compact summary (row count, elapsed time,
pairwise row-set agreement, per-engine errors) prints to stdout after the
run. Pass `--engine-report PATH` to write a full
`GgenIgniter.EngineComparisonReport` — `.json` extension for JSON
(`to_json/1`), anything else for Markdown (`to_markdown/1`).

## `--engine all`

`--engine all` expands to every engine whose preconditions are met
(`lib/ggen_igniter/engine_registry.ex` `resolve/2`): qlever is included
only when `--store-id` was given AND a real reachability probe
(`SELECT ?s WHERE { ?s ?p ?o } LIMIT 1` against the live endpoint)
succeeds. Otherwise qlever is silently excluded with a logged warning —
name it explicitly (`--engine oxigraph,sparql,qlever`) if you want the real
error instead of silent exclusion.

## API notes (if you call the registry directly)

- `GgenIgniter.EngineRegistry.resolve/1,2` parses a single name,
  comma-separated list, or `"all"` into a validated, deduplicated engine
  atom list, in the order named. Invalid names return
  `{:error, "invalid --engine name(s): nope, must be one of: graphlaw, oxigraph, qlever, sparql"}`.
- `GgenIgniter.EngineRegistry.run_all/4` fans a query out and returns a
  `GgenIgniter.EngineComparisonReport.t()`.

## Caveats, verified in code

- Row-value shape differs between `sparql` (bare unwrapped values) and
  `oxigraph`/`graphlaw` (plain but N-Triples-normalized values) —
  `lib/mix/tasks/ggen_igniter.sync.ex` moduledoc.
- `graphlaw`'s artifact is resolved in this order
  (`lib/ggen_igniter/engine/graphlaw.ex`): `Application.get_env(:ggen_igniter,
  :graphlaw_wasm_path)` override, else the packaged `priv/graphlaw_wasm.wasm`
  (sha256 `8bfff66cccd1e1a4834d61a893888bb479f046c1da1152a29098be7de0fe71a8`),
  else the dev default `~/graphlaw/target/wasm32-wasip1/wasm/graphlaw_wasm.wasm`.
  A missing artifact fails fast in `prepare!/2` with a typed error naming
  the paths tried.
