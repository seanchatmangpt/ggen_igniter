defmodule GgenIgniter.SyncEngineReportDryRunTest do
  @moduledoc """
  Chicago-style, real subprocess (no mocks): regression test for the
  high-severity finding that `report_engine_comparison!/2` in
  `lib/mix/tasks/ggen_igniter.sync.ex` wrote the `--engine-report PATH` file
  via a raw `File.write!/2` with NO `--dry-run` gate at all, unlike every
  other mutation path in the task. Runs the real `mix ggen_igniter.sync`
  task as a real OS subprocess (same pattern as
  `test/ggen_igniter_sync_dry_run_test.exs` and
  `test/ggen_igniter_engine_mode_matrix_test.exs`) with a comma-separated
  `--engine sparql,oxigraph` spec (comparison mode, per ADR-0008) plus
  `--engine-report PATH`, and asserts on real filesystem state: the report
  path must NOT exist after a `--dry-run` invocation, and MUST exist (with
  real, parseable content) after a non-dry-run invocation.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  defp base_args(out_path, manifest_dir, report_path) do
    [
      "ggen_igniter.sync",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--query",
      "sections=test/fixtures/sections.rq",
      "--query",
      "entities=test/fixtures/entities.rq",
      "--query",
      "fields=test/fixtures/fields.rq",
      "--template",
      "test/fixtures/extension.ex.eex",
      "--out",
      out_path,
      "--manifest-dir",
      manifest_dir,
      "--engine",
      "sparql,oxigraph",
      "--engine-report",
      report_path,
      "--verify-cwd",
      File.cwd!()
    ]
  end

  test "--dry-run with --engine <a,b> and --engine-report PATH writes nothing to PATH" do
    root_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_engine_report_dry_run_test_#{System.unique_integer([:positive])}"
      )

    out_dir = Path.join(root_dir, "output")
    out_path = Path.join(out_dir, "resource.ex")
    report_path = Path.join(root_dir, "engine_report.json")

    File.rm_rf!(root_dir)
    on_exit(fn -> File.rm_rf!(root_dir) end)

    {output, exit_code} =
      System.cmd("mix", base_args(out_path, root_dir, report_path) ++ ["--dry-run"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert exit_code == 0,
           "mix ggen_igniter.sync --dry-run (engine comparison) failed:\n#{output}"

    # The fix: dry-run must print a dry-run notice, never perform the write.
    assert output =~ "[dry-run]"
    assert output =~ report_path

    refute File.exists?(report_path),
           "--dry-run must not write the --engine-report file to disk, but it exists at " <>
             report_path

    # And, as before the fix, the ordinary write target is also untouched
    # under --dry-run (this file's real regression is scoped to the report
    # write specifically, but the rest of the pipeline's existing dry-run
    # discipline should still hold here too).
    refute File.exists?(out_path)
  end

  test "without --dry-run, --engine <a,b> and --engine-report PATH really writes PATH" do
    root_dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_engine_report_real_write_test_#{System.unique_integer([:positive])}"
      )

    out_dir = Path.join(root_dir, "output")
    out_path = Path.join(out_dir, "resource.ex")
    report_path = Path.join(root_dir, "engine_report.json")

    File.rm_rf!(root_dir)
    on_exit(fn -> File.rm_rf!(root_dir) end)

    {output, exit_code} =
      System.cmd("mix", base_args(out_path, root_dir, report_path),
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert exit_code == 0,
           "mix ggen_igniter.sync (engine comparison, real run) failed:\n#{output}"

    assert output =~ "engine comparison report written to #{report_path}"
    assert File.exists?(report_path)

    # Real content: valid JSON (report_path has a .json extension per
    # `encode_engine_report/2`'s extension dispatch).
    content = File.read!(report_path)
    assert {:ok, _decoded} = Jason.decode(content)
  end
end
