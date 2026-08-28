defmodule GgenIgniter.Controller do
  @moduledoc """
  A persistent, BEAM-native reconciliation controller: a real `GenServer`
  that holds live reconciliation state IN THIS PROCESS across multiple
  `reconcile/2` calls -- in contrast to `mix ggen_igniter.sync`'s
  per-invocation model, where every run is a fresh OS process with zero
  in-memory continuity to the previous run (any "what did the last run do"
  question can only be answered by re-reading disk, because there is no
  process to ask).

  Wraps `GgenIgniter.Reconcile.run/1` (the one real reconciliation pipeline
  implementation, shared with `Mix.Tasks.GgenIgniter.Sync`) -- this module
  adds no new reconciliation LOGIC of its own, only in-process state plus a
  small public API around that one shared pipeline call.

  ## State shape

      %{
        last_reconciliations: %{
          pack_key => %{
            ontology_path: String.t(),
            manifest: %{out_path :: String.t() => outcome :: atom()},
            reconciliation_count: pos_integer(),
            last_run_at: DateTime.t(),
            receipt: map()
          }
        }
      }

  `reconciliation_count` is real, process-only knowledge: it is NOT
  recoverable by reading the output file alone (the file's content is
  byte-identical after reconciliation #1 and #2 once nothing has changed --
  that is the whole point of `Actuate.write_file!/3`'s idempotency guard),
  yet this controller can still answer "how many times has this key actually
  been reconciled, in this process" without touching disk. That is the
  concrete, testable economic claim this architecture makes over the CLI's
  model (see `test/ggen_igniter_controller_test.exs`).

  ## Fault isolation

  A real failure inside `GgenIgniter.Reconcile.run/1` (bad ontology path,
  missing template, engine error, ...) is caught in `handle_call/3` and
  turned into a clean `{:error, reason}` reply -- it does NOT crash this
  GenServer, and it does NOT touch any other `pack_key`'s already-stored good
  record. This is a real, tested guarantee, not an assumption.

  ## Scope

  This is a bounded, real proof-of-concept slice: no Reactor integration, no
  distributed/multi-node topology, no crash-SUPERVISION-policy design (this
  module is about fault ISOLATION between keys within one already-alive
  GenServer -- a different concern from a Supervisor's restart strategy for
  the GenServer itself, which this pass does not attempt to design).
  Legitimate future directions, out of scope here.

  ## Wiring

  Started as an OPT-IN child of `GgenIgniter.Application`'s supervision
  tree, gated behind `Application.get_env(:ggen_igniter, :start_controller,
  false)` (default `false`) -- a consuming application that wants it sets
  `config :ggen_igniter, start_controller: true` explicitly. In a test (or
  any other caller that wants its own instance), call `start_link/1`
  directly instead of relying on the application's supervision tree.
  """

  use GenServer

  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Reconcile

  @type pack_key :: term()
  @type record :: %{
          ontology_path: String.t(),
          manifest: %{optional(String.t()) => atom()},
          reconciliation_count: pos_integer(),
          last_run_at: DateTime.t(),
          receipt: map()
        }

  # -- Public API ---------------------------------------------------------

  @doc """
  Starts the controller `GenServer`. `opts` are plain
  `GenServer.start_link/3` options (`:name`, etc.) -- pass `name:
  GgenIgniter.Controller` to start the singleton the application's
  supervision tree expects; omit `:name` (as tests do) to start an
  independent, unnamed instance addressed by its returned pid.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Runs the real reconciliation pipeline (`GgenIgniter.Reconcile.run/1`) for
  `pack_key`, using `reconcile_opts` (the same option shape
  `Mix.Tasks.GgenIgniter.Sync` accepts, within `GgenIgniter.Reconcile.run/1`'s
  own bounded scope -- see that module's moduledoc: `:ontology`/`:query`/
  `:template`/`:pack`/`:pack_dir`/`:engine`/`:mode`/`:out`/`:unless_exists`/
  `:skip_if`/`:dry_run`).

  On success, updates this server's in-process state for `pack_key` and
  returns `{:ok, record()}`. On a real pipeline failure, returns
  `{:error, reason}` -- this server's state for `pack_key` (and every other
  key) is left completely unchanged, and the server itself does not crash.
  """
  @spec reconcile(GenServer.server(), pack_key(), keyword()) ::
          {:ok, record()} | {:error, term()}
  def reconcile(server, pack_key, reconcile_opts) do
    GenServer.call(server, {:reconcile, pack_key, reconcile_opts}, :infinity)
  end

  @doc """
  Returns the real, current in-memory record for `pack_key` -- `{:ok,
  record()}` -- or `:never_reconciled` if this server has never
  successfully reconciled that key. A pure in-process state read: this call
  never touches disk.
  """
  @spec status(GenServer.server(), pack_key()) :: {:ok, record()} | :never_reconciled
  def status(server, pack_key) do
    GenServer.call(server, {:status, pack_key})
  end

  # -- GenServer callbacks --------------------------------------------------

  @impl true
  def init(:ok) do
    {:ok, %{last_reconciliations: %{}}}
  end

  @impl true
  def handle_call({:reconcile, pack_key, reconcile_opts}, _from, state) do
    case run_pipeline(reconcile_opts) do
      {:ok, result} ->
        previous = Map.get(state.last_reconciliations, pack_key)
        record = build_record(reconcile_opts, result, previous)
        new_state = put_in(state, [:last_reconciliations, pack_key], record)
        {:reply, {:ok, record}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:status, pack_key}, _from, state) do
    reply =
      case Map.fetch(state.last_reconciliations, pack_key) do
        {:ok, record} -> {:ok, record}
        :error -> :never_reconciled
      end

    {:reply, reply, state}
  end

  # Runs the real pipeline, converting any real raised exception (or thrown/
  # exited value) into a clean `{:error, reason}` tuple -- the ONLY place
  # this module catches an exception. Everything else in this GenServer
  # (state bookkeeping in `handle_call/3` above) is left to crash loudly, on
  # purpose, if it is ever actually buggy -- only the real external pipeline
  # call gets this fault boundary.
  #
  # Opt-in Reactor dispatch: `Application.get_env(:ggen_igniter, :use_reactor,
  # false)` (default `false`) gates whether this call runs the real Reactor
  # coordination pipeline (`GgenIgniter.Reactors.ReconcileReactor`) instead of
  # calling `GgenIgniter.Reconcile.run/1` directly. When the flag is left at
  # its default, this function's behavior is BYTE-FOR-BYTE UNCHANGED from
  # before this pipeline existed -- the branch below is skipped entirely.
  defp run_pipeline(reconcile_opts) do
    if Application.get_env(:ggen_igniter, :use_reactor, false) do
      run_via_reactor(reconcile_opts)
    else
      Reconcile.run(reconcile_opts)
    end
  rescue
    exception -> {:error, {exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # Runs `GgenIgniter.Reactors.ReconcileReactor.run/1` (its own recommended
  # entry point -- guarantees a real, persisted `GgenIgniter.Receipt` on
  # every path, not just success) and reshapes that receipt into the exact
  # `{:ok, result()}` shape `Reconcile.run/1` returns (see this module's
  # `build_record/3`, unchanged either way) using the receipt's own
  # best-effort single-target compatibility fields in `receipt.metadata` --
  # real for any run with exactly one target (the only shape `reconcile_opts`
  # arrives in via this module's own public API, which has no `:targets`
  # concept of its own).
  defp run_via_reactor(reconcile_opts) do
    case ReconcileReactor.run(reconcile_opts) do
      {:ok, receipt} ->
        {:ok, receipt_to_legacy_result(reconcile_opts, receipt)}

      {:error, receipt} ->
        {:error, receipt.reason || receipt.standing}
    end
  end

  defp receipt_to_legacy_result(reconcile_opts, receipt) do
    %{
      engine: reconcile_opts[:engine] || "oxigraph",
      ontology_path: nil,
      template_path: reconcile_opts[:template],
      query_count: length(Keyword.get_values(reconcile_opts, :query)),
      total_rows: 0,
      mode: metadata_atom(receipt.metadata["mode"]) || :file,
      out_path: receipt.metadata["out_path"],
      outcome: metadata_atom(receipt.metadata["outcome"]),
      value: nil,
      notice: receipt.metadata["notice"] || "ggen_igniter reactor: reconciled"
    }
  end

  defp metadata_atom(nil), do: nil
  defp metadata_atom(str) when is_binary(str), do: String.to_existing_atom(str)

  defp build_record(reconcile_opts, result, previous) do
    previous_count =
      case previous do
        %{reconciliation_count: n} -> n
        _ -> 0
      end

    manifest =
      case result.out_path do
        nil -> %{}
        out_path -> %{out_path => result.outcome}
      end

    %{
      ontology_path: result.ontology_path,
      manifest: manifest,
      reconciliation_count: previous_count + 1,
      last_run_at: DateTime.utc_now(),
      receipt: %{
        engine: result.engine,
        template_path: result.template_path,
        query_count: result.query_count,
        total_rows: result.total_rows,
        mode: result.mode,
        out_path: result.out_path,
        outcome: result.outcome,
        notice: result.notice,
        opts: reconcile_opts
      }
    }
  end
end
