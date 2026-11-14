defmodule GgenIgniter.ReviewEval.GateTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Chicago-style: real synthetic git repo fixture (real git commands), real
  corpus files on disk, real receipts read back from disk. Covers seeding
  determinism + refuse-overwrite, baseline sealing, admit/refuse/exit-2
  classes.
  """

  alias GgenIgniter.ReviewEval.{Corpus, Gate, Seed}
  alias GgenIgniter.TestSupport.ReviewEvalFixture

  setup do
    fx = ReviewEvalFixture.build!("gate")
    on_exit(fn -> ReviewEvalFixture.destroy!(fx) end)
    {:ok, fx: fx}
  end

  defp receipt_dir(fx, run_id),
    do: Path.join([Corpus.base_dir(fx.root), run_id])

  defp write_run_receipt(fx, run_id, score, per_surface \\ %{}) do
    dir = receipt_dir(fx, run_id)
    File.mkdir_p!(dir)

    receipt = %{
      "run_id" => run_id,
      "head_sha" => fx.fix_sha,
      "corpus_digest" => Corpus.digest(fx.root),
      "score" => score,
      "per_surface" => per_surface
    }

    path = Path.join(dir, "receipt.json")
    File.write!(path, Jason.encode!(receipt))
    path
  end

  describe "Seed.run/1" do
    test "mines fix + revert commits deterministically (same HEAD, byte-identical corpus)", %{
      fx: fx
    } do
      {:ok, r1} = Seed.run(repo_root: fx.root, force: true)
      bytes1 = File.read!(Corpus.corpus_path(fx.root))
      {:ok, _r2} = Seed.run(repo_root: fx.root, force: true)
      bytes2 = File.read!(Corpus.corpus_path(fx.root))

      assert bytes1 == bytes2
      assert r1["counts"]["git_fix_commit"] >= 1
      assert r1["counts"]["git_revert_receipt"] >= 1
    end

    test "seeded cases carry real shas and derived locations", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)
      {:ok, cases} = Corpus.load(fx.root)

      assert length(cases) >= 2
      fix_case = Enum.find(cases, &(&1["source"]["kind"] == "git_fix_commit"))
      assert fix_case["diff_ref"]["fix_sha"] == fx.fix_sha
      assert fix_case["diff_ref"]["parent_sha"] == fx.defect_sha
      assert fix_case["location"]["file"] == fx.defect_file
      assert fix_case["location"]["line"] == fx.defect_line
      assert fix_case["schema_version"] == 1
    end

    test "refuses overwrite without --force", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)
      assert {:error, {:corpus_exists, path}} = Seed.run(repo_root: fx.root)
      assert String.ends_with?(path, "corpus.jsonl")
    end

    test "seeds a receipt file under seeds/", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)
      files = Path.wildcard(Path.join([Corpus.base_dir(fx.root), "seeds", "*-seed.json"]))
      assert files != []
    end
  end

  describe "Gate.seal/1" do
    test "seals a run whose receipt exists, digest matches, head is ancestor", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)
      run_id = "run-test-#{String.slice(fx.fix_sha, 0, 7)}"
      write_run_receipt(fx, run_id, %{"recall" => 0.5})

      assert {:ok, baseline} = Gate.seal(repo_root: fx.root, run_id: run_id)
      assert baseline["recall"] == 0.5
      assert baseline["run_id"] == run_id
      assert File.exists?(Gate.baseline_path(fx.root))
    end

    test "refuses (exit-2 class) when the run receipt is missing", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)

      assert {:error, {:run_receipt_missing, _}} =
               Gate.seal(repo_root: fx.root, run_id: "run-does-not-exist")
    end

    test "refuses when the corpus digest changed after the run", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)
      run_id = "run-test-stale"
      write_run_receipt(fx, run_id, %{"recall" => 0.5})
      # mutate the corpus after the receipt was written
      Corpus.write([], fx.root)

      assert {:error, {:corpus_digest_changed, _}} =
               Gate.seal(repo_root: fx.root, run_id: run_id)
    end
  end

  describe "Gate.admit/1" do
    test "missing baseline is the exit-2 class", %{fx: fx} do
      receipt = %{"score" => %{"recall" => 1.0}}

      assert {:error, {:no_baseline, _}} =
               Gate.admit(repo_root: fx.root, run_receipt: receipt)
    end

    test "corpus digest changed since seal -> refuse, not admit", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)
      write_run_receipt(fx, "run-base", %{"recall" => 0.5})
      {:ok, _} = Gate.seal(repo_root: fx.root, run_id: "run-base")

      Corpus.write([], fx.root)
      candidate = %{"score" => %{"recall" => 0.5}, "per_surface" => %{}}

      assert {:refuse, :corpus_digest_changed, _} =
               Gate.admit(repo_root: fx.root, run_receipt: candidate)
    end

    test "recall at baseline -> admitted", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)
      write_run_receipt(fx, "run-base", %{"recall" => 0.5})
      {:ok, _} = Gate.seal(repo_root: fx.root, run_id: "run-base")

      candidate = %{"score" => %{"recall" => 0.5}, "per_surface" => %{}}

      assert {:ok, :admitted, %{baseline_recall: 0.5, candidate_recall: 0.5}} =
               Gate.admit(repo_root: fx.root, run_receipt: candidate)
    end

    test "recall below baseline -> refused", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)
      write_run_receipt(fx, "run-base", %{"recall" => 0.5})
      {:ok, _} = Gate.seal(repo_root: fx.root, run_id: "run-base")

      candidate = %{"score" => %{"recall" => 0.0}, "per_surface" => %{}}

      assert {:refuse, {:recall_regression, _}, _} =
               Gate.admit(repo_root: fx.root, run_receipt: candidate)
    end

    test "per-surface drop beyond tolerance -> refused even at parity recall", %{fx: fx} do
      {:ok, _} = Seed.run(repo_root: fx.root, force: true)

      write_run_receipt(fx, "run-base", %{"recall" => 0.5}, %{"thing" => 1.0})
      {:ok, _} = Gate.seal(repo_root: fx.root, run_id: "run-base")

      # same overall recall but surface "thing" collapsed
      candidate = %{"score" => %{"recall" => 0.5}, "per_surface" => %{"thing" => 0.0}}

      assert {:refuse, {:surface_recall_drop, "thing", drop}, _} =
               Gate.admit(repo_root: fx.root, run_receipt: candidate, surface_tolerance: 0)

      assert drop >= 1
    end
  end
end
