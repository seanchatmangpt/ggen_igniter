defmodule GgenIgniter.Convergence.Critic do
  @moduledoc """
  The default deterministic critic for the convergence loop
  (`GgenIgniter.Convergence.run/2`'s `:reviewer` contract): a pure function
  over the round's hunk texts — same input, same findings, zero I/O, no LLM.

  Three mechanical rules over ADDED lines (lines beginning `+`, excluding the
  `+++` file header) within each hunk:

    * `:formatting` — an added line ends in trailing whitespace.
    * `:dead_code` — an added line contains `IO.inspect` or `dbg(`.
    * `:missing_doc` — an added line opens `defmodule` and no added
      `@moduledoc` line appears anywhere earlier in the same hunk text.
      Hunk-local approximation, disclosed: a moduledoc landing in a separate
      hunk is not seen. Widening the window to file-level pairing is
      disclosed follow-on work, not silently promised.

  All classes are members of the closed set
  (`GgenIgniter.Convergence.Classes.classes/0`). A hunk with no rule hits
  yields nothing — a clean diff reviews to `[]`, which the loop reads as
  `:pass` on round 1.
  """

  @doc """
  Reviewer-contract entry point: `%{scope:, hunks:, round:}` -> `[finding]`,
  deterministic. Ignores `scope` and `round` — every round critiques exactly
  the hunks it is handed; carrying and dedup across rounds is the loop's law
  (`GgenIgniter.Convergence`'s diff-only re-review), not the critic's.
  """
  @spec review(map()) :: [map()]
  def review(%{hunks: hunks}) when is_list(hunks) do
    Enum.flat_map(hunks, &critique_hunk/1)
  end

  def review(_), do: []

  # One hunk -> one fold over its lines. doc_state tracks whether an added
  # `@moduledoc` has been seen since the hunk began (the missing_doc rule's
  # hunk-local window).
  defp critique_hunk(%{file: file, hunk_id: hunk_id, hunk_text: text}) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.reduce({[], false}, fn line, {acc, saw_moduledoc} ->
      cond do
        String.starts_with?(line, "@@") ->
          {acc, saw_moduledoc}

        not String.starts_with?(line, "+") or String.starts_with?(line, "+++") ->
          # Context and removed lines never trigger the added-line rules.
          {acc, saw_moduledoc}

        true ->
          body = String.slice(line, 1..-1//1)

          {acc ++ added_line_findings(body, file, hunk_id, saw_moduledoc),
           saw_moduledoc or String.contains?(body, "@moduledoc")}
        end
    end)
    |> elem(0)
  end

  defp critique_hunk(_hunk), do: []

  defp added_line_findings(body, file, hunk_id, saw_moduledoc) do
    line_rules = [
      {:formatting, Regex.match?(~r/[ \t]\z/, body), "added line has trailing whitespace"},
      {:dead_code, String.contains?(body, "IO.inspect") or String.contains?(body, "dbg("),
       "added line contains debug instrumentation (IO.inspect/dbg)"}
    ]

    line_findings =
      line_rules
      |> Enum.filter(fn {_class, hit?, _msg} -> hit? end)
      |> Enum.map(fn {class, _hit?, msg} ->
        %{file: file, hunk_id: hunk_id, class: class, message: msg}
      end)

    module_finding =
      if String.contains?(body, "defmodule ") and not saw_moduledoc do
        [
          %{
            file: file,
            hunk_id: hunk_id,
            class: :missing_doc,
            message: "added defmodule opens a module with no @moduledoc earlier in the hunk"
          }
        ]
      else
        []
      end

    line_findings ++ module_finding
  end
end
