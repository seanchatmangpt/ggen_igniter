defmodule GgenIgniter.Telemetry.OcelEmitterTest do
  @moduledoc """
  Chicago-style, no-mocks proof of `GgenIgniter.Telemetry.OcelEmitter`: a
  real running `Agent` sink, and a real `:telemetry.attach/4` handler
  actually receiving the emitted event -- no mock of `:telemetry` or of the
  sink anywhere in this file.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Telemetry.OcelEmitter

  describe "new_sink/0, emit/4, drain_sink/1, peek_sink/1" do
    test "emit/4 returns a real OCEL-shaped event and accumulates it in a real sink" do
      sink = OcelEmitter.new_sink()

      event =
        OcelEmitter.emit(sink, "ACTUATION_STARTED", [OcelEmitter.file_object("lib/a.ex")], %{
          "paths" => ["lib/a.ex"]
        })

      assert event["activity"] == "ACTUATION_STARTED"
      assert event["objects"] == [%{"type" => "file", "id" => "lib/a.ex"}]
      assert event["attributes"] == %{"paths" => ["lib/a.ex"]}
      assert is_binary(event["id"])
      assert is_binary(event["time"])

      assert OcelEmitter.peek_sink(sink) == [event]

      # peek_sink/1 does not stop the agent -- a second emit still accumulates.
      event2 = OcelEmitter.emit(sink, "FILES_CHANGED", [], %{})
      assert OcelEmitter.peek_sink(sink) == [event, event2]

      drained = OcelEmitter.drain_sink(sink)
      assert drained == [event, event2]

      # The agent is really stopped now.
      refute Process.alive?(sink)
    end

    test "drain_sink/1 and peek_sink/1 on nil return an empty list, no error" do
      assert OcelEmitter.drain_sink(nil) == []
      assert OcelEmitter.peek_sink(nil) == []
    end

    test "emit/4 with a nil sink still builds and returns a real event (no accumulation, no crash)" do
      event = OcelEmitter.emit(nil, "VERIFICATION_SUCCEEDED", [], %{})
      assert event["activity"] == "VERIFICATION_SUCCEEDED"
    end
  end

  describe "real :telemetry emission" do
    test "emit/4 really executes a :telemetry event a real attached handler receives" do
      test_pid = self()
      handler_id = "ocel-emitter-test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        OcelEmitter.telemetry_event(),
        fn _event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_received, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      OcelEmitter.emit(nil, "STANDING_SET", [], %{"standing" => "alive"})

      assert_receive {:telemetry_received, %{count: 1}, %{"activity" => "STANDING_SET"}}, 1000
    end
  end

  describe "file_object/1, run_object/1, find_last/2, any?/2" do
    test "file_object/1 and run_object/1 build the expected OCEL object shape" do
      assert OcelEmitter.file_object("lib/a.ex") == %{"type" => "file", "id" => "lib/a.ex"}
      assert OcelEmitter.run_object("run_123") == %{"type" => "reconcile_run", "id" => "run_123"}
    end

    test "find_last/2 returns the LAST matching event, any?/2 checks presence" do
      events = [
        %{"activity" => "A", "attributes" => %{"n" => 1}},
        %{"activity" => "B", "attributes" => %{"n" => 2}},
        %{"activity" => "A", "attributes" => %{"n" => 3}}
      ]

      assert OcelEmitter.find_last(events, "A")["attributes"]["n"] == 3
      assert OcelEmitter.find_last(events, "C") == nil
      assert OcelEmitter.any?(events, "B")
      refute OcelEmitter.any?(events, "C")
    end
  end
end
