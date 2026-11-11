defmodule GgenIgniter.SecurityReview.Checks.SecretsInDiff do
  @moduledoc """
  Flags added lines that look like credentials: AWS access keys, PEM private
  keys, and high-entropy `token|secret|password|api_key` assignments. The
  matched secret value is masked to its first 4 characters in the evidence —
  the gate reports a finding, never a copy of the credential.
  """

  @behaviour GgenIgniter.SecurityReview

  @aws_key ~r/\bAKIA[0-9A-Z]{16}\b/
  @pem ~r/BEGIN (?:RSA |EC )?PRIVATE KEY/
  @assignment ~r/(?:token|secret|password|api_key|apikey|access_key)["']?\s*[:=]\s*["']?([A-Za-z0-9+\/=_-]{8,})/i

  @impl GgenIgniter.SecurityReview
  def check(diff, _opts) do
    for file <- diff.files,
        {line_no, text} <- file.added_lines,
        finding = match_line(text),
        finding != nil do
      category_file_rule(finding, file.path, line_no, text)
    end
  end

  defp match_line(text) do
    cond do
      Regex.match?(@aws_key, text) -> {:aws_access_key, :high}
      Regex.match?(@pem, text) -> {:private_key, :high}
      true -> assignment_finding(text)
    end
  end

  defp assignment_finding(text) do
    case Regex.run(@assignment, text) do
      [_, value] ->
        if high_entropy?(value), do: {:credential_assignment, :high}

      _ ->
        nil
    end
  end

  defp category_file_rule({rule, severity}, path, line_no, text) do
    masked = mask_secret(text)

    %{
      category: "secrets",
      file: path,
      rule: to_string(rule),
      severity: severity,
      line: line_no,
      evidence: masked
    }
  end

  # Secret values masked to their first 4 chars before the evidence ever
  # leaves this check — both credential shapes this rule detects.
  defp mask_secret(text) do
    masked_assignment = Regex.replace(@assignment, text, fn whole, value ->
      String.replace(whole, value, String.slice(value, 0, 4) <> "...")
    end)

    Regex.replace(@aws_key, masked_assignment, fn key -> String.slice(key, 0, 4) <> "..." end)
  end

  # Shannon entropy over the character set, plus a digit+letter mix — a
  # placeholder like "changeme" or "example_key" stays below the bar.
  defp high_entropy?(value) do
    freq = value |> String.graphemes() |> Enum.frequencies()
    n = String.length(value)

    entropy =
      freq
      |> Map.values()
      |> Enum.reduce(0.0, fn c, acc ->
        p = c / n
        acc - p * :math.log2(p)
      end)

    has_digit? = String.match?(value, ~r/\d/)
    has_letter? = String.match?(value, ~r/[A-Za-z]/)

    entropy >= 3.0 and has_digit? and has_letter?
  end
end
