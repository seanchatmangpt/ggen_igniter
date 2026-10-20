defmodule GgenIgniter.Query do
  @moduledoc """
  Fixed-engine SPARQL facade (engine-selection removal, b514bf5 follow-up):
  `Query.run/2` now routes to `GgenIgniter.Query.Oxigraph.run/2` — the
  fixed engine's row contract (string keys, plain unwrapped values) — so the
  surviving `Query.run/2` call sites (gall_ticket.ex, semantic_a2a.ex) keep
  compiling and keep the row shape callers already consume. The old
  `sparql`-hex-backed implementation was deleted with the engine-selection
  refactor; this facade is a delegation, not an engine revival.
  """

  @doc "Runs `query_string` against `graph` via the fixed engine (Oxigraph)."
  @spec run(RDF.Graph.t(), String.t()) :: [map()]
  def run(graph, query_string), do: GgenIgniter.Query.Oxigraph.run(graph, query_string)
end
