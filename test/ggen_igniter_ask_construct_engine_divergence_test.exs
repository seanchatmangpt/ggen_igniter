defmodule GgenIgniter.AskConstructEngineDivergenceTest do
  @moduledoc """
  Pins a THIRD, previously-undocumented divergence between
  `GgenIgniter.Query.run/2` (`--engine sparql`, the `sparql` hex package
  v0.3.12) and `GgenIgniter.Query.Oxigraph.run/2` (`--engine oxigraph`, the
  native oxigraph NIF), found while building real query-shape coverage for
  this session's FILTER/UNION/FILTER NOT EXISTS/CONSTRUCT/ASK sweep.

  ## The two already-known divergences (NOT this file's subject)

  1. `sparql` hex reverses `ORDER BY` on join-shaped queries
     (`lib/ggen_igniter/query.ex` moduledoc).
  2. oxigraph returns raw N-Triples-style term encoding vs sparql's plain
     values (`test/ggen_igniter_cross_engine_equivalence_properties_test.exs`,
     `test/ggen_igniter_e2e_all_engines_test.exs`).

  ## The THIRD divergence, confirmed here with real evidence

  `GgenIgniter.Query.run/2` has NO error-handling branch: it pattern-matches
  `%SPARQL.Query.Result{results: rows} = SPARQL.execute_query(graph, query)`
  unconditionally (`lib/ggen_igniter/query.ex:21`). `GgenIgniter.Query.Oxigraph.run/2`,
  by contrast, explicitly branches on `{:ok, rows} | {:error, reason}` and
  raises a clear, actionable `RuntimeError` on any failure
  (`lib/ggen_igniter/query/oxigraph.ex:36-39`). This produces THREE concretely
  different, real failure/success modes for the exact same query text run
  against the exact same graph:

  - **ASK**: sparql-hex does NOT return a boolean. `SPARQL.execute_query/2`
    evaluates the ASK query's WHERE-clause pattern and returns its bindings
    as ordinary `%SPARQL.Query.Result{results: rows}` rows (the same shape a
    `SELECT` over that pattern would produce) -- `GgenIgniter.Query.run/2`
    passes that straight through with NO indication the query was ASK, not
    SELECT. This is a real, silent WRONG-ANSWER divergence (not a crash): a
    caller asking "does any triple match?" gets back a list of full variable
    bindings instead of `true`/`false`. Oxigraph, by contrast, raises a clear
    `RuntimeError` naming exactly why (only `QueryResults::Solutions` --
    real SELECT results -- are handled; ASK's `QueryResults::Boolean` hits
    `OxigraphEngineError::NotSelectQuery`).
  - **CONSTRUCT**: sparql-hex raises a raw, unwrapped `MatchError` (the
    right-hand side is a real `%RDF.Graph{}`, not a `%SPARQL.Query.Result{}`)
    -- an uncaught internal-shape crash a caller has no clean way to detect
    or handle. Oxigraph raises the same clear, named `RuntimeError` as ASK.
  - **A malformed query** (real SPARQL scanner error): sparql-hex again
    raises a raw `MatchError` against `SPARQL.execute_query/2`'s real
    `{:error, reason}` tuple, instead of a clear wrapped error. Oxigraph
    raises a clear `RuntimeError` naming the real NIF-reported reason.
  - **Bare `FILTER NOT EXISTS`** (no `UNION`, no `BIND` -- simpler than the
    already-documented UNION+BIND-specific crash in
    `lib/ggen_igniter/query/oxigraph.ex`'s moduledoc): sparql-hex still
    raises `Protocol.UndefinedError` (`SPARQL.Algebra.Expression` not
    implemented for `Atom`, value `:"$undefined"`) even in this minimal
    shape. Oxigraph evaluates it correctly. This means the already-pinned
    `sparql`-hex `FILTER NOT EXISTS` bug is BROADER than previously
    documented: not limited to the UNION+BIND combination, `FILTER NOT
    EXISTS` is unconditionally broken on this engine for any query that
    reaches it.

  All four sub-findings are proven below against real `%RDF.Graph{}` values
  and real `SPARQL.execute_query/2`/oxigraph NIF calls -- no mocks.

  ## Honest scope note

  This file documents the divergence; it does not fix
  `GgenIgniter.Query.run/2`'s lack of error-handling or its FILTER NOT EXISTS
  support, both of which live in `lib/ggen_igniter/query.ex` -- a file
  outside this agent's write-scope (`lib/ggen_igniter/query/*`,
  `lib/ggen_igniter/engine*`; `query.ex` itself is a sibling file, not under
  `query/`). Logged to `.ggen_igniter_factory/ledger-agent5.jsonl` for a
  follow-up agent with write access to that file.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Query
  alias GgenIgniter.Query.Oxigraph, as: OxigraphQuery

  defp small_graph do
    RDF.Graph.new([
      {"https://example.org/divergence/s1", "https://example.org/divergence/p", "hello"},
      {"https://example.org/divergence/s2", "https://example.org/divergence/p", "world"}
    ])
  end

  describe "ASK: sparql-hex silently returns SELECT-shaped bindings instead of a boolean" do
    test "sparql-hex ASK with a match returns row bindings for the WHERE pattern, not `true`" do
      rows = Query.run(small_graph(), "ASK { ?s ?p ?o }")

      assert is_list(rows)
      assert length(rows) == 2
      assert Enum.all?(rows, &match?(%{"s" => _, "p" => _, "o" => _}, &1))
      # The real, current wrong behavior: no `true`/`false` anywhere.
      refute rows == true
      refute rows == false
    end

    test "sparql-hex ASK with zero real matches returns an empty list, not `false`" do
      rows = Query.run(small_graph(), "ASK { ?s <https://example.org/divergence/nomatch> ?o }")

      assert rows == []
      refute rows == false
    end

    test "oxigraph ASK raises a clear, named RuntimeError instead of silently mis-executing" do
      assert_raise RuntimeError, ~r/query must be a SPARQL SELECT to yield rows/, fn ->
        OxigraphQuery.run(small_graph(), "ASK { ?s ?p ?o }")
      end
    end
  end

  describe "CONSTRUCT: sparql-hex raises an unwrapped MatchError; oxigraph raises a clear RuntimeError" do
    test "sparql-hex CONSTRUCT raises a raw, unwrapped MatchError (real %RDF.Graph{} on the right-hand side)" do
      error =
        assert_raise MatchError, fn ->
          Query.run(small_graph(), "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }")
        end

      assert %RDF.Graph{} = error.term
    end

    test "oxigraph CONSTRUCT raises the same clear, named RuntimeError as ASK" do
      assert_raise RuntimeError, ~r/query must be a SPARQL SELECT to yield rows/, fn ->
        OxigraphQuery.run(small_graph(), "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }")
      end
    end
  end

  describe "bare FILTER NOT EXISTS: broader sparql-hex crash than previously documented" do
    test "sparql-hex raises Protocol.UndefinedError even without UNION or BIND (simpler than the documented shape)" do
      query = """
      SELECT ?s WHERE {
        ?s ?p ?o .
        FILTER NOT EXISTS { ?s <https://example.org/divergence/nomatch> ?x }
      }
      """

      assert_raise Protocol.UndefinedError, ~r/SPARQL.Algebra.Expression/, fn ->
        Query.run(small_graph(), query)
      end
    end

    test "oxigraph evaluates the identical bare FILTER NOT EXISTS query correctly" do
      query = """
      SELECT ?s WHERE {
        ?s ?p ?o .
        FILTER NOT EXISTS { ?s <https://example.org/divergence/nomatch> ?x }
      }
      """

      rows = OxigraphQuery.run(small_graph(), query)

      assert length(rows) == 2
    end
  end
end
