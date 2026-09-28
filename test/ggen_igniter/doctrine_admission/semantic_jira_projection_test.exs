defmodule GgenIgniter.DoctrineAdmission.SemanticJiraProjectionTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.SemanticJiraProjection

  test "manufactures candidate with canonical source identity and no standing" do
    input = %{
      "subject" => "strategy-11",
      "source_repository" => "seanchatmangpt/ggen-marketplace",
      "source_sha" => "dcdedbcc6c8482a22487ca100bcf93c3b54291fa",
      "objective" => "objective-3",
      "origin_authority" => "https://ggen.dev/ontology/strategic-doctrine#objective-3"
    }

    assert {:ok, candidate} = SemanticJiraProjection.project(input)
    assert candidate["source_repository"] == "seanchatmangpt/ggen-marketplace"
    assert candidate["subject_sha"] == "dcdedbcc6c8482a22487ca100bcf93c3b54291fa"
    assert candidate["source_artifact_sha"] == "225e3eff18f0570817646ebf7c210117ee1a82b5"
    assert candidate["source_path"] == "packs/strategic-doctrine-pack"
    assert candidate["standing"] == "UNKNOWN"
    assert candidate["authority_requirement"] == "NONE"
    assert candidate["evidence_ceiling"] == "CONSTRUCT"
    assert candidate["replay_identity"] =~ candidate["source_artifact_sha"]
  end

  test "refuses non-canonical doctrine source" do
    assert {:error, {:refused_doctrine, :source_identity, {:source_mismatch, _, _}}} =
             SemanticJiraProjection.project(%{
               "subject" => "strategy-11",
               "source_repository" => "seanchatmangpt/ggen-marketplace",
               "source_sha" => String.duplicate("a", 40),
               "objective" => "objective-3",
               "origin_authority" => "https://ggen.dev/ontology/strategic-doctrine#objective-3"
             })
  end
end
