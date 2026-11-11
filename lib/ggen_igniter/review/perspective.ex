defmodule GgenIgniter.Review.Perspective do
  @moduledoc """
  The review-perspective behaviour: one `review_diff/2` per lens over a diff.

  Agent execution is out of scope for this layer (the LLM reviewer agents are
  L1's concern). Perspectives are therefore PURE functions over structured
  input: the diff text plus `opts` carrying structured findings, attributions,
  and round context — so tests drive real data and the aggregation core is
  falsifiable without an agent in the loop.

  Registry: `perspectives/0` pins the four shipped lenses; `GgenIgniter.Review`
  fans out over it with `Task.async_stream`.
  """

  @callback review_diff(diff_text :: String.t(), opts :: keyword()) :: [
              GgenIgniter.Review.Finding.t()
            ]

  @doc "The pinned perspective implementations, as {name, module} pairs."
  @spec perspectives() :: [{atom(), module()}]
  def perspectives do
    [
      {:correctness, GgenIgniter.Review.Perspectives.Correctness},
      {:invariants, GgenIgniter.Review.Perspectives.Invariants},
      {:chicago_tests, GgenIgniter.Review.Perspectives.ChicagoTests},
      {:epoch_law, GgenIgniter.Review.Perspectives.EpochLaw}
    ]
  end

  @doc "Runs one perspective module, normalizing raise to a typed result."
  @spec run(module(), String.t(), keyword()) :: {:ok, [GgenIgniter.Review.Finding.t()]}
  def run(module, diff_text, opts) do
    {:ok, module.review_diff(diff_text, opts)}
  end
end
