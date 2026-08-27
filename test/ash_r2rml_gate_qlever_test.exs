defmodule GgenIgniter.AshR2rmlGateQleverTest do
  @moduledoc """
  Chicago-style, no-mocks proof that the SAME real gate queries that crash the
  `sparql` 0.3.12 engine (pinned in `ash_r2rml_gate_integration_test.exs`) run
  correctly against a real, independent SPARQL 1.1 engine: QLever.

  Requires a real, already-running local QLever server (started via the real
  `qlever` CLI: `qlever index && qlever start`, loaded from
  `~/ash_r2rml/priv/ontologies/fortune5/operational_shapes.ttl`) reachable at
  http://localhost:7020. Named, visible skip via the `:requires_qlever_server`
  tag if that endpoint isn't reachable -- never a silent mock substitution.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Query.Qlever, as: QleverQuery

  @ash_r2rml_root Path.expand("~/ash_r2rml")
  @gate_010 Path.join(
              @ash_r2rml_root,
              "priv/ggen/ash-r2rml-pack/gates/010_required_resource_contract.rq"
            )
  @gate_020 Path.join(@ash_r2rml_root, "priv/ggen/ash-r2rml-pack/gates/020_property_contract.rq")

  @manifest_graph "config/gno/test/store.ttl"
                  |> RDF.Turtle.read_file!(base: "http://example.com/")
  @store_id "http://example.com/Qlever"

  setup do
    endpoint_reachable? =
      case :httpc.request(:get, {~c"http://localhost:7020", []}, [{:timeout, 1_000}], []) do
        {:ok, _} -> true
        _ -> false
      end

    unless endpoint_reachable? do
      ExUnit.configure(exclude: [:requires_qlever_server])
    end

    :ok
  end

  @tag :requires_qlever_server
  test "gate 010 (broke sparql 0.3.12) returns real rows from real QLever" do
    store = QleverQuery.load_store!(@manifest_graph, @store_id)
    query = File.read!(@gate_010)

    rows = QleverQuery.run(store, query)

    assert is_list(rows)
    assert rows != []

    assert Enum.all?(rows, fn row ->
             Map.has_key?(row, "shape") and Map.has_key?(row, "missing")
           end)

    missing_predicates = rows |> Enum.map(& &1["missing"]) |> Enum.uniq() |> Enum.sort()

    assert missing_predicates == [
             "https://ash-r2ml.dev/ns#identityProperty",
             "https://ash-r2ml.dev/ns#module",
             "https://ash-r2ml.dev/ns#subjectTemplate",
             "https://ash-r2ml.dev/ns#table"
           ]
  end

  @tag :requires_qlever_server
  test "gate 020 (broke sparql 0.3.12) returns real rows from real QLever" do
    store = QleverQuery.load_store!(@manifest_graph, @store_id)
    query = File.read!(@gate_020)

    rows = QleverQuery.run(store, query)

    assert is_list(rows)
    assert rows != []

    assert Enum.all?(rows, fn row ->
             Map.has_key?(row, "shape") and Map.has_key?(row, "property") and
               Map.has_key?(row, "missing")
           end)
  end

  @tag :requires_qlever_server
  test "the exact query shape that raises Protocol.UndefinedError in sparql 0.3.12 succeeds on QLever" do
    # Reproduces the minimal failing shape from ash_r2rml_gate_integration_test.exs's
    # discovered `sparql` 0.3.12 bug: FILTER NOT EXISTS (unprojected inner var) +
    # BIND(constant IRI) inside UNION.
    store = QleverQuery.load_store!(@manifest_graph, @store_id)

    query = """
    PREFIX sh: <http://www.w3.org/ns/shacl#>
    SELECT ?shape ?missing WHERE {
      ?shape a sh:NodeShape .
      {
        FILTER NOT EXISTS { ?shape sh:targetClass ?v }
        BIND(sh:targetClass AS ?missing)
      } UNION {
        FILTER NOT EXISTS { ?shape sh:nonExistentMarker ?v }
        BIND(sh:nonExistentMarker AS ?missing)
      }
    }
    """

    rows = QleverQuery.run(store, query)

    assert is_list(rows)
    assert rows != []
  end
end
