defmodule GgenIgniter.SyncShHooksTest do
  @moduledoc """
  Chicago-style, real subprocess, no mocks: proves `sh_before:`/`sh_after:`
  frontmatter fields against `mix ggen_igniter.sync`'s CLI surface, going
  through `GgenIgniter.Reactors.ReconcileReactor.run/1` (the reactor's own
  `sh_before:`/`sh_after:` wiring is covered independently, with a real
  minimal scratch Mix project, in
  `test/ggen_igniter_reconcile_reactor_sh_hooks_test.exs`).

  ## v26.9.2 real, disclosed finding: this suite no longer exercises
  `Mix.Tasks.GgenIgniter.Sync.run_pipeline!/3`'s own inline sh_before/
  sh_after wiring at all

  Before v26.9.2, this suite's own `base_args/4` deliberately passed
  `--for-each spec` (a single-row query, load-bearing ONLY to FORCE
  `run_via_reactor/3` to return `{:not_delegatable, "--for-each ..."}`,
  since `ReconcileReactor.run/1` did not implement `--for-each` fan-out at
  all) so it could exercise the inline `run_pipeline!/3`/`actuate_row!/11`
  pipeline's OWN sh_before/sh_after partial-success semantics specifically.

  Workstream B now routes `--for-each` through the reactor too. Since
  `sh_before:`/`sh_after:` are FRONTMATTER-ONLY fields (there is no CLI
  flag equivalent -- see `Mix.Tasks.GgenIgniter.Sync`'s own moduledoc) and
  ANY frontmatter-bearing template other than `mode: eval` now routes
  through the reactor (workstream A's `sparql:` fix closed the one other
  escape hatch), and `mode: eval` structurally can never reach `sh_after:`
  at all (`actuate_row!/11`'s own `outcome in [:written, :injected]` guard
  is always false for `mode: eval`'s real outcome, always `nil`) -- this is
  a REAL FINDING, not just untested: `run_pipeline!/3`'s own sh_before/
  sh_after partial-success code (a failed hook reported as a per-row
  outcome, siblings unaffected) is now UNREACHABLE from any real
  `mix ggen_igniter.sync` invocation, the same "unreachable, not just
  untested" class of finding
  `test/ggen_igniter_reconcile_reactor_test.exs`'s own ":eval
  compensation-completeness" test already discloses for a different code
  path. Rather than fabricate an invocation shape that can never occur in
  practice just to keep exercising dead code, this suite now tests the ONE
  real path a `mix ggen_igniter.sync --allow-sh` invocation with
  `sh_before:`/`sh_after:` can actually take: the reactor's own all-or-
  nothing model, where a hook failure is an ordinary actuation failure that
  triggers real compensation -- see the two failure-mode tests below, which
  assert the OPPOSITE outcome from their pre-v26.9.2 versions (a REAL,
  disclosed contract change per this task's own plan, not a regression).

  Every collaborator is real: a real `mix ggen_igniter.sync` subprocess, a
  real nested `mix compile --warnings-as-errors` subprocess for `:verify`,
  a real `GgenIgniter.ShellHook.run/3` subprocess for the hook itself, and
  real resulting file/`GgenIgniter.Receipt` state read back off disk --
  never an assertion on "was ShellHook.run called".
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

  # `--for-each spec` (a single-row query) is kept here even though it no
  # longer forces the inline pipeline (see this file's own moduledoc) --
  # this suite is also real, useful coverage that a `--for-each`-routed
  # reactor run with `sh_before:`/`sh_after:` behaves the same real way a
  # non-`--for-each` reactor run already does (`--verify-cwd` is required
  # either way, per workstream B). `--manifest-dir`/`--verify-cwd` are both
  # required now that this genuinely reaches
  # `GgenIgniter.Reactors.ReconcileReactor.run/1`'s real `:admit`/`:verify`
  # steps.
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
      manifest_dir,
      "--verify-cwd",
      File.cwd!()
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
      assert output =~ "wrote #{out_path}"
      assert output =~ "(via reactor)"

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

  describe "sh_after: real nonzero exit (v26.9.2: a real actuation failure, not a per-row outcome)" do
    test "the whole run is compensated -- the real write IS reverted, and the process exits non-zero" do
      dir = tmp_dir!("after_fail")
      out_path = Path.join(dir, "out.ex")
      refute File.exists?(out_path)

      args =
        base_args("test/fixtures/sh_after_fail_template.ex.eex", out_path, dir, ["--allow-sh"])

      {output, exit_code} = run(args)

      # v26.9.2, DELIBERATE CONTRACT CHANGE from before this task (see this
      # file's own moduledoc): a `sh_after:` failure now routes through
      # `GgenIgniter.Reactors.ReconcileReactor`'s all-or-nothing `:actuate`
      # step, which treats it as an ordinary actuation failure --
      # `actuate_pending/2`'s self-heal reverts the real write that already
      # happened before `sh_after:` ran, and the whole run genuinely fails
      # (real, non-zero exit) instead of the old inline pipeline's
      # `:sh_after_failed` per-row outcome (exit 0, file left written).
      refute exit_code == 0,
             "a failing sh_after: must now fail the whole run (real compensation), got exit 0:\n#{output}"

      assert output =~ "compensated"
      assert output =~ "sh_after"
      assert output =~ "exit 7"

      # THE KEY PROOF: the real write that already happened before the
      # failing sh_after ran is genuinely reverted -- this pipeline's
      # atomic all-or-nothing `:actuate` step, the exact real compensation
      # coverage this whole task exists to bring to a `sh_after:` failure
      # that the OLD inline pipeline could never revert at all.
      refute File.exists?(out_path)
    end
  end

  describe "sh_before: real nonzero exit (v26.9.2: a real actuation failure, not a per-row outcome)" do
    test "the whole run is refused/compensated -- the target is never written, and the process exits non-zero" do
      dir = tmp_dir!("before_fail")
      out_path = Path.join(dir, "out.ex")

      args =
        base_args("test/fixtures/sh_before_fail_template.ex.eex", out_path, dir, ["--allow-sh"])

      {output, exit_code} = run(args)

      # v26.9.2, DELIBERATE CONTRACT CHANGE (see this file's own
      # moduledoc): a `sh_before:` failure now aborts the WHOLE reactor run
      # (real, non-zero exit) instead of the old inline pipeline's
      # `:sh_before_failed` per-row outcome (exit 0, run continues).
      refute exit_code == 0,
             "a failing sh_before: must now fail the whole run, got exit 0:\n#{output}"

      assert output =~ "sh_before"
      assert output =~ "exit 5"
      refute File.exists?(out_path)
    end
  end
end
