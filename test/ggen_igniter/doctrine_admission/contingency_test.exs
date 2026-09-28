defmodule GgenIgniter.DoctrineAdmission.ContingencyTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Contingency

  test "builds one bounded nondeterministic observation" do
    input = %{"strategy" => "s1", "falsifier" => %{"property" => "runway", "comparator" => "lt", "threshold" => 6}}
    assert {:ok, %{"outcomes" => ["held", "refuted"], "authority" => "NONE"}} = Contingency.build(input)
  end

  test "refuses unknown comparators" do
    input = %{"strategy" => "s1", "falsifier" => %{"property" => "runway", "comparator" => "approx", "threshold" => 6}}
    assert {:error, {:refused_doctrine, :contingency, :invalid_falsifier}} = Contingency.build(input)
  end
end
