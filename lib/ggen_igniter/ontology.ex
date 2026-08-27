defmodule GgenIgniter.Ontology do
  @moduledoc """
  Loads a Turtle ontology file into an in-memory RDF.Graph via the `rdf` library. Real IO/parsing, no fixture stubbing.
  """

  @doc "Parses the Turtle file at `path` into an RDF.Graph, raising on parse failure."
  @spec load!(String.t()) :: RDF.Graph.t()
  def load!(path) do
    RDF.Turtle.read_file!(path)
  end
end
