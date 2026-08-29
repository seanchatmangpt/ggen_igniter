defmodule GgenIgniter.PlanTaskTest do
  @moduledoc """
  Chicago-style: real `System.cmd("mix", ["ggen_igniter.plan", ...])` subprocess
  invocations of the real `mix ggen_igniter.plan` task -- no mocking of any kind.
  Mirrors `test/ggen_igniter_doctor_task_test.exs`'s exact verification technique
  for the `--json` single-clean-document regression (piping real stdout through a
  real external `python3 -m json.tool` subprocess) and
  `test/ggen_igniter_sync_task_test.exs`'s real-subprocess pattern generally.

  Reuses `test/fixtures/sample-pack/` (the same real fixture pack
  `ggen_igniter_doctor_task_test.exs` already exercises via `--pack-dir`) rather
  than inventing a new fixture pack.

  This file is a new complementary test file -- it does not edit or replace
  `test/ggen_igniter_plan_schema_test.exs`, which is a pure local JSON-schema
  fixture validator with no real task invocation.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @pack_dir "test/fixtures/sample-pack"

  describe "mix ggen_igniter.plan --json" do
    test "emits exactly one valid JSON document, verified by a real external " <>
           "python3 -m json.tool subprocess" do
      # Must stay within the repo root (GgenIgniter.ArtifactIdentity's
      # authorized-project-root check refuses paths outside `File.cwd!()`,
      # exercised for real here rather than worked around) -- a fresh,
      # never-existing relative path under the fixture pack itself, exactly
      # like `test/ggen_igniter_sync_task_test.exs`'s real `--out` usage.
      out_path =
        Path.join(@pack_dir, "plan_test_out_#{System.unique_integer([:positive])}.ex")

      File.rm(out_path)
      on_exit(fn -> File.rm(out_path) end)

      {output, exit_code} =
        System.cmd(
          "mix",
          ["ggen_igniter.plan", "--pack-dir", @pack_dir, "--out", out_path, "--json"],
          cd: File.cwd!()
        )

      assert exit_code == 0, "mix ggen_igniter.plan --json failed:\n#{output}"

      # Real, computed plan data -- nothing was actually written to disk (this
      # task is read-only, per its own moduledoc).
      refute File.exists?(out_path)

      payload = Jason.decode!(output)
      assert payload["engine"] == "oxigraph"
      assert is_list(payload["pending_actuations"])
      assert [pending] = payload["pending_actuations"]
      assert pending["operation"] == "create"
      assert pending["target"] == out_path
      assert is_binary(pending["desired_hash"])

      # A real subprocess-level regression test for the same class of bug
      # ggen_igniter_doctor_task_test.exs's `--json` tests close: Igniter's own
      # "No proposed content changes!" footer (or any other trailing text) must
      # never follow the JSON document on stdout.
      refute output =~ "No proposed content changes"
      refute output =~ "Igniter:"

      tmp_json_path =
        Path.join(
          System.tmp_dir!(),
          "ggen_igniter_plan_json_#{System.unique_integer([:positive])}.json"
        )

      File.write!(tmp_json_path, output)
      on_exit(fn -> File.rm(tmp_json_path) end)

      case System.find_executable("python3") do
        nil ->
          :ok

        python3 ->
          {py_output, py_exit} =
            System.cmd(python3, ["-m", "json.tool", tmp_json_path], stderr_to_stdout: true)

          assert py_exit == 0,
                 "python3 -m json.tool rejected mix ggen_igniter.plan --json output as " <>
                   "invalid/extra-data JSON:\n#{py_output}"
      end
    end
  end

  describe "mix ggen_igniter.plan --help / -h" do
    test "both produce byte-identical, concise USAGE/FLAGS help output, exit 0" do
      {help_output, help_exit} =
        System.cmd("mix", ["ggen_igniter.plan", "--help"],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      {h_output, h_exit} =
        System.cmd("mix", ["ggen_igniter.plan", "-h"], cd: File.cwd!(), stderr_to_stdout: true)

      assert help_exit == 0, "mix ggen_igniter.plan --help failed:\n#{help_output}"
      assert h_exit == 0, "mix ggen_igniter.plan -h failed:\n#{h_output}"

      # Real regression test for AR-11 (fixed for sync/doctor in commit b184d907):
      # Igniter's own generated `run/1` intercepts `-h` before this task's own
      # `print_help/0` unless the task deliberately routes both flags to the same
      # concise help text -- neither flag should ever fall through to Igniter's
      # full generated Mix.Task moduledoc dump.
      assert help_output == h_output,
             "mix ggen_igniter.plan --help and -h produced different output " <>
               "(a real, disclosed regression -- see AR-11):\n\n" <>
               "--help:\n#{help_output}\n\n-h:\n#{h_output}"

      assert help_output =~ "USAGE"
      assert help_output =~ "FLAGS"
      assert help_output =~ "mix ggen_igniter.plan --template path.eex --query name=path.rq"

      # Neither flag's output should be Igniter's own generated task-help dump
      # (which prints the module's full @moduledoc, not a concise USAGE block).
      refute help_output =~ "## Read-only, no lock (FR-5)"
      refute h_output =~ "## Read-only, no lock (FR-5)"
    end
  end
end
