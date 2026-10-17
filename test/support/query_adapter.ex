defmodule GgenIgniter.Query do
  @moduledoc """
  TEST-SUPPORT-ONLY adapter (2026-10-17): the production
  `GgenIgniter.Query` module (the `sparql` hex engine adapter with its
  ORDER BY post-sort workaround) was REMOVED when the engine became fixed
  (graphlaw); this test-support module keeps the ~10 test files that used
  `GgenIgniter.Query.run/2` purely as a row helper compiling, routing them
  through the ONE fixed engine. Not compiled into the hex package (test/
  is not packaged); not an engine choice -- a test convenience over
  `GgenIgniter.Engine.Graphlaw`.
  """
  @spec run(RDF.Graph.t(), String.t()) :: [map()]
  def run(graph, query) do
    graph
    |> GgenIgniter.Engine.Graphlaw.prepare!([])
    |> GgenIgniter.Engine.Graphlaw.run(query)
  end
end
