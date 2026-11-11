defmodule GgenIgniter.TestSupport.ReviewEvalFixture do
  @moduledoc """
  Real synthetic git repo fixture: baseline -> defect -> fix -> revert,
  built with real `git` commands (Chicago: real collaborators, state asserts).
  """

  @doc """
  Builds the fixture repo. Returns:

      %{
        root: path, baseline_sha:, defect_sha:, fix_sha:, revert_sha:,
        defect_file: "lib/ggen_igniter/review_eval/thing.ex", defect_line: 2
      }
  """
  def build!(tag \\ "rv") do
    root =
      Path.join([
        System.tmp_dir!(),
        "review-eval-fixture-#{tag}-#{:erlang.unique_integer([:positive])}"
      ])

    File.mkdir_p!(Path.join(root, "lib/ggen_igniter/review_eval"))
    git(root, ["init", "-q"])
    git(root, ["config", "user.email", "fixture@example.com"])
    git(root, ["config", "user.name", "Fixture"])
    git(root, ["checkout", "-q", "-b", "main"])

    thing = Path.join(root, "lib/ggen_igniter/review_eval/thing.ex")

    # c0 baseline
    File.write!(thing, base_content())
    File.write!(Path.join(root, "README.md"), "fixture\n")
    git(root, ["add", "."])
    git(root, ["commit", "-q", "-m", "chore: baseline"])

    # c1 defect: flip + to - on line 2
    File.write!(thing, String.replace(base_content(), "f(x), do: x + 1", "f(x), do: x - 1"))
    git(root, ["add", "."])
    git(root, ["commit", "-q", "-m", "feat: change f/1 (introduces the defect)"])

    # c2 fix: restore line 2 (subject starts with "fix")
    File.write!(thing, base_content())
    git(root, ["add", "."])
    git(root, ["commit", "-q", "-m", "fix(review_eval): restore f/1 addition semantics"])

    # c3 revert-styled commit creating bug.ex (mined as git_revert_receipt)
    File.mkdir_p!(Path.join(root, "lib/ggen_under_test"))
    File.write!(Path.join(root, "lib/ggen_under_test/bug.ex"), "defmodule Bug do\nend\n")
    git(root, ["add", "."])
    git(root, ["commit", "-q", "-m", "revert: undo the sub(x) defect class"])

    {out, 0} = System.cmd("git", ["log", "--format=%H", "--reverse"], cd: root)
    [baseline, defect, fix, revert] = String.split(String.trim_trailing(out), "\n")

    %{
      root: root,
      baseline_sha: baseline,
      defect_sha: defect,
      fix_sha: fix,
      revert_sha: revert,
      defect_file: "lib/ggen_igniter/review_eval/thing.ex",
      defect_line: 2
    }
  end

  def destroy!(%{root: root}), do: File.rm_rf!(root)

  defp base_content do
    "defmodule Thing do\n  def f(x), do: x + 1\n  def g(x), do: x * 2\n  def h(x), do: x - 1\n  def i(x), do: x / 2\nend\n"
  end

  defp git(root, args) do
    {out, code} = System.cmd("git", args, cd: root, stderr_to_stdout: true)

    if code != 0 do
      raise "fixture git #{Enum.join(args, " ")} failed (#{code}): #{out}"
    end

    out
  end
end
