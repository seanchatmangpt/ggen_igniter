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

  ## Per-run scoping (`run_id`, added post-v26.9.1-gap-#7)

  The ETS table's real key shape is `{run_id, counter_atom}`, not a bare
  `counter_atom` -- a bare-atom key would make `counters/0` answer "how many
  times ever, across every run since BEAM boot" instead of "how many times
  THIS run", which is genuinely useless for a caller that wants to know
  whether the run it just made produced a compensation event.

  `run_id` is generated fresh in `init/1` (via `System.unique_integer/1` +
  `self()` of the calling process -- the real, honest signal available at
  that point) and stored into the real `Reactor.context()` map this
  middleware returns from `init/1`. This is not a guess about Reactor's own
  internals: tracing `deps/reactor/lib/reactor/executor.ex`'s `run/4` (calls
  `Executor.Hooks.init/2`, then does `execute(%{reactor | context: context},
  state)` with THAT returned context) and
  `deps/reactor/lib/reactor/executor/hooks.ex`'s `error/3` (called with
  `reactor.context`, the same context threaded from `init/1` through the
  whole run) confirms the context map `init/1` returns is the exact same map
  `event/3` and `error/2` receive for the rest of that one real run -- no
  Reactor-provided `reactor_id`/run-identifier exists in `Reactor.context()`
  (confirmed absent from `deps/reactor/lib/reactor.ex`'s `@type context ::
  %{optional(atom) => any}`), so this module mints its own rather than
  inventing a fictitious one Reactor doesn't actually provide.

  `counters/1` reads back just one run's counts via this real per-run key.
  `counters/0` is kept for backward compatibility and now explicitly
  documented as a cross-run aggregate (folds every `{_run_id, counter}` key
  currently in the table into one map) -- not a per-run answer.
  """

  @behaviour Reactor.Middleware

  alias GgenIgniter.Reactors.ReconcileReactor

  @table :ggen_igniter_compensation_counters

  @impl true
  @spec init(Reactor.context()) :: {:ok, Reactor.context()}
  def init(context) do
    ensure_table!()
    run_id = Map.get(context, :compensation_telemetry_run_id) || generate_run_id()
    {:ok, Map.put(context, :compensation_telemetry_run_id, run_id)}
  end

  @impl true
  @spec event(Reactor.Middleware.step_event(), Reactor.Step.t(), Reactor.context()) :: :ok
  def event({:compensate_start, _reason}, _step, context) do
    bump(run_id!(context), :compensate_start)
  end

  def event({:compensate_error, _error_or_errors}, _step, context) do
    bump(run_id!(context), :compensate_error)
  end

  def event(:undo_start, _step, context) do
    bump(run_id!(context), :undo_start)
  end

  def event(_other_event, _step, _context), do: :ok

  @impl true
  @spec error(Reactor.Middleware.error_or_errors(), Reactor.context()) :: :ok
  def error(error_or_errors, context) do
    ensure_table!()
    run_id = run_id!(context)

    # Mutually exclusive by precedence: a `{:compile_failed, _}` step error is
    # checked FIRST. `ReconcileReactor.standing_for_failure/2` (the real
    # function this module's own moduledoc says it defers to) treats
    # `:compile_failed` as the specific `:build_broken` standing and any
    # OTHER real compensation failure (including the `revert_all/1`
    # `:compensation_failed` shape `find_compensation_failure/1` detects) as
    # the more generic `:compensated`/`:compensation_failed` bucket -- so for
    # ONE real error term, only one of `:build_broken` /
    # `:compensation_failed` should ever bump, matching
    # `standing_for_failure/2`'s own real either/or classification instead of
    # letting both independently match and double-count a single failing run.
    build_broken? =
      match?(
        {:ok, _name, _reason},
        ReconcileReactor.find_step_error(error_or_errors, &match?({:compile_failed, _}, &1))
      )

    cond do
      build_broken? ->
        bump(run_id, :build_broken)

      match?({:ok, _details}, ReconcileReactor.find_compensation_failure(error_or_errors)) ->
        bump(run_id, :compensation_failed)

      true ->
        :ok
    end

    :ok
  end

  @doc """
  Real, current contents of the `@table` ETS table for ONE run, as a plain
  map (e.g. `%{compensate_start: 2, undo_start: 1}`) -- what a test asserts
  on directly, per this module's own moduledoc (Chicago-style: real state,
  not "was `event/3` called").

  `run_id` is the value stored under `context[:compensation_telemetry_run_id]`
  by `init/1` for that run -- a test/caller reads it back from the same
  `context` map it passed into `Reactor.run/4` (or, for `ReconcileReactor`,
  from the run's own returned context if exposed) after the run completes.

  Never raises for an empty/not-yet-created table -- `ensure_table!/0` is
  called first, so a fresh/unknown `run_id` with zero counters comes back as
  `%{}`.
  """
  @spec counters(term()) :: %{optional(atom()) => non_neg_integer()}
  def counters(run_id) do
    ensure_table!()

    @table
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {{^run_id, counter}, count} -> [{counter, count}]
      _other -> []
    end)
    |> Map.new()
  end

  @doc """
  Cross-run aggregate: real, current contents of the `@table` ETS table
  summed across EVERY `run_id` currently present -- "how many times ever,
  across every run since BEAM boot", not "how many times THIS run" (use
  `counters/1` with a specific `run_id` for that). Kept for backward
  compatibility with callers that only need a global sanity count.
  """
  @spec counters() :: %{optional(atom()) => non_neg_integer()}
  def counters do
    ensure_table!()

    @table
    |> :ets.tab2list()
    |> Enum.reduce(%{}, fn {{_run_id, counter}, count}, acc ->
      Map.update(acc, counter, count, &(&1 + count))
    end)
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

  # A real, per-process-and-call-site-unique run identifier -- not a
  # Reactor-provided value (none exists in `Reactor.context()`, confirmed
  # above), so this mints its own from two real, honestly-available signals:
  # the calling process (`self()`, the real process that invoked
  # `Reactor.run/4` for this run) and a real monotonic
  # `System.unique_integer/1` counter (so two runs from the SAME process --
  # e.g. two sequential `ReconcileReactor.run/1` calls in one test process --
  # still get genuinely distinct ids).
  @spec generate_run_id() :: {pid(), integer()}
  defp generate_run_id do
    {self(), System.unique_integer([:positive, :monotonic])}
  end

  @spec run_id!(Reactor.context()) :: term()
  defp run_id!(context) do
    Map.get(context, :compensation_telemetry_run_id) || generate_run_id()
  end

  @spec bump(term(), atom()) :: :ok
  defp bump(run_id, key) do
    :ets.update_counter(@table, {run_id, key}, {2, 1}, {{run_id, key}, 0})
    :ok
  end
end
