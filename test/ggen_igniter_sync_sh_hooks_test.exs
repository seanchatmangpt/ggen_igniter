defmodule GgenIgniter.SyncShHooksTest do
  @moduledoc """
  Chicago-style, real subprocess, no mocks: proves `sh_before:`/`sh_after:`
  frontmatter fields are real (not just parsed-and-inert) against
  `mix ggen_igniter.sync`'s INLINE pipeline (`run_pipeline!/3`) -- the
  ReconcileReactor pipeline is covered separately in
  `test/ggen_igniter_reconcile_reactor_sh_hooks_test.exs`, since these are
  two genuinely separate call paths (see `Mix.Tasks.GgenIgniter.Sync`'s own
  moduledoc). This suite runs the real CLI task as a real subprocess and
  asserts on real resulting file/marker state and real `GgenIgniter.Receipt`
  content on disk -- never on "was ShellHook.run called".
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.Receipt

  defp tmp_dir!(basename) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_sh_hooks_test_#{basename}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp run(args) do
    System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
  end

  # `--for-each spec` is the load-bearing bit here, NOT genuine multi-row
  # fan-out (the `spec` query returns exactly one row) -- it is what forces
  # `run_via_reactor/3` to return `{:not_delegatable, "--for-each ..."}`
  # (`GgenIgniter.Reactors.ReconcileReactor.run/1` does not implement
  # `--for-each` fan-out at all), so this suite genuinely exercises
  # `run_pipeline!/3`'s own inline `actuate_row!/11` wiring -- the SEPARATE
  # call path this module's own moduledoc and
  # `test/ggen_igniter_reconcile_reactor_sh_hooks_test.exs` both cite. Without
  # `--for-each`, an ordinary `mode: file` template routes through the
  # Reactor pipeline instead (AR-9/AR-10), which would silently test the
  # WRONG code path.
  defp base_args(template, out_path, manifest_dir, extra) do
    [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/audit_trail_ontology.ttl",
      "--query",
      "spec=test/fixtures/spec.rq",
      "--for-each",
      "spec",
      "--template",
      template,
      "--out",
      out_path,
      "--manifest-dir",
      manifest_dir
    ] ++ extra
  end

  describe "sh_after: without --allow-sh" do
    test "refuses the whole run before any actuation -- no file written, no hook run" do
      dir = tmp_dir!("refuse")
      out_path = Path.join(dir, "out.ex")
      marker = Path.join(dir, "sh_after_ran.marker")

      args =
        base_args("test/fixtures/sh_after_success_template.ex.eex", out_path, dir, [])

      {output, exit_code} = run(args)

      assert exit_code != 0
      assert output =~ "--allow-sh"
      assert output =~ "sh_after"

      refute File.exists?(out_path)
      refute File.exists?(marker)
    end
  end

  describe "sh_after: with --allow-sh (real success)" do
    test "runs the real command after a real write, and populates a real Receipt.commands entry" do
      dir = tmp_dir!("success")
      out_path = Path.join(dir, "out.ex")
      marker = Path.join(dir, "sh_after_ran.marker")

      args =
        base_args("test/fixtures/sh_after_success_template.ex.eex", out_path, dir, ["--allow-sh"])

      {output, exit_code} = run(args)

      assert exit_code == 0, "mix ggen_igniter.sync --allow-sh failed:\n#{output}"
      assert output =~ "ggen_igniter: wrote #{out_path}"
      assert output =~ "ran sh_after: touch sh_after_ran.marker"

      assert File.exists?(out_path)
      assert File.read!(out_path) =~ "def package_name, do: \"audit_trail\""
      # The real `touch` command genuinely ran, cd:'d into --manifest-dir.
      assert File.exists?(marker)

      assert [receipt] = Receipt.read_all!(dir)
      assert receipt["standing"] == "alive"
      assert [command] = receipt["commands"]
      assert command["kind"] == "sh_after"
      assert command["cmd"] == "touch sh_after_ran.marker"
      assert command["exit_code"] == 0
      assert command["status"] == "ok"
      assert is_integer(command["duration_ms"])
    end
  end

  describe "sh_after: with --dry-run (real command never runs)" do
    test "previews the exact planned line and touches nothing at all" do
      dir = tmp_dir!("dry_run")
      out_path = Path.join(dir, "out.ex")
      marker = Path.join(dir, "sh_after_ran.marker")

      args =
        base_args("test/fixtures/sh_after_success_template.ex.eex", out_path, dir, [
          "--allow-sh",
          "--dry-run"
        ])

      {output, exit_code} = run(args)

      assert exit_code == 0, "mix ggen_igniter.sync --dry-run failed:\n#{output}"
      assert output =~ "planned: run sh_after: touch sh_after_ran.marker"
      assert output =~ "planned: write #{out_path}"

      # Real proof the underlying subprocess genuinely never started: the
      # marker file `touch` would have created does not exist, and neither
      # does the main output file --dry-run also never writes.
      refute File.exists?(marker)
      refute File.exists?(out_path)
      refute File.exists?(Receipt.dir(dir))
    end
  end

  describe "sh_after: real nonzero exit does NOT abort the run" do
    test "the row's outcome is reported as sh_after failed, the file WAS written, and the process exits 0" do
      dir = tmp_dir!("after_fail")
      out_path = Path.join(dir, "out.ex")

      args =
        base_args("test/fixtures/sh_after_fail_template.ex.eex", out_path, dir, ["--allow-sh"])

      {output, exit_code} = run(args)

      assert exit_code == 0,
             "a failing sh_after: must not abort the whole run, got exit #{exit_code}:\n#{output}"

      assert output =~ "sh_after failed (exit 7): exit 7"
      # The real write already happened before sh_after ran -- not reverted
      # (no compensation exists for a shell-hook failure, per the disclosed
      # limitation).
      assert File.exists?(out_path)

      assert [receipt] = Receipt.read_all!(dir)
      assert [command] = receipt["commands"]
      assert command["status"] == "failed"
      assert command["exit_code"] == 7
    end
  end

  describe "sh_before: real nonzero exit skips the write but does NOT abort the run" do
    test "the row's outcome is reported as sh_before failed and the target is never written" do
      dir = tmp_dir!("before_fail")
      out_path = Path.join(dir, "out.ex")

      args =
        base_args("test/fixtures/sh_before_fail_template.ex.eex", out_path, dir, ["--allow-sh"])

      {output, exit_code} = run(args)

      assert exit_code == 0,
             "a failing sh_before: must not abort the whole run, got exit #{exit_code}:\n#{output}"

      assert output =~ "sh_before failed (exit 5): exit 5"
      refute File.exists?(out_path)

      assert [receipt] = Receipt.read_all!(dir)
      assert [command] = receipt["commands"]
      assert command["kind"] == "sh_before"
      assert command["status"] == "failed"
      assert command["exit_code"] == 5
    end
  end
end
