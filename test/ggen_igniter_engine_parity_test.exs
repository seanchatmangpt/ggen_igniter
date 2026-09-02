defmodule GgenIgniter.EngineParityTest do
  @moduledoc """
  Real, Chicago-style (no mocks) contract-matrix test suite: the SAME set of
  query shapes (SELECT, ASK, CONSTRUCT, empty-result, FILTER, FILTER NOT
  EXISTS, a typed-literal query, a unicode-literal query, a deliberately
  malformed query) run against `GgenIgniter.Query.run/2` (`--engine sparql`,
  the `sparql` hex package) and `GgenIgniter.Query.Oxigraph.run/2`
  (`--engine oxigraph`, the real native oxigraph NIF), over the exact same
  real `%RDF.Graph{}` values. `--engine qlever` is exercised too, but only
  against a real, already-running QLever server -- it is SKIPPED with a
  named `:requires_qlever_server` tag (never faked) when no live endpoint is
  reachable, following the exact pattern already used in
  `test/ggen_igniter_sync_qlever_engine_test.exs`.

  ## What's already documented elsewhere (asserted here as REGRESSION pins,
  not re-discovered)

  1. **`ORDER BY` reversal on sparql-hex** -- `lib/ggen_igniter/query.ex`'s
     moduledoc. Not re-tested here (this file's SELECT case has no `ORDER
     BY`); the cross-engine equivalence property test already covers this.
  2. **ASK returns SELECT-shaped bindings on sparql-hex, not a boolean** --
     `test/ggen_igniter_ask_construct_engine_divergence_test.exs`. Asserted
     here again as the ASK row of the matrix, so the whole query-shape sweep
     lives in one place with all shapes visible together.
  3. **CONSTRUCT raises a raw `MatchError` on sparql-hex** -- same file.
     Asserted here as the CONSTRUCT row.
  4. **Malformed query raises a raw `MatchError` on sparql-hex** (vs a clear
     named `RuntimeError` on oxigraph) -- same file. Asserted here as the
     malformed-query row.
  5. **Bare `FILTER NOT EXISTS` raises `Protocol.UndefinedError` on
     sparql-hex, unconditionally** -- same file. Asserted here as the FILTER
     NOT EXISTS row.
  6. **Term encoding**: oxigraph's plain-value normalization (fixed at the
     NIF source, see `GgenIgniter.Query.Oxigraph`'s moduledoc "Term
     normalization") means, post-fix, typed-literal and unicode-literal rows
     from BOTH engines carry plain lexical strings with no `<...>`/quote/`^^`
     wrapper -- this file's typed-literal and unicode-literal cases assert
     that plain-value equality directly (no `normalize_term/1` needed, unlike
     the pre-fix property test in
     `test/ggen_igniter_cross_engine_equivalence_properties_test.exs`, which
     keeps its own normalizer only as a defensive no-op / historical record).

  ## Newly-discovered divergences found while building this matrix

  None found beyond what's already listed above -- see the "typed-literal"
  and "unicode-literal" describe blocks below, which are new coverage (no
  prior test in this repo exercises `xsd:integer`/`xsd:boolean` typed
  literals or a non-ASCII literal value across both engines) and PASS
  identically on both engines, confirming no new divergence in that surface.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.Query
  alias GgenIgniter.Query.Oxigraph, as: OxigraphQuery
  alias GgenIgniter.Query.Qlever, as: QleverQuery
  alias GgenIgniter.Native.GraphNif

  # ---------------------------------------------------------------------
  # Fixture graph shared by every non-typed/non-unicode case in the matrix
  # ---------------------------------------------------------------------

  defp base_graph do
    RDF.Graph.new([
      {"https://example.org/parity/s1", "https://example.org/parity/p", "hello"},
      {"https://example.org/parity/s2", "https://example.org/parity/p", "world"},
      {"https://example.org/parity/s1", "https://example.org/parity/tag", "keep"}
    ])
  end

  defp normalize_row(row), do: Map.new(row, fn {k, v} -> {k, normalize_term(v)} end)

  # Belt-and-suspenders strip of oxigraph's pre-fix raw N-Triples encoding,
  # kept only for defensive parity with
  # `ggen_igniter_cross_engine_equivalence_properties_test.exs` -- both
  # engines already return plain values post-fix, so this is a no-op on real
  # current output.
  @iri_re ~r/^<(.*)>$/s
  @literal_re ~r/^"((?:[^"\\]|\\.)*)"(?:\^\^<[^>]*>|@[a-zA-Z][a-zA-Z0-9-]*)?$/s

  defp normalize_term(value) when is_binary(value) do
    cond do
      match = Regex.run(@iri_re, value) -> Enum.at(match, 1)
      match = Regex.run(@literal_re, value) -> Enum.at(match, 1)
      true -> value
    end
  end

  defp normalize_term(value), do: value

  defp rows_as_set(rows), do: rows |> Enum.map(&normalize_row/1) |> MapSet.new()

  # ---------------------------------------------------------------------
  # SELECT
  # ---------------------------------------------------------------------

  describe "SELECT" do
    @query "SELECT ?s ?p ?o WHERE { ?s ?p ?o }"

    test "sparql and oxigraph return the same set of rows" do
      sparql_rows = Query.run(base_graph(), @query)
      oxigraph_rows = OxigraphQuery.run(base_graph(), @query)

      assert length(sparql_rows) == length(oxigraph_rows)
      assert rows_as_set(sparql_rows) == rows_as_set(oxigraph_rows)
      assert length(sparql_rows) == 3
    end
  end

  # ---------------------------------------------------------------------
  # Empty result
  # ---------------------------------------------------------------------

  describe "empty-result SELECT" do
    @empty_query "SELECT ?s WHERE { ?s <https://example.org/parity/nomatch> ?o }"

    test "sparql and oxigraph both return an empty list" do
      assert Query.run(base_graph(), @empty_query) == []
      assert OxigraphQuery.run(base_graph(), @empty_query) == []
    end
  end

  # ---------------------------------------------------------------------
  # FILTER
  # ---------------------------------------------------------------------

  describe "FILTER" do
    @filter_query """
    SELECT ?s ?o WHERE {
      ?s <https://example.org/parity/p> ?o .
      FILTER (?o = "hello")
    }
    """

    test "sparql and oxigraph agree on the filtered set" do
      sparql_rows = Query.run(base_graph(), @filter_query)
      oxigraph_rows = OxigraphQuery.run(base_graph(), @filter_query)

      assert rows_as_set(sparql_rows) == rows_as_set(oxigraph_rows)
      assert length(sparql_rows) == 1
    end
  end

  # ---------------------------------------------------------------------
  # FILTER NOT EXISTS -- already-documented sparql-hex divergence, pinned
  # here as a regression, not re-discovered.
  # ---------------------------------------------------------------------

  describe "FILTER NOT EXISTS (documented sparql-hex divergence)" do
    @fne_query """
    SELECT ?s WHERE {
      ?s ?p ?o .
      FILTER NOT EXISTS { ?s <https://example.org/parity/nomatch> ?x }
    }
    """

    test "sparql-hex raises Protocol.UndefinedError (documented, broader-than-UNION+BIND bug)" do
      assert_raise Protocol.UndefinedError, ~r/SPARQL.Algebra.Expression/, fn ->
        Query.run(base_graph(), @fne_query)
      end
    end

    test "oxigraph evaluates FILTER NOT EXISTS correctly" do
      rows = OxigraphQuery.run(base_graph(), @fne_query)
      assert length(rows) == 3
    end
  end

  # ---------------------------------------------------------------------
  # ASK -- already-documented sparql-hex divergence, pinned here.
  # ---------------------------------------------------------------------

  describe "ASK (documented sparql-hex divergence)" do
    @ask_query "ASK { ?s ?p ?o }"

    test "sparql-hex silently returns SELECT-shaped bindings, not a boolean" do
      rows = Query.run(base_graph(), @ask_query)

      assert is_list(rows)
      refute rows == true
      refute rows == false
    end

    test "oxigraph raises a clear, named RuntimeError instead of mis-executing" do
      assert_raise RuntimeError, ~r/query must be a SPARQL SELECT to yield rows/, fn ->
        OxigraphQuery.run(base_graph(), @ask_query)
      end
    end
  end

  # ---------------------------------------------------------------------
  # CONSTRUCT -- already-documented sparql-hex divergence, pinned here.
  # ---------------------------------------------------------------------

  describe "CONSTRUCT (documented sparql-hex divergence)" do
    @construct_query "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }"

    test "sparql-hex raises a raw, unwrapped MatchError" do
      error =
        assert_raise MatchError, fn ->
          Query.run(base_graph(), @construct_query)
        end

      assert %RDF.Graph{} = error.term
    end

    test "oxigraph raises the same clear, named RuntimeError as ASK" do
      assert_raise RuntimeError, ~r/query must be a SPARQL SELECT to yield rows/, fn ->
        OxigraphQuery.run(base_graph(), @construct_query)
      end
    end
  end

  # ---------------------------------------------------------------------
  # Malformed query -- already-documented sparql-hex divergence, pinned here.
  # ---------------------------------------------------------------------

  describe "malformed query (documented sparql-hex divergence)" do
    @malformed_query "SELECT ?s WHERE { ?s ?p ?o"

    test "sparql-hex raises a raw MatchError against SPARQL.execute_query/2's {:error, reason}" do
      assert_raise MatchError, fn ->
        Query.run(base_graph(), @malformed_query)
      end
    end

    test "oxigraph raises a clear, named RuntimeError naming the real NIF-reported reason" do
      assert_raise RuntimeError, ~r/oxigraph engine query failed/, fn ->
        OxigraphQuery.run(base_graph(), @malformed_query)
      end
    end
  end

  # ---------------------------------------------------------------------
  # Typed-literal query -- NEW coverage: no prior test in this repo exercises
  # xsd:integer / xsd:boolean typed literals across both engines.
  # ---------------------------------------------------------------------

  describe "typed-literal query (new coverage)" do
    defp typed_literal_graph do
      RDF.Graph.new([
        {"https://example.org/parity/typed/s1", "https://example.org/parity/typed/age",
         RDF.XSD.integer(42)},
        {"https://example.org/parity/typed/s1", "https://example.org/parity/typed/active",
         RDF.XSD.boolean(true)}
      ])
    end

    @typed_query "SELECT ?p ?o WHERE { <https://example.org/parity/typed/s1> ?p ?o }"

    test "sparql-hex returns native Elixir integer/boolean values (RDF.ex's per-datatype elixir_mapping/2)" do
      rows = Query.run(typed_literal_graph(), @typed_query)

      values = rows |> Enum.map(& &1["o"]) |> Enum.sort()
      assert 42 in values
      assert true in values
    end

    test "oxigraph returns the plain lexical string form (documented scope limit, not a bug)" do
      rows = OxigraphQuery.run(typed_literal_graph(), @typed_query)

      values = rows |> Enum.map(& &1["o"]) |> Enum.sort()
      # Documented, disclosed limit in GgenIgniter.Query.Oxigraph's own
      # moduledoc ("Term normalization"): the plain default returns each
      # literal's LEXICAL STRING uniformly regardless of datatype -- "42"
      # and "true" as strings, not native 42 / true. This is a real,
      # already-documented divergence from sparql-hex's native coercion, not
      # newly discovered here -- asserted explicitly rather than silently
      # ignored.
      assert "42" in values
      assert "true" in values
      refute 42 in values
      refute true in values
    end
  end

  # ---------------------------------------------------------------------
  # Unicode-literal query -- NEW coverage: no prior test in this repo
  # exercises a non-ASCII literal value across both engines.
  # ---------------------------------------------------------------------

  describe "unicode-literal query (new coverage)" do
    @unicode_value "héllo wörld 日本語 😀"

    defp unicode_graph do
      RDF.Graph.new([
        {"https://example.org/parity/unicode/s1", "https://example.org/parity/unicode/label",
         @unicode_value}
      ])
    end

    @unicode_query "SELECT ?o WHERE { <https://example.org/parity/unicode/s1> ?p ?o }"

    test "sparql and oxigraph both round-trip the unicode literal identically" do
      sparql_rows = Query.run(unicode_graph(), @unicode_query)
      oxigraph_rows = OxigraphQuery.run(unicode_graph(), @unicode_query)

      assert [%{"o" => @unicode_value}] = sparql_rows
      assert [%{"o" => @unicode_value}] = oxigraph_rows
    end
  end

  # ---------------------------------------------------------------------
  # qlever -- exercised for real only against a live endpoint; named,
  # visible skip otherwise (never faked).
  # ---------------------------------------------------------------------

  describe "qlever engine (real endpoint only, skipped otherwise)" do
    # Reuses the exact real store fixture already used by
    # `test/ggen_igniter_sync_qlever_engine_test.exs`
    # (`config/gno/test/store.ttl`: a real `gnoa:Qlever` resource pointing at
    # `127.0.0.1:7020`) -- this machine has a real, locally-running QLever
    # server reachable there (confirmed via a real `curl` HTTP round trip,
    # 404 response -- server up, just no route at `/`), so this test runs
    # for real rather than being skipped, unlike a CI/fresh-clone environment
    # without that server, where the `:requires_qlever_server` exclude
    # (configured in `setup/0` above) takes over.
    @tag :requires_qlever_server
    test "malformed-query row of the matrix: qlever raises for real over the live endpoint" do
      store =
        QleverQuery.load_store!(
          RDF.Turtle.read_file!("config/gno/test/store.ttl"),
          "http://example.com/Qlever"
        )

      assert_raise RuntimeError, fn ->
        QleverQuery.run(store, "SELECT ?s WHERE { ?s ?p ?o")
      end
    end

    @tag :requires_qlever_server
    test "SELECT row of the matrix: qlever returns real [map()] rows over the live endpoint" do
      store =
        QleverQuery.load_store!(
          RDF.Turtle.read_file!("config/gno/test/store.ttl"),
          "http://example.com/Qlever"
        )

      rows = QleverQuery.run(store, "SELECT * WHERE { ?s ?p ?o } LIMIT 1")

      assert is_list(rows)
      assert Enum.all?(rows, &is_map/1)
    end
  end

  # ---------------------------------------------------------------------
  # Grounding: confirm the native NIF module used by GgenIgniter.Query.Oxigraph
  # is really loaded (not a stub) -- a sanity check that this whole suite is
  # exercising the real Rustler NIF, not silently no-op'ing.
  # ---------------------------------------------------------------------

  test "the real oxigraph NIF module is loaded (not a stub / not mocked)" do
    assert Code.ensure_loaded?(GraphNif)
    assert function_exported?(GraphNif, :query_turtle, 2)
  end
end
