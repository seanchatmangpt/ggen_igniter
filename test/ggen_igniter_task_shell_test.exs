defmodule GgenIgniterTaskShellTest do
  @moduledoc """
  Chicago-style: `GgenIgniter.TaskShell` is a pure module, exercised directly with real
  argv lists and real closures; the final `describe` drives the REAL
  `Mix.Tasks.GgenIgniter.Rename` and `.Install` `run/1` with `--help`/`-h` and asserts on
  the real output. No test doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.TaskShell

  describe "help_requested?/2" do
    test "matches the literal --help only by default" do
      assert TaskShell.help_requested?(["--help"])
      assert TaskShell.help_requested?(["a", "--help", "b"])
      refute TaskShell.help_requested?(["-h"])
      refute TaskShell.help_requested?([])
    end

    test "honours an explicit flag list" do
      assert TaskShell.help_requested?(["-h"], ["--help", "-h"])
      refute TaskShell.help_requested?(["--helpme"], ["--help", "-h"])
    end
  end

  describe "run_with_help/4" do
    test "runs help_fun and not continue_fun when help is requested" do
      assert :help == TaskShell.run_with_help(["--help"], fn -> :help end, fn -> :go end)
    end

    test "runs continue_fun otherwise, and -h falls through by default" do
      assert :go == TaskShell.run_with_help(["--x"], fn -> :help end, fn -> :go end)
      assert :go == TaskShell.run_with_help(["-h"], fn -> :help end, fn -> :go end)
    end

    test "-h routes to help when listed" do
      assert :help ==
               TaskShell.run_with_help(["-h"], fn -> :help end, fn -> :go end, ["--help", "-h"])
    end
  end

  describe "real tasks delegate to it (subprocess)" do
    for {task, flag} <- [
          {"ggen_igniter.rename", "--help"},
          {"ggen_igniter.rename", "-h"},
          {"ggen_igniter.install", "--help"}
        ] do
      @tag task: task
      test "mix #{task} #{flag} prints the task's own concise help and exits 0" do
        {out, status} =
          System.cmd("mix", [unquote(task), unquote(flag)],
            stderr_to_stdout: true,
            env: [{"MIX_BUILD_ROOT", System.get_env("MIX_BUILD_ROOT") || "_build"}]
          )

        assert status == 0
        assert out =~ "mix #{unquote(task)}"
      end
    end
  end
end
