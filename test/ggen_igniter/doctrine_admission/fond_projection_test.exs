defmodule GgenIgniter.DoctrineAdmission.FondProjectionTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.FondProjection

  test "projects falsifier to a oneof effect without authority" do
    input = %{"strategy" => "s1", "falsifier" => %{"property" => "runway", "comparator" => "lt", "threshold" => 6}}
    assert {:ok, ir} = FondProjection.project(input)
    assert ir["effect"] == {:oneof, ["held", "refuted"]}
    assert ir["authority"] == "NONE"
  end
end
