defmodule GgenIgniter.SyncGraphlawCliTest do
  @moduledoc """
  CLI-level tests for the FIXED engine (2026-10-17): the engine is a
  constant (`GgenIgniter.Engine.fixed/0` == "graphlaw"); there is no
  `--engine` flag to pass. The former selectable/comparison surface
  (`--engine oxigraph,graphlaw`, `--engine-report`, `--store-id`) is removed;
  these tests pin the fail-closed behavior and prove the fixed engine runs
  the real specimen end-to-end through a real `mix ggen_igniter.sync`
  subprocess.

  Chicago-style: real registry, real wasm artifact, real subprocess, asserts
  on real files/exit codes. No mocks.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.EngineRegistry

  # ------------------------------------------------------------------
  # Fixed-engine resolution (real EngineRegistry.resolve/1)
  # ------------------------------------------------------------------

  test "the fixed engine name resolves to a single-engine list" do
    assert {:ok, [:graphlaw]} = EngineRegistry.resolve("graphlaw")
  end

  test "\"all\" trivially expands to the one fixed engine" do
    assert {:ok, [:graphlaw]} = EngineRegistry.resolve("all")
  end

  test "any other name (including historical engine names) refuses" do
    for name <- ["nope", "oxigraph", "sparql", "qlever", "oxigraph,graphlaw"] do
      assert {:error, msg} = EngineRegistry.resolve(name)
      assert msg =~ "fixed"
    end
  end

  # ------------------------------------------------------------------
  # Fixed engine over the real 2-triple specimen (real subprocess)
  # ------------------------------------------------------------------

  describe "mix ggen_igniter.sync (fixed engine, real subprocess)" do
    # async: false -- real `mix` subprocesses share this checkout's _build.
    @describetag :integration

    setup do
      root_dir =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_graphlaw_cli_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(root_dir)
      on_exit(fn -> File.rm_rf!(root_dir) end)

      %{root_dir: root_dir, out_path: Path.join(root_dir, "output/specimen.ex")}
    end

    test "the fixed engine runs the specimen and renders the output", %{
      out_path: out_path,
      root_dir: root_dir
    } = ctx do
      {output, exit_code} =
        System.cmd("mix", sync_args(ctx), cd: File.cwd!(), stderr_to_stdout: true)

      assert exit_code == 0, "sync (fixed engine) failed:\n#{output}"
      assert File.exists?(out_path)
      assert output =~ "graphlaw"
      assert root_dir != nil
    end

    test "passing the removed --engine flag is an invalid invocation (fail-closed)", %{
      root_dir: root_dir
    } = ctx do
      {output, exit_code} =
        System.cmd(
          "mix",
          sync_args(ctx) ++ ["--engine", "oxigraph"],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      refute exit_code == 0, "expected the removed --engine flag to refuse, got 0:\n#{output}"
      assert output =~ "engine"
    end
  end

  defp sync_args(%{root_dir: root_dir, out_path: out_path}) do
    [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/graphlaw_specimen.ttl",
      "--query",
      "pairs=test/fixtures/graphlaw_specimen.rq",
      "--template",
      "test/fixtures/graphlaw_specimen.ex.eex",
      "--out",
      out_path,
      "--manifest-dir",
      root_dir,
      "--verify-cwd",
      File.cwd!()
    ]
  end
end
