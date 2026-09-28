defmodule GgenIgniter.SemanticJira.Closure.FalsifierTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Falsifier
 test "falsifier boundary admits witness and refuses minimal falsifier" do
  assert :ok = Falsifier.validate(%{falsifier: "falsifier:witness"})
  assert {:refused,_,_} = Falsifier.validate(%{falsifier: ""})
  assert {:refused,_,_} = Falsifier.validate(%{})
 end
end
