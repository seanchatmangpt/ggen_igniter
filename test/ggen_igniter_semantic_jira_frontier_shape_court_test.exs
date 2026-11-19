defmodule GgenIgniter.SemanticJiraFrontierShapeCourtTest do
  @moduledoc """
  Mutual frontier-shape court against the shared ggen golden fixture
  (`crates/ggen-sjira/tests/fixtures/golden_frontier_orders.json`).

  Asserts Elixir SemanticJira admits the same `{"work_orders":[...]}`
  envelope Rust `orders_from_json` + frontier consume (WP census GAP:
  Rust CLI previously required a `{work_order,...}` wrap).
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira

  @fixture Path.expand(
             "../ggen/crates/ggen-sjira/tests/fixtures/golden_frontier_orders.json",
             Path.join(__DIR__, "..")
           )

  @tag :frontier_shape_court
  test "shared golden frontier orders admit on Elixir (mutual SoT)" do
    assert File.exists?(@fixture),
           "expected sibling ggen fixture at #{@fixture}"

    %{"work_orders" => orders} = @fixture |> File.read!() |> Jason.decode!()
    assert length(orders) == 2

    for order <- orders do
      assert {:ok, admitted} = SemanticJira.admit_work_order(order)
      assert admitted["authority"] == "NONE"
      assert admitted["identity"] in ["SJ-FRONT-A", "SJ-FRONT-B"]
    end

    b = Enum.find(orders, &(&1["identity"] == "SJ-FRONT-B"))
    assert [%{"type" => "requiresReceipt", "upstream" => "SJ-FRONT-A"}] = b["dependencies"]
  end

  @tag :frontier_shape_court
  test "Cli.frontier accepts the golden Elixir SoT envelope" do
    assert File.exists?(@fixture)

    decoded = @fixture |> File.read!() |> Jason.decode!()
    assert %{"work_orders" => [_ | _]} = decoded

    tmp =
      Path.join(
        System.tmp_dir!(),
        "sjira-frontier-shape-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    ledger = Path.join(tmp, "ledger")
    File.mkdir_p!(ledger)

    try do
      {code, result} =
        GgenIgniter.SemanticJira.Cli.frontier(work_orders: @fixture, ledger: ledger)

      assert code == 0, "frontier refused: #{inspect(result)}"
      assert result["status"] == "ok"
      eligible_ids = Enum.map(result["eligible"], & &1["identity"])
      assert "SJ-FRONT-A" in eligible_ids
      blocked = Enum.find(result["blocked"], &(&1["identity"] == "SJ-FRONT-B"))
      assert blocked["reason"] == "dependencies_unsatisfied"
    after
      File.rm_rf(tmp)
    end
  end
end
