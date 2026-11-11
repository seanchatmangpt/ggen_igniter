defmodule GgenIgniter.SecurityReceiptTest do
  @moduledoc """
  Chicago-style: the real `GgenIgniter.SecurityReview.Receipt` over real
  files in real temp dirs and a real temp git repo (two real commits for the
  auto-clear roundtrip), byte-level determinism asserted by comparing the
  real ledger bytes from two independent runs — no doubles anywhere.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SecurityReview
  alias GgenIgniter.SecurityReview.Receipt

  defp finding(overrides \\ []) do
    Map.merge(
      %{
        category: "secrets",
        file: "lib/leaky.ex",
        rule: "credential_assignment",
        severity: :high,
        evidence: "token = \"TESTONLYFAKE00\""
      },
      Map.new(overrides)
    )
  end

  defp tmp_repo(ctx_tag) do
    dir =
      Path.join(System.tmp_dir!(), "sec_receipt_#{ctx_tag}_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    # RealDir resolves the macOS TMPDIR symlink and requires an existing dir.
    dir = RealDir.real_dir!(dir)
    git!(dir, ["init", "-b", "main"])
    File.write!(Path.join(dir, "README.md"), "base\n")
    git!(dir, ["add", "."])
    # --allow-empty: the base commit's only job is to give HEAD a parent for
    # the diff; if the just-written README somehow fails to stage under heavy
    # machine load ("nothing to commit" was observed once in CI-class fan-out),
    # setup must not abort — the real change arrives via commit_all!/2.
    git!(dir, [
      "-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "base"
    ])
    dir
  end

  defp commit_all!(dir, msg) do
    # every commit carries a real change so "nothing to commit" never fires
    File.write!(Path.join(dir, "log.txt"), "#{msg}\n", [:append])
    git!(dir, ["add", "."])

    git!(dir, ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", msg])

    String.trim_trailing(git!(dir, ["rev-parse", "HEAD"]))
  end

  describe "finding_id/1" do
    test "is stable and prefixed SEC-<CATEGORY>-" do
      id = Receipt.finding_id(finding())

      assert String.starts_with?(id, "SEC-SECRETS-")
      assert id == Receipt.finding_id(finding())
    end

    test "survives line renumbering and whitespace reformat" do
      renumbered = finding(line: 99)
      reformatted = finding(evidence: "token    =   \"TESTONLYFAKE00\"")

      assert Receipt.finding_id(finding()) == Receipt.finding_id(renumbered)
      assert Receipt.finding_id(finding()) == Receipt.finding_id(reformatted)
    end

    test "differs across files and rules" do
      other_file = Receipt.finding_id(finding(file: "lib/other.ex"))
      other_rule = Receipt.finding_id(finding(rule: "aws_access_key"))

      refute other_file == Receipt.finding_id(finding())
      refute other_rule == Receipt.finding_id(finding())
    end
  end

  describe "write/3 determinism" do
    test "two runs over the same inputs are byte-identical (ledger and sealed copy)" do
      dir = tmp_repo("determinism")
      commit = commit_all!(dir, "second")

      r1 = Receipt.write([finding()], dir, commit)
      bytes1 = File.read!(Path.join(dir, ".ggen_igniter/security-findings.json"))

      # reset the ledger so the second write cannot just merge with the first
      File.rm!(Path.join(dir, ".ggen_igniter/security-findings.json"))

      r2 = Receipt.write([finding()], dir, commit)
      bytes2 = File.read!(Path.join(dir, ".ggen_igniter/security-findings.json"))

      assert bytes1 == bytes2
      assert r1 == r2

      sealed = Path.join(dir, "receipts/security/" <> String.slice(commit, 0, 8) <> ".json")
      assert File.exists?(sealed)

      # the sealed copy is the same deterministic bytes
      assert File.read!(sealed) == String.trim_trailing(bytes1)
    end
  end

  describe "auto-clear roundtrip (real two-commit git repo)" do
    test "base commit with the defect, head commit fixing it auto-clears" do
      dir = tmp_repo("autoclear")
      _base_commit = commit_all!(dir, "first")

      # commit 2 introduces the defect; the gate opens the finding
      commit2 = commit_all!(dir, "with-defect")
      r1 = Receipt.write([finding()], dir, commit2)
      assert r1["status"] == "blocked"

      # commit 3 removes it; the same finding id is absent from the current set
      commit3 = commit_all!(dir, "fixed")
      r2 = Receipt.write([], dir, commit3)

      assert r2["status"] == "clear"
      assert [%{"state" => "auto_cleared", "cleared_at_commit" => ^commit3}] = r2["findings"]
      assert r2["open_count"] == 0
    end

    test "a finding still present stays open with its first_seen_commit" do
      dir = tmp_repo("stillopen")
      commit1 = commit_all!(dir, "c1")

      r1 = Receipt.write([finding()], dir, commit1)
      assert [%{"state" => "open", "first_seen_commit" => ^commit1}] = r1["findings"]

      commit2 = commit_all!(dir, "c2")
      r2 = Receipt.write([finding(line: 42)], dir, commit2)

      assert [%{"state" => "open", "first_seen_commit" => ^commit1, "line" => 42}] =
               r2["findings"]
    end

    test "cleared never resurrects: the same defect reappearing stays auto_cleared" do
      dir = tmp_repo("noresurrect")
      commit1 = commit_all!(dir, "c1")

      Receipt.write([finding()], dir, commit1)
      commit2 = commit_all!(dir, "c2")
      Receipt.write([], dir, commit2)

      commit3 = commit_all!(dir, "c3")
      r3 = Receipt.write([finding()], dir, commit3)

      assert [%{"state" => "auto_cleared"}] = r3["findings"]
      assert r3["status"] == "clear"
    end

    test "run/2 verdict follows the ledger: blocked iff any open" do
      dir = tmp_repo("verdict")
      File.write!(Path.join(dir, "lib.txt"), "safe\n")
      git!(dir, ["add", "."])

      assert {:ok, %{status: :clear}} = SecurityReview.run(cwd: dir)

      File.write!(Path.join(dir, "lib.txt"), "token = \"TESTONLYFAKE00\"\n")
      git!(dir, ["add", "."])

      assert {:ok, %{status: :blocked, receipt: blocked}} = SecurityReview.run(cwd: dir)
      assert blocked["status"] == "blocked"

      File.write!(Path.join(dir, "lib.txt"), "safe again\n")
      git!(dir, ["add", "."])

      assert {:ok, %{status: :clear, receipt: cleared}} = SecurityReview.run(cwd: dir)
      assert Enum.all?(cleared["findings"], &(&1["state"] == "auto_cleared"))
    end
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    out
  end
end
