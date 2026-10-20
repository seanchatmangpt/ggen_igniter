defmodule GgenIgniter.AshR2rmlGateIntegrationTest do
  @moduledoc """
  Chicago-style end-to-end composition test: proves GgenIgniter's own
  Ontology.load!/1 + Query.run/2 pipeline can execute an INDEPENDENTLY-AUTHORED
  external ggen-marketplace pack's real SPARQL gate queries against an
  INDEPENDENTLY-AUTHORED external real ontology -- both sourced live from
  ~/ash_r2rml, not copied into this repo's fixtures, and not mocked.

  No test doubles: this loads real files from disk via RDF.Turtle.read_file!/1
  (through GgenIgniter.Ontology.load!/1) and executes real SPARQL via
  SPARQL.execute_query/2 (through GgenIgniter.Query.run/2). Assertions are on
  the real returned row data (state), not on any call/interaction.

  Skips (named, visible) if ~/ash_r2rml is not present on this machine.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, Query}

  @ash_r2rml_root Path.expand("~/ash_r2rml")
  @gate_010 Path.join(
              @ash_r2rml_root,
              "priv/ggen/ash-r2rml-pack/gates/010_required_resource_contract.rq"
            )
  @gate_020 Path.join(@ash_r2rml_root, "priv/ggen/ash-r2rml-pack/gates/020_property_contract.rq")
  @fortune5_shapes Path.join(@ash_r2rml_root, "priv/ontologies/fortune5/operational_shapes.ttl")

  @tag :requires_ash_r2rml
  test "loads the real fortune5 SHACL ontology from ash_r2rml via GgenIgniter.Ontology" do
    assert File.exists?(@fortune5_shapes),
           "expected real file at #{@fortune5_shapes} -- run this from a machine with ~/ash_r2rml checked out"

    graph = Ontology.load!(@fortune5_shapes)

    assert %RDF.Graph{} = graph
    assert RDF.Graph.triple_count(graph) > 0
  end

  # --- RESOLVED INCOMPATIBILITY (graphlaw engine, b514bf5) -----------------
  #
  # Running ash_r2rml's real gate 010/020 queries against the real fortune5
  # ontology through GgenIgniter.Query.run/2 USED to raise under the
  # pure-Elixir `sparql` engine. Reproduced with the bare `sparql` library
  # directly (no ggen_igniter code involved: `SPARQL.execute_query
  # (RDF.Turtle.read_file!(...), File.read!(...))` from a standalone
  # `mix run` script) -- so this was a real limitation in `sparql` 0.3.12 itself,
  # not in ggen_igniter's Ontology/Query wrappers:
  #
  #   ** (Protocol.UndefinedError) protocol SPARQL.Algebra.Expression not
  #   implemented for Atom. Got value: :"$undefined"
  #     (sparql 0.3.12) lib/sparql/algebra/expression/filter.ex:9:
  #       SPARQL.Algebra.Filter.result_set/4
  #     (sparql 0.3.12) lib/sparql/algebra/expression/union.ex:30: ... Union.evaluate/3
  #
  # Root cause (from the query shape, both gates share it): each UNION branch
  # is `{ FILTER NOT EXISTS { ?shape sh:targetClass ?v } BIND(sh:targetClass AS ?missing) }`
  # -- a FILTER NOT EXISTS whose inner pattern's only variable (?v) is never
  # projected, combined with a BIND of a bare constant IRI, inside a UNION.
  # `sparql` 0.3.12's Filter.result_set/4 evaluates that inner ?v as an
  # internal `:"$undefined"` sentinel atom and then tries to run it back
  # through SPARQL.Algebra.Expression.evaluate/3, which has no clause for a
  # plain Atom -- an engine defect, not a query-authoring error (the query is
  # valid, spec-conformant SPARQL 1.1).
  #
  # The engine law (b514bf5) made graphlaw the fixed engine; graphlaw
  # executes both gates clean -- the limitation was in the retired engine,
  # not the queries. Both tests below now assert the real, currently-passing
  # behavior: the gates execute and return their real row data.

  @tag :requires_ash_r2rml
  test "gate 010 (required resource contract) executes clean under the fixed graphlaw engine against real fortune5 shapes" do
    graph = Ontology.load!(@fortune5_shapes)
    gate_query = File.read!(@gate_010)

    rows = Query.run(graph, gate_query)

    assert is_list(rows)
    assert rows != []

    for row <- rows do
      assert Map.has_key?(row, "shape")
      assert Map.has_key?(row, "missing")
    end
  end

  @tag :requires_ash_r2rml
  test "gate 020 (property contract) executes clean under the fixed graphlaw engine against real fortune5 shapes" do
    graph = Ontology.load!(@fortune5_shapes)
    gate_query = File.read!(@gate_020)

    rows = Query.run(graph, gate_query)

    assert is_list(rows)
    assert rows != []

    for row <- rows do
      assert Map.has_key?(row, "shape")
      assert Map.has_key?(row, "property")
      assert Map.has_key?(row, "missing")
    end
  end
end
