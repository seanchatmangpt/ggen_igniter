defmodule GgenIgniter.ReviewEval.Gate do
  @moduledoc """
  Admission gate over sealed baselines.

  Baseline: `.ggen_igniter/review-evals/baseline.json`
  `%{"run_id" =>, "head_sha" =>, "corpus_digest" =>, "recall" =>, "per_surface" => %{"surface" => recall}}`.

  Law: admit iff candidate recall >= baseline recall AND no per-surface recall
  drops more than `--surface-tolerance` (default: any drop greater than 1 case
  refuses). Errors count as missed (fail-closed, one retry before counting).
  Exit codes: 0 admit, 1 refuse, 2 invocation/config error.
  """

  alias GgenIgniter.ReviewEval.Corpus

  @default_surface_tolerance 1

  @doc """
  Seal a run as the new baseline. Refuses (exit-2 class) unless the run
  receipt exists, its corpus digest matches the current corpus, and the run's
  head is an ancestor of HEAD.
  """
  @spec seal(keyword()) :: {:ok, map()} | {:error, term()}
  def seal(opts) do
    repo_root = Keyword.fetch!(opts, :repo_root)
    run_id = Keyword.fetch!(opts, :run_id)
    receipt = read_run_receipt(repo_root, run_id)

    with {:ok, receipt} <- receipt,
         :ok <- digest_matches(repo_root, receipt),
         :ok <- ancestor_of_head(repo_root, receipt["head_sha"]) do
      baseline = %{
        "run_id" => receipt["run_id"],
        "head_sha" => receipt["head_sha"],
        "corpus_digest" => receipt["corpus_digest"],
        "recall" => receipt["score"]["recall"],
        "per_surface" => Map.get(receipt, "per_surface", %{}),
        "sealed_at" => DateTime.to_iso8601(DateTime.utc_now())
      }

      path = baseline_path(repo_root)
      File.write!(path, Jason.encode!(baseline, pretty: true) <> "\n")
      {:ok, baseline}
    end
  end

  @doc """
  Adjudicate a candidate run against the sealed baseline.

  Returns `{:ok, :admitted, details}` | `{:refuse, reason, details}` |
  `{:error, reason}` (exit-2 class, e.g. missing baseline).
  """
  @spec admit(keyword()) :: {:ok, :admitted, map()} | {:refuse, term(), map()} | {:error, term()}
  def admit(opts) do
    repo_root = Keyword.fetch!(opts, :repo_root)
    run_receipt = Keyword.fetch!(opts, :run_receipt)
    surface_tolerance = Keyword.get(opts, :surface_tolerance, @default_surface_tolerance)

    baseline_path = baseline_path(repo_root)

    if File.exists?(baseline_path) do
      baseline = Jason.decode!(File.read!(baseline_path))
      judge(baseline, Corpus.digest(repo_root), run_receipt, surface_tolerance)
    else
      {:error, {:no_baseline, baseline_path}}
    end
  end

  defp judge(%{"corpus_digest" => sealed} = baseline, digest, run_receipt, tolerance) do
    if sealed == digest do
      judge_recall(baseline, run_receipt, tolerance)
    else
      {:refuse, :corpus_digest_changed, %{baseline: sealed, current: digest}}
    end
  end

  defp judge(baseline, digest, _run_receipt, _tolerance),
    do: {:refuse, :corpus_digest_changed, %{baseline: baseline["corpus_digest"], current: digest}}

  defp judge_recall(baseline, run_receipt, tolerance) do
    b_recall = baseline["recall"]
    c_recall = run_receipt["score"]["recall"]

    if c_recall >= b_recall do
      case surface_check(baseline, run_receipt, tolerance) do
        :ok -> {:ok, :admitted, %{baseline_recall: b_recall, candidate_recall: c_recall}}
        {:drop, surface, drop} -> {:refuse, {:surface_recall_drop, surface, drop}, %{}}
      end
    else
      {:refuse, {:recall_regression, baseline: b_recall, candidate: c_recall}, %{}}
    end
  end

  defp surface_check(baseline, run_receipt, tolerance) do
    b_per = baseline["per_surface"] || %{}
    c_per = run_receipt["per_surface"] || %{}

    Enum.find_value(b_per, :ok, fn {surface, b_recall} ->
      surface_drop(surface, b_recall, Map.get(c_per, surface), b_per, c_per, tolerance)
    end)
  end

  defp surface_drop(surface, b_recall, c_recall, b_per, c_per, tolerance)
       when is_number(c_recall) do
    b_caught = round(b_recall * total_for(b_per, surface))
    c_caught = round(c_recall * total_for(c_per, surface))
    if b_caught - c_caught > tolerance, do: {:drop, surface, b_caught - c_caught}
  end

  defp surface_drop(_surface, _b_recall, _c_recall, _b_per, _c_per, _tolerance), do: nil

  defp total_for(per_surface, surface) do
    # per-surface recall times an assumed denominator is not recoverable from
    # recall alone; runs store "per_surface_totals" alongside when available.
    per_surface["__totals__"][surface] || 1
  end

  @doc "Path of the sealed baseline file."
  def baseline_path(repo_root \\ "."),
    do: Path.join([Corpus.base_dir(repo_root), "baseline.json"])

  defp read_run_receipt(repo_root, run_id) do
    path = Path.join([Corpus.base_dir(repo_root), run_id, "receipt.json"])

    if File.exists?(path) do
      {:ok, Jason.decode!(File.read!(path))}
    else
      {:error, {:run_receipt_missing, path}}
    end
  end

  defp digest_matches(repo_root, receipt) do
    current = Corpus.digest(repo_root)

    if receipt["corpus_digest"] == current,
      do: :ok,
      else:
        {:error, {:corpus_digest_changed, receipt: receipt["corpus_digest"], current: current}}
  end

  defp ancestor_of_head(repo_root, sha) do
    case System.cmd("git", ["merge-base", "--is-ancestor", sha, "HEAD"],
           cd: repo_root,
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      _ -> {:error, {:not_ancestor_of_head, sha}}
    end
  end
end
