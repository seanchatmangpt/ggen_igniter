defmodule GgenIgniter.Telemetry.OcelEmitter do
  @moduledoc """
  CONSTRUCTION NOTE (2026-08-27): at the time this module was written, a
  concurrent workflow was tasked with building `lib/ggen_igniter/receipt.ex`,
  `lib/ggen_igniter/reactors/reconcile_reactor.ex`, and this file
  (`lib/ggen_igniter/telemetry/ocel_emitter.ex`). This repo was polled for
  their existence 6 times (roughly 90 seconds, per the concurrency protocol
  given) and none of the three had appeared -- only a forward-referencing
  comment in `mix.exs` (`{:reactor, "~> 1.0"}`'s dependency note) evidenced
  that the other workflow had *started*. This module is therefore this
  session's own from-scratch, best-effort construction, not a correction to
  pre-existing code. If the concurrent workflow's real version lands later,
  reconcile the two rather than silently preferring either.

  An OCEL (object-centric event log, https://www.ocel-standard.org/)-SHAPED
  event emitter for one reconciliation attempt's real lifecycle:

      ACTUATION_STARTED -> FILES_CHANGED -> VERIFICATION_FAILED ->
      COMPENSATION_STARTED -> FILES_RESTORED -> STANDING_SET

  (or, on the happy path: ACTUATION_STARTED -> FILES_CHANGED ->
  VERIFICATION_SUCCEEDED -> ADMITTED -> STANDING_SET.)

  This is the exact stage sequence the user specified for
  `GgenIgniter.Receipt`'s `standing: :compensated` case -- this module is
  what actually PRODUCES that sequence as real, structured data (not prose):
  each call to `emit/4` returns one OCEL-shaped event map, real enough to
  serialize into a receipt's `events` list verbatim.

  ## Two real, independent effects per `emit/4` call

  1. A real `:telemetry.execute/3` call under `[:ggen_igniter, :reconcile,
     :ocel]` -- so any process that wants to observe reconciliation activity
     (logging, metrics, a future dashboard) can attach a real `:telemetry`
     handler and receive these events live, without this module knowing or
     caring whether anyone is listening.
  2. If a `sink` (a real, running `Agent` pid from `new_sink/0`) is given,
     the event is ALSO appended to that agent's real in-memory list -- this
     is how `GgenIgniter.Reactors.ReconcileReactor` accumulates one
     attempt's full event log across multiple Reactor steps (`:actuate`'s
     `run/3` AND its `undo/3`, `:verify`, `:admit`, ...) into a single
     ordered list it can embed in a `GgenIgniter.Receipt`, including on a
     FAILURE path where the reactor's own return value carries no such
     accumulated state.

  Using a real, separately-started `Agent` process (rather than, say, the
  process dictionary or an ETS table) keeps this fully Chicago-style
  testable: a test starts a real sink, runs real code that emits into it,
  and asserts on the real list `drain_sink/1` returns -- no interaction-based
  mock of "was emit called" is needed anywhere.
  """

  @telemetry_event [:ggen_igniter, :reconcile, :ocel]

  @typedoc "An OCEL \"object\" reference -- `{type, id}` as a JSON-friendly map."
  @type object :: %{required(String.t()) => String.t()}

  @typedoc "One OCEL-shaped event."
  @type event :: %{
          required(String.t()) => String.t() | [object()] | map()
        }

  @doc "The `:telemetry` event name every `emit/4` call executes under."
  @spec telemetry_event() :: [atom(), ...]
  def telemetry_event, do: @telemetry_event

  @doc """
  Starts a fresh, real event sink (a plain `Agent` holding an ordered list,
  most-recent-first internally). Returns its pid. Callers own the pid's
  lifecycle -- pass `nil` anywhere a sink is accepted to opt out of
  accumulation entirely (telemetry still fires either way).
  """
  @spec new_sink() :: pid()
  def new_sink do
    {:ok, pid} = Agent.start_link(fn -> [] end)
    pid
  end

  @doc """
  Drains `sink` -- returns every event appended so far, in the real order
  they were emitted (oldest first) -- and stops the agent. Safe to call at
  most once per sink (the agent is gone afterward); calling with `nil`
  returns `[]` with no error, so callers that never had a sink can call this
  unconditionally.
  """
  @spec drain_sink(pid() | nil) :: [event()]
  def drain_sink(nil), do: []

  def drain_sink(sink) when is_pid(sink) do
    if Process.alive?(sink) do
      events = sink |> Agent.get(& &1) |> Enum.reverse()
      Agent.stop(sink)
      events
    else
      []
    end
  end

  @doc """
  Peeks at `sink`'s current events (oldest first) WITHOUT stopping it --
  unlike `drain_sink/1`, the sink stays alive and can receive more events
  afterward. Used by callers (e.g. `GgenIgniter.Reactors.ReconcileReactor`'s
  own `:actuate` step `undo/3` callback) that need to read back an
  already-emitted attribute (like a recorded pre-run hash) mid-attempt.
  `nil` returns `[]`.
  """
  @spec peek_sink(pid() | nil) :: [event()]
  def peek_sink(nil), do: []

  def peek_sink(sink) when is_pid(sink) do
    if Process.alive?(sink) do
      sink |> Agent.get(& &1) |> Enum.reverse()
    else
      []
    end
  end

  @doc """
  Builds one OCEL-shaped event, executes it as a real `:telemetry` event,
  appends it to `sink` (if not `nil`), and returns the built event map --
  callers that need the event's own generated `"id"` (e.g. to cross-reference
  it from a receipt) get it directly from the return value, not by
  re-reading the sink.

    * `activity` -- the event's OCEL "activity" name, e.g.
      `"ACTUATION_STARTED"`. A plain string (not an atom) so it round-trips
      through `Jason.encode!/1` and a receipt's persisted JSONL unchanged.
    * `objects` -- the OCEL objects this event is about (build with
      `file_object/1` / `run_object/1`).
    * `attributes` -- a plain, JSON-encodable map of this event's own
      payload (e.g. `%{"paths" => [...], "pre_run_hash" => "sha256:..."}`).
  """
  @spec emit(pid() | nil, String.t(), [object()], map()) :: event()
  def emit(sink, activity, objects, attributes \\ %{})
      when is_binary(activity) and is_list(objects) and is_map(attributes) do
    event = build_event(activity, objects, attributes)

    :telemetry.execute(@telemetry_event, %{count: 1}, event)

    if is_pid(sink) and Process.alive?(sink) do
      Agent.update(sink, fn events -> [event | events] end)
    end

    event
  end

  defp build_event(activity, objects, attributes) do
    %{
      "id" => generate_id(),
      "activity" => activity,
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "objects" => objects,
      "attributes" => attributes
    }
  end

  defp generate_id do
    "ev_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  @doc "Builds a `\"file\"`-typed OCEL object reference for `path`."
  @spec file_object(String.t()) :: object()
  def file_object(path) when is_binary(path), do: %{"type" => "file", "id" => path}

  @doc "Builds a `\"reconcile_run\"`-typed OCEL object reference for `run_id`."
  @spec run_object(String.t()) :: object()
  def run_object(run_id) when is_binary(run_id), do: %{"type" => "reconcile_run", "id" => run_id}

  @doc """
  Finds the last event in `events` (oldest-first, as returned by
  `drain_sink/1`/`peek_sink/1`) whose `"activity"` is `activity`, or `nil`.
  A small real query helper -- both `GgenIgniter.Reactors.ReconcileReactor`
  and its tests use this to pull a specific attribute (e.g. a recorded
  `"pre_run_hash"`) back out of the real, already-emitted event log instead
  of threading it through a second, parallel channel.
  """
  @spec find_last(list(), String.t()) :: map() | nil
  def find_last(events, activity) when is_list(events) and is_binary(activity) do
    events
    |> Enum.filter(&(&1["activity"] == activity))
    |> List.last()
  end

  @doc "Whether any event in `events` has `\"activity\"` equal to `activity`."
  @spec any?(list(), String.t()) :: boolean()
  def any?(events, activity) when is_list(events) and is_binary(activity) do
    Enum.any?(events, &(&1["activity"] == activity))
  end
end
