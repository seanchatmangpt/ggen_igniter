defmodule GgenIgniter.Query.Oxigraph do
  @moduledoc """
  Runs SPARQL queries via a real, native oxigraph engine (a Rustler NIF over
  `~/ggen/crates/ggen-graph-wasm`'s `OxigraphEngine`, `native/ggen_graph_nif`)
  instead of the pure-Elixir `sparql` hex package used by
  `GgenIgniter.Query.run/2`.

  Same `[map()]` row-list contract as `GgenIgniter.Query.run/2` and
  `GgenIgniter.Query.Qlever.run/2` -- a drop-in alternative engine, not a
  replacement API.

  Real motivation, not just "one more engine option": `GgenIgniter.Query.run/2`
  (the `sparql` 0.3.12 hex package) has a confirmed, already-pinned bug --
  it raises `Protocol.UndefinedError` on real gate queries shaped like
  `FILTER NOT EXISTS { ... }` with an unprojected variable inside a `UNION`,
  combined with `BIND` (see `test/ash_r2rml_gate_integration_test.exs`).
  Oxigraph is a full, independent SPARQL 1.1 engine -- routing that same
  query shape through this module is a real, testable way to check whether
  it resolves that blocker (see `test/ggen_igniter_oxigraph_engine_test.exs`).
  """

  alias GgenIgniter.Native.GraphNif

  @doc """
  Serializes `graph` back to Turtle (it is already fully loaded in memory by
  `GgenIgniter.Ontology.load!/1` -- no re-read from disk) and runs `query`
  against it via the native oxigraph NIF. Raises `RuntimeError` with a clear
  message on any NIF-reported error, never letting a raw `{:error, reason}`
  tuple surface uncaught (same discipline as the recent
  `GgenIgniter.Query.Qlever.run/2` bugfix).
  """
  @spec run(RDF.Graph.t(), String.t()) :: [map()]
  def run(%RDF.Graph{} = graph, query) when is_binary(query) do
    turtle = RDF.Turtle.write_string!(graph)

    case GraphNif.query_turtle(turtle, query) do
      {:ok, rows} -> rows
      {:error, reason} -> raise RuntimeError, message: "oxigraph engine query failed: #{reason}"
    end
  end
end
