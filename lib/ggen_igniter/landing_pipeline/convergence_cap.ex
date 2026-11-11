defmodule GgenIgniter.LandingPipeline.Stage.ConvergenceCap do
  @moduledoc """
  Stage 6 (`:convergence_cap`) — bounded review-convergence gate. A real
  `mix ggen_igniter.review.convergence --sha <worktree_sha> --json`
  subprocess over `GgenIgniter.Convergence.run/2`'s round state machine
  (terminal states are final — no round 4 ever). Exit-code mapping per that
  task's contract: 0 (passed) → `:pass`; 1 (escalated — review findings did
  not converge within the cap) → `:block`; 2 (bad invocation) → `:refused`.
  The `:pass` embeds the real captured task output — a vacuous pass blocks
  by design.
  """

  @behaviour GgenIgniter.LandingPipeline.Stage

  alias GgenIgniter.LandingPipeline.Stage

  @impl true
  def name, do: :convergence_cap

  @impl true
  def order, do: 6

  @impl true
  @spec run(Stage.t()) ::
          {:pass, map()} | {:block, term(), map()} | {:refused, term()}
  def run(%Stage{} = ctx) do
    capture =
      Stage.capture("mix", [
        "ggen_igniter.review.convergence",
        "--sha",
        ctx.worktree_sha,
        "--max-rounds",
        "1",
        "--json"
      ])

    case capture["exit"] do
      0 -> {:pass, %{"output" => %{"commands" => [capture]}}}
      1 -> {:block, {:review_escalated, capture["exit"]}, %{"output" => %{"commands" => [capture]}}}
      2 -> {:refused, {:convergence_invocation_failed, capture["stdout_tail"]}}
      other -> {:refused, {:convergence_unexpected_exit, other, capture["stdout_tail"]}}
    end
  end
end
