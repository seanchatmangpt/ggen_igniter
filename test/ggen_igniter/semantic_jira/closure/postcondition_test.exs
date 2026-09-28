defmodule GgenIgniter.SemanticJira.Closure.PostconditionTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Postcondition
 test "postcondition evidence admits witness and refuses minimal falsifier" do
  assert :ok = Postcondition.validate(%{postcondition: "postcondition:witness"})
  assert {:refused,_,_} = Postcondition.validate(%{postcondition: ""})
  assert {:refused,_,_} = Postcondition.validate(%{})
 end
end
