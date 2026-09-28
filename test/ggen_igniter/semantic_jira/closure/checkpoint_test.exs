defmodule GgenIgniter.SemanticJira.Closure.CheckpointTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Checkpoint
 test "checkpoint identity admits witness and refuses minimal falsifier" do
  assert :ok = Checkpoint.validate(%{checkpoint: "0123456789abcdef0123456789abcdef01234567"})
  assert {:refused,_,_} = Checkpoint.validate(%{checkpoint: "abc"})
  assert {:refused,_,_} = Checkpoint.validate(%{})
 end
end
