defmodule GgenIgniter.SemanticJiraReconcilerTest do
  @moduledoc """
  Chicago, no-mocks: real WorkOrders, real promote/3 admission, real
  file-backed transition log in a scratch dir. Asserts on projected state.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Reconciler, TransitionLog}

  @sha String.duplicate("a", 40)
  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"

  defp wo(id, deps \\ []) do
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
      "origin_authority" => @origin_authority,
      "dependencies" =>
        Enum.map(
          deps,
          &%{"upstream" => &1, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
        )
    }
  end

  defp receipt(w, target \\ "ALIVE") do
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

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_log_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "definition_digest ignores standing, snapshot digest does not" do
    a = wo("A")
    {:ok, d1} = SemanticJira.definition_digest(a)
    {:ok, d2} = SemanticJira.definition_digest(Map.put(a, "standing", "ALIVE"))
    assert d1 == d2
    assert {:ok, x} = SemanticJira.admit_work_order(a)
    assert {:ok, y} = SemanticJira.admit_work_order(Map.put(a, "standing", "ALIVE"))
    refute x["work_order_digest"] == y["work_order_digest"]
  end

  test "transition makes dependent eligible; siblings on stale snapshots both admitted; replay equals",
       %{dir: dir} do
    root = wo("ROOT")
    b = wo("B", ["ROOT"])
    c = wo("C", ["ROOT"])
    graph = [root, b, c]

    assert %{eligible: [%{"identity" => "ROOT"}], blocked: blocked} =
             SemanticJira.frontier_from_events(graph, [])

    assert length(blocked) == 2

    assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root), dir)

    front = SemanticJira.frontier_from_events(graph, TransitionLog.read(dir))
    assert Enum.map(front.eligible, & &1["identity"]) == ["B", "C"]

    # B and C receipts were minted before ROOT moved (stale snapshot vs current
    # log state); both are still admitted, neither invalidates the other.
    rb = receipt(b)
    rc = receipt(c)
    assert {:ok, _, :appended} = Reconciler.reconcile(b, rb, dir)
    assert {:ok, _, :appended} = Reconciler.reconcile(c, rc, dir)

    # idempotent
    assert {:ok, _, :already_recorded} = Reconciler.reconcile(b, rb, dir)
    assert length(TransitionLog.read(dir)) == 3

    {projected, _} = SemanticJira.project(graph, TransitionLog.read(dir))
    assert Enum.map(projected, & &1["standing"]) == ["ALIVE", "ALIVE", "ALIVE"]

    # replay from log alone (fresh read, producer state discarded)
    events = dir |> TransitionLog.read() |> Enum.map(&Map.drop(&1, ["seq"]))

    {again, _} =
      SemanticJira.project(
        graph,
        Enum.with_index(events, 1) |> Enum.map(fn {e, i} -> Map.put(e, "seq", i) end)
      )

    assert again == projected
  end

  test "dependent refused until dependency transitioned", %{dir: dir} do
    b = wo("B", ["ROOT"])

    assert {:error, {:refused, {:promotion_refused, failed}}} =
             Reconciler.reconcile(b, receipt(b), dir)

    assert :dependencies in failed
    assert TransitionLog.read(dir) == []
  end

  test "tampered definition refused", %{dir: dir} do
    root = wo("ROOT")
    r = receipt(root)
    tampered = Map.put(root, "acceptance", ["a1", "sneaky"])

    assert {:error, {:refused, :definition_mismatch}} = Reconciler.reconcile(tampered, r, dir)
    assert TransitionLog.read(dir) == []
  end

  test "work order stripped of origin_authority refuses before any transition lands", %{dir: dir} do
    root = wo("ROOT")

    # The receipt is built from the full root: reconcile computes
    # definition_digest/1 of the WORK ORDER first and refuses there, so the
    # receipt's contents never matter for this refusal path.
    assert {:error, {:refused, {:refused_work_order, {:missing_required_field, "origin_authority"}}}} =
             Reconciler.reconcile(Map.delete(root, "origin_authority"), receipt(root), dir)

    assert TransitionLog.read(dir) == []
  end

  test "failed court is refused", %{dir: dir} do
    root = wo("ROOT")
    r = put_in(receipt(root), ["evidence", "court_results", "ci", "passed"], false)

    assert {:error, {:refused, {:promotion_refused, [:courts]}}} =
             Reconciler.reconcile(root, r, dir)
  end
end
