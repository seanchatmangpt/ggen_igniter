defmodule GgenIgniter.SecurityReview.Checks.DependencyChange do
  @moduledoc """
  Flags ANY dependency-graph change as blocking: an added dep tuple (or the
  `defp deps` block itself) in `mix.exs`, and any added line in `mix.lock`
  (a lockfile line is a resolved-version transition and carries no safe
  subset — it blocks whole). Dependency supply-chain changes are the one
  class this gate never severity-negotiates.
  """

  @behaviour GgenIgniter.SecurityReview

  @dep_tuple ~r/\{:/
  @deps_block ~r/defp?\s+deps/

  @impl GgenIgniter.SecurityReview
  def check(diff, _opts) do
    for file <- diff.files,
        {line_no, text} <- file.added_lines,
        finding = match_line(file.path, text),
        finding != nil do
      %{
        category: "dependency_change",
        file: file.path,
        rule: to_string(elem(finding, 0)),
        severity: :high,
        line: line_no,
        evidence: text
      }
    end
  end

  defp match_line(path, text) do
    basename = Path.basename(path)

    cond do
      basename == "mix.lock" ->
        {:mix_lock_changed, :high}

      basename == "mix.exs" and Regex.match?(@deps_block, text) ->
        {:deps_block_changed, :high}

      basename == "mix.exs" and Regex.match?(@dep_tuple, text) ->
        {:dependency_added, :high}

      true ->
        nil
    end
  end
end
