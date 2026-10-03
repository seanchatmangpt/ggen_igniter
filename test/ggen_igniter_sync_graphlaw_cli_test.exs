defmodule GgenIgniter.SyncGraphlawCliTest do
  @moduledoc """
  CLI-arg-handling tests for the graphlaw engine lane (W3): `--engine
  graphlaw` and `--engine oxigraph,graphlaw` comparison mode through the REAL
  `GgenIgniter.EngineRegistry.resolve/1` and the REAL `mix ggen_igniter.sync`
  subprocess over a real 2-triple specimen
  (`test/fixtures/graphlaw_specimen.ttl` -- `ex:a ex:p ex:b .` and
  `ex:c ex:p ex:d .`).

  Chicago-style: real registry, real wasm artifact, real subprocess, asserts
  on real files/exit codes. No mocks.

  The comparison-mode test documents the ADR-0008 evidence gate W3 added to
  `lib/mix/tasks/ggen_igniter.sync.ex`'s `report_engine_comparison!/2`: a
  real row-set disagreement between two successfully-run engines REFUSES the
  run with the typed refusal `REFUSED:ENGINE_COMPARISON_DIVERGENT` (nonzero
  exit, Mix error exit code 1) rather than rendering from divergent evidence.
  Row-order-only divergence stays non-fatal (separately tracked as
  `order_equal?`).
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.EngineRegistry

  # ------------------------------------------------------------------
  # Registry parsing (real EngineRegistry.resolve/1)
  # ------------------------------------------------------------------

  test "--engine graphlaw resolves to a single-engine list" do
    assert {:ok, [:graphlaw]} = EngineRegistry.resolve("graphlaw")
  end

  test "--engine oxigraph,graphlaw resolves to both, in named order" do
    assert {:ok, [:oxigraph, :graphlaw]} = EngineRegistry.resolve("oxigraph,graphlaw")
  end

  test "--engine all includes graphlaw" do
    assert {:ok, engines} = EngineRegistry.resolve("all")
    assert :graphlaw in engines
    # `all` sorts non-qlever names ascending, qlever (if any) last.
    assert engines ==
             Enum.sort(engines -- [:qlever]) ++ if(:qlever in engines, do: [:qlever], else: [])
  end

  test "an invalid engine name still refuses" do
    assert {:error, _} = EngineRegistry.resolve("nope")
  end

  # ------------------------------------------------------------------
  # Comparison mode over the real 2-triple specimen (real subprocess)
  # ------------------------------------------------------------------

  describe "mix ggen_igniter.sync --engine oxigraph,graphlaw (real subprocess)" do
    # async: false -- real `mix` subprocesses share this checkout's _build.
    # ExUnit has no per-describe async toggle; the module-level `async: true`
    # above is safe for the pure registry tests, and the subprocess tests
    # below each use their own tmp dirs and serialize naturally on the
    # shared _build lock held by `mix` itself.
    @describetag :integration

    setup do
      root_dir =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_graphlaw_cli_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(root_dir)
      on_exit(fn -> File.rm_rf!(root_dir) end)

      %{
        root_dir: root_dir,
        out_path: Path.join(root_dir, "output/specimen.ex"),
        report_path: Path.join(root_dir, "engine_report.json")
      }
    end

    test "--engine graphlaw alone runs the specimen and renders the output",
         %{out_path: out_path, report_path: _report_path} = ctx do
      {output, exit_code} =
        System.cmd("mix", sync_args(ctx) ++ ["--engine", "graphlaw"],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      assert exit_code == 0, "sync --engine graphlaw failed:\n#{output}"
      assert File.exists?(out_path)
      assert output =~ "graphlaw"
    end

    test "comparison mode produces a report with both engines' columns and zero disagreement",
         %{report_path: report_path} = ctx do
      {output, exit_code} =
        System.cmd("mix", sync_args(ctx) ++ ["--engine", "oxigraph,graphlaw"],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      assert exit_code == 0, "comparison run failed:\n#{output}"
      assert File.exists?(report_path)
      assert {:ok, decoded} = Jason.decode(File.read!(report_path))

      assert %{
               "query" => _,
               "candidates" => [
                 %{"engine" => "oxigraph", "status" => "ok"},
                 %{"engine" => "graphlaw", "status" => "ok"}
               ]
             } = decoded

      agreements = decoded["pairwise_agreement"]
      assert is_list(agreements) and agreements != []

      assert Enum.all?(agreements, fn agreement ->
               agreement["row_set_equal?"] == true
             end)

      # Documented evidence gate (W3, `report_engine_comparison!/2`): a real
      # row-set DISAGREEMENT between two successfully-run engines exits
      # NONZERO with the typed refusal `REFUSED:ENGINE_COMPARISON_DIVERGENT`
      # (Mix error exit code 1) instead of rendering from divergent evidence.
      # The agreement above is 100%, so the gate does not fire on this
      # specimen; the refusal text/exit-code contract it enforces is:
      #
      #   exit_code != 0 and output =~ "REFUSED:ENGINE_COMPARISON_DIVERGENT"
      #
      # on any specimen where the engines genuinely disagree.
    end
  end

  defp sync_args(%{root_dir: root_dir, out_path: out_path, report_path: report_path}) do
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
      "--engine-report",
      report_path,
      "--verify-cwd",
      File.cwd!()
    ]
  end
end
