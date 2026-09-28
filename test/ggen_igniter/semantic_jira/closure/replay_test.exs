defmodule GgenIgniter.SemanticJira.Closure.ReplayTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Replay
 test "replay determinism admits witness and refuses minimal falsifier" do
  assert :ok = Replay.validate(%{replay_key: "replay:witness"})
  assert {:refused,_,_} = Replay.validate(%{replay_key: ""})
  assert {:refused,_,_} = Replay.validate(%{})
 end
end
