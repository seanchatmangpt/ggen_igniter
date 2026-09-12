defmodule GgenIgniter.RecurrenceDetectorTest do
  @moduledoc "Chicago-style state tests over real OCEL-shaped event maps; no mocks, no actuation."

  use ExUnit.Case, async: true

  alias GgenIgniter.RecurrenceDetector

  defp event(run_id, reasoning_class, activity \\ "STANDING_SET") do
    %{
      "id" => "ev_#{run_id}_#{activity}",
      "activity" => activity,
      "objects" => [%{"type" => "reconcile_run", "id" => run_id}],
      "attributes" => %{"reasoning_class" => reasoning_class}
    }
  end

  test "returns a candidate only after recurrence spans distinct runs" do
    events = [
      event("run-1", "repair/generated-drift"),
      event("run-2", "repair/generated-drift", "VERIFICATION_FAILED"),
      event("run-3", "repair/generated-drift")
    ]

    assert [candidate] = RecurrenceDetector.scan(events)
    assert candidate["reasoning_class"] == "repair/generated-drift"
    assert candidate["occurrences"] == 3
    assert candidate["distinct_runs"] == 3
    assert candidate["run_ids"] == ["run-1", "run-2", "run-3"]
    assert candidate["standing"] == "CANDIDATE"
    assert candidate["authority"] == "NONE"
    assert candidate["recommendation"] == "pack_or_template"
  end

  test "does not mistake repeated events inside one run for cross-run recurrence" do
    events = [
      event("run-1", "repair/generated-drift", "ACTUATION_STARTED"),
      event("run-1", "repair/generated-drift", "FILES_CHANGED"),
      event("run-1", "repair/generated-drift", "STANDING_SET")
    ]

    assert [] = RecurrenceDetector.scan(events)
  end

  test "ignores events without explicit reasoning-class or run identity" do
    events = [
      %{"activity" => "STANDING_SET", "objects" => [], "attributes" => %{"reasoning_class" => "x"}},
      %{"activity" => "STANDING_SET", "objects" => [%{"type" => "reconcile_run", "id" => "run-1"}], "attributes" => %{}}
    ]

    assert [] = RecurrenceDetector.scan(events, min_occurrences: 1, min_distinct_runs: 1)
  end

  test "orders candidates deterministically by reasoning class" do
    events = [
      event("run-1", "z-class"),
      event("run-2", "z-class"),
      event("run-1", "a-class"),
      event("run-2", "a-class")
    ]

    candidates = RecurrenceDetector.scan(events, min_occurrences: 2)
    assert Enum.map(candidates, & &1["reasoning_class"]) == ["a-class", "z-class"]
  end

  test "refuses invalid thresholds" do
    assert_raise ArgumentError, fn -> RecurrenceDetector.scan([], min_occurrences: 0) end
  end
end
