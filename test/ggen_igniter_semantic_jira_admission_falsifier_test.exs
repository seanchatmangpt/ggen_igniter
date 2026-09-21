defmodule GgenIgniter.SemanticJiraAdmissionFalsifierTest do
  @moduledoc """
  QUALIFIER falsifiers for the full-shape SHACL admission
  (`GgenIgniter.SemanticJira.Admission`, `Reconciler.reconcile/4 admission: :shacl`).

  Chicago, no doubles: the real shipped shape file, the real `Shacl` validator, a
  real temp shape file for the fail-closed witness, a real temp `TransitionLog`.

  Each test asserts the CORRECT (fail-closed) behavior. A failure here is a
  falsification of the stream's claim that a candidate violating the full shape is
  REFUSED and never reaches the log.
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

  defp receipt(w, sha) do
    {:ok, dd} = SemanticJira.definition_digest(w)
    {:ok, a} = SemanticJira.admit_work_order(w)

    %{
      "definition_digest" => dd,
      "snapshot_digest" => a["work_order_digest"],
      "target" => "ALIVE",
      "candidate_sha" => sha,
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
    dir = Path.join(System.tmp_dir!(), "sj_falsifier_log_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  describe "sh:pattern anchoring: PCRE `$` accepts a trailing newline that the SHACL/XPath regex `$` does not" do
    for {key, value} <- [
          {"identity", "ROOT\n"},
          {"authority_ceiling", "CONSTRUCT\n"}
        ] do
      test "#{key} = #{inspect(value)} must be REFUSED by the full shape and never logged",
           %{dir: dir} do
        key = unquote(key)
        value = unquote(value)
        candidate = Map.put(wo("ROOT"), key, value)

        # kernel admits it (it does not check this pattern), so SHACL is the only court
        assert {:ok, _} = SemanticJira.admit_work_order(candidate)

        assert {:error, {:refused_work_order, {:shacl_violations, _}}} =
                 Admission.admit(candidate)

        assert {:error, {:refused, {:refused_work_order, {:shacl_violations, _}}}} =
                 Reconciler.reconcile(candidate, receipt(candidate, @sha), dir,
                   admission: :shacl,
                   work_orders: [candidate]
                 )

        assert TransitionLog.read(dir) == []
      end
    end
  end

  describe "fail-closed: a shape construct the validator cannot evaluate must refuse, not admit" do
    # Shacl documents: "encountering any of these is itself a violation, so an
    # unknown construct fails closed instead of passing". The violation it emits
    # has focus_node nil; Admission keeps only violations whose focus is a
    # candidate node, so the fail-closed violation is discarded.
    test "shape carrying an unsupported term (sh:in) does not silently admit", %{dir: dir} do
      shipped = File.read!(Admission.shapes_path())

      # add an unsupported sh:in to the authority-ceiling property shape: the
      # validator cannot evaluate it, so it reports :unsupported_constraint
      tampered =
        String.replace(
          shipped,
          ~s|sh:path sj:authorityCeiling ; sh:minCount 1 ;|,
          ~s|sh:path sj:authorityCeiling ; sh:in ( "OBSERVE" ) ; sh:minCount 1 ;|,
          global: false
        )

      refute tampered == shipped

      path =
        Path.join(
          System.tmp_dir!(),
          "sj_falsifier_shape_#{System.unique_integer([:positive])}.ttl"
        )

      File.write!(path, tampered)
      on_exit(fn -> File.rm(path) end)

      # authority_ceiling CONSTRUCT is outside the sh:in list ("OBSERVE"), so a
      # validator that evaluated sh:in would refuse it; one that cannot evaluate
      # it must fail closed. Either way: NOT admitted.
      candidate = wo("ROOT")

      assert {:error, _} = Admission.admit(candidate, shapes_path: path)

      assert {:error, {:refused, _}} =
               Reconciler.reconcile(candidate, receipt(candidate, @sha), dir,
                 admission: :shacl,
                 work_orders: [candidate],
                 shapes_path: path
               )

      assert TransitionLog.read(dir) == []
    end
  end

  describe "typed refusal, never a raise (Admission.to_graph/1 documents: never raises on malformed field values)" do
    # identity is kernel-required-present but not kernel-typed, so a map identity is
    # kernel-admitted; the projection then calls to_string/1 on it and raises.
    test "kernel-admissible non-scalar identity is refused with a typed reason", %{dir: dir} do
      candidate = Map.put(wo("ROOT"), "identity", %{"a" => 1})
      assert {:ok, _} = SemanticJira.admit_work_order(candidate)

      result =
        try do
          Reconciler.reconcile(candidate, receipt(candidate, @sha), dir,
            admission: :shacl,
            work_orders: [candidate]
          )
        rescue
          e -> {:raised, e.__struct__}
        end

      assert {:error, {:refused, _}} = result
      assert TransitionLog.read(dir) == []
    end
  end
end
