defmodule GgenIgniter.SemanticJiraAdmissionSiblingFalsifierTest do
  @moduledoc """
  QUALIFIER falsifiers (labelled: added by the qualification pass, not the
  builder) for `GgenIgniter.SemanticJira.Admission`, complementing the
  candidate-side raise falsifiers already committed in
  `ggen_igniter_semantic_jira_admission_qualifier_test.exs`.

  The moduledoc of `Admission` states that "a malformed sibling in the context
  graph does not block an unrelated candidate" and that `to_graph/1` "never
  raises on malformed field values". The builder's own test covers a sibling
  with a missing field only. These tests cover a sibling whose `identity` is
  kernel-admissible but non-scalar (the kernel only checks that `identity` is
  present), and a candidate whose `identity` is a list holding a map.

  Chicago, no doubles: real shipped shape, real `Shacl` validator, real kernel
  court, real temp `TransitionLog`. Each test asserts the CORRECT behavior; a
  failure falsifies the documented invariant.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Admission, Reconciler, TransitionLog}

  @sha String.duplicate("b", 40)

  defp wo(id) do
    %{
      "identity" => id,
      "title" => id,
      "description" => "d-#{id}",
      "subject" => "subj-#{id}",
      "repository" => "o/r",
      "base_sha" => @sha,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "observed",
      "authority_ceiling" => "CONSTRUCT",
      "authority_requirement" => "NONE",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid-#{id}",
      "path_scope" => ["lib/ggen_igniter/semantic_jira"],
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "required_receipt_classes" => ["verification"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"],
      "next_action" => "run-court",
      "next_checkpoint" => "checkpoint-#{id}",
      "dependencies" => []
    }
  end

  defp receipt(w) do
    {:ok, dd} = SemanticJira.definition_digest(w)
    {:ok, a} = SemanticJira.admit_work_order(w)

    %{
      "definition_digest" => dd,
      "snapshot_digest" => a["work_order_digest"],
      "target" => "ALIVE",
      "candidate_sha" => @sha,
      "evidence" => %{
        "subject" => w["subject"],
        "repository" => w["repository"],
        "base_sha" => w["base_sha"],
        "evidence_types" => ["exec"],
        "court_results" => %{"ci" => %{"passed" => true}},
        "acceptance_results" => %{"a1" => true},
        "falsifier_results" => %{"f1" => "survived"},
        "receipt_classes" => ["verification"],
        "evidence_ceiling" => "observed",
        "observed_execution" => true
      }
    }
  end

  # Runs `fun`, mapping a raise to {:raised, exception module} so a crash is a
  # clean assertion failure instead of an aborted test.
  defp run(fun) do
    fun.()
  rescue
    e -> {:raised, e.__struct__}
  end

  setup do
    dir =
      Path.join(System.tmp_dir!(), "sj_sibling_falsifier_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "a sibling with a non-scalar identity does not crash or block a lawful candidate" do
    lawful = wo("FINE")
    poisoned = Map.put(wo("OTHER"), "identity", %{"a" => 1})

    assert {:ok, _} = SemanticJira.admit_work_order(poisoned)
    assert {:ok, _} = SemanticJira.admit_work_order(lawful)

    assert {:ok, _} = run(fn -> Admission.admit(lawful, work_orders: [poisoned]) end)
  end

  test "reconcile/4 :shacl appends a lawful candidate despite a malformed sibling in work_orders",
       %{dir: dir} do
    lawful = wo("FINE")
    poisoned = Map.put(wo("OTHER"), "identity", %{"a" => 1})

    assert {:ok, _, :appended} =
             run(fn ->
               Reconciler.reconcile(lawful, receipt(lawful), dir,
                 admission: :shacl,
                 work_orders: [lawful, poisoned]
               )
             end)

    assert [%{"identity" => "FINE", "seq" => 1}] = TransitionLog.read(dir)
  end

  test "an identity that is a list holding a map is refused with a typed reason, not an ArgumentError",
       %{dir: dir} do
    candidate = Map.put(wo("ROOT"), "identity", [%{"a" => 1}])
    assert {:ok, _} = SemanticJira.admit_work_order(candidate)

    assert {:error, {:refused, _}} =
             run(fn ->
               Reconciler.reconcile(candidate, receipt(candidate), dir,
                 admission: :shacl,
                 work_orders: [candidate]
               )
             end)

    assert TransitionLog.read(dir) == []
  end
end
