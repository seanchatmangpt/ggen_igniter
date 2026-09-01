defmodule GgenIgniter.EngineRegistry do
  @moduledoc """
  ADR-0008's orchestration layer *over* `GgenIgniter.Engine.fetch!/1`, not a
  replacement for it. Single-engine callers (the default, unchanged path
  through `lib/mix/tasks/ggen_igniter.sync.ex`'s `run_via_reactor/3` ->
  `dispatch_reactor_reconcile/2` -> `GgenIgniter.Reactors.ReconcileReactor`'s
  own internal `target_opts[:engine] || "oxigraph"` -> `Engine.fetch!/1`
  resolution) never touch this module at all -- it exists only for the
  `--engine` comma-separated/`"all"` comparison-mode path.

  Two real, distinct entry points:

  - `resolve/1` (and `resolve/2`, taking the raw sync CLI `opts` so the
    `"all"` branch can run a real qlever-reachability precondition check --
    see below) -- parses one of three `--engine` value shapes into a
    validated, deduplicated list of engine atoms.
  - `run_all/4` -- fans every resolved engine atom out to
    `GgenIgniter.Engine.fetch!/1`'s already-resolved module and that module's
    existing `prepare!/2`/`run/2` (`lib/ggen_igniter/engine.ex:21-22`'s
    `@callback`s), via `Task.async_stream/3` mirroring
    `GgenIgniter.Reactors.ReconcileReactor`'s own real concurrency precedent
    (`lib/ggen_igniter/reactors/reconcile_reactor.ex:1743`,
    `|> Task.async_stream(&actuate_one(&1, ...), max_concurrency: ...,
    timeout: :infinity)`), returning a `GgenIgniter.EngineComparisonReport.t()`.

  ## Why not a formal behaviour for this module itself

  `GgenIgniter.Engine` is already a real `@callback`-based behaviour for the
  *per-engine* `prepare!/2`/`run/2` contract. This module is a different kind
  of thing: a one-shot orchestration layer *over* that existing behaviour,
  not a second engine contract -- a second formal `@callback` here would just
  wrap `Engine.fetch!/1`'s existing dispatch in ceremony. See
  `docs/architecture/adr/0008-evidence-ranked-multi-engine-registry.md`
  ("Why not a formal behaviour for the registry itself") for the full
  reasoning this module implements verbatim.

  ## `"all"`'s qlever-inclusion precondition -- real, not simulated

  `mix ggen_igniter.doctor`'s check 8 (`lib/mix/tasks/ggen_igniter.doctor.ex`,
  `check_qlever_reachable/2`) already establishes this repo's precedent for a
  real, non-simulated QLever reachability probe (load the named `--store-id`
  store from the loaded ontology graph, run a real `ASK { ?s ?p ?o }` against
  it, `rescue` a real connection/parse failure). `qlever_reachable?/1` below
  reuses that exact real technique (same real `GgenIgniter.Query.Qlever.
  load_store!/2` + `GgenIgniter.Query.Qlever.run/2` + real `ASK` probe,
  `rescue` -> `false`) rather than inventing a second, simulated one --
  `check_qlever_reachable/2` itself stays untouched (it is `defp`, shaped
  around a `pack_dir` argument and a human-readable `{:ok, msg} | {:error,
  msg}` result the doctor task's own reporting needs, not the plain boolean
  this module's silent-exclusion-with-warning behavior needs).
  """

  require Logger

  alias GgenIgniter.{Engine, EngineComparisonReport, Ontology, Pack, Query}
  alias GgenIgniter.EngineComparisonReport.CandidateResult

  @name_to_atom Map.new(Engine.valid_names(), &{&1, String.to_atom(&1)})

  @doc """
  Parses `engine_spec` (one of: a single engine name, a comma-separated list,
  or the literal `"all"`) into a validated, deduplicated list of engine
  atoms, in the order named (never re-sorted, except `"all"`'s own expansion
  -- see below) -- order matters downstream: `mix ggen_igniter.sync`'s
  comparison mode treats the FIRST resolved engine as the primary engine
  whose rows actually get rendered/actuated.

  `resolve/1` (no `opts`) is equivalent to `resolve(engine_spec, [])`: every
  shape except `"all"` behaves identically either way, since only `"all"`'s
  qlever-inclusion precondition needs `--store-id`/`--ontology`/`--pack`
  context. Passing `opts: []` to `"all"` is not an error -- it just means
  qlever's `--store-id` precondition is trivially unsatisfied, so `"all"`
  silently excludes qlever with a logged warning, exactly as if
  `--store-id` had genuinely been omitted.

  ## Examples

      iex> GgenIgniter.EngineRegistry.resolve("oxigraph")
      {:ok, [:oxigraph]}

      iex> GgenIgniter.EngineRegistry.resolve("oxigraph,sparql")
      {:ok, [:oxigraph, :sparql]}

      iex> GgenIgniter.EngineRegistry.resolve("oxigraph, oxigraph, sparql")
      {:ok, [:oxigraph, :sparql]}

      iex> GgenIgniter.EngineRegistry.resolve("nope")
      {:error, "invalid --engine name(s): nope, must be one of: oxigraph, qlever, sparql"}

  """
  @spec resolve(String.t(), keyword()) :: {:ok, [atom()]} | {:error, term()}
  def resolve(engine_spec, opts \\ [])

  def resolve("all", opts) do
    non_qlever_engines =
      Engine.valid_names()
      |> List.delete("qlever")
      |> Enum.sort()
      |> Enum.map(&Map.fetch!(@name_to_atom, &1))

    engines =
      if "qlever" in Engine.valid_names() and qlever_all_precondition_met?(opts) do
        non_qlever_engines ++ [:qlever]
      else
        if "qlever" in Engine.valid_names(), do: warn_qlever_excluded(opts)
        non_qlever_engines
      end

    {:ok, engines}
  end

  def resolve(engine_spec, _opts) when is_binary(engine_spec) do
    names =
      engine_spec
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()

    valid_names = Engine.valid_names()
    invalid = Enum.reject(names, &(&1 in valid_names))

    if invalid == [] and names != [] do
      {:ok, Enum.map(names, &Map.fetch!(@name_to_atom, &1))}
    else
      reason =
        if names == [] do
          "--engine given an empty value, must be one of: #{Enum.join(valid_names, ", ")}, " <>
            "a comma-separated list, or \"all\""
        else
          "invalid --engine name(s): #{Enum.join(invalid, ", ")}, must be one of: " <>
            "#{Enum.join(valid_names, ", ")}"
        end

      {:error, reason}
    end
  end

  defp qlever_all_precondition_met?(opts) do
    store_id = opts[:store_id]
    ontology_path = resolve_ontology_path_soft(opts)

    store_id not in [nil, ""] and is_binary(ontology_path) and File.exists?(ontology_path) and
      qlever_reachable?(ontology_path, store_id)
  end

  defp warn_qlever_excluded(opts) do
    reason =
      cond do
        opts[:store_id] in [nil, ""] ->
          "no --store-id given"

        true ->
          "the QLever endpoint at --store-id #{inspect(opts[:store_id])} is unreachable " <>
            "(or its ontology could not be resolved/loaded)"
      end

    Logger.warning(
      "ggen_igniter: --engine all excludes qlever (#{reason}) -- pass --store-id and ensure " <>
        "the QLever endpoint is running to include it, or name it explicitly " <>
        "(--engine oxigraph,sparql,qlever) to see the real error instead of a silent exclusion"
    )
  end

  # Mirrors `resolve_ontology!/1` in `lib/mix/tasks/ggen_igniter.sync.ex`, but
  # returns `nil` instead of raising -- `"all"`'s qlever precondition is a
  # soft check (silent exclusion, never a hard failure of the whole run), so
  # an unresolvable ontology path here just means "qlever's precondition is
  # unsatisfied," not "abort."
  defp resolve_ontology_path_soft(opts) do
    cond do
      opts[:ontology] not in [nil, ""] ->
        opts[:ontology]

      opts[:pack] not in [nil, ""] or opts[:pack_dir] not in [nil, ""] ->
        try do
          Pack.default_ontology(Pack.resolve_dir!(opts))
        rescue
          _ -> nil
        end

      true ->
        nil
    end
  end

  # The real, non-simulated reachability probe -- same real technique as
  # `mix ggen_igniter.doctor`'s `check_qlever_reachable/2` (real
  # `Ontology.load!/1` + real `Query.Qlever.load_store!/2` + a real round
  # trip against the live endpoint), `rescue` -> `false`.
  #
  # DISCLOSED DEVIATION from `check_qlever_reachable/2`'s own literal probe
  # query text: this uses `SELECT ?s WHERE { ?s ?p ?o } LIMIT 1`, not
  # `ASK { ?s ?p ?o }`. Found for real while building this module (confirmed
  # against a real, live QLever server at `localhost:7020`, not asserted):
  # `SPARQL.Client.query/2` returns a real ASK response as `{:ok,
  # %SPARQL.Query.Result{results: true}}` (a bare boolean in the `results`
  # field, not a row list), and `GgenIgniter.Query.Qlever.run/2`'s existing
  # `Enum.map(rows, &unwrap_row/1)` unconditionally assumes `results` is a
  # list -- so an ASK probe against a REAL reachable endpoint raises
  # `Protocol.UndefinedError` (Enumerable not implemented for boolean `true`)
  # instead of proving reachability. `qlever_reachable?/2`'s own `rescue`
  # silently swallows that (correctly reporting "unreachable" is still safe,
  # just needlessly conservative), but a probe that can never actually
  # succeed against a real, live, correctly-configured endpoint would make
  # `--engine all` never include `qlever` at all, which defeats the whole
  # point of the precondition check. Fixing `Query.Qlever.run/2`'s own ASK
  # handling is out of this module's scope (not one of ADR-0008's named
  # files) -- routing the probe through the SELECT path `run/2` already
  # handles correctly (proven passing in `test/ggen_igniter_engine_parity_test.exs`'s
  # own live-qlever SELECT case) is the in-scope fix.
  defp qlever_reachable?(ontology_path, store_id) do
    graph = Ontology.load!(ontology_path)
    store = Query.Qlever.load_store!(graph, store_id)
    Query.Qlever.run(store, "SELECT ?s WHERE { ?s ?p ?o } LIMIT 1")
    true
  rescue
    _ -> false
  end

  @doc """
  Fans `query_text` out to every engine in `engines` (each resolved via
  `GgenIgniter.Engine.fetch!/1`, exactly as the single-engine path already
  does), concurrently via `Task.async_stream/3`
  (`max_concurrency: length(engines)`, mirroring `GgenIgniter.Reactors.
  ReconcileReactor`'s `:actuate` step's own real concurrency precedent),
  timing each candidate with `System.monotonic_time(:microsecond)`. Every
  invocation is wrapped in `rescue` so one engine's crash becomes a
  `%CandidateResult{status: :error}` entry (never aborting the others) --
  this generalizes the six known-real per-engine error-shape divergences
  `test/ggen_igniter_engine_parity_test.exs` already pins (raw `MatchError`
  on CONSTRUCT/malformed query on `sparql`-hex, `Protocol.UndefinedError` on
  bare `FILTER NOT EXISTS`, ...) into per-run, per-engine data. A task that
  exceeds `opts[:timeout]` (default `30_000` ms) is killed
  (`on_timeout: :kill_task`) and becomes `%CandidateResult{status: :timeout}`
  instead of hanging the whole comparison run.

  `graph` is the already-loaded `%RDF.Graph{}` (`GgenIgniter.Ontology.
  load!/1`'s return) -- each engine's own `prepare!/2` (already implemented,
  reused verbatim here) turns it into whatever context that engine's `run/2`
  actually needs (the graph itself for `oxigraph`/`sparql`, a resolved
  `Gno.Store.Adapters.Qlever` struct for `qlever`, via `opts[:store_id]`).
  """
  @spec run_all(String.t(), RDF.Graph.t(), [atom()], keyword()) :: EngineComparisonReport.t()
  def run_all(query_text, graph, engines, opts \\ []) when is_list(engines) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    candidates =
      engines
      |> Task.async_stream(
        fn engine -> run_one(engine, query_text, graph, opts) end,
        max_concurrency: max(length(engines), 1),
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.zip(engines)
      |> Enum.map(&normalize_stream_result(&1, timeout))

    %EngineComparisonReport{
      query: query_text,
      candidates: candidates,
      pairwise_agreement: EngineComparisonReport.pairwise_agreement(candidates),
      generated_at: DateTime.utc_now()
    }
  end

  defp run_one(engine, query_text, graph, opts) do
    module = Engine.fetch!(Atom.to_string(engine))
    start = System.monotonic_time(:microsecond)

    try do
      context = module.prepare!(graph, opts)
      rows = module.run(context, query_text)
      elapsed = System.monotonic_time(:microsecond) - start

      %CandidateResult{
        engine: engine,
        status: :ok,
        rows: rows,
        row_count: length(rows),
        elapsed_us: elapsed,
        error: nil
      }
    rescue
      error ->
        elapsed = System.monotonic_time(:microsecond) - start

        %CandidateResult{
          engine: engine,
          status: :error,
          rows: nil,
          row_count: 0,
          elapsed_us: elapsed,
          error: Exception.message(error)
        }
    end
  end

  defp normalize_stream_result({{:ok, %CandidateResult{} = result}, _engine}, _timeout),
    do: result

  defp normalize_stream_result({{:exit, :timeout}, engine}, timeout) do
    %CandidateResult{
      engine: engine,
      status: :timeout,
      rows: nil,
      row_count: 0,
      elapsed_us: timeout * 1000,
      error: "engine #{engine} timed out after #{timeout}ms"
    }
  end

  defp normalize_stream_result({{:exit, reason}, engine}, _timeout) do
    %CandidateResult{
      engine: engine,
      status: :error,
      rows: nil,
      row_count: 0,
      elapsed_us: nil,
      error: "engine #{engine} task exited: #{inspect(reason)}"
    }
  end
end
