defmodule GgenIgniterTaskShellTest do
  @moduledoc """
  Chicago-style: `GgenIgniter.TaskShell` is exercised with real argv and closures;
  integration cases drive real Mix tasks. No test doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.TaskShell

  describe "help_requested?/2" do
    test "matches both conventional help spellings by default" do
      assert TaskShell.help_requested?(["--help"])
      assert TaskShell.help_requested?(["-h"])
      refute TaskShell.help_requested?(["--helpme"])
      refute TaskShell.help_requested?([])
    end

    test "honours an explicitly narrowed flag list" do
      assert TaskShell.help_requested?(["--help"], ["--help"])
      refute TaskShell.help_requested?(["-h"], ["--help"])
    end
  end

  describe "run_with_help/4" do
    test "routes both default help spellings to help_fun" do
      assert :help == TaskShell.run_with_help(["--help"], fn -> :help end, fn -> :go end)
      assert :help == TaskShell.run_with_help(["-h"], fn -> :help end, fn -> :go end)
    end

    test "non-help argv reaches continue_fun" do
      assert :go == TaskShell.run_with_help(["--x"], fn -> :help end, fn -> :go end)
      assert :go == TaskShell.run_with_help(["--helpme"], fn -> :help end, fn -> :go end)
    end

    test "explicit narrow boundary can assign -h different semantics" do
      assert :go ==
               TaskShell.run_with_help(["-h"], fn -> :help end, fn -> :go end, ["--help"])
    end
  end

  describe "real tasks delegate to it (subprocess)" do
    @describetag :integration

    for {task, flag} <- [
          {"ggen_igniter.rename", "--help"},
          {"ggen_igniter.rename", "-h"},
          {"ggen_igniter.install", "--help"},
          {"ggen_igniter.install", "-h"}
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
