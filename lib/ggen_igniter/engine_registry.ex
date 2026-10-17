defmodule GgenIgniter.EngineRegistry do
  @moduledoc """
  REMOVED SURFACE (2026-10-17): the multi-engine comparison registry
  (ADR-0008's `resolve/2` of comma-separated/`"all"` engine specs, the qlever
  reachability precondition, and `run_all/4` fan-out over selectable engines)
  existed to compare/select among `sparql`/`qlever`/`oxigraph`/`graphlaw`.
  The engine is now FIXED (`GgenIgniter.Engine.fixed/0` == `"graphlaw"`),
  so there is nothing left to resolve or compare: this module is a thin,
  fail-closed layer over the single fixed engine.

  SHIM-COURT non-vacuity receipt for the standardization: graphlaw matched
  the oxigraph reference engine row-for-row on the entire smalt-substrate-pack
  SELECT query set (11 queries, measured 2026-10-17, including the
  OPTIONAL/!BOUND gates and ORDER BY), so the selectable surface had no
  remaining job and was removed rather than kept as dead scaffolding.
  """

  alias GgenIgniter.{Engine, EngineComparisonReport}

  @doc """
  Resolves an engine spec to the single fixed engine. Any spec other than the
  fixed engine's own name (or the historical `"all"`, which now trivially
  expands to the one engine) is a typed refusal -- the engine is not a choice.
  """
  @spec resolve(String.t(), keyword()) :: {:ok, [atom()]} | {:error, String.t()}
  def resolve(engine_spec, _opts \\ [])

  def resolve("all", _opts), do: {:ok, [engine_atom()]}

  def resolve(engine_spec, _opts) when is_binary(engine_spec) do
    names = engine_spec |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.uniq()
    valid = Engine.valid_names()

    if names == [Engine.fixed()] do
      {:ok, [engine_atom()]}
    else
      invalid = Enum.reject(names, &(&1 in valid))

      {:error,
       "invalid --engine name(s): #{Enum.join(invalid, ", ")}, the engine is fixed to " <>
         "#{Engine.fixed()} (no engine choice)"}
    end
  end

  @doc """
  Runs `query_text` against the one fixed engine (kept for callers of the
  historical `run_all/4`; with one engine the report carries a single
  candidate). Timing + rescue semantics unchanged: one engine's crash becomes
  a `%CandidateResult{status: :error}` entry, never an abort.
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

  defp engine_atom, do: String.to_atom(Engine.fixed())

  defp run_one(engine, query_text, graph, opts) do
    module = Engine.fetch!(Atom.to_string(engine))
    start = System.monotonic_time(:microsecond)

    try do
      context = module.prepare!(graph, opts)
      rows = module.run(context, query_text)
      elapsed = System.monotonic_time(:microsecond) - start

      %EngineComparisonReport.CandidateResult{
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

        %EngineComparisonReport.CandidateResult{
          engine: engine,
          status: :error,
          rows: nil,
          row_count: 0,
          elapsed_us: elapsed,
          error: Exception.message(error)
        }
    end
  end

  defp normalize_stream_result({{:ok, %EngineComparisonReport.CandidateResult{} = r}, _}, _),
    do: r

  defp normalize_stream_result({{:exit, :timeout}, engine}, timeout) do
    %EngineComparisonReport.CandidateResult{
      engine: engine,
      status: :timeout,
      rows: nil,
      row_count: 0,
      elapsed_us: timeout * 1000,
      error: "engine #{engine} timed out after #{timeout}ms"
    }
  end

  defp normalize_stream_result({{:exit, reason}, engine}, _) do
    %EngineComparisonReport.CandidateResult{
      engine: engine,
      status: :error,
      rows: nil,
      row_count: 0,
      elapsed_us: nil,
      error: "engine #{engine} task exited: #{inspect(reason)}"
    }
  end
end
