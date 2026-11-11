defmodule GgenIgniter.SecurityReview.Checks.HookSettingsChange do
  @moduledoc """
  Flags changes to the harness trust surface as blocking: added lines under
  `.claude/settings*.json` (permission grants live there), `.claude/hooks/`
  (hook code executes on every matching tool call), and hook-wired `.sh`
  scripts under `.claude/`. Hooks are intent, never authority — a change to
  what runs automatically is exactly what a reviewer must see.
  """

  @behaviour GgenIgniter.SecurityReview

  @impl GgenIgniter.SecurityReview
  def check(diff, _opts) do
    for file <- diff.files,
        {line_no, text} <- file.added_lines,
        rule = match_path(file.path) do
      %{
        category: "hook_settings_change",
        file: file.path,
        rule: rule,
        severity: :high,
        line: line_no,
        evidence: text
      }
    end
  end

  defp match_path(path) do
    normalized = String.replace(path, "\\", "/")

    cond do
      settings?(normalized) -> "claude_settings_changed"
      hooks_dir?(normalized) -> "claude_hook_changed"
      hook_script?(normalized) -> "claude_hook_script_changed"
      true -> nil
    end
  end

  defp settings?(path) do
    String.contains?(path, ".claude/") and
      String.match?(Path.basename(path), ~r/\Asettings.*\.json\z/)
  end

  defp hooks_dir?(path), do: String.starts_with?(path, ".claude/hooks/")

  defp hook_script?(path) do
    String.contains?(path, ".claude/") and String.ends_with?(path, ".sh")
  end
end
