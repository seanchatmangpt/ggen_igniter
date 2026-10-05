defmodule Mix.Tasks.Pm4pytestTest do
  # Chicago: the wrapper's collaborator is a real subprocess running a real
  # shell script (a degraded but REAL pm4pytest stand-in via PM4PYTEST_BIN),
  # asserting on final state (exit tuple), not on call counts. No mocks.
  use ExUnit.Case, async: false

  @env_var "PM4PYTEST_BIN"

  setup do
    dir = System.tmp_dir!()
    script = Path.join(dir, "fake-pm4pytest-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      System.delete_env(@env_var)
      File.rm(script)
    end)

    %{dir: dir, script: script}
  end

  defp write_script(%{dir: dir, script: script}, body) do
    File.write!(script, body)
    File.chmod!(script, 0o755)
    System.put_env(@env_var, script)
    %{dir: dir, script: script}
  end

  test "execs the binary with passthrough args and streams its exit code (0)", ctx do
    ctx = write_script(ctx, ~s(#!/bin/sh
echo "pm4pytest-args: $@"
exit 0
))

    out =
      ExUnit.CaptureIO.capture_io(fn ->
        assert catch_exit(Mix.Task.rerun("pm4pytest", ["check-conformance", "--log", "x"])) ==
                 {:shutdown, 0}
      end)

    assert out =~ "pm4pytest-args: check-conformance --log x"
    assert File.exists?(ctx.script)
  end

  test "propagates a nonzero child exit code", ctx do
    write_script(ctx, ~s(#!/bin/sh
echo "conformance failed" >&2
exit 1
))

    out =
      ExUnit.CaptureIO.capture_io(fn ->
        assert catch_exit(Mix.Task.rerun("pm4pytest", [])) == {:shutdown, 1}
      end)

    assert out =~ "conformance failed"
  end

  test "refuses with exit 2 when PM4PYTEST_BIN points at a missing file" do
    System.put_env(@env_var, "/nonexistent/pm4pytest")

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert catch_exit(Mix.Task.rerun("pm4pytest", ["check-conformance"])) == {:shutdown, 2}
    end)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert catch_exit(Mix.Task.rerun("pm4pytest", [])) == {:shutdown, 2}
    end)
  end
end
