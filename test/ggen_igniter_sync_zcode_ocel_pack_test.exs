defmodule GgenIgniter.SyncZcodeOcelPackTaskTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `mix ggen_igniter.sync --pack zcode-ocel-pack`
  manufactures the zcode OCEL TypeScript registry (real subprocess, real oxigraph/sparql
  engine, real file on disk). Assertions are on the generated file's content.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @events ~w(TurnStarted TurnComplete TurnError ModelRequest ModelComplete ToolCallScheduled
             ToolCallStarted ToolCallResult ToolCallError PermissionRequested PermissionResolved
             SubagentSpawned SubagentStopped CompactStarted CompactCompleted)
  @objects ~w(session turn tool_call model_request subagent permission file)

  test "sync --pack zcode-ocel-pack writes the full event/object registry" do
    out_dir =
      Path.join(System.tmp_dir!(), "ggen_igniter_zcode_ocel_#{System.unique_integer([:positive])}")

    File.rm_rf!(out_dir)
    on_exit(fn -> File.rm_rf!(out_dir) end)
    out_path = Path.join(out_dir, "registry.ts")

    args = [
      "ggen_igniter.sync", "--engine", "sparql", "--pack", "zcode-ocel-pack",
      "--out", out_path, "--manifest-dir", out_dir, "--verify-cwd", File.cwd!()
    ]

    {output, code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
    assert code == 0, "sync failed:\n#{output}"
    assert output =~ "ggen_igniter: wrote #{out_path}"

    content = File.read!(out_path)

    for e <- @events do
      assert content =~ ~s("#{e}",), "missing event type #{e}"
      assert content =~ ~r/#{e}: \{ from: "\w+", to: "\w+" \}/, "missing transition for #{e}"
    end

    for o <- @objects, do: assert(content =~ ~s("#{o}",), "missing object type #{o}")

    assert content =~ ~s({ event: "ToolCallResult", object: "file", qualifier: "touched" })
    assert content =~ ~s(ToolCallStarted: { from: "tool_pending", to: "tool_running" })
    assert content =~ "export type EventType = (typeof EVENT_TYPES)[number]"
  end
end
