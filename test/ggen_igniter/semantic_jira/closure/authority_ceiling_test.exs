defmodule GgenIgniter.SemanticJira.Closure.AuthorityCeilingTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.AuthorityCeiling
 test "authority ceiling admits witness and refuses minimal falsifier" do
  assert :ok = AuthorityCeiling.validate(%{authority: "CONSTRUCT"})
  assert {:refused,_,_} = AuthorityCeiling.validate(%{authority: "DO"})
  assert {:refused,_,_} = AuthorityCeiling.validate(%{})
 end
end
