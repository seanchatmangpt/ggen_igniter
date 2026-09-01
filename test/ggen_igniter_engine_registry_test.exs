defmodule GgenIgniter.EngineRegistryTest do
  @moduledoc """
  Chicago-style (no mocks): real `GgenIgniter.EngineRegistry.resolve/1,2`
  parsing over the real `GgenIgniter.Engine.valid_names/0` list, and real
  `GgenIgniter.EngineRegistry.run_all/4` fan-out against the real oxigraph
  NIF (`GgenIgniter.Query.Oxigraph`) and the real `sparql` hex engine
  (`GgenIgniter.Query`) over real `%RDF.Graph{}` values -- no
  `Mock`/`mock(`/`patch(`/`monkeypatch` anywhere in this file.

  `--engine qlever`'s real reachability path (`resolve/2`'s `"all"`
  precondition check) is exercised for real too: with no `--store-id`, and
  separately with a real `--store-id`/`--ontology` pair that does NOT
  actually resolve to a live QLever endpoint, both real (not simulated)
  negative paths. A REAL live-endpoint reachability case is additionally
  tagged `:requires_qlever_server` (mirroring
  `test/ggen_igniter_engine_parity_test.exs`'s own convention) and only runs
  when a real QLever server is reachable at `localhost:7020`.

  The key correctness proof this file adds beyond what
  `test/ggen_igniter_cross_engine_equivalence_properties_test.exs` and
  `test/ggen_igniter_engine_parity_test.exs` already establish statically:
  `run_all/4`'s real `pairwise_agreement` surfaces the confirmed `sparql`-hex
  `ORDER BY` row-reversal bug (`lib/ggen_igniter/query.ex:4-16`'s moduledoc)
  at RUNTIME, as `order_equal?: false` with `row_set_equal?: true` -- not
  collapsed into one ambiguous boolean.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias GgenIgniter.EngineComparisonReport
  alias GgenIgniter.EngineComparisonReport.CandidateResult
  alias GgenIgniter.EngineRegistry

  doctest GgenIgniter.EngineRegistry
  doctest GgenIgniter.EngineComparisonReport

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

  # ---------------------------------------------------------------------
  # resolve/1,2 -- single name, comma list, "all"
  # ---------------------------------------------------------------------

  describe "resolve/1,2 (single name)" do
    test "a plain valid name resolves to a one-element atom list" do
      assert EngineRegistry.resolve("oxigraph") == {:ok, [:oxigraph]}
      assert EngineRegistry.resolve("sparql") == {:ok, [:sparql]}
      assert EngineRegistry.resolve("qlever") == {:ok, [:qlever]}
    end

    test "an invalid name returns {:error, reason} naming the valid set" do
      assert {:error, reason} = EngineRegistry.resolve("bogus")
      assert reason =~ "bogus"
      assert reason =~ "oxigraph"
      assert reason =~ "sparql"
      assert reason =~ "qlever"
    end

    test "an empty string returns {:error, reason}" do
      assert {:error, _reason} = EngineRegistry.resolve("")
    end
  end

  describe "resolve/1,2 (comma-separated list)" do
    test "a comma-separated list resolves in the order named" do
      assert EngineRegistry.resolve("oxigraph,sparql") == {:ok, [:oxigraph, :sparql]}
      assert EngineRegistry.resolve("sparql,oxigraph") == {:ok, [:sparql, :oxigraph]}
    end

    test "whitespace around names is trimmed" do
      assert EngineRegistry.resolve("oxigraph, sparql") == {:ok, [:oxigraph, :sparql]}
    end

    test "duplicate names are deduplicated, first occurrence order preserved" do
      assert EngineRegistry.resolve("oxigraph,oxigraph,sparql") == {:ok, [:oxigraph, :sparql]}
    end

    test "one invalid name in the list fails the whole resolve, naming it" do
      assert {:error, reason} = EngineRegistry.resolve("oxigraph,bogus")
      assert reason =~ "bogus"
      refute reason =~ "oxigraph is invalid"
    end
  end

  describe "resolve/2 (\"all\", qlever exclusion)" do
    test "with no --store-id, \"all\" resolves to oxigraph+sparql only, and logs a warning (not a crash)" do
      log =
        capture_log(fn ->
          assert EngineRegistry.resolve("all", []) == {:ok, [:oxigraph, :sparql]}
        end)

      assert log =~ "excludes qlever"
      assert log =~ "no --store-id given"
    end

    test "with a --store-id that does not resolve to a live QLever endpoint, \"all\" still excludes qlever with a warning (real reachability probe, real failure, not simulated)" do
      log =
        capture_log(fn ->
          assert EngineRegistry.resolve("all",
                   store_id: "http://example.com/does-not-exist",
                   ontology: "test/fixtures/audit_trail_ontology.ttl"
                 ) == {:ok, [:oxigraph, :sparql]}
        end)

      assert log =~ "excludes qlever"
    end

    test "with no ontology resolvable at all, \"all\" still excludes qlever gracefully (soft precondition, never a hard failure)" do
      assert EngineRegistry.resolve("all", store_id: "http://example.com/whatever") ==
               {:ok, [:oxigraph, :sparql]}
    end

    @tag :requires_qlever_server
    test "with a real, reachable --store-id, \"all\" includes qlever, appended last" do
      assert EngineRegistry.resolve("all",
               store_id: "http://example.com/Qlever",
               ontology: "config/gno/test/store.ttl"
             ) == {:ok, [:oxigraph, :sparql, :qlever]}
    end
  end

  # ---------------------------------------------------------------------
  # run_all/4 -- real concurrent fan-out, real rows, real timing
  # ---------------------------------------------------------------------

  defp base_graph do
    RDF.Graph.new([
      {"https://example.org/engine_registry/s1", "https://example.org/engine_registry/p",
       "hello"},
      {"https://example.org/engine_registry/s2", "https://example.org/engine_registry/p",
       "world"}
    ])
  end

  @select_query "SELECT ?s ?p ?o WHERE { ?s ?p ?o }"

  describe "run_all/4 (real fan-out)" do
    test "fans out to every resolved engine, returns one :ok CandidateResult per engine with real rows" do
      report = EngineRegistry.run_all(@select_query, base_graph(), [:oxigraph, :sparql], [])

      assert %EngineComparisonReport{query: @select_query, candidates: candidates} = report
      assert %DateTime{} = report.generated_at
      assert length(candidates) == 2

      by_engine = Map.new(candidates, &{&1.engine, &1})

      assert %CandidateResult{status: :ok, row_count: 2, rows: rows, error: nil} =
               by_engine[:oxigraph]

      assert is_list(rows)
      assert is_integer(by_engine[:oxigraph].elapsed_us)
      assert by_engine[:oxigraph].elapsed_us >= 0

      assert %CandidateResult{status: :ok, row_count: 2, error: nil} = by_engine[:sparql]
    end

    test "pairwise_agreement reports real row-set agreement for a query with no order divergence" do
      report = EngineRegistry.run_all(@select_query, base_graph(), [:oxigraph, :sparql], [])

      agreement = report.pairwise_agreement[{:oxigraph, :sparql}]
      assert agreement.row_set_equal? == true
      assert agreement.row_count_diff == 0
    end

    test "one engine crashing (malformed query) becomes a :error CandidateResult, never aborting the others" do
      malformed = "SELECT ?s WHERE { ?s ?p ?o"

      report = EngineRegistry.run_all(malformed, base_graph(), [:oxigraph, :sparql], [])

      by_engine = Map.new(report.candidates, &{&1.engine, &1})

      assert %CandidateResult{status: :error, error: error} = by_engine[:sparql]
      assert is_binary(error)

      assert %CandidateResult{status: :error, error: oxi_error} = by_engine[:oxigraph]
      assert oxi_error =~ "oxigraph engine query failed"

      # A crashing engine excludes itself from every pairwise comparison
      # (real rows required on both sides) rather than comparing against nil.
      assert report.pairwise_agreement == %{}
    end

    test "to_json/1 and to_markdown/1 round-trip real report content" do
      report = EngineRegistry.run_all(@select_query, base_graph(), [:oxigraph, :sparql], [])

      json = EngineComparisonReport.to_json(report)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["query"] == @select_query
      assert length(decoded["candidates"]) == 2

      markdown = EngineComparisonReport.to_markdown(report)
      assert markdown =~ "Engine Comparison Report"
      assert markdown =~ "oxigraph"
      assert markdown =~ "sparql"
    end
  end

  # ---------------------------------------------------------------------
  # THE key correctness proof: the confirmed sparql-hex ORDER BY reversal
  # surfaces as order_equal?: false / row_set_equal?: true at runtime,
  # exactly the shape `lib/ggen_igniter/query.ex:4-16`'s moduledoc documents
  # (a join-shaped query, fieldOf/fieldOrder, ORDER BY ?field_order).
  # ---------------------------------------------------------------------

  describe "run_all/4 (known ORDER BY divergence, reused from the documented bug shape)" do
    @entity "https://example.org/engine_registry/order/entity1"
    @field_of "https://example.org/engine_registry/order/fieldOf"
    @field_order_p "https://example.org/engine_registry/order/fieldOrder"

    defp order_by_graph do
      triples =
        for i <- 0..9 do
          field = "https://example.org/engine_registry/order/field#{i}"

          # `RDF.iri/1` is required for the OBJECT position: RDF.ex coerces a
          # bare string in a triple's object slot to an `RDF.Literal`, not an
          # `RDF.IRI`, so an un-wrapped `@entity` here would silently produce
          # a literal-valued object the query's `<...entity1>` IRI pattern
          # never matches (confirmed empirically while building this test --
          # a real, if easy to trip, RDF.ex coercion rule, not this repo's
          # bug).
          [
            {field, @field_of, RDF.iri(@entity)},
            {field, @field_order_p, RDF.XSD.integer(i)}
          ]
        end
        |> List.flatten()

      RDF.Graph.new(triples)
    end

    # `?field_order` is deliberately NOT projected (SPARQL allows `ORDER BY`
    # on a variable that isn't in the `SELECT` list) -- this isolates the
    # ORDER divergence from a SEPARATE, already-documented divergence found
    # for real while building this test: oxigraph returns a typed literal's
    # plain LEXICAL STRING ("0"), while sparql-hex returns RDF.ex's native
    # Elixir value (integer `0`) -- see `test/ggen_igniter_engine_parity_test.exs`'s
    # "typed-literal query" describe block, the same already-documented,
    # disclosed divergence, not a second new one. Projecting `?field_order`
    # here would make `row_set_equal?` false for an UNRELATED reason (value
    # encoding, not order), muddying the one thing this test exists to prove.
    # `?field` (a plain IRI) unwraps identically on both engines either way.
    @order_by_query """
    SELECT ?field WHERE {
      ?field <#{@field_of}> <#{@entity}> .
      ?field <#{@field_order_p}> ?field_order .
    }
    ORDER BY ?field_order
    """

    test "row_set_equal?: true, order_equal?: false -- the exact shape a real ORDER BY divergence must produce" do
      report = EngineRegistry.run_all(@order_by_query, order_by_graph(), [:oxigraph, :sparql], [])

      by_engine = Map.new(report.candidates, &{&1.engine, &1})
      assert by_engine[:oxigraph].status == :ok
      assert by_engine[:sparql].status == :ok
      assert by_engine[:oxigraph].row_count == 10
      assert by_engine[:sparql].row_count == 10

      agreement = report.pairwise_agreement[{:oxigraph, :sparql}]
      assert agreement.row_set_equal? == true, "same 10 rows on both engines (a set property)"
      assert agreement.row_count_diff == 0
      assert agreement.order_equal? == false, "sparql-hex's real ORDER BY reversal must surface here"

      # Ground truth: oxigraph honors ORDER BY ascending; sparql-hex reverses
      # it -- asserted directly against the real returned rows (field N's
      # position encodes its real fieldOrder), not inferred from the boolean
      # alone.
      oxi_fields = Enum.map(by_engine[:oxigraph].rows, & &1["field"])
      sparql_fields = Enum.map(by_engine[:sparql].rows, & &1["field"])

      expected_ascending =
        Enum.map(0..9, &"https://example.org/engine_registry/order/field#{&1}")

      assert oxi_fields == expected_ascending
      assert sparql_fields == Enum.reverse(expected_ascending)
    end
  end
end
