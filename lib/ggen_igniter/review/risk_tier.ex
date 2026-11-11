defmodule GgenIgniter.Review.RiskTier do
  @moduledoc """
  Deterministic risk classification of a manufactured change (diff) —
  **policy, not actuation; grants no filesystem authority** (same standing
  discipline as `GgenIgniter.SemanticEpoch`: this module only ever computes
  a tier/score/signals triple that OTHER code may consult; it never writes,
  deletes, spawns, or admits anything itself).

  Pure and deterministic at classify time: no LLM, no clock, no IO. The same
  diff always classifies to the same `%Assessment{}`, so a receipt's
  `risk_tier`/`risk_score`/`risk_approvals` fields are reproducible from the
  receipt's own `files` list after the fact.

  Consumed by `GgenIgniter.Receipt` (additive `risk_tier`/`risk_score`/
  `risk_approvals` fields) and populated at
  `GgenIgniter.Reactors.ReconcileReactor`'s three `Receipt.new/1` sites.

  ## Model

  Input: `diff` — a list of `%{path: binary(), kind: :create | :modify | :delete}`.

  * Path weights (longest-prefix match, `path_weight/1`): `"lib/"` = 4,
    `"priv/"` = 3, `".github/"` = 3, `"test/"` = 1, `"docs/"` = 0.
    **Unmatched paths default to 3 (fail-closed)** — an unknown plane is
    treated as privileged-adjacent, not as free.
  * `score` = sum of per-path weights + 5 per `lib/**/*.ex` file.
  * Tier thresholds: `score >= 10` → `:high`, `score >= 3` → `:medium`,
    else `:low`.
  * Escalation floors (only ever RAISE the tier, never lower it; each fired
    floor appends its own signal to `signals`):

    - any `.github/workflows/*` path → at least `:high`
    - any `lib/**/*.ex` path → at least `:medium`
    - 10 or more files → at least `:medium`; 25 or more → at least `:high`
    - any `:delete` under `lib/` → at least `:high`
    - empty diff → `:low`, score 0, single `:empty_diff` signal
  """

  @path_weights [
    {"lib/", 4},
    {"priv/", 3},
    {".github/", 3},
    {"test/", 1},
    {"docs/", 0}
  ]

  @default_weight 3

  @typedoc "One classified change: a path plus what happened to it."
  @type kind :: :create | :modify | :delete
  @type change :: %{path: String.t(), kind: kind()}

  @typedoc "One fired escalation/threshold signal."
  @type signal :: %{rule: atom(), detail: String.t()}

  @type tier :: :low | :medium | :high

  defstruct [:tier, :score, :approvals, :signals]

  @type t :: %__MODULE__{
          tier: tier(),
          score: non_neg_integer(),
          approvals: non_neg_integer(),
          signals: [signal()]
        }

  @tier_rank %{low: 0, medium: 1, high: 2}

  @doc """
  The path-weight table (longest-prefix match against these prefixes).
  Exposed so callers/tests can read policy without duplicating it.
  """
  @spec path_weights() :: [{String.t(), non_neg_integer()}]
  def path_weights, do: @path_weights

  @doc """
  The weight for one path: the LONGEST matching prefix from `path_weights/0`
  wins; an unmatched path defaults to `#{@default_weight}` (fail-closed).
  """
  @spec path_weight(String.t()) :: non_neg_integer()
  def path_weight(path) when is_binary(path) do
    @path_weights
    |> Enum.filter(fn {prefix, _w} -> String.starts_with?(path, prefix) end)
    |> Enum.sort_by(fn {prefix, _w} -> byte_size(prefix) end, :desc)
    |> case do
      [{_prefix, w} | _] -> w
      [] -> @default_weight
    end
  end

  @doc "Approvals required for a tier: low 0, medium 1, high 2."
  @spec approvals(tier() | t()) :: non_neg_integer()
  def approvals(%__MODULE__{tier: tier}), do: approvals(tier)
  def approvals(:low), do: 0
  def approvals(:medium), do: 1
  def approvals(:high), do: 2

  @doc """
  Classifies `diff` (list of `%{path:, kind:}`) into an
  `t:t/0` assessment. Deterministic: same input, same output, always.
  """
  @spec classify([change()]) :: t()
  def classify([]) do
    %__MODULE__{
      tier: :low,
      score: 0,
      approvals: 0,
      signals: [%{rule: :empty_diff, detail: "empty diff classified :low with score 0"}]
    }
  end

  def classify(diff) when is_list(diff) do
    score = score_diff(diff)
    count = length(diff)

    base_tier = threshold_tier(score)

    floors = [base_tier | escalation_floors(diff, count)]

    tier = Enum.reduce(floors, :low, &max_tier/2)

    signals =
      threshold_signals(base_tier, score) ++ escalation_signals(diff, count)

    %__MODULE__{tier: tier, score: score, approvals: approvals(tier), signals: signals}
  end

  # -- internals -------------------------------------------------------------

  defp score_diff(diff) do
    Enum.sum(Enum.map(diff, fn %{path: path} -> path_weight(path) end)) +
      5 * Enum.count(diff, &lib_ex?(&1.path))
  end

  defp threshold_tier(score) when score >= 10, do: :high
  defp threshold_tier(score) when score >= 3, do: :medium
  defp threshold_tier(_score), do: :low

  defp threshold_signals(:low, _score), do: []
  defp threshold_signals(tier, score),
    do: [%{rule: :score_threshold, detail: "score #{score} => #{tier}"}]

  defp escalation_floors(diff, count) do
    floors = []

    floors =
      if Enum.any?(diff, &String.starts_with?(&1.path, ".github/workflows/")),
        do: [:high | floors],
        else: floors

    floors =
      if Enum.any?(diff, &lib_ex?(&1.path)), do: [:medium | floors], else: floors

    floors =
      cond do
        count >= 25 -> [:high | floors]
        count >= 10 -> [:medium | floors]
        true -> floors
      end

    floors =
      if Enum.any?(diff, &(&1.kind == :delete and String.starts_with?(&1.path, "lib/"))),
        do: [:high | floors],
        else: floors

    floors
  end

  defp escalation_signals(diff, count) do
    signals = []

    signals =
      if Enum.any?(diff, &String.starts_with?(&1.path, ".github/workflows/")) do
        [%{rule: :workflows_present, detail: "any .github/workflows/* => :high"} | signals]
      else
        signals
      end

    signals =
      case Enum.filter(diff, &lib_ex?(&1.path)) do
        [] ->
          signals

        lib_ex_paths ->
          [
            %{rule: :lib_elixir, detail: "#{length(lib_ex_paths)} lib/**/*.ex file(s) => :medium"}
            | signals
          ]
      end

    signals =
      cond do
        count >= 25 ->
          [%{rule: :many_files, detail: "#{count} files >= 25 => :high"} | signals]

        count >= 10 ->
          [%{rule: :many_files, detail: "#{count} files >= 10 => :medium"} | signals]

        true ->
          signals
      end

    signals =
      if Enum.any?(diff, &(&1.kind == :delete and String.starts_with?(&1.path, "lib/"))) do
        [%{rule: :lib_delete, detail: "any :delete under lib/ => :high"} | signals]
      else
        signals
      end

    signals
  end

  defp max_tier(a, b), do: if(Map.fetch!(@tier_rank, a) >= Map.fetch!(@tier_rank, b), do: a, else: b)

  defp lib_ex?(path) do
    String.starts_with?(path, "lib/") and String.ends_with?(path, ".ex")
  end
end
