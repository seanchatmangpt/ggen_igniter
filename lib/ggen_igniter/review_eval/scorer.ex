defmodule GgenIgniter.ReviewEval.Scorer do
  @moduledoc """
  Adjudication: a case is CAUGHT iff at least one finding path-suffix-matches
  `location.file` AND (the cited line is within `location.line_tolerance` OR
  the finding cites the case's invariant string). Unmatched findings count
  toward `fp_findings`, never toward `caught`.
  """

  alias GgenIgniter.ReviewEval.Corpus

  @doc """
  Adjudicate one case against raw findings.

  Returns `%{verdict: :caught | :missed, match_evidence: binary | nil, fp_findings: non_neg_integer()}`.
  """
  @spec adjudicate(map(), [map()] | nil) :: map()
  def adjudicate(case, findings)

  def adjudicate(_case, nil) do
    %{verdict: :missed, match_evidence: nil, fp_findings: 0}
  end

  def adjudicate(case, findings) when is_list(findings) do
    file = get_in(case, ["location", "file"])
    line = get_in(case, ["location", "line"])
    tol = get_in(case, ["location", "line_tolerance"]) || Corpus.default_tolerance()
    invariant = get_in(case, ["defect", "invariant"])

    {hits, misses} =
      findings
      |> Enum.split_with(fn f ->
        path_match?(f["file"], file) and
          (line_within?(f["line"], line, tol) or cites_invariant?(f, invariant))
      end)

    case hits do
      [hit | _] ->
        %{
          verdict: :caught,
          match_evidence:
            "finding #{hit["file"]}:#{hit["line"]} within tolerance #{tol} of #{file}:#{line}",
          fp_findings: length(misses)
        }

      [] ->
        %{
          verdict: :missed,
          match_evidence: nil,
          fp_findings: length(findings)
        }
    end
  end

  @doc "Path-suffix match: finding path ends with the corpus location file."
  def path_match?(finding_path, corpus_file)
      when is_binary(finding_path) and is_binary(corpus_file) do
    finding_path == corpus_file or String.ends_with?(finding_path, "/" <> corpus_file) or
      String.ends_with?(corpus_file, "/" <> finding_path)
  end

  def path_match?(_, _), do: false

  defp line_within?(finding_line, corpus_line, tol)
       when is_integer(finding_line) and is_integer(corpus_line),
       do: abs(finding_line - corpus_line) <= tol

  defp line_within?(_, _, _), do: false

  defp cites_invariant?(finding, invariant)
       when is_binary(invariant) do
    text = finding["text"] || finding["raw"] || ""
    String.contains?(text, invariant)
  end

  defp cites_invariant?(_, _), do: false
end
