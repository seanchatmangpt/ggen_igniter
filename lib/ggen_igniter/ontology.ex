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

  @doc """
  Loads `source` and merges every `imports` path (each `Path.expand`ed against
  `base_dir`) into one `RDF.Graph` via `RDF.Graph.add/2`. Mirrors the
  `[ontology].imports` field (`GgenIgniter.ProjectConfig.OntologyConfig`).

  Raises `ArgumentError` naming the path when an import is missing, or when
  the source or an import loads as an `RDF.Dataset` (quad formats cannot be
  merged into a graph without silently dropping graph names). Not wired into
  the reactor.
  """
  @spec load_with_imports!(String.t(), [String.t()], String.t()) :: RDF.Graph.t()
  def load_with_imports!(source, imports, base_dir \\ ".") do
    Enum.reduce(imports, load_graph!(Path.expand(source, base_dir)), fn import, acc ->
      path = Path.expand(import, base_dir)

      unless File.regular?(path) do
        raise ArgumentError, "ontology import not found: #{path}"
      end

      RDF.Graph.add(acc, load_graph!(path))
    end)
  end

  defp load_graph!(path) do
    unless File.regular?(path) do
      raise ArgumentError, "ontology file not found: #{path}"
    end

    case load!(path) do
      %RDF.Graph{} = graph -> graph
      %RDF.Dataset{} -> raise ArgumentError, "ontology import is a Dataset, not a Graph: #{path}"
    end
  end
end
