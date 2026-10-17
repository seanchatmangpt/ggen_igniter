defmodule GgenIgniter.EngineRegistryTest do
  @moduledoc """
  Chicago-style (no mocks): real `GgenIgniter.EngineRegistry.resolve/1,2`
  and real `GgenIgniter.EngineRegistry.run_all/4` over the ONE FIXED engine
  (`GgenIgniter.Engine.fixed/0` == "graphlaw") with real `%RDF.Graph{}`
  values -- no mocks anywhere in this file.

  The historical multi-engine surface (sparql/qlever/oxigraph selection,
  comma lists, the "all" qlever-reachability precondition, the cross-engine
  ORDER BY divergence probes) was removed 2026-10-17 when the engine became
  a fixed constant; git history pins that removed surface.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.EngineComparisonReport
  alias GgenIgniter.EngineComparisonReport.CandidateResult
  alias GgenIgniter.EngineRegistry
  alias GgenIgniter.{Engine}

  doctest GgenIgniter.EngineRegistry
  doctest GgenIgniter.EngineComparisonReport

  describe "resolve/1,2 (fixed engine)" do
    test "the fixed engine name resolves to a one-element atom list" do
      assert EngineRegistry.resolve("graphlaw") == {:ok, [:graphlaw]}
    end

    test "\"all\" trivially expands to the one fixed engine" do
      assert EngineRegistry.resolve("all") == {:ok, [:graphlaw]}
    end

    test "every historical engine name now refuses, naming the fixed engine" do
      for name <- ["oxigraph", "sparql", "qlever", "oxigraph,sparql"] do
        assert {:error, reason} = EngineRegistry.resolve(name)
        assert reason =~ String.replace(name, ",", ", ")
        assert reason =~ "fixed"
      end
    end

    test "an invalid name returns {:error, reason} naming the fixed engine" do
      assert {:error, reason} = EngineRegistry.resolve("bogus")
      assert reason =~ "bogus"
      assert reason =~ "graphlaw"
    end

    test "an empty string returns {:error, reason}" do
      assert {:error, _reason} = EngineRegistry.resolve("")
    end
  end

  # ---------------------------------------------------------------------
  # run_all/4 -- real single-engine fan-out, real rows, real timing
  # ---------------------------------------------------------------------

  defp base_graph do
    RDF.Graph.new([
      {"https://example.org/engine_registry/s1", "https://example.org/engine_registry/p",
       "hello"},
      {"https://example.org/engine_registry/s2", "https://example.org/engine_registry/p", "world"}
    ])
  end

  @select_query "SELECT ?s ?p ?o WHERE { ?s ?p ?o }"

  @entity "https://example.org/engine_registry/order/entity1"
  @field_of "https://example.org/engine_registry/order/fieldOf"
  @field_order_p "https://example.org/engine_registry/order/fieldOrder"

  describe "run_all/4 (real single-engine run)" do
    test "returns one :ok CandidateResult for the fixed engine with real rows" do
      report = EngineRegistry.run_all(@select_query, base_graph(), [:graphlaw], [])

      assert %EngineComparisonReport{query: @select_query, candidates: candidates} = report
      assert %DateTime{} = report.generated_at
      assert length(candidates) == 1

      assert %CandidateResult{engine: :graphlaw, status: :ok, row_count: 2, rows: rows, error: nil} =
               hd(candidates)

      assert is_list(rows)
    end

    test "ORDER BY is honored natively by the fixed engine (the retired sparql-hex reversal bug class is structurally gone)" do
      triples =
        for i <- 0..9 do
          field = "https://example.org/engine_registry/order/field#{i}"

          [
            {field, @field_of, RDF.iri(@entity)},
            {field, @field_order_p, RDF.XSD.integer(i)}
          ]
        end
        |> List.flatten()

      graph = RDF.Graph.new(triples)

      query = """
      SELECT ?field WHERE {
        ?field <#{@field_of}> <#{@entity}> .
        ?field <#{@field_order_p}> ?field_order .
      }
      ORDER BY ?field_order
      """

      report = EngineRegistry.run_all(query, graph, [:graphlaw], [])
      candidate = hd(report.candidates)
      assert candidate.status == :ok and candidate.row_count == 10

      fields = Enum.map(candidate.rows, & &1["field"])
      expected = Enum.map(0..9, &"https://example.org/engine_registry/order/field#{&1}")
      assert fields == expected
    end

    test "a malformed query becomes a :error CandidateResult, never an abort" do
      malformed = "SELECT ?s WHERE { ?s ?p ?o"

      report = EngineRegistry.run_all(malformed, base_graph(), [:graphlaw], [])

      assert %CandidateResult{engine: :graphlaw, status: :error, error: error} =
               hd(report.candidates)

      assert is_binary(error)
      assert report.pairwise_agreement == %{}
    end

    test "to_json/1 and to_markdown/1 round-trip real report content" do
      report = EngineRegistry.run_all(@select_query, base_graph(), [:graphlaw], [])

      json = EngineComparisonReport.to_json(report)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["query"] == @select_query
      assert length(decoded["candidates"]) == 1
      assert hd(decoded["candidates"])["engine"] == "graphlaw"

      markdown = EngineComparisonReport.to_markdown(report)
      assert markdown =~ "Engine Comparison Report"
      assert markdown =~ "graphlaw"
    end
  end

  test "Engine.fixed/0 is the law: exactly one valid name, one registry entry" do
    assert Engine.fixed() == "graphlaw"
    assert Engine.valid_names() == ["graphlaw"]
    assert Engine.registry() == %{"graphlaw" => GgenIgniter.Engine.Graphlaw}
  end
end
