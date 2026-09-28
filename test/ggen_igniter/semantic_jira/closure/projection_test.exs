defmodule GgenIgniter.SemanticJira.Closure.ProjectionTest do
 use ExUnit.Case, async: true
 alias GgenIgniter.SemanticJira.Closure.Projection
 test "projection non-authority admits witness and refuses minimal falsifier" do
  assert :ok = Projection.validate(%{projection: "derived"})
  assert {:refused,_,_} = Projection.validate(%{projection: "handwritten"})
  assert {:refused,_,_} = Projection.validate(%{})
 end
end
