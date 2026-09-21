defmodule GgenIgniter.SemanticJiraAdmissionQualifierTest do
  @moduledoc """
  QUALIFIER falsifiers (labelled: added by the qualification pass, not the
  builder) for `GgenIgniter.SemanticJira.Admission` and
  `Reconciler.reconcile/4 admission: :shacl`.

  Chicago, no doubles: real kernel court, real shipped shape, real `Shacl`
  validator, real temp `TransitionLog`. Each test asserts the CORRECT
  (typed, fail-closed) behavior; a failure here falsifies a documented
  invariant of the stream under review.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Admission, Reconciler, TransitionLog}

  @sha String.duplicate("b", 40)

  defp wo(id) do
    %{
      "identity" => id,
      "title" => "t",
      "description" => "d",
      "subject" => "subj",
      "repository" => "o/r",
      "base_sha" => @sha,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "observed",
      "authority_ceiling" => "CONSTRUCT",
      "authority_requirement" => "NONE",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid",
      "path_scope" => ["lib/ggen_igniter/semantic_jira"],
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "required_receipt_classes" => ["verification"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"],
      "next_action" => "run-court",
      "next_checkpoint" => "cp",
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

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_qualifier_log_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "to_graph/1 never raises on a non-scalar identity or upstream (documented invariant)" do
    assert %RDF.Graph{} = Admission.to_graph([wo("ROOT") |> Map.put("identity", %{"a" => 1})])

    dep = %{"upstream" => %{"a" => 1}, "type" => "requiresReceipt"}
    assert %RDF.Graph{} = Admission.to_graph([wo("ROOT") |> Map.put("dependencies", [dep])])
  end

  test "reconcile/4 :shacl returns a typed refusal, never raises, for a kernel-admitted WorkOrder with a map identity",
       %{dir: dir} do
    candidate = Map.put(wo("ROOT"), "identity", %{"a" => 1})

    # the kernel court admits it (it never type-checks identity) ...
    assert {:ok, _} = SemanticJira.admit_work_order(candidate)

    # ... so the SHACL court is the only refusal path and must be typed
    assert {:error, {:refused, _}} =
             Reconciler.reconcile(candidate, receipt(candidate), dir,
               admission: :shacl,
               work_orders: [candidate]
             )

    assert TransitionLog.read(dir) == []
  end

  test "an unknown admission mode is refused even when the receipt is already recorded",
       %{dir: dir} do
    root = wo("ROOT")
    r = receipt(root)

    assert {:ok, _, :appended} =
             Reconciler.reconcile(root, r, dir, admission: :shacl, work_orders: [root])

    assert {:error, {:refused, {:unknown_admission_mode, :bogus}}} =
             Reconciler.reconcile(root, r, dir, admission: :bogus)
  end
end
