defmodule GgenIgniter.Native.GraphNif do
  @moduledoc """
  Rustler NIF loader for `native/ggen_graph_nif` (the crate wraps the real
  `OxigraphEngine` from `~/ggen/crates/ggen-graph-wasm`'s `oxigraph-engine`
  feature). See `GgenIgniter.Query.Oxigraph` for the consumer-facing wrapper
  with the same `[map()]` row-list contract as the other query engines.
  """

  use Rustler, otp_app: :ggen_igniter, crate: "ggen_graph_nif"

  @doc "NIF stub -- replaced by the loaded native implementation at runtime."
  @spec query_turtle(String.t(), String.t()) ::
          {:ok, [%{optional(String.t()) => String.t()}]} | {:error, String.t()}
  def query_turtle(_turtle, _sparql), do: :erlang.nif_error(:nif_not_loaded)
end
