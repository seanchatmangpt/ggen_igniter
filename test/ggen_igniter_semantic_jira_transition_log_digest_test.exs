defmodule GgenIgniter.SemanticJiraTransitionLogDigestTest do
  @moduledoc """
  Chicago, no doubles: a real file-backed log in a scratch directory, real
  digests, assertions on the digests and files that result.

  Contract: a transition event's `event_digest` commits to the receipt it cites
  and can be re-derived from the stored event alone.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Reconciler, TransitionLog}

  @sha String.duplicate("a", 40)

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_digest_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp digest(seed), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, seed), case: :lower)

  defp event(receipt_seed, transition_seed \\ "transition") do
    %{
      "kind" => "standing_transition_event",
      "identity" => "ROOT",
      "definition_digest" => digest("definition"),
      "snapshot_digest" => digest("snapshot"),
      "from" => "UNKNOWN",
      "to" => "ALIVE",
      "receipt_digest" => digest(receipt_seed),
      "transition_digest" => digest(transition_seed),
      "authority" => "NONE"
    }
  end

  test "digest_exact keeps the reserved digest keys that digest/1 drops" do
    a = event("receipt-a")
    b = event("receipt-b")

    assert SemanticJira.digest(a) == SemanticJira.digest(b)
    refute SemanticJira.digest_exact(a) == SemanticJira.digest_exact(b)
    refute SemanticJira.digest_exact(a) == SemanticJira.digest(a)
  end

  test "two events that differ only in the cited receipt get distinct digests and both land",
       %{dir: dir} do
    assert {:ok, first, :appended} = TransitionLog.append(dir, event("receipt-a"))
    assert {:ok, second, :appended} = TransitionLog.append(dir, event("receipt-b"))

    refute first["event_digest"] == second["event_digest"]
    assert first["receipt_digest"] == digest("receipt-a")
    assert second["receipt_digest"] == digest("receipt-b")

    assert dir |> TransitionLog.read() |> Enum.map(& &1["receipt_digest"]) ==
             [digest("receipt-a"), digest("receipt-b")]
  end

  test "two events that differ only in the cited transition get distinct digests", %{dir: dir} do
    assert {:ok, first, :appended} = TransitionLog.append(dir, event("r", "transition-a"))
    assert {:ok, second, :appended} = TransitionLog.append(dir, event("r", "transition-b"))
    refute first["event_digest"] == second["event_digest"]
  end

  test "the very same event is still idempotent", %{dir: dir} do
    assert {:ok, first, :appended} = TransitionLog.append(dir, event("receipt-a"))
    assert {:ok, again, :already_recorded} = TransitionLog.append(dir, event("receipt-a"))
    assert again == first
    assert length(TransitionLog.read(dir)) == 1
  end

  test "a stored event re-derives, and a swapped citation on disk does not", %{dir: dir} do
    assert {:ok, _, :appended} = TransitionLog.append(dir, event("receipt-a"))
    [stored] = TransitionLog.read(dir)

    assert stored["event_digest"] == TransitionLog.event_digest(stored)

    swapped = Map.put(stored, "receipt_digest", digest("receipt-b"))
    refute swapped["event_digest"] == TransitionLog.event_digest(swapped)

    swapped = Map.put(stored, "transition_digest", digest("transition-b"))
    refute swapped["event_digest"] == TransitionLog.event_digest(swapped)
  end

  test "the legacy derivation is not the current one for a cited-digest event" do
    stored = Map.put(event("receipt-a"), "event_digest", "sha256:0")

    refute TransitionLog.legacy_event_digest(stored) == TransitionLog.event_digest(stored)

    assert TransitionLog.legacy_event_digest(stored) ==
             SemanticJira.digest(Map.drop(stored, ["seq", "event_digest"]))
  end

  test "Reconciler events re-derive from their own content", %{dir: dir} do
    work_order = %{
      "identity" => "ROOT",
      "title" => "ROOT",
      "description" => "d",
      "subject" => "subj-ROOT",
      "repository" => "o/r",
      "base_sha" => @sha,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "observed",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid-ROOT",
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"]
    }

    {:ok, definition} = SemanticJira.definition_digest(work_order)
    {:ok, admitted} = SemanticJira.admit_work_order(work_order)

    receipt = %{
      "definition_digest" => definition,
      "snapshot_digest" => admitted["work_order_digest"],
      "target" => "ALIVE",
      "evidence" => %{
        "subject" => "subj-ROOT",
        "repository" => "o/r",
        "base_sha" => @sha,
        "evidence_types" => ["exec"],
        "court_results" => %{"ci" => %{"passed" => true}},
        "acceptance_results" => %{"a1" => true},
        "falsifier_results" => %{"f1" => "survived"},
        "receipt_classes" => [],
        "evidence_ceiling" => "observed",
        "observed_execution" => true
      }
    }

    assert {:ok, event, :appended} = Reconciler.reconcile(work_order, receipt, dir)
    assert event["event_digest"] == TransitionLog.event_digest(event)
    assert event["receipt_digest"] == SemanticJira.digest(receipt)
  end
end
