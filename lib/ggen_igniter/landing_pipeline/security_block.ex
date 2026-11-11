defmodule GgenIgniter.LandingPipeline.Stage.SecurityBlock do
  @moduledoc """
  Stage 5 (`:security_block`) — security gate. Thin adapter over
  `GgenIgniter.SecurityReview.run/2` with `write: false` (receipt computed,
  ledger untouched — the pipeline's own receipt is the landing record), fed
  by `GgenIgniter.SecurityReview.DiffSource`'s base resolution against
  `ctx.base_sha` (a 40-hex sha, which is exactly the format DiffSource's
  `--base` path requires). Open findings → `{:block, ...}`; clean →
  `:pass`. The `:pass` embeds a real `git diff --stat <base>` capture
  alongside the in-process review — a vacuous pass blocks by design.

  A `SECURITY_REVIEW_DIFF_UNAVAILABLE` refusal propagates as `:refused` —
  the gate never fabricates a diff from a guessed ref.
  """

  @behaviour GgenIgniter.LandingPipeline.Stage

  alias GgenIgniter.LandingPipeline.Stage

  @impl true
  def name, do: :security_block

  @impl true
  def order, do: 5

  @impl true
  @spec run(Stage.t()) ::
          {:pass, map()} | {:block, term(), map()} | {:refused, term()}
  def run(%Stage{} = ctx) do
    stat = Stage.capture("git", ["diff", "--stat", ctx.base_sha])

    case GgenIgniter.SecurityReview.run(base: ctx.base_sha, write: false) do
      {:ok, %{status: :clear, findings: findings, receipt: receipt}} ->
        {:pass,
         %{
           "output" => %{"commands" => [stat]},
           "security_receipt" => receipt,
           "findings" => length(findings)
         }}

      {:ok, %{status: :blocked, findings: findings, receipt: receipt}} ->
        {:block, {:security_findings_open, length(findings)},
         %{"output" => %{"commands" => [stat]}, "security_receipt" => receipt}}

      {:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, detail}} ->
        {:refused, {:security_diff_unavailable, detail}}
    end
  end
end
