defmodule GgenIgniterBaseMixTaskEndUserTest do
  @moduledoc """
  Chicago-style: real `System.cmd("mix", [...])` subprocess (per
  `test/CLAUDE.md`'s documented tmp-dir + `on_exit` cleanup pattern, and
  `Igniter.Test`'s own documented limitation -- "you cannot install new
  dependencies" -- which rules out an in-memory `Igniter.Test.test_project`
  for real CLI entry-point tasks). `mix igniter.refactor.rename_function`
  needs a real, COMPILABLE Mix project: an earlier attempt at this file
  copied ex4pm's real `apps/ex4pm_contracts/lib/ex4pm/contracts.ex` in
  isolation and hit a real `CompileError` (`Ex4pm.Refusal.__struct__/1 is
  undefined`), since that module aliases sibling `ex4pm_core`/`ex4pm_evidence`
  types not present outside the real umbrella. A later attempt copied
  `apps/ex4pm_runtime/lib/ex4pm/runtime/application.ex` from `~/ex4pm`, but
  that path no longer exists: ex4pm was since refactored from an umbrella
  layout to a flat lib, and `Ex4pm.Runtime.Application` was merged into
  `Ex4pm.Application` (see `~/ex4pm/lib/ex4pm/application.ex`'s own
  moduledoc -- "formerly `Ex4pm.Runtime.Application`"). Depending on another
  repo's internal module layout made this test brittle to upstream
  refactors it has nothing to do with, so the fixture module content is now
  written here directly -- still real, unmodified, self-contained
  `Application`/`Supervisor` (both stdlib) content that compiles standalone
  -- into a real temporary subdirectory of THIS project (`~/ggen_igniter`,
  whose own deps are already fetched/compiled, so no network `mix deps.get`
  is needed), run for real via `mix igniter.refactor.rename_function`, and
  cleaned up in `on_exit`. This is the only test file in this family that
  changes files inside this repo's own working tree during a run -- always
  removed by `on_exit`, verified by asserting `git status --short` shows
  nothing left over.
  """

  use ExUnit.Case, async: false
  @moduletag :integration

  @fixture_module """
  defmodule Ex4pm.Runtime.Application do
    @moduledoc \"\"\"
    Top-level OTP application for the ex4pm_runtime app.
    \"\"\"
    use Application

    @impl true
    def start(_type, _args) do
      Supervisor.start_link([], strategy: :one_for_one, name: Ex4pm.Runtime.Supervisor)
    end
  end
  """

  setup do
    repo_root = File.cwd!()

    probe_dir =
      Path.join(repo_root, "lib/tmp_ex4pm_probe_#{System.unique_integer([:positive])}")

    File.rm_rf!(probe_dir)
    File.mkdir_p!(probe_dir)

    target_path = Path.join(probe_dir, "application.ex")
    File.write!(target_path, @fixture_module)

    on_exit(fn -> File.rm_rf!(probe_dir) end)

    {:ok, repo_root: repo_root, target_path: target_path}
  end

  describe "mix igniter.refactor.rename_function (real CLI, real ex4pm_runtime Application module)" do
    test "renames the real Ex4pm.Runtime.Application.start/2 in place via a real subprocess",
         %{repo_root: repo_root, target_path: target_path} do
      {output, exit_code} =
        System.cmd(
          "mix",
          [
            "igniter.refactor.rename_function",
            "Ex4pm.Runtime.Application.start/2",
            "Ex4pm.Runtime.Application.boot/2",
            "--yes"
          ],
          cd: repo_root,
          stderr_to_stdout: true
        )

      assert exit_code == 0, "real subprocess failed:\n#{output}"

      content = File.read!(target_path)
      assert content =~ "def boot(_type, _args) do"
      refute content =~ "def start(_type, _args) do"
      # the real, untouched Supervisor call survives byte-for-byte
      assert content =~
               "Supervisor.start_link([], strategy: :one_for_one, name: Ex4pm.Runtime.Supervisor)"
    end
  end
end
