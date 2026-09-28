defmodule GgenIgniter.DoctrineAdmission.BerthierProjectionTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.DoctrineAdmission.BerthierProjection

  @source_repository "seanchatmangpt/ggen-marketplace"
  @source_sha "dcdedbcc6c8482a22487ca100bcf93c3b54291fa"

  defp input(overrides \\ %{}) do
    Map.merge(
      %{
        "subject" => "doctrine:strategy-11",
        "source_repository" => @source_repository,
        "source_sha" => @source_sha,
        "strategy_id" => "strategy-11",
        "strategy" => "bounded strategic candidate",
        "premise_digests" => %{"market" => String.duplicate("a", 64)},
        "invariants" => ["SELECT != CONSTRUCT != DO", "authority ceiling CONSTRUCT"],
        "required_capabilities" => ["HDDL", "FOND", "SEMANTIC_JIRA"],
        "local_premise_digests" => %{"runway" => String.duplicate("b", 64)},
        "local_constraints" => ["preserve exact source"],
        "actions" => ["SELECT", "DECOMPOSE", "ROUTE", "CONSTRUCT"],
        "falsifier" => "measured consequence contradicts candidate",
        "objectives" => %{"cost" => 3.0, "information_gain" => 1.0}
      },
      overrides
    )
  end

  test "projects canonical doctrine into the merged Berthier consumer contract" do
    assert {:ok, artifact} = BerthierProjection.project(input())
    assert artifact["source"]["repository"] == @source_repository
    assert artifact["source"]["sha"] == @source_sha
    assert artifact["source"]["artifact_sha"] == "225e3eff18f0570817646ebf7c210117ee1a82b5"
    assert artifact["consumer"]["repository"] == "seanchatmangpt/chatman-ecosystem"
    assert artifact["consumer"]["sha"] == "92cb17cda899a8d85abdaa04db10a3d2334e116d"
    assert artifact["authority"] == "NONE"
    assert artifact["actuation"] == "NONE"
    assert artifact["doctrine"]["authority_ceiling"] == "CONSTRUCT"
    assert byte_size(artifact["projection_digest"]) == 64
  end

  test "projection is deterministic" do
    assert {:ok, a} = BerthierProjection.project(input())
    assert {:ok, b} = BerthierProjection.project(input())
    assert a["projection_digest"] == b["projection_digest"]
  end

  test "refuses source drift" do
    assert {:error, {:refused_doctrine, :source_identity, {:source_mismatch, _, "drift"}}} =
             BerthierProjection.project(input(%{"source_sha" => "drift"}))
  end

  test "refuses DO before Berthier" do
    assert {:error, {:refused_doctrine, :berthier_projection, {:illegal_actions, ["DO"]}}} =
             BerthierProjection.project(input(%{"actions" => ["SELECT", "DO"]}))
  end
end
