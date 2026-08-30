defmodule GgenIgniter.SyncInjectTest do
  @moduledoc """
  Chicago-style, real subprocess, no mocks: proves the real, closed injection
  gap -- before this test (and the `sync.ex`/`frontmatter.ex`/`actuate.ex`
  wiring it exercises), a template's `inject: true`/`before:`/`after:`/
  `at_line:` frontmatter fields were parsed but had NO observable effect on
  `mix ggen_igniter.sync`'s behavior; it only ever dispatched to
  `Actuate.write_file!/3`. This suite runs the real CLI task as a real
  subprocess against a real, pre-existing target file on disk, and asserts
  on the real resulting file content -- never on "was inject_content! called".
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  defp tmp_target(basename) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_inject_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    path = Path.join(dir, basename)
    on_exit(fn -> File.rm_rf!(dir) end)
    path
  end

  defp run(args) do
    System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
  end

  # v26.9.2 (workstream A): every fixture in this file (`inject_*.ex.eex`)
  # has a frontmatter inline `sparql:` block, which used to make
  # `Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3` refuse to delegate at all
  # (falling back to the pre-existing inline `run_pipeline!/3` pipeline,
  # which has no authorized-root check and no `:verify` step) -- a real,
  # confirmed finding this session: EVERY test in this file was silently
  # exercising the INLINE pipeline, not `GgenIgniter.Reactors.
  # ReconcileReactor`'s real `:inject`-typed actuation the file's own
  # moduledoc/AR-10's sync.ex comments both claimed. Now that workstream A
  # resolves inline `sparql:` too, these genuinely route through the
  # reactor, which enforces the SAME authorized-project-root/`:verify`
  # requirements every other reactor-routed write in this codebase already
  # does -- `path` here always resolves outside the repo root (a real tmp
  # dir), so `--manifest-dir`/`--verify-cwd` are required the same way
  # `ggen_igniter_sync_task_test.exs`'s own equivalent flags already are.
  defp manifest_args(path) do
    ["--manifest-dir", Path.dirname(path), "--verify-cwd", File.cwd!()]
  end

  describe "inject: true with a literal after: marker" do
    test "splices the rendered body immediately after the matched anchor line, and re-run is idempotent" do
      path = tmp_target("after_target.ex")

      File.write!(path, """
      defmodule InjectAfterTarget do
        # GGEN:INJECT:AFTER
      end
      """)

      args =
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--ontology",
          "test/fixtures/audit_trail_ontology.ttl",
          "--template",
          "test/fixtures/inject_after_literal.ex.eex",
          "--out",
          path
        ] ++ manifest_args(path)

      {output, exit_code} = run(args)
      assert exit_code == 0, "mix ggen_igniter.sync (inject after) failed:\n#{output}"
      assert output =~ "ggen_igniter: injected #{path}"

      assert File.read!(path) == """
             defmodule InjectAfterTarget do
               # GGEN:INJECT:AFTER
               def injected_package_name, do: "audit_trail"
             end
             """

      # Idempotent re-run: same anchor, same content already spliced in at
      # the exact resolved position -> :unchanged, file untouched.
      {output2, exit_code2} = run(args)
      assert exit_code2 == 0, "re-run failed:\n#{output2}"
      assert output2 =~ "ggen_igniter: unchanged (skipped, identical content): #{path}"

      assert File.read!(path) == """
             defmodule InjectAfterTarget do
               # GGEN:INJECT:AFTER
               def injected_package_name, do: "audit_trail"
             end
             """
    end
  end

  describe "inject: true with a literal before: marker" do
    test "splices the rendered body immediately before the matched anchor line" do
      path = tmp_target("before_target.ex")

      File.write!(path, """
      defmodule InjectBeforeTarget do
        # GGEN:INJECT:BEFORE
      end
      """)

      args =
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--ontology",
          "test/fixtures/audit_trail_ontology.ttl",
          "--template",
          "test/fixtures/inject_before_literal.ex.eex",
          "--out",
          path
        ] ++ manifest_args(path)

      {output, exit_code} = run(args)
      assert exit_code == 0, "mix ggen_igniter.sync (inject before) failed:\n#{output}"
      assert output =~ "ggen_igniter: injected #{path}"

      assert File.read!(path) == """
             defmodule InjectBeforeTarget do
               def injected_extension_target, do: "resource"
               # GGEN:INJECT:BEFORE
             end
             """
    end
  end

  describe "inject: true with at_line:" do
    test "splices the rendered body at the given 1-based line number, and re-run is idempotent" do
      path = tmp_target("at_line_target.ex")

      File.write!(path, """
      defmodule InjectAtLineTarget do
      end
      """)

      args =
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--ontology",
          "test/fixtures/audit_trail_ontology.ttl",
          "--template",
          "test/fixtures/inject_at_line.ex.eex",
          "--out",
          path
        ] ++ manifest_args(path)

      {output, exit_code} = run(args)
      assert exit_code == 0, "mix ggen_igniter.sync (inject at_line) failed:\n#{output}"
      assert output =~ "ggen_igniter: injected #{path}"

      assert File.read!(path) == """
             defmodule InjectAtLineTarget do
               def injected_at_line, do: "AuditTrail.Resource"
             end
             """

      {output2, exit_code2} = run(args)
      assert exit_code2 == 0, "re-run failed:\n#{output2}"
      assert output2 =~ "ggen_igniter: unchanged (skipped, identical content): #{path}"
    end
  end

  describe "inject: true with a structured MatchRule (matcher: regex)" do
    test "splices the rendered body after the regex-matched anchor line, and re-run is idempotent" do
      path = tmp_target("regex_target.ex")

      File.write!(path, """
      defmodule InjectRegexTarget do
        # GGEN:INJECT:REGEX
      end
      """)

      args =
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--ontology",
          "test/fixtures/audit_trail_ontology.ttl",
          "--template",
          "test/fixtures/inject_structured_regex.ex.eex",
          "--out",
          path
        ] ++ manifest_args(path)

      {output, exit_code} = run(args)
      assert exit_code == 0, "mix ggen_igniter.sync (inject structured regex) failed:\n#{output}"
      assert output =~ "ggen_igniter: injected #{path}"

      assert File.read!(path) == """
             defmodule InjectRegexTarget do
               # GGEN:INJECT:REGEX
               def injected_regex, do: "audit_trail"
             end
             """

      {output2, exit_code2} = run(args)
      assert exit_code2 == 0, "re-run failed:\n#{output2}"
      assert output2 =~ "ggen_igniter: unchanged (skipped, identical content): #{path}"
    end
  end

  describe "inject: true with --dry-run" do
    test "reports 'planned: inject ...' and touches nothing on a not-yet-injected target" do
      path = tmp_target("dry_run_target.ex")

      original = """
      defmodule InjectAfterTarget do
        # GGEN:INJECT:AFTER
      end
      """

      File.write!(path, original)

      args =
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--ontology",
          "test/fixtures/audit_trail_ontology.ttl",
          "--template",
          "test/fixtures/inject_after_literal.ex.eex",
          "--out",
          path,
          "--dry-run"
        ] ++ manifest_args(path)

      {output, exit_code} = run(args)
      assert exit_code == 0, "mix ggen_igniter.sync --dry-run (inject) failed:\n#{output}"
      assert output =~ "planned: inject #{path}"

      # Zero writes: the real anchor-resolution check ran for real (a
      # missing/ambiguous anchor would still raise under --dry-run), but the
      # target file's actual bytes are completely untouched.
      assert File.read!(path) == original
    end

    test "reports 'planned: skip ... (unchanged)' and touches nothing once already injected" do
      path = tmp_target("dry_run_unchanged_target.ex")

      File.write!(path, """
      defmodule InjectAfterTarget do
        # GGEN:INJECT:AFTER
      end
      """)

      args =
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--ontology",
          "test/fixtures/audit_trail_ontology.ttl",
          "--template",
          "test/fixtures/inject_after_literal.ex.eex",
          "--out",
          path
        ] ++ manifest_args(path)

      # First, a real (non-dry-run) injection.
      {setup_output, setup_exit} = run(args)
      assert setup_exit == 0, "setup real injection failed:\n#{setup_output}"
      injected_content = File.read!(path)
      injected_mtime = File.stat!(path).mtime

      {output, exit_code} = run(args ++ ["--dry-run"])

      assert exit_code == 0,
             "mix ggen_igniter.sync --dry-run (inject unchanged) failed:\n#{output}"

      assert output =~ "planned: skip #{path} (unchanged)"

      # Byte-identical and untouched (mtime unchanged -- proves no write
      # syscall touched it, not just that the bytes happen to match).
      assert File.read!(path) == injected_content
      assert File.stat!(path).mtime == injected_mtime
    end
  end

  describe "inject: true fails closed: ambiguous anchor" do
    test "both before: and after: set raises a clear error, real non-zero exit" do
      args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--ontology",
        "test/fixtures/audit_trail_ontology.ttl",
        "--template",
        "test/fixtures/inject_ambiguous_anchor.ex.eex",
        "--out",
        Path.join(
          System.tmp_dir!(),
          "should_not_be_touched_#{System.unique_integer([:positive])}.ex"
        )
      ]

      {output, exit_code} = run(args)
      assert exit_code != 0
      assert output =~ "more than one anchor is set"
      assert output =~ "before:, after:"
    end
  end

  describe "inject: true fails closed: unsupported structured MatchRule combination" do
    test "occurrence: last (not implemented) raises a clear, named error, real non-zero exit" do
      args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--ontology",
        "test/fixtures/audit_trail_ontology.ttl",
        "--template",
        "test/fixtures/inject_unsupported_occurrence.ex.eex",
        "--out",
        Path.join(
          System.tmp_dir!(),
          "should_not_be_touched_#{System.unique_integer([:positive])}.ex"
        )
      ]

      {output, exit_code} = run(args)
      assert exit_code != 0
      assert output =~ "occurrence: :last"
      assert output =~ "not yet"
      assert output =~ "supported by ggen_igniter's injection engine"
    end
  end

  describe "inject: true fails closed: target file does not exist" do
    test "raises inject_content!/5's real 'does not exist' error, real non-zero exit" do
      missing_path =
        Path.join(System.tmp_dir!(), "does_not_exist_#{System.unique_integer([:positive])}.ex")

      File.rm(missing_path)
      refute File.exists?(missing_path)

      args =
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--ontology",
          "test/fixtures/audit_trail_ontology.ttl",
          "--template",
          "test/fixtures/inject_after_literal.ex.eex",
          "--out",
          missing_path
        ] ++ manifest_args(missing_path)

      {output, exit_code} = run(args)
      assert exit_code != 0
      assert output =~ "does not exist"
      refute File.exists?(missing_path)
    end
  end
end
