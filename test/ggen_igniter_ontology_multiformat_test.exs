defmodule GgenIgniterOntologyMultiformatTest do
  @moduledoc """
  Chicago-style: real file I/O against real fixture files in `test/fixtures/`, parsed by the
  real `rdf` library (`RDF.Turtle.read_file!/1`, `RDF.NTriples.read_file!/1`,
  `RDF.NQuads.read_file!/1`) via `GgenIgniter.Ontology.load!/1`. No mocking/stubbing of the
  parser or filesystem.
  """
  use ExUnit.Case, async: true

  import RDF.Sigils

  alias GgenIgniter.Ontology

  describe "load!/1 (extension dispatch)" do
    test ".ttl fixture still loads via RDF.Turtle.read_file!/1 (regression)" do
      graph = Ontology.load!("test/fixtures/for_each_ontology.ttl")

      assert %RDF.Graph{} = graph
      assert RDF.Graph.triple_count(graph) > 0

      mod_ns = "http://seanchatmangpt.github.io/packs/multi-module#"

      assert RDF.Graph.include?(
               graph,
               {RDF.iri(mod_ns <> "M1"), RDF.iri(mod_ns <> "moduleName"), ~L"Multi.Alpha"}
             )
    end

    test ".nt fixture loads via RDF.NTriples.read_file!/1 into a real RDF.Graph" do
      graph = Ontology.load!("test/fixtures/sample.nt")

      assert %RDF.Graph{} = graph
      assert RDF.Graph.triple_count(graph) == 3

      ns = "http://example.org/nt#"

      assert RDF.Graph.include?(
               graph,
               {RDF.iri(ns <> "Alice"), RDF.iri(ns <> "name"), ~L"Alice"}
             )

      assert RDF.Graph.include?(
               graph,
               {RDF.iri(ns <> "Alice"), RDF.iri(ns <> "knows"), RDF.iri(ns <> "Bob")}
             )

      assert RDF.Graph.include?(
               graph,
               {RDF.iri(ns <> "Bob"), RDF.iri(ns <> "name"), ~L"Bob"}
             )
    end

    test ".nq fixture loads via RDF.NQuads.read_file!/1 into a real RDF.Dataset" do
      dataset = Ontology.load!("test/fixtures/sample.nq")

      assert %RDF.Dataset{} = dataset
      assert RDF.Dataset.statement_count(dataset) == 3

      ns = "http://example.org/nq#"
      graph_name = RDF.iri(ns <> "graph1")

      assert RDF.Dataset.include?(
               dataset,
               {RDF.iri(ns <> "Alice"), RDF.iri(ns <> "name"), ~L"Alice", graph_name}
             )

      assert RDF.Dataset.include?(
               dataset,
               {RDF.iri(ns <> "Alice"), RDF.iri(ns <> "knows"), RDF.iri(ns <> "Bob"), graph_name}
             )

      assert RDF.Dataset.include?(
               dataset,
               {RDF.iri(ns <> "Bob"), RDF.iri(ns <> "name"), ~L"Bob", graph_name}
             )
    end

    test "unrecognized extension falls back to Turtle parsing (raises on N-Triples content, which is not valid Turtle)" do
      assert_raise RuntimeError, fn ->
        Ontology.load!("test/fixtures/sample.unknownext")
      end
    end
  end
end
