defmodule GgenIgniter.SemanticJira.Closure.StandingTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Standing
 test "standing separation admits witness and refuses minimal falsifier" do
  assert :ok = Standing.validate(%{standing: "standing:witness"})
  assert {:refused,_,_} = Standing.validate(%{standing: ""})
  assert {:refused,_,_} = Standing.validate(%{})
 end
end
