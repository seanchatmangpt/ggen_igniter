defmodule GgenIgniter.TestSupport.SubjectRepo do
  @moduledoc """
  Builds a REAL git repository with real commits, for tests that need a WorkOrder
  subject the emitter can materialize (`ReceiptEmitter` `subject_source`).

  Chicago style: the repository is created by real `git` subprocesses (`init`,
  `add`, `commit`), the returned shas and tree are what `git rev-parse` reports,
  and tests assert on what `git archive` really produced. Nothing here fakes or
  stubs `git`.
  """

  @doc """
  Creates a repository under `dir` with two commits and returns
  `%{path: dir, sha: head_sha, first_sha: first_sha, tree: head_tree}`.

  The head commit's tree has `marker.txt` (`"subject-head\\n"`); the first
  commit's tree has `marker.txt` (`"subject-first\\n"`), so a checkout of the
  wrong commit is observable in file content.
  """
  @spec create!(Path.t()) :: %{
          path: Path.t(),
          sha: String.t(),
          first_sha: String.t(),
          tree: String.t()
        }
  def create!(dir) do
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    git!(dir, ["init", "--quiet"])
    File.write!(Path.join(dir, "marker.txt"), "subject-first\n")
    git!(dir, ["add", "marker.txt"])
    commit!(dir, "first")
    first_sha = git!(dir, ["rev-parse", "HEAD"])

    File.write!(Path.join(dir, "marker.txt"), "subject-head\n")
    git!(dir, ["add", "marker.txt"])
    commit!(dir, "head")

    %{
      path: dir,
      sha: git!(dir, ["rev-parse", "HEAD"]),
      first_sha: first_sha,
      tree: git!(dir, ["rev-parse", "HEAD^{tree}"])
    }
  end

  defp commit!(dir, message) do
    git!(dir, [
      "-c",
      "user.name=brce-test",
      "-c",
      "user.email=brce-test@example.invalid",
      "-c",
      "commit.gpgsign=false",
      "commit",
      "--quiet",
      "-m",
      message
    ])
  end

  defp git!(dir, args) do
    case System.cmd("git", ["-C", dir | args],
           stderr_to_stdout: true,
           env: [{"GIT_DIR", nil}, {"GIT_WORK_TREE", nil}]
         ) do
      {out, 0} -> String.trim(out)
      {out, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{out}"
    end
  end
end
