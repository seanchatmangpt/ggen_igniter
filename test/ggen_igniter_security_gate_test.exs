defmodule GgenIgniter.SecurityGateTest do
  @moduledoc """
  Chicago-style: the real `mix ggen_igniter.security_review` task exercised
  as a REAL subprocess (exit codes are real process exit codes), against a
  real temp git repo, plus the real `GgenIgniter.TaskContract` table.
  `async: false` — each test boots a real mix subprocess sharing this
  checkout's build tree.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.TaskContract

  @repo_root File.cwd!()
  @build_root "_build-lane-g1"

  defp tmp_repo(tag) do
    dir =
      Path.join(System.tmp_dir!(), "sec_gate_#{tag}_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir = RealDir.real_dir!(dir)
    git!(dir, ["init", "-b", "main"])
    File.write!(Path.join(dir, "README.md"), "base\n")
    git!(dir, ["add", "."])
    git!(dir, ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "base"])
    dir
  end

  defp run_task(args, dir) do
    System.cmd("mix", ["ggen_igniter.security_review" | args],
      cd: @repo_root,
      # merge: System.cmd's env REPLACES the environment — wiping HOME etc.
      # breaks the mix subprocess (observed: non-git --cwd wrongly exited 0).
      env: Map.merge(System.get_env(), %{"MIX_BUILD_ROOT" => @build_root}),
      stderr_to_stdout: true
    )
    |> then(fn {out, code} -> {out, code, dir} end)
  end

  describe "TaskContract code 5" do
    test "security_blocked is code 5 with standing SECURITY_BLOCKED" do
      assert TaskContract.exit_code(:security_blocked) == 5
      assert TaskContract.standing(:security_blocked) == "SECURITY_BLOCKED"
      assert 5 in TaskContract.documented_codes()
      refute TaskContract.exit_code(:security_blocked) == TaskContract.exit_code(:drift)
    end
  end

  describe "mix ggen_igniter.security_review (real subprocess exits)" do
    test "exit 0 on a clear repo, with the ALIVE envelope" do
      dir = tmp_repo("clear")
      File.write!(Path.join(dir, "lib.txt"), "safe\n")
      git!(dir, ["add", "."])

      {out, code, _} = run_task(["--cwd", dir, "--json"], dir)

      assert code == 0
      env = decode_envelope!(out)
      assert env["exit_code"] == 0
      assert env["standing"] == "ALIVE"
      assert env["data"]["open_count"] == 0
    end

    test "exit 5 on a blocked repo, with the SECURITY_BLOCKED refusal envelope" do
      dir = tmp_repo("blocked")
      File.write!(Path.join(dir, "lib.txt"), "AKIA" <> "TESTONLYFAKE0001\n")
      git!(dir, ["add", "."])

      {out, code, _} = run_task(["--cwd", dir, "--json"], dir)

      assert code == 5
      env = decode_envelope!(out)
      assert env["exit_code"] == 5
      assert env["standing"] == "SECURITY_BLOCKED"
      assert env["ok"] == false
      assert env["refusal"]["code"] == "SECURITY_BLOCKED"
      assert env["refusal"]["detail"] =~ "open security findings"
      assert env["data"]["open_count"] >= 1
    end

    test "--check read mode still exits 5 but writes no ledger" do
      dir = tmp_repo("checkmode")
      File.write!(Path.join(dir, "lib.txt"), "AKIA" <> "TESTONLYFAKE0001\n")
      git!(dir, ["add", "."])

      {out, code, _} = run_task(["--cwd", dir, "--json", "--check"], dir)

      assert code == 5
      env = decode_envelope!(out)
      assert env["exit_code"] == 5
      refute File.exists?(Path.join(dir, ".ggen_igniter/security-findings.json"))
    end

    test "exit 2 on an unrecognized flag" do
      dir = tmp_repo("badflag")

      {_out, code, _} = run_task(["--cwd", dir, "--no-such-flag"], dir)

      assert code == 2
    end

    test "exit 1 with REFUSED:SECURITY_REVIEW_DIFF_UNAVAILABLE outside a git repo" do
      # must NOT be nested inside tmp_repo's git tree — git walks up and would
      # find the repo, making the diff succeed (observed exit 0)
      plain_parent =
        Path.join(System.tmp_dir!(), "sec_gate_nogit_#{System.unique_integer([:positive])}")

      File.mkdir_p!(plain_parent)
      plain_parent = RealDir.real_dir!(plain_parent)
      on_exit(fn -> File.rm_rf!(plain_parent) end)
      plain = Path.join(plain_parent, "plain")
      File.mkdir_p!(plain)

      {out, code, _} = run_task(["--cwd", plain, "--json"], plain)

      assert code == 1
      env = decode_envelope!(out)
      assert env["refusal"]["code"] == "SECURITY_REVIEW_DIFF_UNAVAILABLE"
    end

    test "--receipt-out writes the envelope file" do
      dir = tmp_repo("receiptout")
      out_path = Path.join(dir, "envelope.json")

      {_out, code, _} = run_task(["--cwd", dir, "--json", "--receipt-out", out_path], dir)

      assert code == 0
      assert {:ok, %{"task" => "security_review"}} = Jason.decode(File.read!(out_path))
    end
  end

  defp decode_envelope!(out) do
    line =
      out
      |> String.split("\n", trim: true)
      |> Enum.find(fn l -> String.starts_with?(String.trim(l), "{") end)

    Jason.decode!(line)
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    out
  end
end
