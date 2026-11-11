defmodule Mix.Tasks.GgenIgniter.ReviewEval.Run do
  @moduledoc """
  Run the incident-eval corpus against the reviewer.

      mix ggen_igniter.review_eval.run [--reviewer-cmd "claude"]

  Uses the default `claude -p` adapter unless overridden. Writes a run
  receipt under `.ggen_igniter/review-evals/run-<ts>-<head7>/receipt.json`
  — always, even on REGRESSED.
  """
  use Mix.Task

  alias GgenIgniter.ReviewEval.{CaseRunner, Corpus, Receipt, Scorer}

  @shortdoc "Run the reviewer incident-eval corpus"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: [])

    with {:ok, cases} <- Corpus.load(".") do
      corpus_digest = Corpus.digest(".")
      prompt_sha = prompt_sha()

      adjudicated =
        cases
        |> Enum.map(fn case ->
          run_case = CaseRunner.run(case, Keyword.merge(opts, repo_root: "."))

          adj =
            case run_case.status do
              :ok -> Scorer.adjudicate(case, run_case.findings)
              # fail-closed: reviewer unavailable/error counts as missed-error
              _ -> %{verdict: :error, match_evidence: inspect(run_case.status), fp_findings: 0}
            end

          adj
          |> Map.put(:case_id, case["case_id"])
          |> Map.put(:duration_ms, Map.get(run_case, :duration_ms, 0))
        end)

      {:ok, path, receipt} =
        Receipt.write_run(
          repo_root: ".",
          corpus_digest: corpus_digest,
          reviewer_prompt_sha: prompt_sha,
          adjudicated: adjudicated
        )

      Mix.shell().info("run receipt: #{path}")
      Mix.shell().info("score: #{receipt["score"] |> Jason.encode!()}")
      Mix.shell().info("verdict: #{receipt["verdict"]}")
    end
  end

  defp prompt_sha do
    path = Path.expand(".claude/agents/ggen-reviewer.md", File.cwd!())

    content = if File.exists?(path), do: File.read!(path), else: ""
    Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end
end
