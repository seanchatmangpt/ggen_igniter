defmodule GgenIgniter.Review.Perspectives.ChicagoTests do
  @moduledoc """
  Chicago-testing-discipline perspective — the pinned mock regex from
  `test/CLAUDE.md`, run mechanically over ADDED lines of the diff:

      (use|import) +(Mox|Mimic|Patch)\\b|(Mox|Mimic|Patch)\\.|:meck\\.|mockall|MagicMock|Mock\\(

  Each hit on an added line is a class `:chicago_test` finding at the added
  line's real line number. This is the same discipline as surface 5 of
  `.claude/agents/ggen-reviewer.md`, but pure: diff text in, findings out —
  no agent, no process spawn.
  """

  @behaviour GgenIgniter.Review.Perspective

  alias GgenIgniter.Review.Finding

  @doc "The pinned anti-mock regex, verbatim from test/CLAUDE.md."
  def regex do
    ~r/(use|import) +(Mox|Mimic|Patch)\b|(Mox|Mimic|Patch)\.|:meck\.|mockall|MagicMock|Mock\(/
  end

  @impl true
  def review_diff(diff_text, _opts) do
    diff_text
    |> GgenIgniter.Review.Perspectives.Invariants.added_lines()
    |> Enum.filter(fn {_file, _line, text} -> Regex.match?(regex(), text) end)
    |> Enum.map(fn {file, line, _text} ->
      Finding.new(
        file: file,
        line: line,
        class: :chicago_test,
        severity: :important,
        summary: "added line matches the pinned anti-mock regex (test/CLAUDE.md)",
        perspective: :chicago_tests
      )
    end)
  end
end
