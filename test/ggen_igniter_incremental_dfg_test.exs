defmodule GgenIgniter.Discovery.Examples.IncrementalDfgTest do
  @moduledoc """
  Chicago-style tests over the real, ontology-generated
  `GgenIgniter.Discovery.Examples.IncrementalDfg` (see
  `priv/ggen/incremental-discovery-pack/`) — real `update/2` folds over real
  `%GgenIgniter.Discovery.Examples.Event{}` structs, state-based assertions
  on the real returned DFG/activity/start/end counters, plus a structural
  cross-check that `from_events/1`'s batch oracle agrees with a manual
  `update/2` fold. No mocks.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Discovery.Examples.Event
  alias GgenIgniter.Discovery.Examples.IncrementalDfg

  defp event(activity, case_id) do
    %Event{activity: activity, object_ids: [case_id], timestamp: 0}
  end

  test "update/2 folds one event at a time into a real DFG edge count" do
    state =
      IncrementalDfg.new()
      |> IncrementalDfg.update(event("register", "case_1"))
      |> IncrementalDfg.update(event("approve", "case_1"))
      |> IncrementalDfg.update(event("close", "case_1"))

    assert IncrementalDfg.dfg(state) == %{
             {"register", "approve"} => 1,
             {"approve", "close"} => 1
           }

    assert state.event_count == 3
    assert state.activities == %{"register" => 1, "approve" => 1, "close" => 1}
    assert state.starts == %{"register" => 1}
  end

  test "finalize/1 records the real trailing activity per case as an end" do
    state =
      IncrementalDfg.new()
      |> IncrementalDfg.update(event("register", "case_1"))
      |> IncrementalDfg.update(event("close", "case_1"))
      |> IncrementalDfg.update(event("register", "case_2"))
      |> IncrementalDfg.finalize()

    assert state.ends == %{"close" => 1, "register" => 1}
  end

  test "multi-case interleaving keeps each case's directly-follows edges separate" do
    events = [
      event("a", "case_1"),
      event("a", "case_2"),
      event("b", "case_1"),
      event("b", "case_2")
    ]

    state = IncrementalDfg.from_events(events)

    assert IncrementalDfg.dfg(state) == %{{"a", "b"} => 2}
  end

  test "from_events/1's batch oracle is structurally equivalent to a manual update/2 fold" do
    events = [
      event("a", "case_1"),
      event("b", "case_1"),
      event("c", "case_1"),
      event("a", "case_2"),
      event("c", "case_2")
    ]

    via_from_events = IncrementalDfg.from_events(events)

    via_manual_fold =
      Enum.reduce(events, IncrementalDfg.new(), &IncrementalDfg.update(&2, &1))
      |> IncrementalDfg.finalize()

    assert via_from_events == via_manual_fold
  end

  test "default case-id fallback for an event with no object_ids is the global case" do
    state =
      IncrementalDfg.new()
      |> IncrementalDfg.update(%Event{activity: "ping", object_ids: []})
      |> IncrementalDfg.update(%Event{activity: "pong", object_ids: []})

    assert IncrementalDfg.dfg(state) == %{{"ping", "pong"} => 1}
  end
end
