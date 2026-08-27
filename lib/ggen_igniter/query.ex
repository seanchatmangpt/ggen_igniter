defmodule GgenIgniter.Query do
  @moduledoc """
  Executes a SPARQL SELECT query against an in-memory RDF.Graph via the `sparql` library and reshapes results into plain maps keyed by column name (mirroring the row shape ggen's own Tera templates already consume).

  Disclosed limitation, empirically confirmed (not just asserted): the `sparql`
  hex package (v0.3.12, the default `--engine sparql` used by this module) does
  not correctly honor `ORDER BY`. A join-shaped query mirroring the real gate
  fixtures (`?field ex:fieldOf ?entity ; ex:fieldOrder ?field_order . ?entity
  ex:entityStruct ?entity_struct .` with `ORDER BY ?field_order` over 10 rows)
  came back in reverse order (`[9, 8, 7, 6, 5, 4, 3, 2, 1, 0]` instead of the
  requested ascending `[0, 1, ..., 9]`) when run through `run/2`. The same
  query run through `GgenIgniter.Query.Oxigraph.run/2` (a real, independent,
  spec-conformant SPARQL 1.1 engine) returned the correct ascending order. If
  row order matters for a query, use `--engine oxigraph` instead of the
  default `--engine sparql`.
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
