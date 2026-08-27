defmodule GgenIgniter.SparqlEngineTest do
  @moduledoc """
  Chicago-style, no-mocks exercise of `GgenIgniter.Query.run/2` (the default
  `--engine sparql`, backed by the `sparql` hex package v0.3.12) against real
  `%RDF.Graph{}` values -- mirrors the shape of
  `test/ggen_igniter_oxigraph_engine_test.exs` so the two default in-process
  engines get comparable real-graph coverage: SELECT, FILTER, UNION, ORDER BY,
  Unicode/escaping, malformed query, empty graph, and concurrency.

  This file does NOT re-litigate the two already-confirmed, already-documented
  divergences (`lib/ggen_igniter/query.ex`'s moduledoc: ORDER BY reversal;
  `test/ggen_igniter_cross_engine_equivalence_properties_test.exs`: term
  encoding) -- it only adds real coverage for query shapes not yet pinned
  anywhere for the sparql-hex engine specifically. See
  `test/ggen_igniter_ask_construct_engine_divergence_test.exs` for a THIRD,
  newly-discovered divergence (ASK/CONSTRUCT/bare FILTER NOT EXISTS) found
  while building this coverage.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Query

  defp small_graph do
    RDF.Graph.new([
      {"https://example.org/sparql-engine/s1", "https://example.org/sparql-engine/p", "hello"},
      {"https://example.org/sparql-engine/s2", "https://example.org/sparql-engine/p", "world"}
    ])
  end

  test "runs a basic SELECT against a real graph" do
    rows = Query.run(small_graph(), "SELECT ?s ?o WHERE { ?s ?p ?o }")

    assert length(rows) == 2
    assert Enum.all?(rows, &is_map/1)
    values = rows |> Enum.map(& &1["o"]) |> Enum.sort()
    assert values == ["hello", "world"]
  end

  test "FILTER restricts rows to the matching literal" do
    rows =
      Query.run(
        small_graph(),
        "SELECT ?o WHERE { ?s ?p ?o . FILTER(?o = \"hello\") }"
      )

    assert rows == [%{"o" => "hello"}]
  end

  test "UNION combines both branches, including the branch with zero real matches" do
    query = """
    SELECT ?o WHERE {
      { ?s <https://example.org/sparql-engine/p> ?o }
      UNION
      { ?s <https://example.org/sparql-engine/nomatch> ?o }
    }
    """

    rows = Query.run(small_graph(), query)
    values = rows |> Enum.map(& &1["o"]) |> Enum.sort()
    assert values == ["hello", "world"]
  end

  test "SELECT against a real empty %RDF.Graph{} (zero triples) returns an empty list, not an error" do
    assert Query.run(%RDF.Graph{}, "SELECT * WHERE { ?s ?p ?o }") == []
  end

  test "a malformed query raises rather than silently returning rows (real, unwrapped MatchError -- see the divergence test file for why)" do
    # GgenIgniter.Query.run/2 has no error-handling branch (unlike
    # GgenIgniter.Query.Oxigraph.run/2's `{:ok, rows} -> ...; {:error, reason} ->
    # raise RuntimeError`): it pattern-matches
    # `%SPARQL.Query.Result{results: rows} = SPARQL.execute_query(...)`
    # unconditionally, so a parse error surfaces as a raw MatchError against
    # `SPARQL.execute_query/2`'s real `{:error, reason}` return, not a clear
    # wrapped RuntimeError. Pinned here as real, current behavior -- not
    # silently upgraded to a nicer error by this test.
    assert_raise MatchError, ~r/SPARQL language scanner error/, fn ->
      Query.run(small_graph(), "THIS IS NOT VALID SPARQL {{{")
    end
  end

  test "unicode and escaped characters in literal values round-trip exactly (sparql-hex returns plain unwrapped values)" do
    special_value = "café \"quoted\" — naïve\nsecond line — 日本語 — Zürich"

    graph =
      RDF.Graph.new()
      |> RDF.Graph.add(
        RDF.iri("https://example.org/sparql-engine/unicode-1")
        |> RDF.Description.new()
        |> RDF.Description.add(
          {RDF.iri("https://example.org/sparql-engine/label"), special_value}
        )
      )

    query = """
    SELECT ?value WHERE {
      <https://example.org/sparql-engine/unicode-1> <https://example.org/sparql-engine/label> ?value .
    }
    """

    rows = Query.run(graph, query)

    assert rows == [%{"value" => special_value}]
  end

  test "concurrent Query.run/2 calls with different graphs/queries return correct, non-cross-contaminated results" do
    tasks_input =
      for n <- 1..20 do
        subject = "https://example.org/sparql-engine/concurrent/subject-#{n}"
        value = "concurrent-value-#{n}"

        graph =
          RDF.Graph.new()
          |> RDF.Graph.add(
            RDF.iri(subject)
            |> RDF.Description.new()
            |> RDF.Description.add({RDF.iri("https://example.org/sparql-engine/tag"), value})
          )

        query = """
        SELECT ?value WHERE {
          <#{subject}> <https://example.org/sparql-engine/tag> ?value .
        }
        """

        {n, value, graph, query}
      end

    results =
      tasks_input
      |> Task.async_stream(
        fn {n, expected_value, graph, query} ->
          rows = Query.run(graph, query)
          {n, expected_value, rows}
        end,
        max_concurrency: 20,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert length(results) == 20

    for {n, expected_value, rows} <- results do
      assert rows == [%{"value" => expected_value}],
             "task #{n} got cross-contaminated result: #{inspect(rows)}"
    end
  end
end
