defmodule GgenIgniter.Ontology do
  @moduledoc """
  Loads an ontology file into an in-memory RDF.Graph via the `rdf` library, dispatching on
  file extension. Real IO/parsing, no fixture stubbing. Supported formats:
  - `.ttl` -> `RDF.Turtle.read_file!/1` (fallback for unrecognized extensions)
  - `.nt` -> `RDF.NTriples.read_file!/1`
  - `.nq` -> `RDF.NQuads.read_file!/1`
  """

  @doc "Parses the ontology file at `path` into an RDF.Graph or RDF.Dataset, raising on parse failure."
  @spec load!(String.t()) :: RDF.Graph.t() | RDF.Dataset.t()
  def load!(path) do
    case Path.extname(path) do
      ".nt" -> RDF.NTriples.read_file!(path)
      ".nq" -> RDF.NQuads.read_file!(path)
      _ -> RDF.Turtle.read_file!(path)
    end
  end
end
