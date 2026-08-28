# Telemetry & Event Sinks

Status: **IMPLEMENTED**. Verified against `lib/ggen_igniter/telemetry/ocel_emitter.ex`, `lib/ggen_igniter/reactors/reconcile_reactor.ex`, and test suite `test/ggen_igniter_ocel_emitter_test.exs`.

---

## 1. Overview

`ggen_igniter` integrates Erlang/Elixir `:telemetry` to provide observable execution metrics and structured event logging. The telemetry subsystem serves two concurrent functions:
1. **Broadcast Observable Events**: Emits real `:telemetry.execute/3` events for live consumption by external instrumentation, metric collectors, and logging bridges.
2. **In-Memory Event Accumulation**: Uses an `Agent`-backed event sink to accumulate structured OCEL events during a reconciliation attempt, embedding the complete trace directly into the durable `GgenIgniter.Receipt`.

---

## 2. Implemented Telemetry Events vs. Intended Span Events

### A. Implemented Event: `[:ggen_igniter, :reconcile, :ocel]`

Defined in [`lib/ggen_igniter/telemetry/ocel_emitter.ex`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/telemetry/ocel_emitter.ex#L53-L65):
```elixir
@telemetry_event [:ggen_igniter, :reconcile, :ocel]
```

Every call to `GgenIgniter.Telemetry.OcelEmitter.emit/4` triggers:
```elixir
:telemetry.execute([:ggen_igniter, :reconcile, :ocel], %{count: 1}, event)
```

#### Measurements
- `%{count: 1}` — A constant invocation metric per emitted lifecycle activity.

#### Metadata
The metadata payload is the complete OCEL-shaped event map:
```elixir
%{
  "id" => "ev_...",                     # String: unique event identifier
  "activity" => "ACTUATION_STARTED",     # String: lifecycle activity name
  "time" => "2026-08-27T16:51:29.010Z", # String: ISO 8601 UTC timestamp
  "objects" => [%{"type" => "file", "id" => "lib/app.ex"}], # List: object references
  "attributes" => %{"paths" => ["lib/app.ex"]}               # Map: activity-specific attributes
}
```

---

### B. Lifecycle & Span Event Taxonomy

In standard Erlang/Elixir telemetry conventions, systems often expose paired span events:

| Telemetry Event Name | Intended / Canonical Role | Implemented Status |
|---|---|---|
| `[:ggen_igniter, :sync, :start]` | Start of CLI `mix ggen_igniter.sync` pipeline execution. | **Planned / Architectural**. CLI invokes tasks directly; spans are captured via `:reconcile` activities. |
| `[:ggen_igniter, :sync, :stop]` | Successful completion of CLI sync task. | **Planned / Architectural**. Emitted as `STANDING_SET` with `"standing" => "alive"`. |
| `[:ggen_igniter, :sync, :exception]` | Uncaught failure/exception in CLI task. | **Planned / Architectural**. Captured as `VERIFICATION_FAILED` or `GUARD_REFUSED`. |
| `[:ggen_igniter, :reconcile, :start]` | Initiation of Reactor reconciliation run. | Represented by initial `ACTUATION_STARTED` or step entry. |
| `[:ggen_igniter, :reconcile, :stop]` | Successful conclusion of reconciliation run. | Represented by `ADMITTED` and `STANDING_SET`. |
| `[:ggen_igniter, :reconcile, :exception]` | Reconciliation abort / compensation event. | Represented by `COMPENSATION_STARTED` and `FILES_RESTORED`. |
| `[:ggen_igniter, :reconcile, :ocel]` | **Active Implemented Channel**. Unified event emitter streaming all lifecycle activities. | **IMPLEMENTED** in `GgenIgniter.Telemetry.OcelEmitter`. |

---

## 3. The `Agent`-Backed Event Sink

To capture ordered events across asynchronous tasks, error compensation rollbacks, and multi-step pipelines without polluting the process dictionary or ETS tables, `OcelEmitter` provides an `Agent`-backed sink.

### Lifecycle Functions

Defined in [`lib/ggen_igniter/telemetry/ocel_emitter.ex`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/telemetry/ocel_emitter.ex#L68-L117):

```elixir
# 1. Start a fresh, isolated sink
sink = OcelEmitter.new_sink()

# 2. Emit an event into telemetry AND the sink
event = OcelEmitter.emit(sink, "ACTUATION_STARTED", [OcelEmitter.file_object("lib/a.ex")], %{"paths" => ["lib/a.ex"]})

# 3. Non-destructive inspection mid-attempt (e.g., during compensation)
events = OcelEmitter.peek_sink(sink)

# 4. Drain all events in chronological order (oldest first) and terminate the Agent
final_events = OcelEmitter.drain_sink(sink)
```

### Sink Properties
- **Chronological Ordering**: Internally prepends events (`[event | acc]`) and reverses them on `drain_sink/1` or `peek_sink/1` to ensure oldest-first ordering.
- **Fault-Tolerant Nil Handling**: `drain_sink(nil)` and `peek_sink(nil)` return `[]` without error.
- **Process Cleanup**: `drain_sink/1` stops the Agent process. If the process is already terminated, it returns `[]`.

---

## 4. Query Helpers on Event Lists

`OcelEmitter` provides pure query helpers to inspect already-accumulated event lists ([`ocel_emitter.ex:169-189`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/telemetry/ocel_emitter.ex#L169-L189)):

- **`find_last/2`**:
  ```elixir
  @spec find_last([map()], String.t()) :: map() | nil
  def find_last(events, activity)
  ```
  Returns the last event matching the given `"activity"` string, or `nil`.
- **`any?/2`**:
  ```elixir
  @spec any?([map()], String.t()) :: boolean()
  def any?(events, activity)
  ```
  Returns `true` if any event in the list matches the `"activity"`.

---

## 5. Attaching Telemetry Handlers

External modules can subscribe to reconciliation events live using standard `:telemetry`:

```elixir
:telemetry.attach(
  "my-reconcile-logger",
  [:ggen_igniter, :reconcile, :ocel],
  fn _event_name, _measurements, metadata, _config ->
    IO.puts("Reconcile Activity: #{metadata["activity"]} at #{metadata["time"]}")
  end,
  nil
)
```

---

## 6. Verification & Test Evidence

All telemetry capabilities are verified using real processes and handlers in [`test/ggen_igniter_ocel_emitter_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_ocel_emitter_test.exs):

```bash
$ mix test test/ggen_igniter_ocel_emitter_test.exs
Running ExUnit with seed: ..., max_cases: 32
.......
Finished in 0.1 seconds
7 tests, 0 failures
```

### Verified Assertions
1. **Real Telemetry Execution**: A real handler attached via `:telemetry.attach/4` receives the `STANDING_SET` event with `%{count: 1}` measurement ([`test/ggen_igniter_ocel_emitter_test.exs:53-72`](file:///Users/sac/ggen_igniter/test/ggen_igniter_ocel_emitter_test.exs#L53-L72)).
2. **Sink Accumulation & Peek**: `peek_sink/1` inspects events without stopping the agent, allowing subsequent emissions to accumulate ([`test/ggen_igniter_ocel_emitter_test.exs:14-40`](file:///Users/sac/ggen_igniter/test/ggen_igniter_ocel_emitter_test.exs#L14-L40)).
3. **Sink Drain & Termination**: `drain_sink/1` returns the full ordered trace and terminates the sink process ([`test/ggen_igniter_ocel_emitter_test.exs:34-39`](file:///Users/sac/ggen_igniter/test/ggen_igniter_ocel_emitter_test.exs#L34-L39)).
4. **Query Helper Correctness**: `find_last/2` returns the latest occurrence; `any?/2` validates presence ([`test/ggen_igniter_ocel_emitter_test.exs:80-92`](file:///Users/sac/ggen_igniter/test/ggen_igniter_ocel_emitter_test.exs#L80-L92)).
