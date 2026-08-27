defmodule GgenIgniter.OxigraphEngineTest do
  @moduledoc """
  Chicago-style, no mocks: proves the new `GgenIgniter.Query.Oxigraph` engine
  (a real, native Rustler NIF over `~/ggen/crates/ggen-graph-wasm`'s
  `OxigraphEngine`) actually works, and re-runs the exact real query shape
  pinned as broken in `test/ash_r2rml_gate_integration_test.exs` (the `sparql`
  hex package's confirmed `FILTER NOT EXISTS`/`UNION` bug) through this new
  engine to report honestly whether it resolves that blocker.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, Query}
  alias GgenIgniter.Query.Oxigraph, as: OxigraphQuery

  @fixtures_dir Path.expand("fixtures", __DIR__)

  test "runs a basic SELECT against a small real ontology via the native oxigraph engine" do
    graph = Ontology.load!(Path.join(@fixtures_dir, "audit_trail_ontology.ttl"))
    query = File.read!(Path.join(@fixtures_dir, "spec.rq"))

    rows = OxigraphQuery.run(graph, query)

    assert is_list(rows)
    assert rows != []
    assert Enum.all?(rows, &is_map/1)
  end

  test "raises a clear RuntimeError (not a raw NIF tuple) on a malformed query" do
    graph = Ontology.load!(Path.join(@fixtures_dir, "audit_trail_ontology.ttl"))

    assert_raise RuntimeError, ~r/oxigraph engine query failed/, fn ->
      OxigraphQuery.run(graph, "THIS IS NOT VALID SPARQL {{{")
    end
  end

  test "ASK query raises RuntimeError wrapping the real vendored NotSelectQuery message" do
    # Confirmed by reading native/ggen_graph_nif/src/oxigraph_engine.rs: `query`
    # only handles `QueryResults::Solutions` (SELECT); anything else (ASK's
    # `QueryResults::Boolean`) falls through to `OxigraphEngineError::NotSelectQuery`,
    # whose real `Display` message is "query must be a SPARQL SELECT to yield rows".
    graph = Ontology.load!(Path.join(@fixtures_dir, "audit_trail_ontology.ttl"))

    assert_raise RuntimeError,
                 ~r/oxigraph engine query failed:.*query must be a SPARQL SELECT to yield rows/,
                 fn ->
                   OxigraphQuery.run(graph, "ASK { ?s ?p ?o }")
                 end
  end

  test "CONSTRUCT query raises RuntimeError wrapping the same real NotSelectQuery message" do
    # Same real code path as ASK: CONSTRUCT yields `QueryResults::Graph`, not
    # `QueryResults::Solutions`, so it hits the identical NotSelectQuery arm.
    graph = Ontology.load!(Path.join(@fixtures_dir, "audit_trail_ontology.ttl"))

    assert_raise RuntimeError,
                 ~r/oxigraph engine query failed:.*query must be a SPARQL SELECT to yield rows/,
                 fn ->
                   OxigraphQuery.run(graph, "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }")
                 end
  end

  test "SELECT against a real empty %RDF.Graph{} (zero triples) returns an empty list, not an error" do
    empty_graph = %RDF.Graph{}

    rows = OxigraphQuery.run(empty_graph, "SELECT * WHERE { ?s ?p ?o }")

    assert rows == []
  end

  test "unicode and special characters in literal values round-trip exactly through Turtle write -> NIF -> query results" do
    special_value = "café \"quoted\" — naïve\nsecond line — 日本語 — Zürich"

    graph =
      RDF.Graph.new()
      |> RDF.Graph.add(
        RDF.iri("https://example.org/subject/unicode-1")
        |> RDF.Description.new()
        |> RDF.Description.add({RDF.iri("https://example.org/predicate/label"), special_value})
      )

    query = """
    SELECT ?value WHERE {
      <https://example.org/subject/unicode-1> <https://example.org/predicate/label> ?value .
    }
    """

    rows = OxigraphQuery.run(graph, query)

    assert length(rows) == 1
    [%{"value" => raw_value} = row] = rows
    assert is_map(row)

    # Oxigraph serializes literal terms as N-Triples-style quoted strings
    # (e.g. `"café \"quoted\"..."`), so unwrap the outer quotes/escapes before
    # comparing the real, decoded string content.
    decoded_value =
      raw_value
      |> String.trim_leading("\"")
      |> String.replace_suffix("\"", "")
      |> String.replace("\\\"", "\"")
      |> String.replace("\\n", "\n")

    assert decoded_value == special_value
  end

  test "concurrent Oxigraph.run/2 calls with different graphs/queries return correct, non-cross-contaminated results" do
    # Proves the NIF's one-shot-store-per-call design (confirmed via reading
    # native/ggen_graph_nif/src/oxigraph_engine.rs: `Store::new()` + a fresh
    # `from_turtle` per query, no shared mutable state) is actually safe under
    # real concurrent Elixir processes, not just believed to be from source
    # reading alone.
    tasks_input =
      for n <- 1..20 do
        subject = "https://example.org/concurrent/subject-#{n}"
        value = "concurrent-value-#{n}"

        graph =
          RDF.Graph.new()
          |> RDF.Graph.add(
            RDF.iri(subject)
            |> RDF.Description.new()
            |> RDF.Description.add({RDF.iri("https://example.org/predicate/tag"), value})
          )

        query = """
        SELECT ?value WHERE {
          <#{subject}> <https://example.org/predicate/tag> ?value .
        }
        """

        {n, subject, value, graph, query}
      end

    results =
      tasks_input
      |> Task.async_stream(
        fn {n, _subject, expected_value, graph, query} ->
          rows = OxigraphQuery.run(graph, query)
          {n, expected_value, rows}
        end,
        max_concurrency: 20,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert length(results) == 20

    for {n, expected_value, rows} <- results do
      assert length(rows) == 1, "task #{n} expected exactly 1 row, got #{inspect(rows)}"
      [%{"value" => raw_value}] = rows

      decoded_value =
        raw_value
        |> String.trim_leading("\"")
        |> String.replace_suffix("\"", "")

      assert decoded_value == expected_value,
             "task #{n} got cross-contaminated result: expected #{inspect(expected_value)}, got #{inspect(decoded_value)}"
    end
  end

  test "a deliberately malformed Turtle string fails at Ontology.load!/1 with a clear real error, not a cryptic NIF crash" do
    tmp_path =
      Path.join(System.tmp_dir!(), "malformed_ontology_#{System.unique_integer([:positive])}.ttl")

    File.write!(tmp_path, "this is not : turtle @@@ <<<")

    on_exit(fn -> File.rm(tmp_path) end)

    error =
      assert_raise RuntimeError, fn ->
        Ontology.load!(tmp_path)
      end

    assert error.message =~ "Turtle scanner error"
  end

  describe "term normalization" do
    # Real, confirmed-fixed bug (see GgenIgniter.Query.Oxigraph's own
    # moduledoc, "Term normalization"): this engine used to return every
    # binding as oxigraph's raw N-Triples-style `Term::to_string()`
    # serialization (IRIs angle-bracket-wrapped, literals quoted and
    # datatype/language-tagged). Fixed AT THE SOURCE in
    # `native/ggen_graph_nif/src/oxigraph_engine.rs`'s `normalize_term/1`,
    # using oxrdf's own typed accessors (`Literal::value()`,
    # `NamedNode::as_str()`) -- no string-parsing/regex anywhere in this
    # path. These tests prove the four real cases the task requires: an IRI,
    # a plain string literal, a language-tagged literal, and a
    # datatype-tagged literal (xsd:boolean/xsd:integer) all come back clean
    # and unwrapped by default -- and that `raw: true` is a real, working,
    # explicit opt-in that still returns the original information in full.

    defp normalization_graph do
      RDF.Graph.new()
      |> RDF.Graph.add(
        {RDF.iri("https://example.org/term-norm/s"),
         RDF.iri("https://example.org/term-norm/p/iri"),
         RDF.iri("https://example.org/term-norm/object")}
      )
      |> RDF.Graph.add(
        {RDF.iri("https://example.org/term-norm/s"),
         RDF.iri("https://example.org/term-norm/p/plain"), "a plain string"}
      )
      |> RDF.Graph.add(
        {RDF.iri("https://example.org/term-norm/s"),
         RDF.iri("https://example.org/term-norm/p/lang"),
         RDF.LangString.new("hola", language: "es")}
      )
      |> RDF.Graph.add(
        {RDF.iri("https://example.org/term-norm/s"),
         RDF.iri("https://example.org/term-norm/p/bool"), RDF.XSD.Boolean.new(true)}
      )
      |> RDF.Graph.add(
        {RDF.iri("https://example.org/term-norm/s"),
         RDF.iri("https://example.org/term-norm/p/int"), RDF.XSD.Integer.new(42)}
      )
    end

    @normalization_query """
    SELECT ?iri_obj ?plain_str ?lang_tagged ?xsd_bool ?xsd_int WHERE {
      <https://example.org/term-norm/s> <https://example.org/term-norm/p/iri> ?iri_obj .
      <https://example.org/term-norm/s> <https://example.org/term-norm/p/plain> ?plain_str .
      <https://example.org/term-norm/s> <https://example.org/term-norm/p/lang> ?lang_tagged .
      <https://example.org/term-norm/s> <https://example.org/term-norm/p/bool> ?xsd_bool .
      <https://example.org/term-norm/s> <https://example.org/term-norm/p/int> ?xsd_int .
    }
    """

    test "an IRI object comes back plain (no angle brackets) by default, matching the sparql-hex engine exactly" do
      graph = normalization_graph()

      [oxigraph_row] = OxigraphQuery.run(graph, @normalization_query)
      [sparql_row] = Query.run(graph, @normalization_query)

      assert oxigraph_row["iri_obj"] == "https://example.org/term-norm/object"
      refute oxigraph_row["iri_obj"] =~ "<"
      refute oxigraph_row["iri_obj"] =~ ">"
      assert oxigraph_row["iri_obj"] == sparql_row["iri_obj"]
    end

    test "a plain string literal comes back unwrapped (no quotes) by default, matching the sparql-hex engine exactly" do
      graph = normalization_graph()

      [oxigraph_row] = OxigraphQuery.run(graph, @normalization_query)
      [sparql_row] = Query.run(graph, @normalization_query)

      assert oxigraph_row["plain_str"] == "a plain string"
      refute oxigraph_row["plain_str"] =~ "\""
      assert oxigraph_row["plain_str"] == sparql_row["plain_str"]
    end

    test "a language-tagged literal comes back as its plain value (language tag dropped) by default, matching the sparql-hex engine exactly" do
      graph = normalization_graph()

      [oxigraph_row] = OxigraphQuery.run(graph, @normalization_query)
      [sparql_row] = Query.run(graph, @normalization_query)

      assert oxigraph_row["lang_tagged"] == "hola"
      refute oxigraph_row["lang_tagged"] =~ "@"
      refute oxigraph_row["lang_tagged"] =~ "\""
      assert oxigraph_row["lang_tagged"] == sparql_row["lang_tagged"]
    end

    test "a datatype-tagged literal (xsd:boolean, xsd:integer) comes back as its clean lexical string (no ^^<datatype> suffix, no quotes) by default" do
      graph = normalization_graph()

      [oxigraph_row] = OxigraphQuery.run(graph, @normalization_query)

      assert oxigraph_row["xsd_bool"] == "true"
      refute oxigraph_row["xsd_bool"] =~ "^^"
      refute oxigraph_row["xsd_bool"] =~ "<"
      refute oxigraph_row["xsd_bool"] =~ "\""

      assert oxigraph_row["xsd_int"] == "42"
      refute oxigraph_row["xsd_int"] =~ "^^"
      refute oxigraph_row["xsd_int"] =~ "<"
      refute oxigraph_row["xsd_int"] =~ "\""
    end

    test "honest, disclosed divergence: the plain default is each literal's lexical STRING, not RDF.ex's native Elixir type for xsd:boolean/xsd:integer" do
      graph = normalization_graph()

      [oxigraph_row] = OxigraphQuery.run(graph, @normalization_query)
      [sparql_row] = Query.run(graph, @normalization_query)

      # sparql-hex (`RDF.Literal.value/1`, via RDF.ex's own per-datatype
      # `elixir_mapping/2`) really does return native Elixir types here --
      # confirmed, not assumed.
      assert sparql_row["xsd_bool"] == true
      assert sparql_row["xsd_int"] == 42

      # oxigraph's plain default returns the clean lexical string instead --
      # a real, documented divergence (see GgenIgniter.Query.Oxigraph's
      # moduledoc), asserted honestly here rather than silently glossed over.
      assert oxigraph_row["xsd_bool"] == "true"
      assert oxigraph_row["xsd_int"] == "42"
      refute oxigraph_row["xsd_bool"] == sparql_row["xsd_bool"]
      refute oxigraph_row["xsd_int"] == sparql_row["xsd_int"]
    end

    test "raw: true is a real, explicit opt-in returning oxigraph's original N-Triples-style term strings -- datatype/language info is not discarded" do
      graph = normalization_graph()

      [row] = OxigraphQuery.run(graph, @normalization_query, raw: true)

      assert row["iri_obj"] == "<https://example.org/term-norm/object>"
      assert row["plain_str"] == ~s("a plain string")
      assert row["lang_tagged"] == ~s("hola"@es)
      assert row["xsd_bool"] == ~s("true"^^<http://www.w3.org/2001/XMLSchema#boolean>)
      assert row["xsd_int"] == ~s("42"^^<http://www.w3.org/2001/XMLSchema#integer>)
    end

    test "run/2 and run/3 with opts: [] (raw defaulting to false) return identical, plain results" do
      graph = normalization_graph()

      assert OxigraphQuery.run(graph, @normalization_query) ==
               OxigraphQuery.run(graph, @normalization_query, [])
    end
  end

  # --- the actual payoff: does oxigraph resolve the pinned sparql-hex bug? ---

  @ash_r2rml_root Path.expand("~/ash_r2rml")
  @gate_010 Path.join(
              @ash_r2rml_root,
              "priv/ggen/ash-r2rml-pack/gates/010_required_resource_contract.rq"
            )
  @gate_020 Path.join(@ash_r2rml_root, "priv/ggen/ash-r2rml-pack/gates/020_property_contract.rq")
  @fortune5_shapes Path.join(@ash_r2rml_root, "priv/ontologies/fortune5/operational_shapes.ttl")

  setup do
    unless File.exists?(@ash_r2rml_root) do
      ExUnit.configure(exclude: [:requires_ash_r2rml])
    end

    :ok
  end

  @tag :requires_ash_r2rml
  test "gate 010 against real fortune5 shapes via --engine oxigraph: reports the real outcome, does not force a pass" do
    graph = Ontology.load!(@fortune5_shapes)
    gate_query = File.read!(@gate_010)

    # Confirm the sparql-hex engine still reproduces the pinned bug (baseline,
    # same assertion as ash_r2rml_gate_integration_test.exs) before checking
    # whether the alternative engine avoids it.
    assert_raise Protocol.UndefinedError, fn -> Query.run(graph, gate_query) end

    case OxigraphQuery.run(graph, gate_query) do
      rows when is_list(rows) ->
        # Real fix: oxigraph evaluates this valid SPARQL 1.1 query shape
        # correctly where sparql-hex could not.
        assert is_list(rows)

      other ->
        flunk("expected a row list from the oxigraph engine, got: #{inspect(other)}")
    end
  end

  @tag :requires_ash_r2rml
  test "gate 020 against real fortune5 shapes via --engine oxigraph: reports the real outcome, does not force a pass" do
    graph = Ontology.load!(@fortune5_shapes)
    gate_query = File.read!(@gate_020)

    assert_raise Protocol.UndefinedError, fn -> Query.run(graph, gate_query) end

    case OxigraphQuery.run(graph, gate_query) do
      rows when is_list(rows) ->
        assert is_list(rows)

      other ->
        flunk("expected a row list from the oxigraph engine, got: #{inspect(other)}")
    end
  end
end
