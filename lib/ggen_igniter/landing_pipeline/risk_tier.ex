defmodule GgenIgniter.LandingPipeline.Stage.RiskTier do
  @moduledoc """
  Stage 2 (`:risk_tier`) — deterministic change classification. Thin adapter
  over `GgenIgniter.Review.RiskTier.classify/1` fed by a real
  `git diff --name-status <base>` capture. Stage order is load-bearing: this
  runs BEFORE `FanoutReview` (order 4) so review width is chosen only after
  the change is classified — a high-risk diff can never select its own
  reviewers.

  `classify/1` is total over the parsed change list, so the stage can only
  `:pass` (with tier/score/approvals embedded) or `:refuse` when the
  underlying git capture itself fails. The `:pass` embeds the real captured
  `git diff --name-status` output — a vacuous pass blocks by design
  (`GgenIgniter.LandingPipeline`'s realness law).
  """

  @behaviour GgenIgniter.LandingPipeline.Stage

  alias GgenIgniter.LandingPipeline.Stage

  @impl true
  def name, do: :risk_tier

  @impl true
  def order, do: 2

  @impl true
  @spec run(Stage.t()) ::
          {:pass, map()} | {:block, term(), map()} | {:refused, term()}
  def run(%Stage{} = ctx) do
    capture = Stage.capture("git", ["diff", "--name-status", ctx.base_sha])

    if capture["exit"] != 0 do
      {:refused, {:risk_tier_git_failed, capture["command"], capture["stdout_tail"]}}
    else
      changes = parse_name_status(capture["stdout_tail"])
      assessment = GgenIgniter.Review.RiskTier.classify(changes)

      {:pass,
       %{
         "output" => %{"commands" => [capture]},
         "tier" => to_string(assessment.tier),
         "score" => assessment.score,
         "approvals" => assessment.approvals
       }}
    end
  end

  # `git diff --name-status` lines: `M\tlib/foo.ex`, `A\tx`, `D\ty`,
  # `R100\told\tnew` (rename scores both paths). Unknown statuses map to
  # :modified — classification is deterministic, never crashy.
  defp parse_name_status(tail) do
    tail
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 2) do
        [status, path] -> [%{path: path, kind: kind(status)}]
        _ -> []
      end
    end)
  end

  defp kind("A"), do: :added
  defp kind("D"), do: :deleted
  defp kind(_), do: :modified
end
