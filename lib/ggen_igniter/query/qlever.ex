defmodule GgenIgniter.Query.Qlever do
  @moduledoc """
  Alternate `GgenIgniter.Query`-shaped engine backed by a real QLever SPARQL
  endpoint, via `gno`'s `Gno.Store.Adapters.Qlever` adapter for endpoint
  resolution and `SPARQL.Client` (both real, hex-published deps -- rdf-elixir's
  own `sparql_client`) for protocol execution.

  Same contract as `GgenIgniter.Query.run/2`: `(source, query_string) :: [map()]`.
  Here `source` is a `Gno.Store.Adapters.Qlever` struct (not an `%RDF.Graph{}` --
  QLever is a remote, already-loaded store, not an in-process graph) instead of
  the `%RDF.Graph{}` the default `sparql`-engine-backed `GgenIgniter.Query` takes.

  ## Why this module exists

  `ggen_igniter/test/ash_r2rml_gate_integration_test.exs` pinned a real,
  reproducing bug in the `sparql` 0.3.12 engine (a `FILTER NOT EXISTS` +
  `BIND(constant)` inside `UNION` -- a shape both of `ash_r2rml`'s real gate
  queries use -- raises `Protocol.UndefinedError`). This module is the
  alternate-engine escape hatch: the identical query text against a real,
  independent SPARQL 1.1 engine (QLever), executed over its query endpoint.

  ## Note on `Gno.select/1`

  `Gno.select/1` (the top-level `Gno.Manifest`-driven convenience API) was
  tried first and hit a real bug in `gno` 0.1.0: `Gno.Service`'s polymorphic
  `store` link (`type: Gno.Store`) does not dispatch to the registered
  `Gno.Store.Adapters.Qlever` subtype when loaded through `Grax.load/3` with
  the base `Gno.Store` type -- it validates against `Gno.Store`'s own schema
  (which requires `query_endpoint` at cardinality 1) instead of the adapter's
  overridden schema (`required: false`, computed from scheme/host/port),
  raising a spurious `Grax.Schema.CardinalityError`. Reproduced directly:

      Grax.load(graph, id, Gno.Store)                    # => {:error, CardinalityError}
      Grax.load(graph, id, Gno.Store.Adapters.Qlever)     # => {:ok, %Gno.Store.Adapters.Qlever{...}}

  Loading the concrete adapter type directly (as this module does) sidesteps
  the bug entirely while still using `gno`'s real, working store/endpoint
  abstraction -- not a hand-rolled URL string.
  """

  alias Gno.Store
  alias Gno.Store.Adapters.Qlever

  @doc """
  Loads a `Qlever` store description from a real manifest Turtle graph.

  `graph` must contain a `gnoa:Qlever`-typed resource at `store_id`.
  """
  @spec load_store!(RDF.Graph.t(), RDF.IRI.t() | String.t()) :: Qlever.t()
  def load_store!(graph, store_id) do
    case Grax.load(graph, RDF.iri(store_id), Qlever) do
      {:ok, store} -> store
      {:error, error} -> raise error
    end
  end

  @doc """
  Runs `query_string` against the real QLever endpoint described by `store`.

  Same return shape as `GgenIgniter.Query.run/2`: a list of string-keyed maps,
  values unwrapped from `RDF.IRI`/`RDF.Literal` to bare Elixir values.
  """
  @spec run(Qlever.t(), String.t()) :: [map()]
  def run(%Qlever{} = store, query_string) do
    {:ok, endpoint} = Store.query_endpoint(store)

    case SPARQL.Client.query(query_string, endpoint) do
      {:ok, %SPARQL.Query.Result{results: rows}} ->
        Enum.map(rows, fn row -> Map.new(row, fn {k, v} -> {k, unwrap(v)} end) end)

      {:error, error} ->
        raise error
    end
  end

  defp unwrap(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
  defp unwrap(%RDF.Literal{} = lit), do: RDF.Literal.value(lit)
  defp unwrap(%RDF.BlankNode{} = bnode), do: to_string(bnode)
  defp unwrap(other), do: other
end
