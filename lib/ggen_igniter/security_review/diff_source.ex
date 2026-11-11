defmodule GgenIgniter.SecurityReview.DiffSource do
  @moduledoc """
  Resolves the review base and parses the unified diff `GgenIgniter.SecurityReview.run/2`
  fans through its checks — the diff-acquisition hop of the security gate.

  Three paths, tried in order by `resolve_base/2`:

    * `--base` flag (`opts[:base]`) — must be an exact 40-hex commit SHA
      (the same format law `GgenIgniter.SemanticJira.GitGroundTruth`'s
      `@sha ~r/\\A[0-9a-f]{40}\\z/` enforces), so a well-formed but WRONG sha
      is still accepted here: format is the gate, identity is the caller's.
    * merge-base with the default branch (`main`, then `master`) via
      `git merge-base`.
    * `HEAD~1` — the previous commit.

  Every git invocation is `System.cmd/3` with a LIST of arguments and the
  `"--"` end-of-options separator only — this module must pass its own
  `GgenIgniter.SecurityReview.Checks.ShellInterpolation` check. Any ref that
  fails to resolve or that resolves to a non-40-hex value is a typed refusal
  `{:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, detail}}` — the
  gate never fabricates a diff from a guessed ref.
  """

  @sha ~r/\A[0-9a-f]{40}\z/

  @default_branches ["main", "master"]

  @typedoc "One added (or, with its `+`-line payload) reviewed line inside a hunk."
  @type added_line :: {non_neg_integer(), String.t()}

  @typedoc "The reviewed changes to one file in the diff."
  @type file_diff :: %{
          path: String.t(),
          added_lines: [added_line()]
        }

  @typedoc "The whole parsed unified diff."
  @type diff :: %{files: [file_diff()]}

  @typedoc "Typed refusal carried verbatim by `GgenIgniter.SecurityReview.run/2`."
  @type refusal :: {:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, String.t()}}

  @doc """
  Resolves the base commit SHA and returns the parsed unified diff of
  `<base>..worktree` (really `git diff <sha> --`). `opts`: `:base` (40-hex
  flag override), `:cwd` (repo root, default `File.cwd!()`).
  """
  @spec run(keyword()) :: {:ok, diff()} | refusal()
  def run(opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    with {:ok, sha} <- resolve_base(opts, cwd),
         {:ok, text} <- git_diff_text(sha, cwd) do
      {:ok, parse(text)}
    end
  end

  @doc """
  Resolves the base commit: the `--base` flag when present (must be exactly
  40-hex — a leading `-` or any non-40-hex value is refused, never passed to
  git), else the merge-base with `main`/`master`, else `HEAD~1`.
  """
  @spec resolve_base(keyword(), String.t()) :: {:ok, String.t()} | refusal()
  def resolve_base(opts, cwd) do
    case Keyword.get(opts, :base) do
      nil -> merge_base_or_head(cwd)
      flag -> flag_base(flag, cwd)
    end
  end

  defp flag_base(flag, _cwd) when not is_binary(flag),
    do: refused("--base must be a 40-hex commit SHA, got #{inspect(flag)}")

  defp flag_base(<<"-", _rest::binary>>, _cwd),
    do: refused("--base may not start with '-' (option injection)")

  defp flag_base(flag, _cwd) do
    if Regex.match?(@sha, flag) do
      {:ok, flag}
    else
      refused("--base #{inspect(flag)} is not a 40-hex commit SHA")
    end
  end

  defp merge_base_or_head(cwd) do
    Enum.find_value(@default_branches, fn branch ->
      case git(["merge-base", branch, "HEAD"], cwd) do
        {:ok, sha} -> {:ok, String.trim_trailing(sha)}
        {:error, _} -> nil
      end
    end)
    |> case do
      {:ok, sha} -> validate_sha(sha, "merge-base")
      nil -> rev_parse("HEAD~1", cwd)
    end
  end

  defp rev_parse(ref, cwd) do
    case git(["rev-parse", ref], cwd) do
      {:ok, out} -> validate_sha(String.trim_trailing(out), ref)
      {:error, reason} -> refused("could not resolve base #{inspect(ref)}: #{reason}")
    end
  end

  defp validate_sha(value, source) do
    if Regex.match?(@sha, value) do
      {:ok, value}
    else
      refused("#{source} resolved to a non-40-hex value: #{inspect(value)}")
    end
  end

  defp git_diff_text(sha, cwd) do
    case git(["diff", sha, "--"], cwd) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> refused("git diff failed against #{sha}: #{reason}")
    end
  end

  defp git(args, cwd) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {err, _code} -> {:error, String.trim_trailing(err)}
    end
  end

  defp refused(detail), do: {:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, detail}}

  @doc """
  Parses a unified diff's text into `%{files: [...]}`. Only ADDED lines are
  kept (the checks review what a change introduces); each added line carries
  its new-file line number from the hunk header. Binary-file and rename
  headers without hunks yield a file entry with no added lines.
  """
  @spec parse(String.t()) :: diff()
  def parse(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.reduce(%{files: [], file: nil, new_line: 0}, fn line, acc ->
      case classify(line) do
        {:file_start, path} ->
          files =
            if acc.file && acc.file.added_lines != [],
              do: acc.files ++ [acc.file],
              else: acc.files

          %{acc | files: files, file: new_file(path), new_line: 0}

        {:hunk, rest} ->
          %{acc | new_line: hunk_start(rest)}

        {:added, content} ->
          push_line(acc, content)

        :context ->
          %{acc | new_line: acc.new_line + 1}

        :other ->
          acc
      end
    end)
    |> finalize()
  end

  defp classify("+++ b/" <> path), do: {:file_start, path}
  defp classify("+++ " <> _), do: :other
  defp classify("--- " <> _), do: :other
  defp classify("@@ " <> rest), do: {:hunk, rest}
  defp classify("+" <> content), do: {:added, content}
  # A context line occupies a new-file line number, so it advances the
  # counter even though it is never reviewed.
  defp classify(" " <> _), do: :context
  defp classify(_), do: :other

  defp new_file(path), do: %{path: String.trim_trailing(path), added_lines: []}

  # `@@ -l,s +l,s @@` — the new-file start is the second range's first number.
  defp hunk_start(rest) do
    case Regex.run(~r/\+(\d+)/, rest) do
      [_, n] -> String.to_integer(n)
      nil -> 1
    end
  end

  defp push_line(%{file: nil} = acc, _content), do: acc

  defp push_line(%{file: file, new_line: n} = acc, content) do
    line = {n, content}

    %{
      acc
      | file: %{file | added_lines: file.added_lines ++ [line]},
        new_line: n + 1
    }
  end

  defp finalize(%{files: files, file: file}) do
    files = if file && file.added_lines != [], do: files ++ [file], else: files
    %{files: files}
  end
end
