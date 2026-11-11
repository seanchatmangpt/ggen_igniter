defmodule GgenIgniterReviewConvergenceStoreTest do
  @moduledoc "Chicago-style: real tmp dirs under System.tmp_dir!() (unique per test), real rounds.jsonl append logs, real GgenIgniter.Lock serialization, real Digest.sha256 line hashes — no mocks. async: false: each test owns a unique tmp root but the file asserts against real disk state. NOTE: lane L2 simultaneously landed test/ggen_igniter_review_store_test.exs for ITS GgenIgniter.Review.Store; this file is lane L4's store for GgenIgniter.ReviewStore (rounds.jsonl per content-sha) and the two are deliberately distinct modules with distinct files."
  use ExUnit.Case, async: false

  alias GgenIgniter.Digest
  alias GgenIgniter.ReviewStore

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "review-store-l4-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    Process.put(:l4_tmp, tmp_dir)
    {:ok, base: tmp_dir}
  end

  defp record(round, state \\ :round_passed) do
    %{
      sha: "sha-x",
      round: round,
      state: state,
      decision: :pass,
      reviewed_scope: :full,
      hunks_reviewed: [%{"file" => "a.ex", "hunk_id" => "sha256:aa"}],
      findings_open: [],
      findings_carried: [],
      findings_new: [],
      findings_cleared: [],
      class_fixed_globally: [],
      rounds_to_pass: round,
      receipt_hash: nil,
      ts: "2026-10-20T00:00:0#{round}Z"
    }
  end

  describe "append_round!/3 + read_rounds/2" do
    test "append + read round-trip with line_hash verification" do
      base = base_from_ctx()
      ReviewStore.append_round!(base, "sha-x", record(1))
      ReviewStore.append_round!(base, "sha-x", record(2))

      path = ReviewStore.rounds_path(base, "sha-x")
      assert String.contains?(path, ".ggen_igniter/reviews/sha-x/rounds.jsonl")
      assert File.exists?(path)

      [r1, r2] = ReviewStore.read_rounds(base, "sha-x")
      assert r1["round"] == 1
      assert r2["round"] == 2
      assert r1["line_hash_valid"] == true
      assert r2["line_hash_valid"] == true
      assert String.starts_with?(r1["line_hash"], "sha256:")
    end

    test "line_hash is a real Digest.sha256 over the line minus the hash" do
      base = base_from_ctx()
      stamped = ReviewStore.append_round!(base, "sha-x", record(1))

      expected =
        stamped
        |> Map.drop(["line_hash"])
        |> Enum.sort_by(fn {k, _} -> k end)
        |> Enum.into(%{})
        |> Jason.encode!()
        |> Digest.sha256()

      assert stamped["line_hash"] == expected
    end

    test "append is exclusive — prior lines never rewritten or truncated" do
      base = base_from_ctx()
      ReviewStore.append_round!(base, "sha-x", record(1))
      first = File.read!(ReviewStore.rounds_path(base, "sha-x"))

      ReviewStore.append_round!(base_from_ctx(), "sha-x", record(2))
      second = File.read!(ReviewStore.rounds_path(base, "sha-x"))

      assert String.starts_with?(second, first)
    end

    test "partial-line tolerance: torn trailing line skipped, good lines survive, store still appends" do
      base = base_from_ctx()
      ReviewStore.append_round!(base, "sha-x", record(1))
      path = ReviewStore.rounds_path(base, "sha-x")

      File.write!(path, File.read!(path) <> ~s({"round": 2, "state": "rou))

      [r1] = ReviewStore.read_rounds(base, "sha-x")
      assert r1["round"] == 1

      ReviewStore.append_round!(base, "sha-x", record(3))
      rounds = ReviewStore.read_rounds(base, "sha-x")
      assert Enum.map(rounds, & &1["round"]) == [1, 3]
    end

    test "tampered line is flagged line_hash_valid=false, never silently dropped" do
      base = base_from_ctx()
      ReviewStore.append_round!(base, "sha-x", record(1))
      path = ReviewStore.rounds_path(base, "sha-x")

      tampered =
        File.read!(path)
        |> String.replace(~s("decision":"pass"), ~s("decision":"escalate"))

      File.write!(path, tampered)

      [r1] = ReviewStore.read_rounds(base, "sha-x")
      assert r1["line_hash_valid"] == false
    end
  end

  describe "diff snapshots + terminal summary" do
    test "snapshot_diff! lands at diff/<round>.patch byte-exact" do
      base = base_from_ctx()

      path = ReviewStore.snapshot_diff!(base, "sha-x", 2, "diff --git a/x b/x\n@@ -1 +1 @@\n")

      assert path == ReviewStore.diff_path(base, "sha-x", 2)
      assert File.read!(path) == "diff --git a/x b/x\n@@ -1 +1 @@\n"
    end

    test "summary.json written at terminal state and read back; nil before" do
      base = base_from_ctx()

      assert ReviewStore.read_summary(base, "sha-x") == nil

      ReviewStore.write_summary!(base, "sha-x", %{
        "final_state" => "round_passed",
        "rounds" => 2
      })

      assert %{"final_state" => "round_passed", "rounds" => 2} =
               ReviewStore.read_summary(base, "sha-x")
    end

    test "reads return [] / nil honestly when nothing exists" do
      base = base_from_ctx()
      assert ReviewStore.read_rounds(base, "nope") == []
      assert ReviewStore.read_summary(base, "nope") == nil
    end
  end

  # -- helpers --

  defp base_from_ctx(), do: Process.get(:l4_tmp) || raise("no tmp base: run via setup")
end
