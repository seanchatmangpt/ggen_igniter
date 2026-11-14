defmodule GgenIgniter.SecurityReviewTest do
  @moduledoc """
  Chicago-style: real unified-diff fixtures parsed by the real
  `GgenIgniter.SecurityReview.DiffSource.parse/1`, real temp git repos via
  `git init`/`git commit` subprocesses, real `System.cmd` throughout — no
  doubles anywhere; assertions land on the real returned finding/verdict
  state. Fixture credential SHAPES are fragment-built, obviously-fake
  TESTONLY placeholders assembled at runtime so no real credential material
  (and no literal credential-shaped text) ever appears in source.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SecurityReview
  alias GgenIgniter.SecurityReview.DiffSource

  alias GgenIgniter.SecurityReview.Checks.{
    DependencyChange,
    HookSettingsChange,
    PathTraversal,
    SecretsInDiff,
    ShellInterpolation
  }

  # Check modules are aliased above and called by their real names.

  # ── fragment-built, obviously-fake fixtures (see moduledoc) ────────────────

  defp fake_aws, do: "AKIA" <> "TESTONLYFAKE0001"

  defp aws_line, do: Enum.join(["aws_key", " = \"", fake_aws(), "\""])

  defp high_entropy_line, do: Enum.join(["db_password", " = \"TESTONLYFAKE00\""])

  defp weak_line, do: Enum.join(["password", " = \"notasecret\""])

  defp pem_line, do: Enum.join(["-----BEGIN ", "PRIV", "ATE KEY-----"])

  describe "DiffSource.parse/1" do
    test "keeps only added lines, with new-file line numbers" do
      diff =
        DiffSource.parse("""
        diff --git a/lib/a.ex b/lib/a.ex
        index 111..222 100644
        --- a/lib/a.ex
        +++ b/lib/a.ex
        @@ -1,4 +1,5 @@
         context line
        -removed line
        +added line one
        +added line two
         more context
        """)

      assert [%{path: "lib/a.ex", added_lines: lines}] = diff.files
      assert lines == [{2, "added line one"}, {3, "added line two"}]
    end

    test "a second file starts a fresh line counter" do
      diff =
        DiffSource.parse("""
        --- a/lib/a.ex
        +++ b/lib/a.ex
        @@ -1,2 +1,3 @@
         ctx
        +first
        --- a/lib/b.ex
        +++ b/lib/b.ex
        @@ -5,2 +5,6 @@
        +second
        """)

      assert [
               %{path: "lib/a.ex", added_lines: [{2, "first"}]},
               %{path: "lib/b.ex", added_lines: [{5, "second"}]}
             ] = diff.files
    end

    test "deletions and /dev/null deletions never open a file" do
      diff =
        DiffSource.parse("""
        --- a/lib/gone.ex
        +++ /dev/null
        -def gone, do: 1
        """)

      assert diff.files == []
    end
  end

  describe "DiffSource.run/1 over a real temp git repo" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "sec_review_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      dir = RealDir.real_dir!(dir)
      git!(dir, ["init", "-b", "main"])
      File.write!(Path.join(dir, "README.md"), "base\n")
      git!(dir, ["add", "."])
      git!(dir, ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "base"])

      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    test "clear worktree diffs against the base and is :clear", %{dir: dir} do
      File.write!(Path.join(dir, "lib.txt"), "safe\n")
      # `git diff <sha> --` covers tracked files only — stage so the review
      # sees the worktree.
      git!(dir, ["add", "."])

      assert {:ok, %{status: :clear, findings: [], receipt: receipt}} =
               SecurityReview.run(cwd: dir)

      assert receipt["status"] == "clear"
      assert receipt["open_count"] == 0
      assert File.exists?(Path.join(dir, ".ggen_igniter/security-findings.json"))
    end

    test "a leaked AWS-key-shaped fixture in the worktree is :blocked", %{dir: dir} do
      File.mkdir_p!(Path.join(dir, "config"))
      File.write!(Path.join(dir, "config/creds.txt"), aws_line() <> "\n")
      git!(dir, ["add", "."])

      assert {:ok, %{status: :blocked, findings: [finding | _]}} =
               SecurityReview.run(cwd: dir)

      assert finding.category == "secrets"
      assert finding.severity == :high
      assert finding.file == "config/creds.txt"
      # masked: only the first 4 chars of the value survive into evidence
      assert finding.evidence == "aws_key = \"AKIA...\""
    end

    test "unresolvable --base is the typed DIFF_UNAVAILABLE refusal", %{dir: dir} do
      assert {:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, detail}} =
               SecurityReview.run(cwd: dir, base: "no-such-ref")

      assert detail =~ "not a 40-hex commit SHA"
    end

    test "a dash-leading --base is refused as option injection", %{dir: dir} do
      assert {:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, detail}} =
               SecurityReview.run(cwd: dir, base: "--upload-pack=/bin/evil")

      assert detail =~ "may not start with '-'"
    end

    test "a non-git cwd is the typed refusal (fail closed)", %{dir: _dir} do
      # OUTSIDE any git repo — a subdir of the temp repo would still resolve
      # (git walks up to the parent .git).
      plain_dir =
        Path.join(System.tmp_dir!(), "sec_nonrepo_#{System.unique_integer([:positive])}")

      File.mkdir_p!(plain_dir)
      on_exit(fn -> File.rm_rf!(plain_dir) end)

      assert {:error, {:refused, :SECURITY_REVIEW_DIFF_UNAVAILABLE, _}} =
               SecurityReview.run(cwd: plain_dir)
    end
  end

  describe "run/2 (checks_override seam)" do
    test "evidence is truncated to 80 chars" do
      long = String.duplicate("TESTONLY", 12)

      assert {:ok, %{status: :blocked, findings: [f]}} =
               SecurityReview.run([cwd: nonrepo_dir(), write: false], [trunc_check(long)])

      assert byte_size(f.evidence) == 80
      assert f.evidence == String.slice(long, 0, 80)
    end

    test "dedup collapses findings identical after evidence normalization" do
      c1 = const_check("  same   evidence  ")
      c2 = const_check("same evidence")

      assert {:ok, %{status: :blocked, findings: [single]}} =
               SecurityReview.run([cwd: nonrepo_dir(), write: false], [c1, c2])

      assert single.evidence == "  same   evidence  "
    end
  end

  describe "checks (parsed fixture diffs)" do
    test "secrets: high-entropy assignment flagged, weak placeholder not" do
      diff = lines_diff([high_entropy_line(), weak_line()])
      findings = SecretsInDiff.check(diff, [])
      rules = Enum.map(findings, & &1.rule)

      assert "credential_assignment" in rules

      assert Enum.map(findings, & &1.evidence) == [
               # masked to first 4 chars of the value
               "db_" <> Enum.join(["password", " = \"TEST...\""])
             ]

      refute Enum.any?(findings, &(&1.evidence == weak_line()))
    end

    test "secrets: PEM-shaped line is flagged" do
      assert [%{rule: "private_key", severity: :high}] =
               SecretsInDiff.check(lines_diff([pem_line()]), [])
    end

    test "shell_interpolation: interpolated System.cmd flagged, list-arg call clean" do
      bad = "System.cmd(\"sh\", [\"-c\", \"ls \#{path}\"])"
      good = "System.cmd(\"git\", [\"diff\", sha, \"--\"])"

      diff = lines_diff([bad, good])
      rules = Enum.map(ShellInterpolation.check(diff, []), & &1.rule)

      assert rules == ["system_cmd_interpolation"]
    end

    test "shell_interpolation: :os.cmd and Port.open shell string flagged" do
      diff =
        lines_diff([
          ":os.cmd(~c\"ls \#{dir}\")",
          "Port.open({:spawn, \"cat \#{f}\"}, [])"
        ])

      rules = Enum.map(ShellInterpolation.check(diff, []), & &1.rule)

      assert "os_cmd" in rules
      assert "port_open_shell_string" in rules
    end

    test "path_traversal: dot-dot concat and unvalidated interpolation flagged" do
      diff =
        lines_diff([
          "Path.join(base, \"../\" <> user)",
          "File.read(\"/etc/\#{name}\")"
        ])

      rules = Enum.map(PathTraversal.check(diff, []), & &1.rule)

      assert "path_call_with_dotdot" in rules
      assert "file_call_unvalidated_interpolation" in rules
    end

    test "dependency_change: mix.exs dep tuple and any mix.lock line block" do
      diff = %{
        files: [
          %{path: "mix.exs", added_lines: [{3, "{:jason, \"~> 1.4\"}"}]},
          %{path: "mix.lock", added_lines: [{1, "\"jason\" => :hex"}]}
        ]
      }

      findings = DependencyChange.check(diff, [])
      assert length(findings) == 2
      assert Enum.all?(findings, &(&1.severity == :high))
    end

    test "hook_settings_change: settings json, hooks dir, and .claude .sh flagged" do
      diff = %{
        files: [
          %{path: ".claude/settings.json", added_lines: [{2, "{}"}]},
          %{path: ".claude/hooks/gate.sh", added_lines: [{1, "#!/bin/sh"}]},
          %{path: "lib/x.ex", added_lines: [{1, "def x, do: 1"}]}
        ]
      }

      findings = HookSettingsChange.check(diff, [])

      assert length(findings) == 2
      assert Enum.all?(findings, &(&1.file =~ ".claude/"))
    end
  end

  # ── fixtures/helpers (real data, no doubles) ───────────────────────────────

  defp lines_diff(lines, path \\ "fixture.txt") do
    %{
      files: [
        %{
          path: path,
          added_lines: lines |> Enum.with_index(1) |> Enum.map(fn {t, i} -> {i, t} end)
        }
      ]
    }
  end

  # A real, clean temp git repo: the seam tests produce a real (empty) diff
  # but never touch a ledger anywhere (write: false).
  defp nonrepo_dir do
    dir =
      Path.join(System.tmp_dir!(), "sec_seam_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir = RealDir.real_dir!(dir)
    git!(dir, ["init", "-b", "main"])
    File.write!(Path.join(dir, "README.md"), "base\n")
    git!(dir, ["add", "."])
    git!(dir, ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "base"])
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp trunc_check(long) do
    fn _diff, _opts ->
      [%{category: "secrets", file: "f", rule: "r", severity: :high, evidence: long}]
    end
  end

  defp const_check(evidence) do
    fn _diff, _opts ->
      [%{category: "x", file: "f.ex", rule: "r", severity: :medium, evidence: evidence}]
    end
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    out
  end
end
