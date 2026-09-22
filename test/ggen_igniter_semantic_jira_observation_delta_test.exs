defmodule GgenIgniter.SemanticJiraObservationDeltaTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira

  @base_sha String.duplicate("c", 40)

  defp binding do
    %{
      "repository" => "seanchatmangpt/biblegym",
      "base_sha" => @base_sha,
      "path_scope" => ["ontology.ttl", "ggen", "tests"],
      "required_courts" => ["court:semantic-life-loop"],
      "required_evidence" => ["evidence:life-observation", "evidence:formation-packet"],
      "acceptance" => ["candidate remains authority-free until independent verification"],
      "falsifiers" => ["candidate with DO authority is refused"],
      "projections" => ["jira", "sa2a", "verification", "receipt", "replay"],
      "required_receipt_classes" => ["manufacture", "verification", "replay"],
      "evidence_ceiling" => "OBSERVATION_AND_CONSTRUCT_ONLY",
      "promotion_rule" => "exact-subject verification receipt plus replay"
    }
  end

  defp delta do
    %{
      "schema" => "semantic-life-loop.observation-delta.v1",
      "episode_id" => "semantic-life-loop-example-001",
      "digest" => "sha256:" <> String.duplicate("a", 64),
      "work_candidates" => [
        %{
          "id" => "SLL-001",
          "kind" => "INVESTIGATE_NOVEL_OBSERVATION",
          "episode_id" => "semantic-life-loop-example-001",
          "subject_ref" => "https://ggen.dev/ontology/semantic-life-loop#ExampleSubject",
          "delta_class" => "NOVEL_OBSERVATION",
          "evidence_ref" => "observation:example-profile-scripture-bridge",
          "authority" => "CONSTRUCT_ONLY",
          "standing" => "CANDIDATE",
          "do_authority" => false,
          "dispatch" => "NOT_EXECUTED"
        }
      ]
    }
  end

  test "admits a GGen-manufactured life/formation observation as UNKNOWN work" do
    assert {:ok, [work_order]} =
             SemanticJira.observation_delta_work_orders(delta(), binding())

    assert work_order["identity"] == "SLL-001"
    assert work_order["standing"] == "UNKNOWN"
    assert work_order["authority"] == "NONE"
    assert work_order["authority_requirement"] == "NONE"
    assert work_order["repository"] == "seanchatmangpt/biblegym"
    assert work_order["base_sha"] == @base_sha
    assert work_order["source_observation_kind"] == "semantic-observation"
    assert work_order["source_delta_schema"] == "semantic-life-loop.observation-delta.v1"
    assert work_order["source_episode_id"] == "semantic-life-loop-example-001"
    assert work_order["source_candidate_authority"] == "CONSTRUCT_ONLY"
    assert work_order["source_candidate_dispatch"] == "NOT_EXECUTED"
    assert String.starts_with?(work_order["definition_digest"], "sha256:")
    assert String.starts_with?(work_order["work_order_digest"], "sha256:")
  end

  test "preserves deterministic identity on replay of the same delta" do
    assert {:ok, first} = SemanticJira.observation_delta_work_orders(delta(), binding())
    assert {:ok, second} = SemanticJira.observation_delta_work_orders(delta(), binding())
    assert first == second
  end

  test "refuses authority or dispatch smuggling before WorkOrder admission" do
    [candidate] = delta()["work_candidates"]

    for poisoned <-
          [
            Map.put(candidate, "do_authority", true),
            Map.put(candidate, "authority", "DO"),
            Map.put(candidate, "dispatch", "EXECUTED"),
            Map.put(candidate, "standing", "ALIVE")
          ] do
      bad = %{delta() | "work_candidates" => [poisoned]}

      assert {:error, {:refused_observation_delta, {:candidate_boundary_violation, "SLL-001"}}} =
               SemanticJira.observation_delta_work_orders(bad, binding())
    end
  end

  test "refuses an unsupported class-to-kind mapping" do
    [candidate] = delta()["work_candidates"]
    bad_candidate = Map.put(candidate, "kind", "CLOSE_READINESS_GAP")
    bad = %{delta() | "work_candidates" => [bad_candidate]}

    assert {:error, {:refused_observation_delta, {:candidate_boundary_violation, "SLL-001"}}} =
             SemanticJira.observation_delta_work_orders(bad, binding())
  end
end
