defmodule GgenIgniter.DoctrineAdmission.HddlProjectionTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.HddlProjection

  test "preserves total order in the HDDL IR" do
    input = %{
      "strategy" => "s1",
      "steps" => [
        %{"order" => 1, "operator" => "position"},
        %{"order" => 2, "operator" => "probe"},
        %{"order" => 3, "operator" => "delay"}
      ]
    }

    assert {:ok, ir} = HddlProjection.project(input)
    assert ir["subtasks"] == [{"s1", "position"}, {"s2", "probe"}, {"s3", "delay"}]
    assert ir["ordering"] == [{"s1", "s2"}, {"s2", "s3"}]
    assert ir["ceiling"] == "CONSTRUCT"
  end
end
