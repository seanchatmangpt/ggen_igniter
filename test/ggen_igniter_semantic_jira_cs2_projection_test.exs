defmodule GgenIgniter.SemanticJira.CS2ProjectionTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{CS2Batch, CS2Ingest, CS2Projection}

  @sha String.duplicate("a", 40)
  @digest String.duplicate("b", 64)

  defp batch(overrides \\ %{}) do
    Map.merge(
      %{
        "batchId" => "cs2:fixture:1",
        "subject" => "https://chatman.ai/cs2#RFC-CS2-001",
        "source" => %{
          "repo" => "seanchatmangpt/ggen-marketplace",
          "sha" => @sha,
          "digest" => @digest
        },
        "work" => [
          %{
            "workKey" => "CS2-WRK-001",
            "objective" => "Manufacture source-bound semantic work.",
            "acceptance" => "Canonical work is admitted.",
            "falsifier" => "Any authority is manufactured.",
            "nextEdge" => "CS2-WRK-002",
            "dependencies" => [],
            "pathScope" => ["packs/cs2-semantic-work"],
            "projections" => ["worker", "verification"]
          },
          %{
            "workKey" => "CS2-WRK-002",
            "objective" => "Consume admitted semantic work.",
            "acceptance" => "Dependency order is conserved.",
            "falsifier" => "Consumer runs before producer.",
            "nextEdge" => "XaaS consumer",
            "dependencies" => ["CS2-WRK-001"],
            "pathScope" => ["lib/ggen_igniter/semantic_jira"],
            "projections" => ["worker", "machine"]
          }
        ],
        "authority" => "NONE"
      },
      overrides
    )
  end

  test "projects marketplace batch into admitted SemanticJira work orders" do
    assert {:ok, projected} = CS2Projection.project_batch(batch())
    assert projected["authority"] == "NONE"
    assert projected["repository"] == "seanchatmangpt/ggen-marketplace"
    assert Enum.map(projected["work_orders"], & &1["identity"]) ==
             ["CS2-WRK-001", "CS2-WRK-002"]

    assert Enum.all?(projected["work_orders"], fn order ->
             order["admitted"] == true and order["authority"] == "NONE"
           end)
  end

  test "dependency layering is deterministic and dependency ordered" do
    assert {:ok, projected} = CS2Projection.project_batch(batch())
    assert {:ok, [[first], [second]]} = CS2Batch.dependency_layers(projected)
    assert first["identity"] == "CS2-WRK-001"
    assert second["identity"] == "CS2-WRK-002"
  end

  test "unknown dependency target refuses the whole batch" do
    raw = batch()
    [first, second] = raw["work"]
    bad = %{second | "dependencies" => ["CS2-WRK-999"]}

    assert {:error, {:refused_cs2_projection, {:refused_cs2_batch, {:unknown_dependency_targets, _}}}} =
             CS2Projection.project_batch(%{raw | "work" => [first, bad]})
  end

  test "cycle refuses rather than becoming runnable annotation" do
    raw = batch()
    [first, second] = raw["work"]

    cyclic = %{
      raw
      | "work" => [
          %{first | "dependencies" => ["CS2-WRK-002"]},
          %{second | "dependencies" => ["CS2-WRK-001"]}
        ]
    }

    assert {:ok, projected} = CS2Projection.project_batch(cyclic)

    assert {:error, {:refused_cs2_batch, {:cyclic_dependencies, ["CS2-WRK-001", "CS2-WRK-002"]}}} =
             CS2Batch.dependency_layers(projected)
  end

  test "different absolute subject refuses before SemanticJira admission" do
    other = "https://chatman.ai/cs2#OTHER"

    assert {:error, {:refused_cs2_projection, {:subject_mismatch, ^other}}} =
             CS2Projection.project_batch(batch(%{"subject" => other}))
  end

  test "non-NONE authority refuses before SemanticJira admission" do
    assert {:error, {:refused_cs2_projection, :authority_must_be_none}} =
             CS2Projection.project_batch(batch(%{"authority" => "EXECUTE"}))
  end

  test "ingest composes projection, admission, layering, and candidates" do
    assert {:ok, ingested} = CS2Ingest.ingest(batch())
    assert length(ingested["orders"]) == 2
    assert Enum.map(ingested["candidates"], &{&1["layer"], &1["identity"]}) ==
             [{0, "CS2-WRK-001"}, {1, "CS2-WRK-002"}]
    assert ingested["authority"] == "NONE"
  end
end
