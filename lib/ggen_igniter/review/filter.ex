defmodule GgenIgniter.Review.Filter do
  @moduledoc """
  Cross-round repeat suppression over VOTE SURVIVORS.

  `GgenIgniterReview.Review` applies this module only to findings that already
  sustained the verifier vote — a vote-rejected finding is suppressed by the
  vote and never resurrected here. Laws:

  1. A survivor whose `suppression_key` was `:posted` in the LATEST prior
     round is suppressed this round (a carried repeat, not news).
  2. Chain continuity: a survivor whose key was `:suppressed` with
     `consecutive_suppressed >= 1` in the latest prior round remains in the
     chain (consec increments toward the escalation threshold). Without this,
     a suppressed repeat oscillates posted/suppressed and
     `escalation_candidate` at >= 3 consecutive suppressed rounds is
     unreachable.
  3. `first_seen_round` is copied from the chain, never reset by suppression.
  4. Different-line `:pre_existing` findings are never suppressed: the key
     embeds the line, so the structural guarantee is stated explicitly here
     rather than trusted to key construction.
  5. Only the latest prior round participates; earlier rounds are already
     summarized by its chain state.
  """

  alias GgenIgniter.Review.Finding

  @escalation_threshold 3

  @doc """
  Applies repeat suppression to vote-survivor findings given prior round
  history docs (`GgenIgniter.Review.Store.load_history/2` shape: `%{round:,
  findings: [entry_map]}` with string-keyed maps) and the current round
  number. Returns findings with `:status`, `:first_seen_round`,
  `:consecutive_suppressed`, and `:escalation_candidate` set.
  """
  @spec suppress_repeats([Finding.t()], term(), pos_integer()) :: [Finding.t()]
  def suppress_repeats(findings, history, round) do
    latest = latest_prior_round(history, round)
    by_key = index_by_key(latest)

    Enum.map(findings, fn f ->
      key = Finding.suppression_key(f)
      entry = Map.get(by_key, key)

      cond do
        is_nil(entry) ->
          fresh(f, round)

        f.severity == :pre_existing and entry_line(entry) != f.line ->
          fresh(f, round)

        entry_status(entry) == :posted or entry_consec(entry) >= 1 ->
          consec = entry_consec(entry) + 1

          %{
            f
            | status: :suppressed,
              first_seen_round: entry_first_seen(entry) || f.first_seen_round || round,
              consecutive_suppressed: consec,
              escalation_candidate: consec >= @escalation_threshold
          }

        true ->
          # Suppressed last round with consec 0 (no active chain): fresh.
          fresh(f, round)
      end
    end)
  end

  defp fresh(f, round) do
    %{
      f
      | status: :posted,
        first_seen_round: f.first_seen_round || round,
        consecutive_suppressed: 0,
        escalation_candidate: false
    }
  end

  # --- history normalization -------------------------------------------

  defp latest_prior_round(history, round) when is_list(history) do
    history
    |> Enum.filter(fn doc -> keyword_or_map_get(doc, :round) < round end)
    |> Enum.max_by(&keyword_or_map_get(&1, :round), fn -> nil end)
    |> case do
      nil -> %{}
      doc -> doc
    end
  end

  defp latest_prior_round(%{} = history, round) when not is_struct(history) do
    history
    |> Enum.filter(fn {_r, _doc} -> true end)
    |> Enum.map(fn {r, doc} -> {r, doc} end)
    |> Enum.filter(fn {r, _doc} -> is_integer(r) and r < round end)
    |> Enum.sort(:desc)
    |> case do
      [{_r, doc} | _] -> doc
      [] -> %{}
    end
  end

  defp latest_prior_round(_, _), do: %{}

  defp index_by_key(prior) do
    findings = keyword_or_map_get(prior, :findings) || []

    Map.new(findings, fn entry ->
      {keyword_or_map_get(entry, :suppression_key), entry}
    end)
  end

  defp entry_status(entry) do
    status = keyword_or_map_get(entry, :status)

    if status == :posted or status == "posted", do: :posted, else: :suppressed
  end

  defp entry_consec(entry) do
    case keyword_or_map_get(entry, :consecutive_suppressed) do
      n when is_integer(n) and n >= 0 -> n
      _ -> 0
    end
  end

  defp entry_first_seen(entry) do
    case keyword_or_map_get(entry, :first_seen_round) do
      n when is_integer(n) and n >= 1 -> n
      _ -> nil
    end
  end

  defp entry_line(entry) do
    case keyword_or_map_get(entry, :line) do
      n when is_integer(n) -> n
      _ -> line_from_key(keyword_or_map_get(entry, :suppression_key))
    end
  end

  defp line_from_key(nil), do: nil

  defp line_from_key(key) when is_binary(key) do
    case String.split(key, ":") do
      [_file, line, _class] ->
        case Integer.parse(line) do
          {n, ""} -> n
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp line_from_key(_), do: nil

  defp keyword_or_map_get(term, key) when is_map(term) and is_atom(key) do
    cond do
      Map.has_key?(term, key) -> Map.get(term, key)
      Map.has_key?(term, Atom.to_string(key)) -> Map.get(term, Atom.to_string(key))
      true -> nil
    end
  end

  defp keyword_or_map_get(term, key) when is_list(term) do
    if Keyword.keyword?(term), do: Keyword.get(term, key), else: nil
  end

  defp keyword_or_map_get(_, _), do: nil
end
