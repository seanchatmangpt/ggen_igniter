defmodule GgenIgniter.SemanticJiraGitGroundTruthTest do
  @moduledoc """
  Chicago, no doubles (V23-T6R; PRD PR-006, ARD §7 standing model): the real
  `GitGroundTruth.verify_base_shas!/2` against real temporary git repositories
  (real `git init`/`commit`, a real `remote.origin.url` configured locally — no
  network), asserting on the returned verification report and the raised
  typed refusals.

  Jurisdiction law under test: a row outside the verified work tree's own
  repository is a TYPED SKIP in the returned report under `:all` (never
  silently dropped, never "verified"), a REFUSAL when the row opted itself in,
  and the repository comparison is exact `owner/repo` (never substring).
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.GitGroundTruth

  @origin "https://github.com/seanchatmangpt/ggen_igniter.git"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_ggt_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp repo!(dir, origin) do
    repo = Path.join(dir, "checkout")
    File.mkdir_p!(repo)
    git!(repo, ["init", "-q"])
    git!(repo, ["config", "user.email", "v23-t6r@example.invalid"])
    git!(repo, ["config", "user.name", "V23-T6R"])
    git!(repo, ["config", "commit.gpgsign", "false"])
    if origin, do: git!(repo, ["remote", "add", "origin", origin])
    File.write!(Path.join(repo, "README"), "subject\n")
    git!(repo, ["add", "README"])
    git!(repo, ["commit", "-q", "-m", "base"])
    %{repo: repo, head: git!(repo, ["rev-parse", "HEAD"])}
  end

  defp row(id, repository, base_sha, extra \\ %{}) do
    Map.merge(
      %{
        "work_order" => "https://ggen-igniter.dev/ontology/semantic-jira##{id}",
        "id" => id,
        "repository" => repository,
        "base_sha" => base_sha
      },
      extra
    )
  end

  test ":all verifies in-jurisdiction rows and reports every other row as a typed skip",
       %{dir: dir} do
    %{repo: repo, head: head} = repo!(dir, @origin)
    foreign_sha = String.duplicate("e", 40)
    trap_sha = String.duplicate("f", 40)

    rows = [
      # oxigraph-shaped literals normalize exactly like sparql-shaped ones
      row("SJ-IN", ~s("seanchatmangpt/ggen_igniter"), ~s("#{head}")),
      row("SJ-EDS", "local/eds", foreign_sha),
      # substring trap: "seanchatmangpt/ggen" is contained in the origin URL
      # but names a different repository; it is NOT in jurisdiction
      row("SJ-TRAP", "seanchatmangpt/ggen", trap_sha)
    ]

    report =
      GitGroundTruth.verify_base_shas!([{"work_orders", rows}], verify_cwd: repo, all: true)

    assert report["verified"] == [head]

    assert report["skipped"] == [
             %{
               "kind" => "outside_jurisdiction",
               "id" => "SJ-EDS",
               "work_order" => "https://ggen-igniter.dev/ontology/semantic-jira#SJ-EDS",
               "repository" => "local/eds",
               "base_sha" => foreign_sha,
               "jurisdiction" => "seanchatmangpt/ggen_igniter"
             },
             %{
               "kind" => "outside_jurisdiction",
               "id" => "SJ-TRAP",
               "work_order" => "https://ggen-igniter.dev/ontology/semantic-jira#SJ-TRAP",
               "repository" => "seanchatmangpt/ggen",
               "base_sha" => trap_sha,
               "jurisdiction" => "seanchatmangpt/ggen_igniter"
             }
           ]

    assert GitGroundTruth.skip_line(hd(report["skipped"])) =~
             "SKIPPED:SEMANTIC_JIRA_BASE_SHA_OUTSIDE_JURISDICTION"
  end

  test "an in-jurisdiction baseSha that is not a reachable commit refuses", %{dir: dir} do
    %{repo: repo} = repo!(dir, @origin)
    forged = row("SJ-FORGED", "seanchatmangpt/ggen_igniter", String.duplicate("d", 40))

    error =
      assert_raise ArgumentError, fn ->
        GitGroundTruth.verify_base_shas!([{"work_orders", [forged]}], verify_cwd: repo, all: true)
      end

    assert error.message =~ GitGroundTruth.refusal_prefix()
  end

  test "a per-order opt-in outside the jurisdiction refuses instead of skipping", %{dir: dir} do
    %{repo: repo, head: head} = repo!(dir, @origin)
    opted = row("SJ-EDS", "local/eds", head, %{"requires_git_ground_truth" => "true"})

    error =
      assert_raise ArgumentError, fn ->
        GitGroundTruth.verify_base_shas!([{"work_orders", [opted]}], verify_cwd: repo)
      end

    assert error.message =~ GitGroundTruth.refusal_prefix()
    assert error.message =~ "outside the jurisdiction"

    # Without the opt-in and without :all nothing is targeted.
    plain = Map.delete(opted, "requires_git_ground_truth")

    assert GitGroundTruth.verify_base_shas!([{"work_orders", [plain]}], verify_cwd: repo) ==
             %{"verified" => [], "skipped" => []}
  end

  test "a work tree without an origin remote verifies every row (no jurisdiction)",
       %{dir: dir} do
    %{repo: repo, head: head} = repo!(dir, nil)
    rows = [row("SJ-EDS", "local/eds", head), row("SJ-NOREPO", nil, head)]

    assert GitGroundTruth.verify_base_shas!([{"work_orders", rows}], verify_cwd: repo, all: true) ==
             %{"verified" => [head], "skipped" => []}
  end

  test "nothing targeted is vacuous and never touches git", %{dir: dir} do
    missing = Path.join(dir, "does-not-exist")

    assert GitGroundTruth.verify_base_shas!([{"work_orders", [row("SJ-X", "a/b", "x")]}],
             verify_cwd: missing
           ) == %{"verified" => [], "skipped" => []}
  end
end
