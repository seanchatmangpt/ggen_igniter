defmodule GgenIgniter.DoctrineAdmission.MethodTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.Method

  test "orders a complete primitive chain and refuses gaps" do
    {:ok, method} = Method.build(%{"strategy" => "s1", "steps" => [%{"order" => 2, "operator" => "probe"}, %{"order" => 1, "operator" => "position"}]})
    assert Enum.map(method["steps"], & &1["order"]) == [1, 2]
    assert method["authority"] == "NONE"

    assert {:error, {:refused_doctrine, :method, :non_total_order}} =
             Method.build(%{"strategy" => "s1", "steps" => [%{"order" => 1, "operator" => "position"}, %{"order" => 3, "operator" => "probe"}]})
  end
end
