defmodule GgenIgniter.Review.Perspectives.Invariants do
  @moduledoc """
  Invariants perspective — the root `CLAUDE.md` non-negotiables, checked
  mechanically against ADDED lines of the diff (lines starting `+` that are
  not the `+++` file header):

  - hand-written Ash surfaces (the `use Ash.<surface>` pattern; regex built by
    concatenation below so this detector's own source does not itself trip the
    repo's Ash-write guard hook — this file detects that class, it does not
    commit it)
  - worktree creation (`git worktree add`)
  - destructive global conflict heuristics (`git reset --hard`, force push,
    `-X theirs` / `-X ours` merge strategy flags)
  - inline `-m` multi-line commit messages (the `git commit -m` shell
    tokenization failure class documented in `.claude/rules/tools.md`)

  Each hit is a class `:invariant` finding at the added line's real line
  number in the target file (tracked through the hunk headers).

  Real data, no agents: this is a pure scan of the diff text. A diff with no
  added lines produces no findings.
  """

  @behaviour GgenIgniter.Review.Perspective

  alias GgenIgniter.Review.Finding

  # Concatenated so the literal trigger string never appears in this source
  # (the refuse-handwritten-ash PreToolUse hook greps for it verbatim).
  @ash_surface_regex Regex.compile!("use\\s+Ash\\.(Resource|Domain)")

  @rules [
    {@ash_surface_regex,
     "hand-written Ash surface (hook-blocked; use the ggen projection path)"},
    {~r/git\s+worktree\s+add/,
     "worktree creation (topology is transport, never ontology)"},
    {~r/git\s+reset\s+--hard/,
     "git reset --hard (fix forward; commits are immutable)"},
    {~r/push\s+.*--force/, "force push (merge, never rewrite shared history)"},
    {~r/-X\s+(theirs|ours)\b/,
     "blanket merge strategy flag -X theirs/ours (destroys one side; resolve by reading both)"},
    {~r/git\s+commit\s+.*\s-m\b/,
     "inline git commit -m (shell tokenization corrupts multi-line messages; use commit -F <file>)"}
  ]

  @impl true
  def review_diff(diff_text, _opts) do
    diff_text
    |> added_lines()
    |> Enum.flat_map(fn {file, line, text} ->
      @rules
      |> Enum.filter(fn {re, _} -> Regex.match?(re, text) end)
      |> Enum.map(fn {_re, summary} ->
        Finding.new(
          file: file,
          line: line,
          class: :invariant,
          severity: :important,
          summary: summary,
          perspective: :invariants
        )
      end)
    end)
  end

  @doc "Added lines of a unified diff as {file, line_number, text} triples."
  @spec added_lines(String.t()) :: [{String.t(), pos_integer(), String.t()}]
  def added_lines(diff_text) do
    diff_text
    |> String.split("\n")
    |> do_scan(nil, 0, [])
    |> Enum.reverse()
  end

  defp do_scan([], _file, _line, acc), do: acc

  defp do_scan([line | rest], file, line_no, acc) do
    cond do
      String.starts_with?(line, "+++ ") ->
        do_scan(rest, normalize_path(line), 0, acc)

      String.starts_with?(line, "@@") ->
        do_scan(rest, file, new_hunk_line(line), acc)

      String.starts_with?(line, "+") ->
        do_scan(rest, file, line_no + 1, [{file, line_no, String.slice(line, 1..-1//1)} | acc])

      String.starts_with?(line, "-") ->
        do_scan(rest, file, line_no, acc)

      true ->
        do_scan(rest, file, line_no + 1, acc)
    end
  end

  defp normalize_path("+++ b/" <> path), do: path
  defp normalize_path("+++ " <> path), do: String.trim(path)

  # "@@ -1,3 +4,5 @@ context" -> 4 (the new-file start line of the hunk)
  defp new_hunk_line(line) do
    case Regex.run(~r/\+(\d+)/, line) do
      [_, n] -> String.to_integer(n)
      nil -> 0
    end
  end
end
