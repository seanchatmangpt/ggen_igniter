defmodule GgenIgniter.Stream.Examples.SensorSinkTest do
  @moduledoc """
  Chicago-style tests over the real, ontology-generated
  `GgenIgniter.Stream.Examples.SensorSink` (see `priv/ggen/sensor-sink-pack/`)
  — real `sample/2`/`sample_all/2` folds over real raw sensor readings,
  state-based assertions on the real emitted
  `%GgenIgniter.Discovery.Examples.Event{}` structs and the sink's own
  running state. No mocks.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Discovery.Examples.Event
  alias GgenIgniter.Stream.Examples.SensorSink

  test "sample/2 emits nothing for a reading that does not cross the threshold" do
    state = SensorSink.new(threshold: 10.0)
    assert {_new_state, nil} = SensorSink.sample(state, {3.0, 0, "sensor_a"})
  end

  test "sample/2 emits a real rising-edge event on the first crossing above threshold" do
    state = SensorSink.new(threshold: 10.0)
    {state, nil} = SensorSink.sample(state, {3.0, 0, "sensor_a"})

    assert {new_state, %Event{} = event} = SensorSink.sample(state, {15.0, 1, "sensor_a"})

    assert event.activity == "threshold_crossed_above"
    assert event.object_ids == ["sensor_a"]
    assert event.attributes == %{value: 15.0}
    assert new_state.emitted == 1
  end

  test "sample/2 emits a real falling-edge event when the value drops back at-or-below threshold" do
    state = SensorSink.new(threshold: 10.0)
    {state, nil} = SensorSink.sample(state, {15.0, 0, "sensor_a"})
    {state, _rising} = SensorSink.sample(state, {20.0, 1, "sensor_a"})

    assert {_state, %Event{activity: "threshold_crossed_below"}} =
             SensorSink.sample(state, {5.0, 2, "sensor_a"})
  end

  test "sample_all/2 abstracts a real sequence of samples into only the crossing events" do
    readings = [
      {3.0, 0, "sensor_a"},
      {15.0, 1, "sensor_a"},
      {16.0, 2, "sensor_a"},
      {4.0, 3, "sensor_a"},
      {2.0, 4, "sensor_a"}
    ]

    {final_state, events} = SensorSink.sample_all(SensorSink.new(threshold: 10.0), readings)

    assert Enum.map(events, & &1.activity) == [
             "threshold_crossed_above",
             "threshold_crossed_below"
           ]

    assert final_state.emitted == 2
  end

  test "handle_message/2 forwards the emitted event via the real forward callback" do
    state = SensorSink.new(threshold: 10.0)
    {state, nil} = SensorSink.sample(state, {3.0, 0, "sensor_a"})

    test_pid = self()
    context = %{sink_state: state, forward: fn event -> send(test_pid, {:forwarded, event}) end}

    SensorSink.handle_message(%{data: {15.0, 1, "sensor_a"}}, context)

    assert_received {:forwarded, %Event{activity: "threshold_crossed_above"}}
  end
end
