defmodule GgenIgniter.SleepGate do
  @moduledoc """
  Fail-closed no-sleep gate (see `~/.claude/rules/no-sleep-testing.md`).

  `scan/1` parses every `.ex`/`.exs` file under `<root>/lib` and `<root>/test`
  with `Code.string_to_quoted/2` and walks the AST for `Process.sleep/1` and
  `:timer.sleep/1` calls, so docs, heredocs, comments and string-embedded
  scripts never match. Violations:

  - `:unclassified_lib` -- a `lib/` sleep with no `# SLEEP-CLASS: <class>`
    comment on the same line or within 3 lines above it.
  - `:bad_class` -- the annotation names a class other than `SCHEDULING` or
    `POLL-STEP`.
  - `:test_sleep` -- any `test/` sleep outside `allowlist/0` (the single
    audited poll implementation).

  Files that fail to parse are skipped (the compiler owns syntax errors).
  Mix entry point: `mix ggen_igniter.sleep_gate`.
  """

  @type violation :: %{file: String.t(), line: pos_integer(), kind: kind()}
  @type kind :: :unclassified_lib | :bad_class | :test_sleep

  @allowlist ["test/support/assert_eventually.ex"]
  @classes ["SCHEDULING", "POLL-STEP"]
  @lookback 3

  @doc "Test-side files allowed to sleep (relative to the repo root)."
  @spec allowlist() :: [String.t()]
  def allowlist, do: @allowlist

  @doc "Scans `root`'s `lib/` and `test/` trees; returns violations sorted by file then line."
  @spec scan(Path.t()) :: [violation()]
  def scan(root) do
    for dir <- ["lib", "test"],
        path <- Path.wildcard(Path.join([root, dir, "**", "*.{ex,exs}"])),
        File.regular?(path),
        v <- scan_file(root, dir, path) do
      v
    end
    |> Enum.sort_by(&{&1.file, &1.line})
  end

  defp scan_file(root, dir, path) do
    rel = Path.relative_to(path, root)
    source = File.read!(path)

    case Code.string_to_quoted(source, columns: true, token_metadata: true) do
      {:ok, ast} ->
        lines = String.split(source, "\n")

        ast
        |> sleep_lines()
        |> Enum.flat_map(&classify(dir, rel, lines, &1))

      {:error, _} ->
        []
    end
  end

  defp classify("test", rel, _lines, line) do
    if rel in @allowlist, do: [], else: [%{file: rel, line: line, kind: :test_sleep}]
  end

  defp classify("lib", rel, lines, line) do
    case annotation(lines, line) do
      nil -> [%{file: rel, line: line, kind: :unclassified_lib}]
      class when class in @classes -> []
      _other -> [%{file: rel, line: line, kind: :bad_class}]
    end
  end

  # Nearest `# SLEEP-CLASS: X` on the call line or up to @lookback lines above.
  defp annotation(lines, line) do
    line..max(line - @lookback, 1)//-1
    |> Enum.find_value(fn n ->
      case Regex.run(~r/#\s*SLEEP-CLASS:\s*([A-Za-z_-]+)/, Enum.at(lines, n - 1, "")) do
        [_, class] -> class
        _ -> nil
      end
    end)
  end

  defp sleep_lines(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Process]}, :sleep]}, meta, _args} = node, acc ->
          {node, [meta[:line] | acc]}

        {{:., _, [:timer, :sleep]}, meta, _args} = node, acc ->
          {node, [meta[:line] | acc]}

        node, acc ->
          {node, acc}
      end)

    acc |> Enum.reject(&is_nil/1) |> Enum.reverse()
  end
end
