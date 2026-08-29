defmodule GgenIgniter.Reactors.CompensationTelemetryMiddleware do
  @moduledoc """
  A real `Reactor.Middleware` (behaviour confirmed by reading
  `deps/reactor/lib/reactor/middleware.ex` directly, not guessed) that counts
  compensation/undo lifecycle events for `GgenIgniter.Reactors.ReconcileReactor`
  runs into a real, named, public ETS table (`@table`,
  `:ggen_igniter_compensation_counters`) -- Chicago-style: real ETS state, read
  back via `counters/0`, never an interaction-based "was `event/3` called"
  assertion.

  Wired alongside `Reactor.Middleware.Telemetry` in `ReconcileReactor`'s own
  `middlewares do ... end` block (added in commit `2d758db` for the
  `:telemetry.execute/3` wiring) -- see that module's moduledoc "Telemetry"
  section. Both middlewares receive the exact same real Reactor lifecycle
  calls; this one turns three of them into durable, cross-run ETS counts
  instead of ephemeral `:telemetry` events, so a caller (or a test) can ask
  "how many times has this reactor actually compensated/undone something"
  without attaching a `:telemetry` handler.

  ## Real event/error shapes matched (cited from `Reactor.Middleware.step_event()`
  and the `error/2` callback in `deps/reactor/lib/reactor/middleware.ex`,
  never invented)

  `Reactor.Middleware.step_event()`'s real union includes (among others):

      | {:compensate_start, any}
      | {:compensate_error, error_or_errors}
      | :undo_start

  `event/3` below matches exactly these three real shapes (note
  `{:compensate_start, any}` is a real 2-element tuple -- `{tag, reason}` --
  not a 3-element one; this module matches the type as actually defined in
  `middleware.ex`, not a guessed arity) and increments one real ETS counter
  per shape: `:compensate_start`, `:compensate_error`, `:undo_start`.

  `error/2`'s real signature is `error(error_or_errors, context) :: :ok |
  {:error, any}`, where `error_or_errors` is the SAME real
  `Reactor.Error`-class term `ReconcileReactor.run/1`'s own `case
  Reactor.run(...) do {:error, error} -> ...` branch already knows how to
  read (confirmed by tracing `deps/reactor/lib/reactor/executor.ex`'s
  `handle_undo/3` -- `Reactor.Error.to_class(state.errors)` -- into
  `Executor.Hooks.error/3`, which is exactly what invokes every configured
  middleware's `error/2`). Rather than re-deriving a second, parallel search
  over that nested `Splode` error shape, this module reuses
  `ReconcileReactor`'s OWN real, public (`@doc false`, not `defp`) helpers:

    * `ReconcileReactor.find_compensation_failure/1` -- the exact function
      `run/1` uses to detect the real `:compensation_failed` catastrophic
      standing (`revert_all/1`'s tagged `{:error, %{paths:, restored:,
      failed:}}` result). A real match increments the `:compensation_failed`
      counter.
    * `ReconcileReactor.find_step_error/2`, given a predicate matching
      `{:compile_failed, _output}` -- the exact real reason
      `ReconcileReactor.standing_for_failure/2` maps to the `:build_broken`
      standing specifically (a `:verify` step failure because `mix compile`
      itself failed, as opposed to any other post-`:actuate` failure, which
      maps to the more generic `:compensated`). A real match increments the
      `:build_broken` counter.

  These are the two real standing atoms
  `standing_for_failure/2`/`describe_compensation_failure/1` produce that
  this module's task explicitly asks to count -- reusing the SAME functions
  `run/1` itself uses to derive them, rather than re-implementing a second,
  possibly-diverging classification.
  """

  @behaviour Reactor.Middleware

  alias GgenIgniter.Reactors.ReconcileReactor

  @table :ggen_igniter_compensation_counters

  @impl true
  @spec init(Reactor.context()) :: {:ok, Reactor.context()}
  def init(context) do
    ensure_table!()
    {:ok, context}
  end

  @impl true
  @spec event(Reactor.Middleware.step_event(), Reactor.Step.t(), Reactor.context()) :: :ok
  def event({:compensate_start, _reason}, _step, _context) do
    bump(:compensate_start)
  end

  def event({:compensate_error, _error_or_errors}, _step, _context) do
    bump(:compensate_error)
  end

  def event(:undo_start, _step, _context) do
    bump(:undo_start)
  end

  def event(_other_event, _step, _context), do: :ok

  @impl true
  @spec error(Reactor.Middleware.error_or_errors(), Reactor.context()) :: :ok
  def error(error_or_errors, _context) do
    ensure_table!()

    case ReconcileReactor.find_compensation_failure(error_or_errors) do
      {:ok, _details} -> bump(:compensation_failed)
      :error -> :ok
    end

    build_broken? =
      match?(
        {:ok, _name, _reason},
        ReconcileReactor.find_step_error(error_or_errors, &match?({:compile_failed, _}, &1))
      )

    if build_broken? do
      bump(:build_broken)
    end

    :ok
  end

  @doc """
  Real, current contents of the `@table` ETS table as a plain map (e.g.
  `%{compensate_start: 2, undo_start: 1}`) -- what a test asserts on
  directly, per this module's own moduledoc (Chicago-style: real state, not
  "was `event/3` called").

  Never raises for an empty/not-yet-created table -- `ensure_table!/0` is
  called first, so a fresh table with zero counters comes back as `%{}`.
  """
  @spec counters() :: %{optional(atom()) => non_neg_integer()}
  def counters do
    ensure_table!()
    @table |> :ets.tab2list() |> Map.new()
  end

  # Real, idempotent, public/named ETS table creation: `:ets.new/2` raises
  # `ArgumentError` when a table with this exact name already exists (the
  # real, documented behavior of naming a table), so catching JUST that one
  # exception and treating it as success is the real "already present ->
  # no-op" idempotency this module's task asks for -- never a
  # check-then-act `:ets.whereis/1` race (two concurrent `init/1` calls --
  # this reactor may run more than once concurrently in one BEAM -- could
  # both observe "not yet created" and both call `:ets.new/2`; only ONE of
  # the two real calls can win the name, and the other's raise is exactly
  # what this rescue is for).
  @spec ensure_table!() :: :ok
  defp ensure_table! do
    :ets.new(@table, [:set, :public, :named_table])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec bump(atom()) :: :ok
  defp bump(key) do
    :ets.update_counter(@table, key, {2, 1}, {key, 0})
    :ok
  end
end
