defmodule GgenIgniter.Engine do
  @moduledoc """
  Behaviour every `--engine NAME` implementation satisfies, so
  `Mix.Tasks.GgenIgniter.Sync` dispatches through a lookup table
  (`GgenIgniter.Engine.registry/0`) instead of hardcoded, string-pattern-matched
  function clauses (`run_queries("sparql", ...)`, `run_queries("qlever", ...)`,
  etc.). Adding a new engine means adding one module + one registry entry, not
  editing the sync task's dispatch logic.

  Two callbacks, split so per-engine setup (e.g. `qlever`'s `--store-id`
  lookup and Finch bootstrap) happens once per sync run, not once per query:

  - `prepare!/2` — takes the loaded `%RDF.Graph{}` and the raw CLI opts,
    returns whatever context `run/2` needs (the graph itself, a loaded store
    struct, ...).
  - `run/2` — takes that context and one query string, returns `[map()]` rows
    (the same row-list contract every engine module already honored before
    this abstraction existed).
  """

  @callback prepare!(RDF.Graph.t(), keyword()) :: term()
  @callback run(term(), String.t()) :: [map()]

  @registry %{
    "sparql" => GgenIgniter.Engine.Sparql,
    "qlever" => GgenIgniter.Engine.Qlever,
    "oxigraph" => GgenIgniter.Engine.Oxigraph
  }

  @doc """
  The `--engine` name => implementing module map. The single source of truth
  for valid `--engine` values.

  ## Examples

      iex> GgenIgniter.Engine.registry()
      %{
        "sparql" => GgenIgniter.Engine.Sparql,
        "qlever" => GgenIgniter.Engine.Qlever,
        "oxigraph" => GgenIgniter.Engine.Oxigraph
      }

  """
  @spec registry() :: %{optional(String.t()) => module()}
  def registry, do: @registry

  @doc """
  Valid `--engine` names, for CLI validation/error messages.

  ## Examples

      iex> GgenIgniter.Engine.valid_names()
      ["oxigraph", "qlever", "sparql"]

  """
  @spec valid_names() :: [String.t()]
  def valid_names, do: Map.keys(@registry)

  @doc """
  Looks up the engine module for `name`, raising `ArgumentError` on an unknown
  engine.

  ## Examples

      iex> GgenIgniter.Engine.fetch!("sparql")
      GgenIgniter.Engine.Sparql

      iex> GgenIgniter.Engine.fetch!("nope")
      ** (ArgumentError) invalid --engine "nope", must be one of: oxigraph, qlever, sparql

  """
  @spec fetch!(String.t()) :: module()
  def fetch!(name) do
    Map.get(@registry, name) ||
      raise ArgumentError,
            "invalid --engine #{inspect(name)}, must be one of: #{Enum.join(valid_names(), ", ")}"
  end
end

defmodule GgenIgniter.Engine.Sparql do
  @moduledoc "Adapts `GgenIgniter.Query.run/2` (the `sparql` hex package) to `GgenIgniter.Engine`."
  @behaviour GgenIgniter.Engine

  @impl true
  def prepare!(graph, _opts), do: graph

  @impl true
  def run(graph, query), do: GgenIgniter.Query.run(graph, query)
end

defmodule GgenIgniter.Engine.Qlever do
  @moduledoc """
  Adapts `GgenIgniter.Query.Qlever` (real, remote QLever HTTP) to
  `GgenIgniter.Engine`.

  `:gno` and `:tesla` are both `optional: true` in `mix.exs` (see the comment
  there). Neither is referenced here at compile time (no struct patterns, no
  aliases into `Gno`/`Tesla`) -- every reference is a plain remote call or a
  bare atom (`Application.ensure_all_started(:tesla)`), so this module always
  compiles regardless of whether a consumer has those deps. `prepare!/2` does
  add real `Code.ensure_loaded?/1` runtime guards, though: without them, a
  consumer missing `:gno`/`:tesla` would still hit `--engine qlever` and get a
  raw `MatchError` (from `Application.ensure_all_started(:tesla)` returning
  `{:error, ...}`) instead of a clear, actionable message -- and would hit that
  confusing error before ever reaching `GgenIgniter.Query.Qlever.load_store!/2`
  (whose own stub, compiled when `:gno` is missing, raises the same message).
  """
  @behaviour GgenIgniter.Engine

  @missing_gno_message "ggen_igniter: :gno is required for --engine qlever " <>
                         "(Gno.Store.Adapters.Qlever) but is not loaded -- add " <>
                         "{:gno, \"~> 0.1\"} to your own mix.exs deps"

  @missing_tesla_message "ggen_igniter: :tesla is required for --engine qlever " <>
                           "(the real HTTP client QLever's SPARQL.Client uses) but is " <>
                           "not loaded -- add {:tesla, \"~> 1.8\"} to your own mix.exs deps"

  @impl true
  def prepare!(graph, opts) do
    store_id =
      opts[:store_id] ||
        raise ArgumentError, "--store-id is required when --engine qlever is given"

    unless Code.ensure_loaded?(Gno.Store.Adapters.Qlever) do
      raise RuntimeError, message: @missing_gno_message
    end

    unless Code.ensure_loaded?(Tesla) do
      raise RuntimeError, message: @missing_tesla_message
    end

    # Igniter tasks don't boot the full OTP application tree (they operate on
    # ASTs, not a running app), so ensure the real HTTP client stack this
    # engine needs is up, idempotently, right before using it.
    {:ok, _} = Application.ensure_all_started(:tesla)

    unless Process.whereis(GgenIgniter.Finch),
      do: {:ok, _} = Finch.start_link(name: GgenIgniter.Finch)

    GgenIgniter.Query.Qlever.load_store!(graph, store_id)
  end

  @impl true
  def run(store, query), do: GgenIgniter.Query.Qlever.run(store, query)
end

defmodule GgenIgniter.Engine.Oxigraph do
  @moduledoc "Adapts `GgenIgniter.Query.Oxigraph` (real, native oxigraph NIF) to `GgenIgniter.Engine`."
  @behaviour GgenIgniter.Engine

  @impl true
  def prepare!(graph, _opts), do: graph

  @impl true
  def run(graph, query), do: GgenIgniter.Query.Oxigraph.run(graph, query)
end
