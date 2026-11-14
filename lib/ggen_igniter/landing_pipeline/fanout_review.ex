defmodule GgenIgniter.LandingPipeline.Stage.FanoutReview do
  @moduledoc """
  Stage 4 (`:fanout_review`) — fan-out review gate. A real
  `mix ggen_igniter.review --base <base_sha> --json` subprocess, delegating
  100% to `GgenIgniter.Review` (perspectives → verifiers → tally → store).
  Exit-code mapping per that task's contract: 0 (no POSTED findings) →
  `:pass`; 1 (posted findings remain, or a typed refusal such as bad diff
  refs) → `:block`; 2 (bad invocation) → `:refused`. The `:pass` embeds the
  real captured task output — a vacuous pass blocks by design.

  Order note: this stage runs AFTER `RiskTier` (order 2) so the review width
  is chosen only after classification — see the pipeline moduledoc.
  """

  @behaviour GgenIgniter.LandingPipeline.Stage

  alias GgenIgniter.LandingPipeline.Stage

  @impl true
  def name, do: :fanout_review

  @impl true
  def order, do: 4

  @impl true
  @spec run(Stage.t()) ::
          {:pass, map()} | {:block, term(), map()} | {:refused, term()}
  def run(%Stage{} = ctx) do
    capture =
      Stage.capture("mix", ["ggen_igniter.review", "--base", ctx.base_sha, "--json"])

    case capture["exit"] do
      0 ->
        {:pass, %{"output" => %{"commands" => [capture]}}}

      1 ->
        {:block, {:review_findings_posted, capture["exit"]},
         %{"output" => %{"commands" => [capture]}}}

      2 ->
        {:refused, {:review_invocation_failed, capture["stdout_tail"]}}

      other ->
        {:refused, {:review_unexpected_exit, other, capture["stdout_tail"]}}
    end
  end
end
