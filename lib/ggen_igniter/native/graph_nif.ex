defmodule GgenIgniter.Native.GraphNif do
  @moduledoc """
  Rustler NIF loader for `native/ggen_graph_nif` (the crate wraps the real
  `OxigraphEngine` from `~/ggen/crates/ggen-graph-wasm`'s `oxigraph-engine`
  feature). See `GgenIgniter.Query.Oxigraph` for the consumer-facing wrapper
  with the same `[map()]` row-list contract as the other query engines.
  """

  use Rustler, otp_app: :ggen_igniter, crate: "ggen_graph_nif"

  @doc """
  NIF stub -- replaced by the loaded native implementation at runtime.

  Values are PLAIN and normalized at the source (real oxrdf `Term`
  accessors -- `native/ggen_graph_nif/src/oxigraph_engine.rs`'s
  `normalize_term/1` -- not string-parsing): IRIs unwrapped (no `<...>`),
  literals unwrapped to their lexical value (no surrounding quotes, no
  `^^<datatype>`/`@lang` suffix). See `query_turtle_raw/2` for the explicit
  opt-in that returns oxigraph's original, pre-fix raw term-string shape.
  """
  @spec query_turtle(String.t(), String.t()) ::
          {:ok, [%{optional(String.t()) => String.t()}]} | {:error, String.t()}
  def query_turtle(_turtle, _sparql), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  NIF stub -- replaced by the loaded native implementation at runtime.

  Same contract as `query_turtle/2`, except every value is oxigraph's
  ORIGINAL, unprocessed N-Triples-style term string (IRIs angle-bracket-
  wrapped, literals quoted and datatype-IRI/language-tag-suffixed) -- this
  engine's behavior before the literal-quoting-bug fix, kept as a real,
  explicit, documented opt-in for callers who genuinely need the datatype/
  language information `query_turtle/2`'s plain values no longer carry
  inline. See `GgenIgniter.Query.Oxigraph.run/3`'s `raw: true` option.
  """
  @spec query_turtle_raw(String.t(), String.t()) ::
          {:ok, [%{optional(String.t()) => String.t()}]} | {:error, String.t()}
  def query_turtle_raw(_turtle, _sparql), do: :erlang.nif_error(:nif_not_loaded)
end
