defmodule GgenIgniter.SemanticJiraMeetingDeltaTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira

  @base_sha String.duplicate("a", 40)

  defp binding do
    %{
      "repository" => "seanchatmangpt/zoela",
      "base_sha" => @base_sha,
      "path_scope" => ["docs/sjira/v26.9.21", "gym"],
      "required_courts" => ["court:zoe-youth-readiness"],
      "required_evidence" => ["evidence:typed-meeting-delta"],
      "acceptance" => ["actual observation remains authority-free"],
      "falsifiers" => ["candidate with DO authority is refused"],
      "projections" => ["jira", "sa2a", "worker", "verification", "receipt", "replay"],
      "required_receipt_classes" => ["verification", "replay"],
      "evidence_ceiling" => "TYPED_TRANSCRIPT_OBSERVATION_ONLY",
      "promotion_rule" => "exact-head verifier receipt plus replay"
    }
  end

  defp delta do
    %{
      "schema" => "zoe.meeting.delta.v1",
      "episode_id" => "ZOE-YTH-READINESS-001",
      "digest" => String.duplicate("b", 64),
      "work_candidates" => [
        %{
          "id" => "sjira:001",
          "kind" => "CLOSE_READINESS_GAP",
          "episode_id" => "ZOE-YTH-READINESS-001",
          "subject_ref" => "requirement:systems_and_access",
          "delta_class" => "MISSING_TRANSITION",
          "evidence_ref" => "transcript:42",
          "authority" => "CONSTRUCT_ONLY",
          "standing" => "CANDIDATE",
          "do_authority" => false,
          "dispatch" => "NOT_EXECUTED"
        },
        %{
          "id" => "sjira:002",
          "kind" => "RESOLVE_BINDING",
          "episode_id" => "ZOE-YTH-READINESS-001",
          "subject_ref" => "requirement:schedule_and_arrival",
          "delta_class" => "INCOMPLETE_BINDING",
          "evidence_ref" => "transcript:15",
          "authority" => "CONSTRUCT_ONLY",
          "standing" => "CANDIDATE",
          "do_authority" => false,
          "dispatch" => "NOT_EXECUTED"
        }
      ]
    }
  end

  test "projects deterministic authority-free meeting deltas into canonical work orders" do
    assert {:ok, first} = SemanticJira.meeting_delta_work_orders(delta(), binding())
    assert {:ok, second} = SemanticJira.meeting_delta_work_orders(delta(), binding())
    assert first == second
    assert Enum.map(first, & &1["identity"]) == ["sjira:001", "sjira:002"]

    for work_order <- first do
      assert work_order["standing"] == "UNKNOWN"
      assert work_order["authority"] == "NONE"
      assert work_order["authority_requirement"] == "NONE"
      assert work_order["replay_required"] == true
      assert work_order["repository"] == "seanchatmangpt/zoela"
      assert work_order["base_sha"] == @base_sha
      assert work_order["source_episode_id"] == "ZOE-YTH-READINESS-001"
      assert work_order["source_candidate_authority"] == "CONSTRUCT_ONLY"
      assert work_order["source_candidate_dispatch"] == "NOT_EXECUTED"
      assert String.starts_with?(work_order["work_order_digest"], "sha256:")
      assert String.starts_with?(work_order["definition_digest"], "sha256:")
    end
  end

  test "refuses a candidate that attempts to cross the DO boundary" do
    [first | rest] = delta()["work_candidates"]
    poisoned = %{delta() | "work_candidates" => [Map.put(first, "do_authority", true) | rest]}

    assert {:error, {:refused_meeting_delta, {:candidate_boundary_violation, "sjira:001"}}} =
             SemanticJira.meeting_delta_work_orders(poisoned, binding())
  end

  test "refuses a semantic mismatch between delta class and work kind" do
    [first | rest] = delta()["work_candidates"]
    poisoned = %{
      delta()
      | "work_candidates" => [Map.put(first, "kind", "RESOLVE_BINDING") | rest]
    }

    assert {:error, {:refused_meeting_delta, {:candidate_boundary_violation, "sjira:001"}}} =
             SemanticJira.meeting_delta_work_orders(poisoned, binding())
  end

  test "requires an exact repository base and bounded path scope" do
    assert {:error, {:refused_meeting_delta, {:invalid_sha, :base_sha, "moving"}}} =
             SemanticJira.meeting_delta_work_orders(delta(), %{binding() | "base_sha" => "moving"})

    assert {:error, {:refused_meeting_delta, _}} =
             SemanticJira.meeting_delta_work_orders(delta(), %{binding() | "path_scope" => []})
  end
end
