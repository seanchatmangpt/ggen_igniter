Code.require_file(Path.join([__DIR__, "e2e", "support", "e2e_case.ex"]))

defmodule GgenIgniter.E2eCaseUnitTest do
  @moduledoc """
  Fast, network-free unit tests for `GgenIgniter.E2e.Case.cmd!/3` -- the real
  helper used by the (slow, network-dependent) e2e tier. These run under the
  normal `mix test` suite since they touch no network and take a fraction of
  a second.
  """

  use ExUnit.Case, async: true

  use GgenIgniter.E2e.Case

  test "cmd! raises with the real captured output when the command fails" do
    error =
      assert_raise RuntimeError, fn ->
        cmd!("mix", ["nonexistent_task_xyz12345"])
      end

    assert error.message =~ "command failed: mix nonexistent_task_xyz12345"
    assert error.message =~ "nonexistent_task_xyz12345"
  end

  test "cmd! returns cleanly for a real, fast, network-free command" do
    output = cmd!("mix", ["--version"])

    assert output =~ "Mix"
  end
end
