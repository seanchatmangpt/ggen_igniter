defmodule GgenIgniter.DoctrineAdmission.DeterminismTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Determinism

  test "map key order does not change digest" do
    left = %{"b" => 2, "a" => %{"z" => 1, "y" => 0}}
    right = %{"a" => %{"y" => 0, "z" => 1}, "b" => 2}

    assert Determinism.digest(left) == Determinism.digest(right)
  end

  test "semantic value change changes digest" do
    refute Determinism.digest(%{"a" => 1}) == Determinism.digest(%{"a" => 2})
  end
end
