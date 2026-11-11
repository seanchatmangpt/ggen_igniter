defmodule GgenIgniter.SecurityReview.Checks.ShellInterpolation do
  @moduledoc """
  Flags added lines that interpolate untrusted text into a shell boundary:
  `System.cmd` called with an interpolated (`\#{}`) or concatenated (`<>`)
  command string, `:os.cmd`, and `Port.open` over a raw string. A clean
  list-arg `System.cmd("git", ["diff", sha, "--"])` call is the blessed shape
  and is never flagged — `GgenIgniter.SecurityReview.DiffSource` is written
  in exactly that shape and must pass this check.
  """

  @behaviour GgenIgniter.SecurityReview

  @system_cmd ~r/System\.cmd\(/
  @interp ~r/#\{/
  @concat ~r/<>/
  @os_cmd ~r/:os\.cmd\(/
  @port_open ~r/Port\.open\(/

  @impl GgenIgniter.SecurityReview
  def check(diff, _opts) do
    for file <- diff.files,
        {line_no, text} <- file.added_lines,
        finding = match_line(text),
        finding != nil do
      %{
        category: "shell_interpolation",
        file: file.path,
        rule: to_string(elem(finding, 0)),
        severity: :high,
        line: line_no,
        evidence: text
      }
    end
  end

  defp match_line(text) do
    cond do
      Regex.match?(@os_cmd, text) ->
        {:os_cmd, :high}

      Regex.match?(@port_open, text) and string_port?(text) ->
        {:port_open_shell_string, :high}

      Regex.match?(@system_cmd, text) and interp_in_call?(text) ->
        {:system_cmd_interpolation, :high}

      true ->
        nil
    end
  end

  # `Port.open({:spawn, "shell command"})` — a string (or a string-built
  # charlist via `to_charlist`) is a shell boundary. The tuple-with-list form
  # (`{:spawn_executable, path}`) is not flagged.
  defp string_port?(text) do
    Regex.match?(~r/:spawn\b/, text) and not Regex.match?(~r/:spawn_executable/, text)
  end

  # Interpolation or `<>` concatenation inside the same line as the
  # System.cmd call: the line-level heuristic this check commits to. A
  # multi-line build-up of a command string one variable at a time is the
  # disclosed boundary of a single-line review pass.
  defp interp_in_call?(text) do
    after_call = call_args(text)
    Regex.match?(@interp, after_call) or Regex.match?(@concat, after_call)
  end

  defp call_args(text) do
    case Regex.run(@system_cmd, text, return: :index) do
      [{off, len}] -> binary_part(text, off + len, byte_size(text) - off - len)
      _ -> ""
    end
  end
end
