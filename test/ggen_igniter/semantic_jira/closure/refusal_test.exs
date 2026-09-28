defmodule GgenIgniter.SemanticJira.Closure.RefusalTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Refusal
 test "typed refusal admits witness and refuses minimal falsifier" do
  assert :ok = Refusal.validate(%{refusal: "refusal:witness"})
  assert {:refused,_,_} = Refusal.validate(%{refusal: ""})
  assert {:refused,_,_} = Refusal.validate(%{})
 end
end
