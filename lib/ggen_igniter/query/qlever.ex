# `:gno` is `optional: true` in `mix.exs`: it still resolves/compiles for THIS
# project's own dev/test (needed for this project's own test suite), but a
# consuming app that adds `ggen_igniter` as a dependency without itself
# depending on `:gno` must still be able to compile. `%Qlever{}` (i.e.
# `%Gno.Store.Adapters.Qlever{}`) is a `%Struct{}`-sugar pattern, which requires
# `Gno.Store.Adapters.Qlever.__struct__/0` to be resolvable at COMPILE time to
# expand the pattern -- if `:gno` isn't in the consumer's own deps, that struct
# expansion fails the whole module's compilation ("Gno.Store.Adapters.Qlever.
# __struct__/1 is undefined"), before any runtime guard could ever run.
#
# The fix: branch on `Code.ensure_loaded?/1` at the TOP LEVEL of this file (a
# plain `if/else`, evaluated once, at compile time) so only one of the two
# module bodies below is ever actually compiled. When `:gno` is loaded (this
# project's own dev/test, or any consumer that added `:gno` itself), the real
# implementation compiles exactly as before. When it isn't, a stub
# `GgenIgniter.Query.Qlever` compiles instead -- no struct pattern, no
# `Gno`/`SPARQL.Client` reference anywhere in it -- whose `load_store!/2` and
# `run/2` raise a clear, actionable `RuntimeError` the moment `--engine qlever`
# is actually used, instead of a raw compile error or `UndefinedFunctionError`.
if Code.ensure_loaded?(Gno.Store.Adapters.Qlever) do
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

    `Gno.select/1` (the top-level `Gno.Manifest`-driven convenience API) works
    fine once a manifest is authored correctly (in particular, once shared
    resources like a store description live in DCATR's "default graph" so its
    Manifest Graph Expansion can pull them into the service-manifest graph --
    see `~/dev/ggen_igniter/config/gno/test/store.ttl` for a real example, and
    https://github.com/rdf-elixir/gno/pull/2 for an unrelated real doc-comment
    fix found along the way). This module deliberately bypasses `Gno.Manifest`
    entirely: it takes a plain `%RDF.Graph{}` (the same type
    `GgenIgniter.Ontology.load!/1` already produces) and a store resource IRI,
    and loads just that one `Gno.Store.Adapters.Qlever` resource directly via
    `Grax.load/3` -- no `gno:Service`/`dcatr:Repository` manifest ceremony
    needed when all `ggen_igniter.sync` wants is "run this query against this
    QLever endpoint."

    ## Optional dependency

    `:gno` is `optional: true` in `mix.exs` (so is `:tesla`, which `gno` itself
    depends on). This module body only compiles when
    `Code.ensure_loaded?(Gno.Store.Adapters.Qlever)` is true at compile time --
    see the top of `qlever.ex` for the `else` branch a consumer without `:gno`
    gets instead.
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
          Enum.map(rows, &unwrap_row/1)

        {:error, %{__exception__: true} = error} ->
          raise error

        {:error, error} ->
          raise RuntimeError, message: "SPARQL.Client.query failed: #{inspect(error)}"
      end
    end

    defp unwrap_row(row), do: Map.new(row, fn {k, v} -> {k, unwrap(v)} end)

    defp unwrap(%RDF.IRI{} = iri), do: RDF.IRI.to_string(iri)
    defp unwrap(%RDF.Literal{} = lit), do: RDF.Literal.value(lit)
    defp unwrap(%RDF.BlankNode{} = bnode), do: to_string(bnode)
    defp unwrap(other), do: other
  end
else
  defmodule GgenIgniter.Query.Qlever do
    @moduledoc """
    Stub compiled in place of the real QLever-backed engine when `:gno` is not
    loaded -- `:gno` is a genuinely optional dependency (`optional: true` in
    `mix.exs`), so a consumer app that adds `ggen_igniter` without adding `:gno`
    to its own deps must still compile. This stub has no reference to
    `Gno`/`SPARQL.Client`/any `%Qlever{}` struct anywhere in it, so it compiles
    clean regardless; both functions simply raise a clear, actionable
    `RuntimeError` the moment `--engine qlever` is actually reached, instead of
    letting a raw `UndefinedFunctionError` or compile error surface.
    """

    @missing_gno_message "ggen_igniter: :gno is required for --engine qlever " <>
                           "(Gno.Store.Adapters.Qlever) but is not loaded -- add " <>
                           "{:gno, \"~> 0.1\"} to your own mix.exs deps"

    @doc false
    @spec load_store!(RDF.Graph.t(), RDF.IRI.t() | String.t()) :: no_return()
    def load_store!(_graph, _store_id), do: raise(RuntimeError, message: @missing_gno_message)

    @doc false
    @spec run(term(), String.t()) :: no_return()
    def run(_store, _query_string), do: raise(RuntimeError, message: @missing_gno_message)
  end
end
