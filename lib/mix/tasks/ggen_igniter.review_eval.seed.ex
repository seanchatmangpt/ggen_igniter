defmodule Mix.Tasks.GgenIgniter.ReviewEval.Seed do
  @moduledoc """
  Seed the incident-eval corpus from git history (fix/revert mining).

      mix ggen_igniter.review_eval.seed [--force] [--min-conf 0.5] [--max 50]

  Deterministic for a given HEAD; refuses to overwrite an existing corpus
  without `--force`. Writes a seed receipt under
  `.ggen_igniter/review-evals/seeds/`.
  """
  use Mix.Task

  alias GgenIgniter.ReviewEval.Seed

  @shortdoc "Seed the reviewer incident-eval corpus from git history"
  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} =
      OptionParser.parse!(args,
        strict: [force: :boolean, min_conf: :float, max: :integer]
      )

    kw = [
      force: Keyword.get(opts, :force, false),
      min_conf: Keyword.get(opts, :min_conf, 0.5),
      max: Keyword.get(opts, :max, 50)
    ]

    case Seed.run(kw) do
      {:ok, receipt} ->
        Mix.shell().info("corpus seeded: #{receipt["counts"] |> Jason.encode!()}")
        Mix.shell().info("digest: #{receipt["corpus_digest"]}")

      {:error, {:corpus_exists, path}} ->
        Mix.raise("corpus already exists at #{path} (use --force to overwrite)")
    end
  end
end
