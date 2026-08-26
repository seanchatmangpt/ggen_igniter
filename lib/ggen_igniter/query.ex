
defmodule GgenIgniter.Query do
  @moduledoc """
  Executes a SPARQL SELECT query against an in-memory RDF.Graph via the `sparql` library and reshapes results into plain maps keyed by column name (mirroring the row shape ggen's own Tera templates already consume).
  """




  @doc "Runs `query_string` against `graph`, returning a list of %{column_name => value} maps."
  @spec run(RDF.Graph.t(), String.t()) :: [map()]
  def run(graph, query_string) do
    %SPARQL.Query.Result{results: rows} = SPARQL.execute_query(graph, query_string)
    Enum.map(rows, fn row -> Map.new(row, fn {k, v} -> {k, unwrap(v)} end) end)
  end

  # Strips RDF.ex's own term wrappers down to plain Elixir values so callers (EEx
  # templates) never see RDF.Literal/RDF.IRI structs directly.
  defp unwrap(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp unwrap(%RDF.Literal{} = lit), do: RDF.Literal.value(lit)
  defp unwrap(other), do: other

end
