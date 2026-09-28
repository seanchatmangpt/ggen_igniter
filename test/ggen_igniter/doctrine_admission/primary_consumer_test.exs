defmodule GgenIgniter.DoctrineAdmission.PrimaryConsumerTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.PrimaryConsumer

  test "planning projection preserves exact doctrine source identity" do
    work = %{
      "identity" => "doctrine:s1:o1",
      "objective" => "o1",
      "subject_sha" => "dcdedbcc6c8482a22487ca100bcf93c3b54291fa",
      "source_repository" => "seanchatmangpt/ggen-marketplace",
      "source_artifact_sha" => "225e3eff18f0570817646ebf7c210117ee1a82b5",
      "source_path" => "packs/strategic-doctrine-pack"
    }

    assert {:ok, projection} = PrimaryConsumer.project(work)
    assert projection.kind == :planning_candidate
    assert projection.authority == :none
    assert projection.subject_sha == work["subject_sha"]
    assert projection.source_repository == work["source_repository"]
    assert projection.source_artifact_sha == work["source_artifact_sha"]
    assert projection.source_path == work["source_path"]
  end
end
