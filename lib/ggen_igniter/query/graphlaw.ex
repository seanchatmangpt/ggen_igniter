defmodule GgenIgniter.Query.Graphlaw do
  @moduledoc """
  One-shot SPARQL SELECT over an in-memory `RDF.Graph` through the graphlaw
  WASM engine (`GgenIgniter.Engine.Graphlaw`), replacing the oxigraph NIF as the
  engine behind `GgenIgniter.Query.run/2`.

  Same `[map()]` row contract as `GgenIgniter.Query.Oxigraph.run/2`: string keys,
  plain unwrapped values, unbound variables omitted. Raises `RuntimeError` on any
  engine refusal. `raw: true` (oxigraph's N-Triples term strings) is not
  available here and is refused with `ArgumentError`.
  """

  alias GgenIgniter.Engine.Graphlaw

  @doc "True when the graphlaw wasm artifact resolves and instantiates."
  @spec available?() :: boolean()
  def available? do
    Graphlaw.prepare!(RDF.Graph.new(), [])
    true
  rescue
    _ -> false
  end

  @spec run(RDF.Graph.t(), String.t()) :: [map()]
  def run(%RDF.Graph{} = graph, query) when is_binary(query), do: run(graph, query, [])

  @spec run(RDF.Graph.t(), String.t(), keyword()) :: [map()]
  def run(%RDF.Graph{} = graph, query, opts) when is_binary(query) and is_list(opts) do
    if Keyword.get(opts, :raw, false) do
      raise ArgumentError,
        message: "graphlaw query: raw: true is not supported (use GgenIgniter.Query.Oxigraph)"
    end

    graph |> Graphlaw.prepare!(opts) |> Graphlaw.run(query)
  end
end
