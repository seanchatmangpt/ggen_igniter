# ADR-0008: Evidence-Ranked Multi-Engine Registry for `--engine` Comparison Mode

## Status

**PROPOSED.** Not accepted, not implemented. No code in `lib/`, `test/`, or
`priv/ggen/` for this decision exists as of this writing — `EngineRegistry`,
`EngineComparisonReport`, `CandidateResult`, and the `--engine-report` flag
are all new names introduced by this ADR, none of which resolve to a real
file today. This deliberately deviates from this directory's own convention
(`docs/CLAUDE.md`: "Never write a 'Proposed' ADR into this directory — this
repo only records decisions already made and verified") at the explicit
request of the design's author, to capture a reviewed design before
implementation begins; it should not be read as this repo's committed
`Accepted` status vocabulary being loosened for any other ADR.

## Context

`ggen_igniter` supports three SPARQL query engines today, dispatched through
one behaviour, `GgenIgniter.Engine` (`lib/ggen_igniter/engine.ex:1-20`,
`@callback prepare!/2` + `@callback run/2`), looked up via a flat registry
map (`lib/ggen_igniter/engine.ex:23-27`, `@registry %{"sparql" => ...,
"qlever" => ..., "oxigraph" => ...}`) and resolved by
`GgenIgniter.Engine.fetch!/1` (`lib/ggen_igniter/engine.ex:73-78`), which
raises `ArgumentError` on an unknown name. `Mix.Tasks.GgenIgniter.Sync`
currently accepts exactly one `--engine` value at a time
(`lib/mix/tasks/ggen_igniter.sync.ex:942-943`: `engine_name = opts[:engine]
|| "oxigraph"` then `engine_module = Engine.fetch!(engine_name)`, repeated
at `:1077-1078` for the reactor-delegatable path) and dispatches every named
query through that single engine module — there is no comparison mode, no
concurrent multi-engine fan-out, and no on-disk or stdout comparison report
anywhere in this codebase today.

Two real, already-landed test files already establish, empirically, that the
three engines diverge in specific, characterized ways — this ADR's design
must build on that existing evidence rather than re-deriving it:

1. **`test/ggen_igniter_cross_engine_equivalence_properties_test.exs:1-50`**
   — a StreamData property test proving `GgenIgniter.Query.run/2`
   (`--engine sparql`) and `GgenIgniter.Query.Oxigraph.run/2`
   (`--engine oxigraph`) return the *same set* of rows (via `MapSet`,
   deliberately ignoring order) across many randomly generated small
   `%RDF.Graph{}` values. Its moduledoc names two divergences as explicitly
   out of scope and already normalized: (a) the confirmed `sparql`-hex
   `ORDER BY` row-reversal bug, documented at the source in
   `lib/ggen_igniter/query.ex:4-16`'s own moduledoc (10 rows returned
   `[9, 8, ..., 0]` instead of ascending `[0, 1, ..., 9]`) and avoided in
   this property test by using an `ORDER BY`-free query template; (b) a
   now-fixed-at-the-NIF-source term-encoding divergence.
2. **`test/ggen_igniter_engine_parity_test.exs:1-32`** — a fixed
   contract-matrix test running 9 query shapes (SELECT, ASK, CONSTRUCT,
   empty-result, FILTER, FILTER NOT EXISTS, typed-literal, unicode-literal,
   malformed) against `sparql`-hex, the oxigraph NIF, and (skipped without a
   live server) `qlever`, pinning 6 known-real divergences as regression
   assertions: `ORDER BY` reversal (line 18-20), ASK returning
   SELECT-shaped bindings instead of a boolean on `sparql`-hex (line 21-24,
   `describe "ASK ..."` at line 186), CONSTRUCT raising a raw `MatchError`
   on `sparql`-hex (line 25-26, `describe` at line 208), malformed query
   raising `MatchError` instead of a clean error (line 27-29, `describe` at
   line 231), and bare `FILTER NOT EXISTS` raising
   `Protocol.UndefinedError` on `sparql`-hex unconditionally (line 30-31,
   `describe` at line 162, `test` at line 170, `assert_raise
   Protocol.UndefinedError, ~r/SPARQL.Algebra.Expression/` at line 171).

**Consequence for scope**: the design below's `pairwise_agreement`
computation is not a new correctness oracle. It is a machine-consumable,
per-run *surfacing* of exactly the row-set/row-order/error-shape
distinctions these two test files already established statically and by
hand. The genuinely new capability is runtime, ad hoc, N-way (not just
2-way) comparison with real timing, invoked via `--engine`, not a stronger
correctness claim than the tests already make.

`GgenIgniter.Reactors.ReconcileReactor`'s `:actuate` step already
establishes this repo's precedent for real concurrent fan-out via
`Task.async_stream/3` (`lib/ggen_igniter/reactors/reconcile_reactor.ex:1743`,
`|> Task.async_stream(&actuate_one(&1, ...), ...)`) — this design reuses that
same stdlib primitive rather than introducing a new concurrency mechanism.
`mix ggen_igniter.doctor`'s check 8 (`lib/mix/tasks/ggen_igniter.doctor.ex:622-631`,
`maybe_check_qlever/2` / `check_qlever_reachable/2`) already establishes
this repo's precedent for a real, non-simulated QLever reachability probe
(a real `ASK` query against the endpoint) gated on `--store-id` being
present (`lib/mix/tasks/ggen_igniter.doctor.ex:513`, `needs_gno? =
opts[:engine] == "qlever"`) — this design's `"all"` precondition check for
`qlever` reuses that same reachability-check shape rather than inventing a
new one.

## Decision

Introduce a new, non-behaviour module `GgenIgniter.EngineRegistry`
(`lib/ggen_igniter/engine_registry.ex`, not yet created) that sits *beside*
`GgenIgniter.Engine.fetch!/1`, not in place of it. Single-engine callers —
the default, unchanged path through `sync.ex:942-943` and `:1077-1078` —
never touch `EngineRegistry` at all; this is additive, not a replacement of
the existing behaviour-based dispatch.

### Why not a formal behaviour for the registry itself

`GgenIgniter.Engine` is already a real `@callback`-based behaviour
(`lib/ggen_igniter/engine.ex:19-20`) for the *per-engine* `prepare!/2` /
`run/2` contract. `EngineRegistry` is a different kind of thing: an
orchestration layer *over* that existing behaviour, not a second engine
contract. The three engines' real call shapes already differ enough that a
second formal contract at the registry layer would just wrap
`Engine.fetch!/1`'s existing dispatch in ceremony — `Query.run/2` needs only
a `%RDF.Graph{}`, `Query.Oxigraph.run/2` needs a compiled NIF ref (obtained
via each engine module's own `prepare!/2`, already abstracting this), and
`Query.Qlever.run/2` needs a resolved `--store-id` store
(`lib/ggen_igniter/engine.ex:120-122`, `store_id = opts[:store_id] ||
raise ArgumentError, "--store-id is required when --engine qlever is
given"`). `EngineRegistry` reuses `Engine.fetch!/1`'s already-resolved
module + each module's already-implemented `prepare!/2`/`run/2` rather than
duplicating that resolution or validation logic.

### `EngineRegistry` shape

```
EngineRegistry.resolve(engine_spec :: String.t()) :: {:ok, [atom]} | {:error, term}
```

Parses one of three `--engine` value shapes into a validated, deduplicated,
precondition-checked list of engine atoms:

- A single name (`"oxigraph"`, `"sparql"`, `"qlever"`) — current behavior,
  unchanged, resolves to a one-element list.
- A comma-separated list (`"oxigraph,sparql"`) — resolves to a deduplicated
  list, each name validated against `GgenIgniter.Engine.valid_names/0`
  (`lib/ggen_igniter/engine.ex:53`, the existing single source of truth for
  valid `--engine` names), reusing it rather than re-deriving a second
  validation list.
- The literal `"all"` — expands to every engine in
  `GgenIgniter.Engine.registry/0` (`lib/ggen_igniter/engine.ex:23-27`) whose
  preconditions are satisfied: `qlever` is included in `"all"`'s expansion
  only if `--store-id` was given *and* a doctor-style reachability check
  (reusing the shape of `check_qlever_reachable/2`,
  `lib/mix/tasks/ggen_igniter.doctor.ex:631`) passes; otherwise `qlever` is
  silently excluded from `"all"`'s resolved list with a warning logged, and
  never included and then allowed to error later in the run.

```
EngineRegistry.run_all(query_text, graph_or_store, engines :: [atom], opts) ::
  GgenIgniter.EngineComparisonReport.t()
```

The one new entry point. Fans out each engine atom to
`GgenIgniter.Engine.fetch!/1`'s already-resolved module and that module's
existing `run/2` (`lib/ggen_igniter/engine.ex:19-20`'s `@callback run/2`),
via `Task.async_stream/3` with `max_concurrency: length(engines)` (real
concurrent execution over real per-engine calls, no simulated concurrency —
mirroring `reconcile_reactor.ex:1743`'s existing pattern in this codebase),
timing each candidate with `System.monotonic_time/1`. Each engine
invocation is wrapped in a `rescue` clause so one engine's crash or timeout
becomes a `%CandidateResult{status: :error}` entry rather than aborting the
others — this directly generalizes the six known-real per-engine
error-shape divergences `test/ggen_igniter_engine_parity_test.exs` already
pins as regression assertions (raw `MatchError` on CONSTRUCT, raw
`MatchError` on malformed query, `Protocol.UndefinedError` on bare `FILTER
NOT EXISTS`) into per-run, per-engine data rather than a test-time-only
assertion.

### `GgenIgniter.EngineComparisonReport` shape

A plain struct (no behaviour needed at this scale — the same reasoning that
kept `EngineRegistry` itself out of behaviour ceremony applies here):

```elixir
defmodule GgenIgniter.EngineComparisonReport do
  defstruct [:query, :candidates, :pairwise_agreement, :generated_at]
end

defmodule GgenIgniter.EngineComparisonReport.CandidateResult do
  defstruct [:engine, :status, :rows, :row_count, :elapsed_us, :error]
  # status :: :ok | :error | :timeout
end
```

- `query` — the SPARQL text run, verbatim.
- `candidates` — `[%CandidateResult{}]`, one per resolved engine.
- `pairwise_agreement` — `%{ {engine_a, engine_b} => %{row_set_equal?:
  boolean, row_count_diff: integer, order_equal?: boolean} }`. Row-set
  equality is computed via `MapSet.new/1` over normalized rows — mirroring
  `test/ggen_igniter_cross_engine_equivalence_properties_test.exs`'s own
  set-comparison method for the identical reason that test file names
  (order is a separately-tracked, already-known-divergent axis, not folded
  into one boolean). Order equality is a separate raw-list `==` check,
  deliberately kept apart from set equality per the `ORDER BY` reversal bug
  already pinned in `lib/ggen_igniter/query.ex:4-16`'s moduledoc — a future
  divergence of this exact shape shows up in a report as `order_equal?:
  false` with `row_set_equal?: true`, rather than being collapsed into a
  single ambiguous boolean.
- `generated_at` — `DateTime.t()`.

`to_markdown/1` and `to_json/1` renderers produce the on-disk/stdout report.
No new templating path: `to_markdown/1` follows this repo's existing
`GgenIgniter.Render.render/2` convention (`lib/ggen_igniter/render.ex:8-11`,
stdlib `EEx.eval_string/2` against bindings) rather than inventing a second
one — either an EEx template under `priv/ggen/` or an equivalent plain
function using the same `EEx.eval_string/2` primitive. No new dependency:
`MapSet`, `Task.async_stream/3`, and `DateTime` are all stdlib, already used
elsewhere in this codebase (`Task.async_stream/3` at
`reconcile_reactor.ex:1743`).

### CLI shape (`Mix.Tasks.GgenIgniter.Sync`)

`--engine` keeps accepting today's single value
(`lib/mix/tasks/ggen_igniter.sync.ex:668`, `--engine ENGINE One of: oxigraph,
sparql, qlever. Default: oxigraph.`) unchanged — default behavior is
unaffected by this decision. `--engine` additionally accepts a
comma-separated list or the literal `"all"`, parsed via
`EngineRegistry.resolve/1`. Any of these forms resolving to more than one
engine flips `sync.ex` into **comparison mode**:

- Each candidate engine's query run happens via `EngineRegistry.run_all/4`
  as described above.
- Downstream rendering and actuation (`Render.render/2`,
  `Actuate.write_file!/3` / `inject_content!/5` / `eval_code!/2`) use only
  one designated **primary** engine's rows — the first engine named in the
  `--engine` list, or `oxigraph` when `--engine all` was given (matching
  today's existing default at `sync.ex:942`/`:1077`). Comparison mode is
  strictly diagnostic-additive: it does not change which rows get rendered
  or actuated, so it introduces no change to this repo's actuation
  semantics, admission invariants, or receipt/manifest behavior (ADR-0005,
  ADR-0004).
- A new, optional `--engine-report PATH` flag writes the
  `GgenIgniter.EngineComparisonReport` (via `to_json/1` or `to_markdown/1`,
  chosen by `PATH`'s extension) to disk. Without `--engine-report`, a
  compact summary table (row count per engine, elapsed time per engine,
  pairwise row-set-agreement percentage, any per-engine errors) prints to
  stdout after the `sync`/`doctor` run completes.

## Consequences (of adopting this design, if accepted)

- **No change to single-engine callers or default behavior.** Every
  existing `mix ggen_igniter.sync --engine oxigraph|sparql|qlever` (or no
  `--engine` flag at all) invocation is byte-for-byte unaffected —
  `EngineRegistry` is invoked only when `--engine` resolves to more than one
  engine.
- **No new correctness claim.** `pairwise_agreement` restates, at runtime
  and per-query, exactly the divergence classes
  `test/ggen_igniter_cross_engine_equivalence_properties_test.exs` and
  `test/ggen_igniter_engine_parity_test.exs` already established
  statically. This design does not supersede or reduce the value of either
  test file; both remain the authoritative, CI-run source of truth for
  *which* divergences are known-real, while the new report is a per-invocation
  *surfacing* mechanism for operators, not a second test suite.
- **`qlever`'s inclusion in `--engine all` is deliberately conservative.**
  Silent exclusion-with-warning (rather than inclusion-then-error) when
  `--store-id` is absent or the endpoint is unreachable avoids a `--engine
  all` invocation failing the whole comparison run over one engine's
  environmental unavailability — this mirrors `mix ggen_igniter.doctor`'s
  own existing pattern of treating `qlever` reachability as conditionally
  checked, not unconditionally required
  (`lib/mix/tasks/ggen_igniter.doctor.ex:622-625`).
- **New disk artifact surface, opt-in only.** `--engine-report PATH` is the
  only new persistent output this design introduces; without it, comparison
  mode's only effect beyond normal `sync` behavior is a stdout summary table
  and (per-run) additional wall-clock time proportional to the slowest
  resolved engine (bounded by `max_concurrency: length(engines)`, not
  serialized).
- **No implementation exists yet.** This ADR records a reviewed design, not
  a landed decision. Before any code lands under this design,
  `docs/CLAUDE.md`'s status-vocabulary discipline requires this ADR's
  `## Status` to be updated to `Accepted` with a real citation (source
  line + a real command's output), per this directory's own convention —
  the same convention this ADR's own `PROPOSED` status is a disclosed,
  explicit exception to.

## See also

- `docs/architecture/adr/0001-oxigraph-default-query-engine.md` — the
  `ORDER BY` reversal bug this design's `order_equal?` field is built to
  keep visible, not hide
- `docs/architecture/adr/0005-receipt-independent-of-manifest.md` — why
  comparison mode is designed to be actuation-inert (no receipt/manifest
  interaction) rather than treated as a second write path
- `test/ggen_igniter_cross_engine_equivalence_properties_test.exs` — the
  existing row-set-equivalence property this design's `pairwise_agreement`
  surfaces at runtime rather than re-deriving
- `test/ggen_igniter_engine_parity_test.exs` — the existing fixed
  9-query-shape × 3-engine contract matrix pinning the 6 known-real
  divergences this design's per-engine `:error` `CandidateResult`s
  generalize
- `docs/status.md` — should gain a row for this design's status once
  implementation begins, per `docs/CLAUDE.md`'s sourcing rule
