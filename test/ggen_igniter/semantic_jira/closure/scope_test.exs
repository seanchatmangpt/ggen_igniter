defmodule GgenIgniter.SemanticJira.Closure.ScopeTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Scope
 test "scope boundary admits witness and refuses minimal falsifier" do
  assert :ok = Scope.validate(%{scope: "scope:witness"})
  assert {:refused,_,_} = Scope.validate(%{scope: ""})
  assert {:refused,_,_} = Scope.validate(%{})
 end
end
