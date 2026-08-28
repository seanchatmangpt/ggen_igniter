defmodule GgenIgniter.SyncInjectReactorAdmissionTest do
  @moduledoc """
  Chicago-style, real subprocess, no mocks: proves the AR-10 correction in
  `Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3` -- a `mode: file`/
  `inject: true` template, run through the real `mix ggen_igniter.sync` CLI
  (a real `System.cmd/3` subprocess, never invoked in-process), now routes
  through `GgenIgniter.Reactors.ReconcileReactor.run/1` exactly like any
  other frontmatter-free `mode: file` write already did, instead of always
  falling back to `sync.ex`'s own pre-Reactor inline pipeline (which has NO
  duplicate-output-path or path-escape admission checks at all -- those
  exist ONLY in `ReconcileReactor`'s `:admit` step).

  Before AR-10, `run_via_reactor/3` refused delegation for ANY
  frontmatter-bearing template (the guard was `frontmatter != nil`), so an
  `inject: true` write -- which can ONLY be expressed via frontmatter, there
  is no `--inject`/`--before`/`--after`/`--at-line` CLI flag -- NEVER got
  `ReconcileReactor`'s real admission-gate coverage via the actual CLI. This
  file proves the fix directly:

    * happy path: an `inject: true` write inside the authorized project
      root is admitted and genuinely spliced, with the real `"(via
      reactor)"` notice suffix `run_via_reactor/3` only ever adds on the
      Reactor path (`sync.ex`'s pre-Reactor inline pipeline never adds this
      suffix).
    * the real admission-gate proof the AR-10 correction exists to
      establish: an `inject: true` write targeting a path OUTSIDE the
      authorized project root (`GgenIgniter.ArtifactIdentity.within_root?/2`,
      enforced only by `ReconcileReactor`'s `:admit` step) is refused --
      real non-zero exit, the real target file genuinely never touched --
      the exact same way an ordinary `mode: file` (no frontmatter at all)
      write already was refused before this correction, proven side by
      side in the last test below for a direct, real comparison.

  Every collaborator here is real: a real `mix ggen_igniter.sync` OS
  subprocess (`System.cmd/3`), real fixture ontology/query/template files
  already used elsewhere in this suite (`test/fixtures/audit_trail_ontology.ttl`,
  `test/fixtures/spec.rq`), and real tmp-directory file I/O. No `Mix`/
  `File`/`Reactor` mocking anywhere in this file.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @ontology "test/fixtures/audit_trail_ontology.ttl"
  @spec_query "spec=test/fixtures/spec.rq"
  @inject_template "test/fixtures/inject_before_reactor_admitted.ex.eex"
  @plain_template "test/fixtures/plain_module_for_admission_test.ex.eex"

  defp run(args), do: System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

  defp within_repo_target(basename) do
    dir = Path.join(File.cwd!(), "tmp_out/reactor_inject_admission")
    File.mkdir_p!(dir)
    path = Path.join(dir, basename)
    on_exit(fn -> File.rm_rf!(dir) end)
    path
  end

  defp outside_repo_target(basename) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_reactor_admission_outside_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    Path.join(dir, basename)
  end

  describe "inject: true, target inside the authorized project root" do
    test "routes through the Reactor pipeline and is genuinely admitted + spliced" do
      path = within_repo_target("host_admitted.ex")

      File.write!(path, """
      defmodule Host do
        # GGEN:INJECT:BEFORE
        def existing, do: :ok
      end
      """)

      args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--ontology",
        @ontology,
        "--query",
        @spec_query,
        "--template",
        @inject_template,
        "--out",
        path
      ]

      {output, exit_code} = run(args)
      assert exit_code == 0, "mix ggen_igniter.sync (inject, via reactor) failed:\n#{output}"

      # The real, distinguishing proof this went through `run_via_reactor/3`
      # and NOT the pre-Reactor inline `dispatch_pipeline/3` fallback: only
      # the Reactor path ever appends this exact suffix.
      assert output =~ "(via reactor)"
      assert output =~ "ggen_igniter: injected #{path}"

      assert File.read!(path) =~ "def injected_resource, do: \"audit_trail\""
      assert File.read!(path) =~ "# GGEN:INJECT:BEFORE"
    end
  end

  describe "admission-gate parity: inject: true vs. plain mode: file, both targeting outside the authorized root" do
    test "an inject: true write escaping the project root is refused, real non-zero exit, target genuinely untouched" do
      path = outside_repo_target("host_outside.ex")

      original = """
      defmodule Host do
        # GGEN:INJECT:BEFORE
        def existing, do: :ok
      end
      """

      File.write!(path, original)

      args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--ontology",
        @ontology,
        "--query",
        @spec_query,
        "--template",
        @inject_template,
        "--out",
        path
      ]

      {output, exit_code} = run(args)

      assert exit_code != 0,
             "expected mix ggen_igniter.sync to refuse an inject target outside the " <>
               "authorized project root, got exit 0:\n#{output}"

      assert output =~ "resolves outside the authorized project root"

      # Fail-closed: the real target file was never touched -- refused at
      # admission time, before `:actuate` ever runs.
      assert File.read!(path) == original
    end

    test "an ordinary mode: file write escaping the project root is refused the exact same real way" do
      path = outside_repo_target("plain_outside.ex")
      refute File.exists?(path)

      args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--ontology",
        @ontology,
        "--query",
        @spec_query,
        "--template",
        @plain_template,
        "--out",
        path
      ]

      {output, exit_code} = run(args)

      assert exit_code != 0,
             "expected mix ggen_igniter.sync to refuse a mode: file target outside the " <>
               "authorized project root, got exit 0:\n#{output}"

      assert output =~ "resolves outside the authorized project root"

      # Refused before any actuation: a target that did not exist before
      # this run still does not exist after it.
      refute File.exists?(path)
    end
  end
end
