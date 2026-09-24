defmodule GgenIgniter.SemanticJira.Bootstrap.Git do
  @moduledoc """
  The git reads of the cold bootstrap (GC23-1): durable refs only, every call
  `git -C <dir> ...` with explicit exit handling (exit 0 is the only success).
  No write, fetch or network command is ever issued.

  `covered_commit/3` is the exact-subject law of PR-006 / F6: the covered
  commit of a revision over a path scope is the last commit reachable from
  that revision that changed any covered path (`git log -1 --format=%H <rev>
  -- <paths>`). A receipt made at subject `S` still covers the current
  subject `H` iff `covered_commit(S) == covered_commit(H)`: no commit after
  `S` changed a covered path. (When `S` itself is the last change -- the usual
  case -- this is `S == covered_commit(H)`.)
  """

  @sha ~r/\A[0-9a-f]{40}\z/

  @doc "The toplevel of the work tree containing `dir`, or `:error`."
  @spec toplevel(Path.t()) :: {:ok, Path.t()} | :error
  def toplevel(dir) do
    if File.dir?(dir) do
      case git(dir, ["rev-parse", "--show-toplevel"]) do
        {:ok, top} when top != "" -> {:ok, top}
        _ -> :error
      end
    else
      :error
    end
  end

  @doc "`HEAD` of the work tree at `dir` (40-hex) or `:error`."
  @spec head(Path.t()) :: {:ok, String.t()} | :error
  def head(dir), do: commit(dir, "HEAD")

  @doc "The branch checked out at `dir`, or `\"(detached)\"`."
  @spec branch(Path.t()) :: String.t()
  def branch(dir) do
    case git(dir, ["symbolic-ref", "-q", "--short", "HEAD"]) do
      {:ok, name} when name != "" -> name
      _ -> "(detached)"
    end
  end

  @doc "The commit `rev` names in the repository at `dir`, or `:error`."
  @spec commit(Path.t(), String.t()) :: {:ok, String.t()} | :error
  def commit(dir, rev) do
    case git(dir, ["rev-parse", "--verify", "--quiet", rev <> "^{commit}"]) do
      {:ok, sha} -> if Regex.match?(@sha, sha), do: {:ok, sha}, else: :error
      :error -> :error
    end
  end

  @doc """
  The last commit reachable from `rev` that changed any of `paths` (pathspecs
  relative to the toplevel `dir`); `{:ok, nil}` when none ever did.
  """
  @spec covered_commit(Path.t(), String.t(), [String.t()]) ::
          {:ok, String.t() | nil} | :error
  def covered_commit(dir, rev, paths) when is_list(paths) and paths != [] do
    case git(dir, ["log", "-1", "--format=%H", rev, "--" | paths]) do
      {:ok, ""} -> {:ok, nil}
      {:ok, sha} -> if Regex.match?(@sha, sha), do: {:ok, sha}, else: :error
      :error -> :error
    end
  end

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: false) do
      {out, 0} -> {:ok, String.trim(out)}
      {_out, _nonzero} -> :error
    end
  rescue
    ErlangError -> :error
  end
end
