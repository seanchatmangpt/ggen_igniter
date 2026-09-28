defmodule GgenIgniter.DoctrineAdmission.SemanticJiraProjectionTest do
  use ExUnit.Case, async: true
  alias GgenIgniter.DoctrineAdmission.SemanticJiraProjection

  test "manufactures candidate with exact source identity and no standing" do
    input = %{
      "subject" => "strategy-11",
      "source_sha" => String.duplicate("a", 40),
      "objective" => "objective-3",
      "origin_authority" => "https://ggen.dev/ontology/strategic-doctrine#objective-3"
    }

    assert {:ok, candidate} = SemanticJiraProjection.project(input)
    assert candidate["standing"] == "UNKNOWN"
    assert candidate["authority_requirement"] == "NONE"
    assert candidate["evidence_ceiling"] == "CONSTRUCT"
    assert candidate["replay_identity"] =~ candidate["subject_sha"]
  end
end
