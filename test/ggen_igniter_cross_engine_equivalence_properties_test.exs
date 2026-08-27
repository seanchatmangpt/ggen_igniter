defmodule GgenIgniter.CrossEngineEquivalencePropertiesTest do
  @moduledoc """
  Real, combinatorial, Chicago-style (no mocks) property test proving that
  `GgenIgniter.Query.run/2` (the default `--engine sparql`, backed by the
  `sparql` hex package) and `GgenIgniter.Query.Oxigraph.run/2`
  (`--engine oxigraph`, a real native Rustler NIF over oxigraph) return the
  SAME SET of result rows for the SAME randomly generated `%RDF.Graph{}` and
  the SAME query, across many StreamData-generated small graphs.

  ## Two real, already-confirmed, deliberately-out-of-scope divergences

  This property is precise about what it does and does not claim, per two
  divergences already pinned elsewhere in this codebase -- neither is
  "papered over" here; both are normalized/avoided honestly and named:

  1. **Row ORDER is not this property's subject.** `lib/ggen_igniter/query.ex`'s
     own moduledoc documents a confirmed bug: the `sparql` hex package
     (v0.3.12) silently REVERSES `ORDER BY` on a real join-shaped query (10
     rows came back `[9, 8, ..., 0]` instead of ascending `[0, 1, ..., 9]`),
     while `GgenIgniter.Query.Oxigraph.run/2` honors it correctly. The fixed
     query template used below (`SELECT ?s ?p ?o WHERE { ?s ?p ?o }`)
     deliberately has NO `ORDER BY`, and every row comparison below goes
     through `MapSet.new/1` (an unordered set), specifically so this
     already-documented, already-understood order divergence cannot leak into
     -- or be mistaken for a failure of -- the SET-equivalence property this
     file actually tests.

  2. **Literal/IRI term ENCODING -- historically normalized here, now FIXED
     at the source.** This property's `normalize_term/1` below was originally
     written to paper over a real, confirmed bug: oxigraph used to return
     raw, N-Triples-style term strings (IRIs wrapped in `<...>`, literals
     wrapped in quotes and, for non-string datatypes, suffixed
     `^^<datatype-iri>` or `@lang`), while `GgenIgniter.Query.run/2` returns
     plain unwrapped Elixir values (`RDF.IRI.to_string/1`,
     `RDF.Literal.value/1` -- no angle brackets, no quotes, no datatype
     suffix). That bug is now fixed AT THE SOURCE, in the Rust NIF itself
     (`native/ggen_graph_nif/src/oxigraph_engine.rs`'s `normalize_term/1`,
     using oxrdf's own typed accessors -- see
     `GgenIgniter.Query.Oxigraph`'s own moduledoc, "Term normalization", and
     `test/ggen_igniter_oxigraph_engine_test.exs`'s "term normalization"
     describe block for the real, verified proof). This test's own
     `normalize_term/1` below is kept as a real, harmless, idempotent no-op
     on both sides now (oxigraph's values are already plain, so stripping
     `<...>`/quotes/suffixes from an already-plain string matches nothing
     and returns it unchanged) -- a defensive belt-and-suspenders layer and
     a living record of the bug's old shape, not a required workaround for a
     still-live divergence.

  ## The real property under test

  For every generated graph and the fixed query template, after
  `normalize_term/1`:

    - the sparql-engine and oxigraph-engine row COUNTS are equal (asserted
      independently first -- a `MapSet`-only comparison alone could silently
      mask a real duplication/undercounting bug by treating `[a, a, b]` and
      `[a, b]` as equal sets), and
    - the sparql-engine and oxigraph-engine rows, each turned into a
      `MapSet` of normalized `%{"s" => .., "p" => .., "o" => ..}` maps, are
      set-equal.

  Graphs are generated via real `RDF.Graph.new/1` (a list of `{subject,
  predicate, object}` triples, coerced through RDF.ex's own real coercion --
  see `deps/rdf/lib/rdf/model/statement.ex`'s `coerce_subject/1`,
  `coerce_predicate/1`, `coerce_object/1` -- no hand-rolled term construction
  here). Both engines run against the exact same real `%RDF.Graph{}` value;
  no engine is mocked, stubbed, or faked.

  `qlever` (`lib/ggen_igniter/query/qlever.ex`) is out of scope for this
  property: it requires a real remote QLever endpoint (see
  `test/ash_r2rml_gate_qlever_test.exs`'s `:requires_qlever_server` tag
  pattern) rather than an in-process `%RDF.Graph{}`, and the task's own scope
  is the sparql/oxigraph pair.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GgenIgniter.Query
  alias GgenIgniter.Query.Oxigraph, as: OxigraphQuery

  @query "SELECT ?s ?p ?o WHERE { ?s ?p ?o }"

  # ---------------------------------------------------------------------
  # Generators -- small, valid RDF graphs
  # ---------------------------------------------------------------------

  # Alphanumeric-only IRI suffixes: simple, always-valid-as-an-IRI-path
  # characters, no percent-encoding edge cases to reason about.
  defp iri_suffix_gen do
    string([?a..?z, ?A..?Z, ?0..?9], min_length: 1, max_length: 8)
  end

  # Literal object values: letters, digits, space, hyphen, underscore only --
  # deliberately excludes `"` and `\` (and all control characters). This
  # keeps the Turtle-write -> oxigraph-NIF-parse -> N-Triples-style
  # `term.to_string()` round trip escape-free on the oxigraph side, so
  # `normalize_term/1`'s quote-stripping needs no real unescaping logic to
  # be exercised for the values this property actually generates (it still
  # carries a real, if untriggered-by-this-generator, unescape path -- see
  # `unescape_literal/1` below -- for honesty about what it would do if a
  # broader generator were used).
  defp literal_value_gen do
    string([?a..?z, ?A..?Z, ?0..?9, ?\s, ?-, ?_], min_length: 0, max_length: 16)
  end

  defp subject_iri(suffix), do: "https://example.org/cross-engine-eq/s/#{suffix}"
  defp predicate_iri(suffix), do: "https://example.org/cross-engine-eq/p/#{suffix}"

  # One triple drawn from a small, already-generated pool of subject/predicate
  # IRIs (rather than a fresh random suffix per triple), so generated graphs
  # realistically overlap -- multiple triples sharing a subject and/or a
  # predicate, the shape a real `SELECT ?s ?p ?o` actually queries over --
  # instead of degenerating into N pairwise-disjoint singleton triples.
  defp triple_gen(subjects, predicates) do
    gen all(
          s <- member_of(subjects),
          p <- member_of(predicates),
          o <- literal_value_gen()
        ) do
      {s, p, o}
    end
  end

  defp graph_triples_gen do
    gen all(
          subject_suffixes <- list_of(iri_suffix_gen(), min_length: 1, max_length: 3),
          predicate_suffixes <- list_of(iri_suffix_gen(), min_length: 1, max_length: 3),
          subjects = subject_suffixes |> Enum.uniq() |> Enum.map(&subject_iri/1),
          predicates = predicate_suffixes |> Enum.uniq() |> Enum.map(&predicate_iri/1),
          triples <- list_of(triple_gen(subjects, predicates), min_length: 1, max_length: 15)
        ) do
      triples
    end
  end

  # ---------------------------------------------------------------------
  # Normalization -- the real, honest fix for the confirmed encoding gap
  # ---------------------------------------------------------------------

  # Matches a whole-string N-Triples-style IRI: `<...>`.
  @iri_re ~r/^<(.*)>$/s

  # Matches a whole-string N-Triples-style literal: a quoted body (with
  # backslash-escaped `"`/`\` allowed inside, per N-Triples grammar) and an
  # optional `^^<datatype-iri>` or `@lang-tag` suffix.
  @literal_re ~r/^"((?:[^"\\]|\\.)*)"(?:\^\^<[^>]*>|@[a-zA-Z][a-zA-Z0-9-]*)?$/s

  @doc false
  def normalize_term(value) when is_binary(value) do
    cond do
      match = Regex.run(@iri_re, value) ->
        Enum.at(match, 1)

      match = Regex.run(@literal_re, value) ->
        match |> Enum.at(1) |> unescape_literal()

      true ->
        value
    end
  end

  def normalize_term(value), do: value

  defp unescape_literal(s) do
    s
    |> String.replace(~s(\\"), ~s("))
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\r", "\r")
  end

  defp normalize_row(row), do: Map.new(row, fn {k, v} -> {k, normalize_term(v)} end)

  # ---------------------------------------------------------------------
  # Grounding: normalize_term/1 against the actual, already-observed real
  # oxigraph output shapes (not synthetic examples) -- cited directly from
  # `test/ggen_igniter_e2e_all_engines_test.exs`'s moduledoc and
  # `test/ggen_igniter_oxigraph_engine_test.exs`'s real assertions, so this
  # helper is checked against real prior evidence before the property below
  # relies on it at scale.
  # ---------------------------------------------------------------------

  test "normalize_term/1 strips a real observed oxigraph IRI encoding (<...>) to the plain sparql-engine form" do
    assert normalize_term("<https://example.org/subject/1>") == "https://example.org/subject/1"
  end

  test "normalize_term/1 strips a real observed oxigraph plain-string literal encoding (\"name\") to the plain sparql-engine form" do
    # Exact shape cited in test/ggen_igniter_e2e_all_engines_test.exs's
    # moduledoc: a string literal comes back from oxigraph as `"name"`.
    assert normalize_term(~s("name")) == "name"
  end

  test "normalize_term/1 strips a real observed oxigraph datatype-annotated literal encoding to the plain sparql-engine form" do
    # Exact shape cited in test/ggen_igniter_e2e_all_engines_test.exs's
    # moduledoc: a typed boolean comes back from oxigraph as
    # `"true"^^<http://www.w3.org/2001/XMLSchema#boolean>`.
    assert normalize_term(~s("true"^^<http://www.w3.org/2001/XMLSchema#boolean>)) == "true"
  end

  test "normalize_term/1 leaves an already-plain sparql-engine value untouched (idempotent no-op on that side)" do
    assert normalize_term("https://example.org/subject/1") == "https://example.org/subject/1"
    assert normalize_term("name") == "name"
    assert normalize_term("") == ""
  end

  # ---------------------------------------------------------------------
  # The real cross-engine equivalence property
  # ---------------------------------------------------------------------

  property "sparql and oxigraph engines return the same SET of normalized rows for SELECT ?s ?p ?o over the same generated graph (order and encoding, both already-documented divergences, are excluded by construction)" do
    check all(triples <- graph_triples_gen()) do
      graph = RDF.Graph.new(triples)

      sparql_rows = Query.run(graph, @query)
      oxigraph_rows = OxigraphQuery.run(graph, @query)

      assert length(sparql_rows) == length(oxigraph_rows),
             "row count differs -- sparql: #{length(sparql_rows)}, oxigraph: #{length(oxigraph_rows)}\n" <>
               "graph triples: #{inspect(triples)}\n" <>
               "sparql rows: #{inspect(sparql_rows)}\n" <>
               "oxigraph rows: #{inspect(oxigraph_rows)}"

      normalized_sparql = sparql_rows |> Enum.map(&normalize_row/1) |> MapSet.new()
      normalized_oxigraph = oxigraph_rows |> Enum.map(&normalize_row/1) |> MapSet.new()

      assert normalized_sparql == normalized_oxigraph,
             """
             sparql and oxigraph engines disagree on the SET of rows after normalization.
             graph triples: #{inspect(triples)}
             sparql rows (raw): #{inspect(sparql_rows)}
             oxigraph rows (raw): #{inspect(oxigraph_rows)}
             sparql rows (normalized): #{inspect(MapSet.to_list(normalized_sparql))}
             oxigraph rows (normalized): #{inspect(MapSet.to_list(normalized_oxigraph))}
             only in sparql: #{inspect(MapSet.to_list(MapSet.difference(normalized_sparql, normalized_oxigraph)))}
             only in oxigraph: #{inspect(MapSet.to_list(MapSet.difference(normalized_oxigraph, normalized_sparql)))}
             """
    end
  end
end
