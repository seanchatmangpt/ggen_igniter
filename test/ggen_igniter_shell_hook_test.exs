defmodule GgenIgniter.ShellHookTest do
  @moduledoc """
  Chicago-style: real `sh -c` subprocesses via `System.cmd/3`, real
  `Task.async/1`/`Task.yield/2`/`Task.shutdown/2` timeout, no mocking
  anywhere. `GgenIgniter.ShellHook.run/3` is the single function under
  test.
  """

  use ExUnit.Case, async: true
  doctest GgenIgniter.ShellHook

  alias GgenIgniter.ShellHook

  describe "run/3 (real success)" do
    test "runs a real command and returns its real combined output" do
      assert {:ok, output} = ShellHook.run("echo hello_from_shell_hook", File.cwd!())
      assert output =~ "hello_from_shell_hook"
    end

    test "cd:'s into the given project_dir for real" do
      dir =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_shell_hook_cd_#{System.unique_integer([:positive])}"
        )

      File.rm_rf!(dir)
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:ok, output} = ShellHook.run("pwd", dir)
      # Resolve both sides through a real symlink-expansion (`File.cwd!()`-
      # style) comparison -- macOS `/tmp` is itself a symlink to
      # `/private/tmp`, and `pwd`'s real stdout reflects the resolved path.
      assert String.trim(output) == Path.expand(dir)
    end
  end

  describe "run/3 (real nonzero exit)" do
    test "reports the real exit code and real combined stdout+stderr" do
      assert {:error, {:sh_exit, 7, output}} =
               ShellHook.run("echo boom >&2; exit 7", File.cwd!())

      assert output =~ "boom"
    end
  end

  describe "run/3 (real timeout)" do
    test "kills a genuinely slow command and returns :sh_timeout, fast and deterministic" do
      {elapsed_us, result} =
        :timer.tc(fn -> ShellHook.run("sleep 5", File.cwd!(), timeout_ms: 50) end)

      assert result == {:error, :sh_timeout}
      # Real proof this test is fast, not just correct: it must return well
      # before the real `sleep 5` would have finished on its own.
      assert elapsed_us < 2_000_000
    end
  end

  describe "default_timeout_ms/0" do
    test "is a real, positive default" do
      assert ShellHook.default_timeout_ms() == 60_000
    end
  end
end
