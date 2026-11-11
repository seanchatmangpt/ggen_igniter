defmodule GgenIgniter.LandingPipeline.Stage.IncidentEval do
  @moduledoc """
  Stage 7 (`:incident_eval`) — incident-eval admission gate. Thin adapter
  over `GgenIgniter.ReviewEval.Gate.admit/1`: the candidate run receipt
  (from `mix ggen_igniter.review_eval.run`) is adjudicated against the
  sealed baseline at `.ggen_igniter/review-evals/baseline.json` (admit iff
  candidate recall >= baseline recall AND no per-surface recall drops beyond
  tolerance). `{:ok, :admitted}` → `:pass`; `{:refuse, ...}` → `:block`;
  `{:error, ...}` (missing baseline/receipt — exit-2 class) → `:refused`.

  Without `opts[:run_receipt]` the stage REFUSES — it cannot judge without
  a candidate receipt, and judging nothing is not a pass. A `:pass` embeds a
  real `git rev-parse HEAD` capture — a vacuous pass blocks by design.
  """

  @behaviour GgenIgniter.LandingPipeline.Stage

  alias GgenIgniter.LandingPipeline.Stage

  @impl true
  def name, do: :incident_eval

  @impl true
  def order, do: 7

  @impl true
  @spec run(Stage.t()) ::
          {:pass, map()} | {:block, term(), map()} | {:refused, term()}
  def run(%Stage{} = ctx) do
    run_receipt = ctx.opts[:run_receipt]

    unless is_binary(run_receipt) and run_receipt != "" do
      {:refused, {:no_run_receipt, "opts[:run_receipt] must name the candidate review-eval receipt"}}
    else
      unless File.exists?(run_receipt) do
        {:refused, {:run_receipt_unreadable, run_receipt}}
      else
        receipt = Jason.decode!(File.read!(run_receipt))
        head = Stage.capture("git", ["rev-parse", "HEAD"])

        case GgenIgniter.ReviewEval.Gate.admit(repo_root: File.cwd!(), run_receipt: receipt) do
          {:ok, :admitted, details} ->
            {:pass,
             %{
               "output" => %{"commands" => [head]},
               "admit_details" => %{"baseline_recall" => details[:baseline_recall], "candidate_recall" => details[:candidate_recall]}
             }}

          {:refuse, reason, details} ->
            {:block, {:eval_refused, reason},
             %{"output" => %{"commands" => [head]}, "admit_details" => inspect(details)}}

          {:error, reason} ->
            {:refused, {:eval_gate_error, reason}}
        end
      end
    end
  end
end
