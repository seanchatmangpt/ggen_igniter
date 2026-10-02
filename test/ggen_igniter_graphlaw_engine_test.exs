defmodule GgenIgniter.GraphlawEngineTest do
  @moduledoc """
  Chicago-style, no mocks: drives the real graphlaw wasm module (real
  `wasmex` instantiation of the real `graphlaw_wasm.wasm` artifact) end to
  end through `GgenIgniter.Engine.Graphlaw`'s `prepare!/2`/`run/2`, and
  differentially asserts it answers a trivial SELECT identically to the
  already-proven oxigraph engine on the same graph.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Engine
  alias GgenIgniter.Engine.Graphlaw

  @turtle_triples """
  @prefix ex: <https://example.org/> .
  ex:alice ex:knows ex:bob .
  ex:bob ex:knows ex:carol .
  """
  # A real, in-memory 2-triple %RDF.Graph{} (not a fixture file): the minimal
  # real subject the differential assertion needs.
  defp two_triple_graph do
    graph =
      RDF.Turtle.read_string!(@turtle_triples)

    assert %RDF.Graph{} = graph
    graph
  end

  describe "registry" do
    test "\"graphlaw\" resolves through Engine.fetch!/1" do
      assert Engine.fetch!("graphlaw") == Graphlaw
      assert "graphlaw" in Engine.valid_names()
    end
  end

  describe "prepare!/2" do
    test "returns a context map carrying the graph as Turtle and the wasm artifacts" do
      context = Graphlaw.prepare!(two_triple_graph(), [])

      assert %{store: store, module: module, instance: instance, memory: memory, turtle: turtle} =
               context

      assert match?(%Wasmex.StoreOrCaller{}, store)
      assert match?(%Wasmex.Module{}, module)
      assert match?(%Wasmex.Instance{}, instance)
      assert match?(%Wasmex.Memory{}, memory)
      assert turtle =~ "ex:knows ex:bob"
    end

    test "raises a clear, typed RuntimeError naming the path when the artifact is missing" do
      bogus = Path.expand("/tmp/does-not-exist-graphlaw.wasm")

      Application.put_env(:ggen_igniter, :graphlaw_wasm_path, bogus)

      try do
        assert_raise RuntimeError, ~r/not found at #{Regex.escape(bogus)}/, fn ->
          Graphlaw.prepare!(two_triple_graph(), [])
        end
      after
        Application.delete_env(:ggen_igniter, :graphlaw_wasm_path)
      end
    end
  end

  describe "run/2 (differential vs oxigraph)" do
    test "answers a trivial 2-triple SELECT identically to the oxigraph engine" do
      graph = two_triple_graph()
      query = "SELECT ?s ?o WHERE { ?s <https://example.org/knows> ?o }"

      graphlaw_rows =
        graph |> Graphlaw.prepare!([]) |> Graphlaw.run(query)

      oxigraph_rows = GgenIgniter.Query.Oxigraph.run(graph, query)

      # SPARQL SELECT rows are unordered; compare as sorted multisets.
      assert Enum.sort(graphlaw_rows) == Enum.sort(oxigraph_rows)

      assert Enum.sort(graphlaw_rows) == [
               %{"o" => "https://example.org/bob", "s" => "https://example.org/alice"},
               %{"o" => "https://example.org/carol", "s" => "https://example.org/bob"}
             ]
    end

    test "literal bindings come back as plain lexical strings, matching oxigraph" do
      graph =
        RDF.Turtle.read_string!("""
        @prefix ex: <https://example.org/> .
        ex:audit ex:count 42 .
        """)

      query = "SELECT ?c WHERE { ?s <https://example.org/count> ?c }"

      graphlaw_rows = graph |> Graphlaw.prepare!([]) |> Graphlaw.run(query)
      oxigraph_rows = GgenIgniter.Query.Oxigraph.run(graph, query)

      assert graphlaw_rows == oxigraph_rows
      assert graphlaw_rows == [%{"c" => "42"}]
    end

    test "raises a clear RuntimeError on a malformed query" do
      context = Graphlaw.prepare!(two_triple_graph(), [])

      assert_raise RuntimeError, ~r/graphlaw engine query failed/, fn ->
        Graphlaw.run(context, "THIS IS NOT VALID SPARQL {{{")
      end
    end

    test "raises a clear RuntimeError on an ASK query (only SELECT is supported)" do
      context = Graphlaw.prepare!(two_triple_graph(), [])

      assert_raise RuntimeError, ~r/graphlaw engine query failed/, fn ->
        Graphlaw.run(context, "ASK { ?s ?p ?o }")
      end
    end
  end
end
