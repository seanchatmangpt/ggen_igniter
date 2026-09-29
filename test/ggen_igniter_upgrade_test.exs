defmodule GgenIgniterUpgradeTest do
  @moduledoc """
  Chicago-style: real Igniter test projects, the real upgrade task composed via
  `Igniter.compose_task/3`, assertions on resulting patches/issues; range selection
  is a pure function asserted on its return value. No test doubles.
  """
  use ExUnit.Case, async: true
  import Igniter.Test

  alias GgenIgniter.Upgrades

  defp run(igniter, from, to),
    do: Igniter.compose_task(igniter, "ggen_igniter.upgrade", [from, to])

  test "range selection: inside window selects, at/below from or above to does not" do
    assert {:ok, [GgenIgniter.Upgrades.V26_9_28]} = Upgrades.select("26.9.24", "26.9.28")
    assert {:ok, [GgenIgniter.Upgrades.V26_9_28]} = Upgrades.select("26.9.24", "26.10.1")
    assert {:ok, []} = Upgrades.select("26.9.28", "26.10.1")
    assert {:ok, []} = Upgrades.select("26.9.24", "26.9.27")
    assert {:ok, []} = Upgrades.select("26.9.28", "26.9.28")
  end

  test "range selection orders ascending over a custom registry" do
    reg = %{"2.0.0" => :b, "1.5.0" => :a, "3.0.0" => :c}
    assert {:ok, [:a, :b]} = Upgrades.select("1.0.0", "2.0.0", reg)
  end

  test "downgrade and invalid versions are typed refusals" do
    assert {:error, {:downgrade, "26.9.28", "26.9.24"}} = Upgrades.select("26.9.28", "26.9.24")
    assert {:error, {:invalid_version, "banana"}} = Upgrades.select("banana", "26.9.28")
    assert {:error, {:invalid_version, "x"}} = Upgrades.select("26.9.24", "x")
  end

  test "upgrade adds import_deps and a second run is unchanged" do
    igniter = test_project() |> run("26.9.24", "26.9.28") |> apply_igniter!()

    assert_has_patch(run(test_project(), "26.9.24", "26.9.28"), ".formatter.exs", """
    + |import_deps: [:ggen_igniter]
    """)

    assert_unchanged(run(igniter, "26.9.24", "26.9.28"), ".formatter.exs")
  end

  test "downgrade through the task adds an issue and changes nothing" do
    ig = run(test_project(), "26.9.28", "26.9.24")
    assert_has_issue(ig, "REFUSED:UPGRADE_DOWNGRADE 26.9.28 -> 26.9.24")
    assert_unchanged(ig)
  end

  test "no-op range leaves the project unchanged" do
    assert_unchanged(run(test_project(), "26.9.28", "26.9.28"))
  end
end
