defmodule GgenIgniter.Convergence.Hunks do
  @moduledoc """
  Unified-diff hunk parser for diff-only re-review. Produces one map per
  hunk — `%{file:, hunk_id:, hunk_text:}` (the raw text, consumed by
  `GgenIgniter.Convergence.Critic`) — where
  `hunk_id = GgenIgniter.Digest.sha256(file <> hunk_text)`, so two rounds
  observing the same hunk text in the same file derive the SAME id (an
  unchanged hunk is recognizable as unchanged) and any byte change in the
  hunk (or its file rename) derives a new one. Pure syntax, no disk access.
  """

  alias GgenIgniter.Digest

  @typedoc "One parsed hunk."
  @type hunk :: %{
          required(:file) => String.t(),
          required(:hunk_id) => String.t(),
          required(:hunk_text) => String.t()
        }

  @doc "Parses a unified diff's text into an ordered list of hunks. `[]` on empty/absent input."
  @spec parse_unified(String.t() | nil) :: [hunk()]
  def parse_unified(nil), do: []
  def parse_unified(""), do: []

  def parse_unified(diff) when is_binary(diff) do
    diff
    |> String.split("\n")
    |> walk(nil, nil, [])
    |> Enum.reverse()
  end

  # state: {current_file, current_hunk_lines} — lines reversed.

  defp walk([], current_file, current_hunk, acc) do
    flush(current_file, current_hunk, acc)
  end

  defp walk([line | rest], current_file, current_hunk, acc) do
    cond do
      String.starts_with?(line, "diff --git ") ->
        walk(rest, current_file, nil, flush(current_file, current_hunk, acc))

      String.starts_with?(line, "+++ ") and String.length(line) > 4 ->
        path = line |> String.slice(4..-1//1) |> strip_timestamp() |> strip_b_prefix()
        walk(rest, path, current_hunk, acc)

      String.starts_with?(line, "@@") ->
        walk(rest, current_file, [line], flush(current_file, current_hunk, acc))

      current_hunk != nil and (line == "" or String.starts_with?(line, [" ", "+", "-", "\\"])) ->
        walk(rest, current_file, [line | current_hunk], acc)

      true ->
        # File-header noise (--- / index / mode lines) outside a hunk body.
        walk(rest, current_file, current_hunk, acc)
    end
  end

  defp flush(_file, nil, acc), do: acc

  defp flush(file, lines, acc) do
    hunk_text = lines |> Enum.reverse() |> Enum.join("\n")
    file = file || "(unknown)"

    [%{file: file, hunk_id: Digest.sha256(file <> hunk_text), hunk_text: hunk_text} | acc]
  end

  defp strip_b_prefix("b/" <> p), do: p
  defp strip_b_prefix(p), do: p

  defp strip_timestamp(path) do
    path |> String.split("\t") |> List.first()
  end
end
