defmodule GgenIgniter.Review do
  @moduledoc """
  The fan-out review aggregation core (top-level facade over
  `lib/ggen_igniter/review/` — same shape as `Query` over `Query.Oxigraph`).

  One round, end to end, pure and deterministic given the same diff and the
  same injected verifiers:

  1. Fan the diff out over the pinned perspectives
     (`GgenIgniter.Review.Perspective.perspectives/0`) via `Task.async_stream`.
  2. Merge findings, dedupe by deterministic `Finding.id`.
  3. Drop `:style` and `:diagnostic` classes PRE-vote (they never consume a
     verifier slot by law).
  4. Vote each survivor under the injected verifiers
     (`GgenIgniter.Review.Verifier`, majority law, default M = 3).
  5. Apply cross-round repeat suppression (`GgenIgniter.Review.Filter`) using
     the review's real `rounds.jsonl` history.
  6. Tally (`GgenIgniter.Review.Tally`) and persist
     (`GgenIgniter.Review.Store`).

  Agent execution is out of scope: structured findings enter via
  `opts[:findings]` (correctness) and diff-text scans (invariants,
  chicago_tests, epoch_law). See each perspective module.
  """

  alias GgenIgniter.Review.{Filter, Finding, Perspective, Store, Tally, Verifier}

  @dropped_pre_vote [:style, :diagnostic]

  @doc """
  Runs one review round over `diff_text`.

  Options:
  - `:verifiers` — list of 1-arity vote fns (real collaborators); padded to
    `:verifier_count` with neutral abstainers (default count 3, so with no
    injected verifiers every finding is rejected — fail closed).
  - `:review_id` — persistence key (default "current").
  - `:base` — store root override (tests use a real tmp dir).
  - `:round` — round number (default 1).
  - `:persist` — set `false` to skip Store (pure aggregation in tests).
  - plus the perspective opts: `:findings`, `:attributions`.

  Returns `{:ok, round_doc}` with the tallied Finding structs.
  """
  @spec run(String.t(), keyword()) ::
          {:ok, %{round: pos_integer(), posted: [Finding.t()], suppressed: [Finding.t()]}}
  def run(diff_text, opts \\ []) when is_binary(diff_text) do
    opts =
      Keyword.validate!(opts,
        verifiers: [],
        verifier_count: Verifier.default_count(),
        review_id: "current",
        base: nil,
        findings: [],
        attributions: %{},
        round: 1,
        persist: true
      )

    round = Keyword.fetch!(opts, :round)

    findings =
      fan_out(diff_text, opts)
      |> dedupe_by_id()
      |> Enum.reject(&(&1.class in @dropped_pre_vote))

    verifiers =
      Verifier.pad_default(
        Keyword.fetch!(opts, :verifiers),
        Keyword.fetch!(opts, :verifier_count)
      )

    tallied = Tally.tally(findings, verifiers)

    {posted, suppressed} = apply_suppression(tallied, opts, round)

    if Keyword.fetch!(opts, :persist) do
      review_id = Keyword.fetch!(opts, :review_id)

      Store.save(
        %{round: round, posted: posted, suppressed: suppressed},
        review_id,
        Keyword.fetch!(opts, :base)
      )
    end

    {:ok, %{round: round, posted: posted, suppressed: suppressed}}
  end

  defp fan_out(diff_text, opts) do
    per_perspective_opts = Keyword.take(opts, [:findings, :attributions])

    Perspective.perspectives()
    |> Task.async_stream(
      fn {_name, module} -> Perspective.run(module, diff_text, per_perspective_opts) end,
      order: :output
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, findings}} -> findings
      {:exit, reason} -> raise "review perspective crashed: #{inspect(reason)}"
    end)
  end

  defp dedupe_by_id(findings) do
    findings
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&{&1.file, &1.line, &1.id})
  end

  defp apply_suppression(%{posted: posted, suppressed: suppressed}, opts, round) do
    review_id = Keyword.fetch!(opts, :review_id)

    history =
      case Store.load_history(review_id, Keyword.fetch!(opts, :base)) do
        {:ok, docs} -> docs
        {:error, _} -> []
      end

    # Only vote SURVIVORS enter repeat suppression; vote-rejected findings
    # stay suppressed and are never resurrected by the filter.
    survivors = Filter.suppress_repeats(posted, history, round)

    kept =
      Enum.filter(survivors, &(&1.status == :posted))

    newly_suppressed = Enum.filter(survivors, &(&1.status == :suppressed))

    rejected =
      Enum.map(suppressed, fn f ->
        %{f | status: :suppressed, first_seen_round: f.first_seen_round || round}
      end)

    {kept, Enum.sort_by(rejected ++ newly_suppressed, &{&1.file, &1.line, &1.id})}
  end
end
