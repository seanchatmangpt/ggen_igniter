defmodule GgenIgniter.SecurityReviewShellInterpolationTest do
  @moduledoc """
  Chicago-style: real unified-diff strings parsed by the real
  `GgenIgniter.SecurityReview.DiffSource.parse/1` and checked by the real
  `GgenIgniter.SecurityReview.Checks.ShellInterpolation`; the dogfood case reads
  the real `diff_source.ex` from disk. No doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SecurityReview.Checks.ShellInterpolation
  alias GgenIgniter.SecurityReview.DiffSource

  @diff_source Path.expand("../lib/ggen_igniter/security_review/diff_source.ex", __DIR__)

  defp findings(lines, path \\ "lib/a.ex") do
    text =
      "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n" <>
        "@@ -1,1 +1,#{length(lines)} @@\n" <> Enum.join(lines, "\n") <> "\n"

    text |> DiffSource.parse() |> ShellInterpolation.check([])
  end

  describe "check/2 (flagged shapes)" do
    test "System.cmd with interpolation is flagged" do
      assert [f] = findings(["+System.cmd(\"sh\", [\"-c\", \"ls \#{dir}\"])"])
      assert f.category == "shell_interpolation"
      assert f.rule == "system_cmd_interpolation"
      assert f.severity == :high
      assert f.file == "lib/a.ex"
      assert f.line == 1
      assert f.evidence == "System.cmd(\"sh\", [\"-c\", \"ls \#{dir}\"])"
    end

    test "System.cmd with <> concatenation is flagged" do
      assert [%{rule: "system_cmd_interpolation"}] =
               findings(["+System.cmd(\"ls \" <> dir, [])"])
    end

    test ":os.cmd is flagged" do
      assert [%{rule: "os_cmd"}] = findings(["+:os.cmd(to_charlist(x))"])
    end

    test "Port.open with a :spawn string is flagged" do
      assert [%{rule: "port_open_shell_string"}] =
               findings(["+Port.open({:spawn, \"ls \#{d}\"}, [:binary])"])
    end
  end

  describe "check/2 (not flagged)" do
    test "list-arg System.cmd, spawn_executable and plain variables pass" do
      lines = [
        "+System.cmd(\"git\", [\"diff\", sha, \"--\"])",
        "+Port.open({:spawn_executable, path}, args: [\"-x\"])",
        "+System.cmd(cmd, args)"
      ]

      assert [] == findings(lines)
    end

    test "removed and context lines are ignored" do
      assert [] == findings(["-:os.cmd(x)", " :os.cmd(x)", "+ok = 1"])
    end
  end

  describe "check/2 (pinned heuristic boundaries)" do
    test "documented false positive: interpolation in a list arg still flags" do
      assert [%{rule: "system_cmd_interpolation"}] =
               findings(["+System.cmd(\"echo\", [\"\#{x}\"])"])
    end

    test "documented false negative: multi-line build-up is not seen" do
      assert [] == findings(["+cmd = \"ls \" <> dir", "+System.cmd(cmd, [])"])
    end

    test "precedence: os_cmd wins over system_cmd and port_open on one line" do
      line = "+:os.cmd(x); System.cmd(\"a\" <> b, []); Port.open({:spawn, s}, [])"
      assert [%{rule: "os_cmd"}] = findings([line])
    end

    test "precedence: port_open_shell_string wins over system_cmd" do
      line = "+Port.open({:spawn, s}, []); System.cmd(\"a\" <> b, [])"
      assert [%{rule: "port_open_shell_string"}] = findings([line])
    end
  end

  describe "check/2 (dogfood)" do
    test "DiffSource's own source, wrapped as added lines, is clean" do
      lines =
        @diff_source
        |> File.read!()
        |> String.split("\n")
        |> Enum.map(&("+" <> &1))

      assert [] == findings(lines, "lib/ggen_igniter/security_review/diff_source.ex")
    end
  end
end
