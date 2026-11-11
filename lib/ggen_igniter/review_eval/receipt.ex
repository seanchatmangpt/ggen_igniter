defmodule GgenIgniter.ReviewEval.Receipt do
  @moduledoc """
  Run receipts for the incident-eval harness:
  `.ggen_igniter/review-evals/run-<ts>-<head7>/receipt.json`.

  A run receipt is ALWAYS written, even when the overall verdict is REGRESSED
  (a regressed run without a receipt would be unfalsifiable).
  """

  alias GgenIgniter.ReviewEval.Corpus

  @doc """
  Build and write the run receipt. `case_results` is a list of
  `%{case_id:, status:, findings:}` from the CaseRunner, already adjudicated
  into `%{verdict: :caught|:missed|:error, match_evidence:, fp_findings:}`.
  """
  def write_run(opts) do
    repo_root = Keyword.fetch!(opts, :repo_root)
    corpus_digest = Keyword.fetch!(opts, :corpus_digest)
    reviewer_prompt_sha = Keyword.fetch!(opts, :reviewer_prompt_sha)
    adjudicated = Keyword.fetch!(opts, :adjudicated)

    head = head_sha(repo_root)
    ts = Calendar.strftime(DateTime.utc_now(), "%Y%m%dT%H%M%SZ")

    run_id = "run-#{ts}-#{String.slice(head, 0, 7)}"

    score = %{
      caught: count_verdict(adjudicated, :caught),
      missed: count_verdict(adjudicated, :missed),
      error: count_verdict(adjudicated, :error),
      recall: recall(adjudicated),
      fp_findings: Enum.sum(Enum.map(adjudicated, & &1.fp_findings)),
      duration_ms: Enum.sum(Enum.map(adjudicated, &Map.get(&1, :duration_ms, 0)))
    }

    receipt = %{
      "run_id" => run_id,
      "head_sha" => head,
      "corpus_digest" => corpus_digest,
      "reviewer_prompt_sha" => reviewer_prompt_sha,
      "per_case" =>
        Enum.map(adjudicated, fn a ->
          %{
            "case_id" => a.case_id,
            "verdict" => Atom.to_string(a.verdict),
            "match_evidence" => Map.get(a, :match_evidence),
            "fp_findings" => Map.get(a, :fp_findings, 0)
          }
        end),
      "score" => score,
      "verdict" => verdict_word(adjudicated)
    }

    dir = Path.join([Corpus.base_dir(repo_root), run_id])
    File.mkdir_p!(dir)
    path = Path.join(dir, "receipt.json")
    File.write!(path, Jason.encode!(receipt, pretty: true) <> "\n")
    {:ok, path, receipt}
  end

  defp verdict_word(adjudicated) do
    errors = count_verdict(adjudicated, :error)

    if errors > 0 do
      "REGRESSED"
    else
      "ADMITTED"
    end
  end

  @doc "Recall over adjudicated results: errors count as missed (fail-closed)."
  def recall(adjudicated) do
    total = length(adjudicated)

    if total == 0 do
      0.0
    else
      caught = count_verdict(adjudicated, :caught)
      caught / total
    end
  end

  defp count_verdict(adjudicated, v), do: Enum.count(adjudicated, &(&1.verdict == v))

  defp head_sha(root) do
    {out, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true)
    String.trim_trailing(out)
  end
end
