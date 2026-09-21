defmodule GgenIgniter.TestSupport.SemanticJiraFixtures do
  @moduledoc """
  Chicago-style: real WorkOrder maps and the real receipts
  `GgenIgniter.SemanticJira.definition_digest/1` and `admit_work_order/1`
  derive for them -- the same shapes the reconciler and crown tests build --
  so store tests drive the real `Reconciler`/`promote/3` admission path.
  """

  alias GgenIgniter.SemanticJira

  @sha String.duplicate("a", 40)

  @spec wo(String.t(), [String.t()]) :: map()
  def wo(id, deps \\ []) do
    %{
      "identity" => id,
      "title" => id,
      "description" => "d",
      "subject" => "subj-#{id}",
      "repository" => "o/r",
      "base_sha" => @sha,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "observed",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid-#{id}",
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"],
      "dependencies" =>
        Enum.map(
          deps,
          &%{"upstream" => &1, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
        )
    }
  end

  @spec receipt(map(), String.t()) :: map()
  def receipt(w, target \\ "ALIVE") do
    {:ok, dd} = SemanticJira.definition_digest(w)
    {:ok, a} = SemanticJira.admit_work_order(w)

    %{
      "definition_digest" => dd,
      "snapshot_digest" => a["work_order_digest"],
      "target" => target,
      "evidence" => %{
        "subject" => w["subject"],
        "repository" => w["repository"],
        "base_sha" => w["base_sha"],
        "evidence_types" => ["exec"],
        "court_results" => %{"ci" => %{"passed" => true}},
        "acceptance_results" => %{"a1" => true},
        "falsifier_results" => %{"f1" => "survived"},
        "receipt_classes" => [],
        "evidence_ceiling" => "observed",
        "observed_execution" => true
      }
    }
  end
end
