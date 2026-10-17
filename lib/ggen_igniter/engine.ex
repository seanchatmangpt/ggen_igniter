defmodule GgenIgniter.Engine do
  @moduledoc """
  Behaviour every engine implementation satisfies, so
  `Mix.Tasks.GgenIgniter.Sync` dispatches through `GgenIgniter.Engine.fetch!/1`
  instead of hardcoded, string-pattern-matched function clauses. Adding a new
  engine means adding one module + one registry entry, not
  editing the sync task's dispatch logic.

  ## The engine is NOT a choice anymore (2026-10-17)

  There is exactly ONE engine: **graphlaw** (`GgenIgniter.Engine.Graphlaw`,
  a real, independent SPARQL 1.1 identity running as a WASM module in-process
  via `wasmex`). The multi-engine selection surface (`--engine sparql`, the
  bug-ridden `sparql` hex 0.3.12 engine; `--engine qlever`; the oxigraph NIF
  as a selectable engine; comma-separated/`"all"` comparison mode) was REMOVED.
  `GgenIgniter.Engine.fetch!/1` now refuses every name except `"graphlaw"`
  (fail-closed). The sparql-hex engine's pinned bug history (no
  FILTER NOT EXISTS, ORDER BY ignored, ASK/CONSTRUCT broken) stays documented
  in git history and in `GgenIgniter.Engine.Graphlaw`'s moduledoc as the
  rationale for the standardization: graphlaw matched oxigraph row-for-row on
  the entire smalt-substrate-pack SELECT query set (11 queries measured
  2026-10-17, including OPTIONAL/!BOUND gates and ORDER BY), so there is no
  remaining need for a second engine.
  """

  @callback prepare!(RDF.Graph.t(), keyword()) :: term()
  @callback run(term(), String.t()) :: [map()]

  @engine_name "graphlaw"

  @registry %{
    @engine_name => GgenIgniter.Engine.Graphlaw
  }

  @doc """
  The single, FIXED engine name (a constant, not a choice).
  """
  @spec fixed() :: String.t()
  def fixed, do: @engine_name

  @doc """
  The engine name => implementing module map. Exactly one entry; kept as a map
  so `fetch!/1`'s lookup shape is unchanged.
  """
  @spec registry() :: %{optional(String.t()) => module()}
  def registry, do: @registry

  @doc """
  Valid engine names. Exactly one: the fixed engine.

  ## Examples

      iex> GgenIgniter.Engine.valid_names()
      ["graphlaw"]

  """
  @spec valid_names() :: [String.t()]
  def valid_names, do: Enum.sort(Map.keys(@registry))

  @doc """
  Looks up the engine module for `name`. Any name other than the fixed engine
  raises `ArgumentError` — the engine is not a choice.

  ## Examples

      iex> GgenIgniter.Engine.fetch!("graphlaw")
      GgenIgniter.Engine.Graphlaw

      iex> GgenIgniter.Engine.fetch!("sparql")
      ** (ArgumentError) invalid --engine "sparql", the engine is fixed to "graphlaw" (no engine choice)

  """
  @spec fetch!(String.t()) :: module()
  def fetch!(name) do
    case Map.fetch(@registry, name) do
      {:ok, module} -> module
      :error ->
        raise ArgumentError,
              "invalid --engine #{inspect(name)}, the engine is fixed to #{inspect(@engine_name)} (no engine choice)"
    end
  end
end
