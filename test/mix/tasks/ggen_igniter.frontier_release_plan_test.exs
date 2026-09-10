defmodule Mix.Tasks.GgenIgniter.FrontierReleasePlanTest do
  @moduledoc "Chicago-style: runs the real Mix task end to end and asserts on its real stdout, with no mocks/stubs."

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @task_args [
    "--opportunity-id",
    "frontier-release-example",
    "--project-name",
    "frontier_response",
    "--project-dir",
    "/tmp/frontier_response",
    "--target-repository",
    "seanchatmangpt/frontier-response",
    "--pack-dir",
    "/packs/frontier-release-factory-pack",
    "--response-mode",
    "compose",
    "--repository-mode",
    "create",
    "--visibility",
    "public"
  ]

  test "reports the real ordered steps for a create-mode plan" do
    output =
      capture_io(fn ->
        Mix.Tasks.GgenIgniter.FrontierReleasePlan.run(@task_args)
      end)

    assert output =~ "ggen_igniter.frontier_release_plan"
    assert output =~ "scaffold-local-project"
    assert output =~ "manufacture-from-pack"
    assert output =~ "verify-local-project"
    assert output =~ "create-github-repository"
    assert output =~ "do_intents (broker-required): 1"
  end

  test "reports the real JSON plan with construct and do intents split" do
    output =
      capture_io(fn ->
        Mix.Tasks.GgenIgniter.FrontierReleasePlan.run(@task_args ++ ["--json"])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert length(decoded["steps"]) == 4
    assert length(decoded["construct_intents"]) == 2
    assert length(decoded["do_intents"]) == 1
    assert hd(decoded["do_intents"])["executable"] == "gh"
  end

  test "reuse mode never emits a repository-create DO intent" do
    args =
      @task_args
      |> replace("--repository-mode", "reuse")
      |> replace("--response-mode", "extend")

    output =
      capture_io(fn ->
        Mix.Tasks.GgenIgniter.FrontierReleasePlan.run(args ++ ["--json"])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["do_intents"] == []
    refute Enum.any?(decoded["steps"], &(&1["id"] == "scaffold-local-project"))
  end

  test "reports a real validation error for a missing required flag" do
    args = List.delete_at(@task_args, Enum.find_index(@task_args, &(&1 == "--project-name")) )
    args = List.delete_at(args, Enum.find_index(args, &(&1 == "frontier_response")))

    output =
      capture_io(:stderr, fn ->
        Mix.Tasks.GgenIgniter.FrontierReleasePlan.run(args)
      end)

    assert output =~ "missing_required"
    assert output =~ "project_name"
  end

  defp replace(args, flag, value) do
    idx = Enum.find_index(args, &(&1 == flag))
    List.replace_at(args, idx + 1, value)
  end
end
