defmodule GgenIgniter.SecurityReview.Checks.PathTraversal do
  @moduledoc """
  Flags added lines where a `File.`/`Path.` call builds a path from `..`
  concatenation or an unvalidated interpolation — the classic
  `Path.join(base, "../../" <> user_input)` escape. Severity medium: a
  traversal by itself is usually a bug, not automatically an exploit.
  """

  @behaviour GgenIgniter.SecurityReview

  @file_call ~r/\bFile\.\w+\(/
  @path_call ~r/\bPath\.\w+\(/
  @dotdot ~r/\.\./
  @interp ~r/#\{/

  @impl GgenIgniter.SecurityReview
  def check(diff, _opts) do
    for file <- diff.files,
        {line_no, text} <- file.added_lines,
        finding = match_line(text),
        finding != nil do
      %{
        category: "path_traversal",
        file: file.path,
        rule: to_string(elem(finding, 0)),
        severity: :medium,
        line: line_no,
        evidence: text
      }
    end
  end

  defp match_line(text) do
    cond do
      Regex.match?(@file_call, text) and Regex.match?(@dotdot, text) ->
        {:file_call_with_dotdot, :medium}

      Regex.match?(@path_call, text) and Regex.match?(@dotdot, text) ->
        {:path_call_with_dotdot, :medium}

      Regex.match?(@file_call, text) and Regex.match?(@interp, text) ->
        {:file_call_unvalidated_interpolation, :medium}

      true ->
        nil
    end
  end
end
