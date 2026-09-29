defmodule GgenIgniter.UpstreamCanariesTest do
  @moduledoc """
  Upstream canaries (Chicago-style, real `igniter` API, real `Igniter.Test.test_project`,
  real subprocesses; no doubles). One canary per defect in
  `docs/jira/v26.9.28/upstream-igniter-issues.md`. Each canary has two halves:

    1. RAW UPSTREAM: calls igniter's own API and asserts the defect is still PRESENT.
       When upstream fixes it this assertion fails with an `UPSTREAM FIXED` message naming
       the workaround (file + symbol) that can now be retired.
    2. WORKAROUND: asserts this repo's workaround still yields the safe behaviour
       (typed issue / rewritten source instead of a crash or silent skip).

  Defect 5c (`add_issue` does not set a non-zero exit) is canaried through a real
  `mix run` subprocess because the exit status is the defect. Defect 5b's workaround half
  (`ggen_igniter.doctor` exit 2) is also a real subprocess. Nothing here is skipped.
  """

  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :known_upstream_bug

  @mix_exs """
  defmodule Sample.MixProject do
    use Mix.Project
    def project, do: [app: :sample, version: "0.1.0", deps: deps()]
    def application, do: [mod: {Sample.Application, []}]
    defp deps, do: []
  end
  """

  @inline_deps_mix_exs """
  defmodule Sample.MixProject do
    use Mix.Project
    def project, do: [app: :sample, version: "0.1.0", deps: [{:jason, "~> 1.0"}]]
    def application, do: [mod: {Sample.Application, []}]
  end
  """

  @inline_app """
  defmodule Sample.Application do
    use Application

    def start(_type, _args) do
      Supervisor.start_link([], strategy: :one_for_one, name: Sample.Sup)
    end
  end
  """

  defp fixed!(defect, workaround) do
    flunk("""
    UPSTREAM FIXED: #{defect}.
    The raw upstream defect no longer reproduces on this igniter version. Retire the
    workaround: #{workaround} -- then delete this canary and the matching section of
    docs/jira/v26.9.28/upstream-igniter-issues.md.
    """)
  end

  defp src(igniter, path),
    do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  # ------------------------------------------------------------------ 1

  @guarded """
  defmodule M.Guarded do
    def foo(x) when x > 0, do: x
    def caller(x), do: foo(x)
  end
  """

  test "1. guarded def: upstream skips the definition; SafeRename renames it" do
    igniter = Igniter.Test.test_project(files: %{"lib/g.ex" => @guarded})

    raw =
      Igniter.Refactors.Rename.rename_function(igniter, {M.Guarded, :foo}, {M.Guarded, :bar},
        arity: 1
      )

    text = src(raw, "lib/g.ex")

    if text =~ "def bar(x) when x > 0" do
      fixed!(
        "Igniter.Refactors.Rename leaves guarded defs un-renamed (rename.ex remap_function_definition/update_refs)",
        "lib/ggen_igniter/refactors/safe_rename.ex rename_remaining_guarded_defs/4 (line ~124)"
      )
    end

    assert text =~ "def foo(x) when x > 0"
    assert text =~ "bar(x)"

    safe =
      GgenIgniter.Refactors.SafeRename.rename_function(
        igniter,
        {M.Guarded, :foo},
        {M.Guarded, :bar},
        arity: 1
      )

    safe_text = src(safe, "lib/g.ex")
    assert safe_text =~ "def bar(x) when x > 0"
    refute safe_text =~ "def foo(x)"
  end

  # ------------------------------------------------------------------ 2

  @parenless """
  defmodule M.Z do
    def foo do
      :ok
    end
  end
  """

  test "2. parenless zero-arity def: upstream crashes with length(nil); SafeRename renames it" do
    igniter = Igniter.Test.test_project(files: %{"lib/z.ex" => @parenless})

    crashed? =
      try do
        Igniter.Refactors.Rename.rename_function(igniter, {M.Z, :foo}, {M.Z, :bar}, arity: 0)
        false
      rescue
        ArgumentError -> true
      end

    unless crashed? do
      fixed!(
        "Igniter.Refactors.Rename.rename_function/4 no longer raises length(nil) on `def foo do`",
        "lib/ggen_igniter/refactors/safe_rename.ex normalize_parenless_defs/3 (line ~98)"
      )
    end

    safe =
      GgenIgniter.Refactors.SafeRename.rename_function(igniter, {M.Z, :foo}, {M.Z, :bar},
        arity: 0
      )

    assert src(safe, "lib/z.ex") =~ "def bar"
  end

  # ------------------------------------------------------------------ 3

  test "3. inline deps: get_dep returns nil and add_dep raises; install refuses fail-closed" do
    igniter = Igniter.Test.test_project(files: %{"mix.exs" => @inline_deps_mix_exs})

    nil_dep? = Igniter.Project.Deps.get_dep(igniter, :jason) == nil

    raised? =
      try do
        Igniter.Project.Deps.add_dep(igniter, {:ash, "~> 3.0"})
        false
      rescue
        CaseClauseError -> true
      end

    unless nil_dep? and raised? do
      fixed!(
        "Igniter.Project.Deps.get_dep/2 (nil? #{nil_dep?}) / add_dep/2 (CaseClauseError? #{raised?}) handle inline `deps:`",
        "lib/mix/tasks/ggen_igniter.install.ex deps_probe/1 + the :error branch of install_ash_domain/1 (line ~274)"
      )
    end

    refused =
      igniter
      |> Igniter.compose_task("ggen_igniter.install", [
        "--with-ash-domain",
        "--domain",
        "Sample.Ash.Domain",
        "--yes"
      ])

    assert Enum.any?(refused.issues, &(&1 =~ "declares deps inline"))
    refute Igniter.changed?(refused, "mix.exs")
  end

  # ------------------------------------------------------------------ 4

  test "4. Supervisor.start_link([]) without a children binding: upstream only warns; install hoists it" do
    igniter =
      Igniter.Test.test_project(
        files: %{"mix.exs" => @mix_exs, "lib/sample/application.ex" => @inline_app}
      )

    raw = Igniter.Project.Application.add_new_child(igniter, Sample.Child)
    inserted? = src(raw, "lib/sample/application.ex") =~ "Sample.Child"

    if inserted? do
      fixed!(
        "Igniter.Project.Application.add_new_child/3 now inserts into an inline Supervisor.start_link([...])",
        "lib/mix/tasks/ggen_igniter.install.ex ensure_children_binding/1 (line ~200)"
      )
    end

    assert Enum.any?(raw.warnings, &(&1 =~ "children = ["))

    installed =
      Igniter.compose_task(igniter, "ggen_igniter.install", [
        "--with-ash-domain",
        "--domain",
        "Sample.Ash.Domain",
        "--yes"
      ])

    app = src(installed, "lib/sample/application.ex")
    assert app =~ "children ="
    assert app =~ "Sample.Ash.Domain"
  end

  # ------------------------------------------------------------------ 5a

  test "5a. -h is not intercepted upstream; TaskShell handles both spellings" do
    if Igniter.Mix.Task.help_requested?(["-h"]) do
      fixed!(
        "Igniter.Mix.Task.help_requested?/1 now honours -h",
        "lib/ggen_igniter/task_shell.ex run_with_help/4 help_flags (each task's run/1)"
      )
    end

    assert Igniter.Mix.Task.help_requested?(["--help"])
    assert GgenIgniter.TaskShell.help_requested?(["-h"], ["--help", "-h"])
    refute GgenIgniter.TaskShell.help_requested?(["-h"])
  end

  # ------------------------------------------------------------------ 5b

  test "5b. unknown flag: upstream validate! raises ParseError; doctor exits 2" do
    info = %Igniter.Mix.Task.Info{schema: [a: :boolean]}

    raised? =
      try do
        Igniter.Util.Info.validate!(["--bogus"], info, "x.y")
        false
      rescue
        OptionParser.ParseError -> true
      end

    unless raised? do
      fixed!(
        "Igniter.Util.Info.validate!/3 no longer raises OptionParser.ParseError on an unknown flag",
        "lib/mix/tasks/ggen_igniter.doctor.ex run/1 first_unknown_flag/1 pre-validation (line ~226)"
      )
    end

    {out, status} = System.cmd("mix", ["ggen_igniter.doctor", "--bogus"], stderr_to_stdout: true)
    assert status == 2, out
  end

  # ------------------------------------------------------------------ 5c

  test "5c. add_issue: do_or_dry_run returns :issues and a task subprocess still exits 0" do
    ret =
      ExUnit.CaptureIO.with_io(fn ->
        Igniter.new() |> Igniter.add_issue("boom") |> Igniter.do_or_dry_run([])
      end)
      |> elem(0)

    script = """
    defmodule Mix.Tasks.Canary.Issue do
      use Igniter.Mix.Task
      def info(_, _), do: %Igniter.Mix.Task.Info{group: :canary, example: "mix canary.issue"}
      def igniter(igniter), do: Igniter.add_issue(igniter, "boom")
    end

    Mix.Tasks.Canary.Issue.run([])
    """

    path = Path.join(System.tmp_dir!(), "canary_issue_#{System.unique_integer([:positive])}.exs")
    File.write!(path, script)
    on_exit(fn -> File.rm(path) end)
    {_out, status} = System.cmd("mix", ["run", "--no-start", path], stderr_to_stdout: true)

    if ret != :issues or status != 0 do
      fixed!(
        "Igniter runner now signals issues (returned #{inspect(ret)}, exit #{status})",
        "System.halt/1 calls in lib/mix/tasks/ggen_igniter.doctor.ex (halt on failure, ~line 338)"
      )
    end

    # Workaround half: doctor halts non-zero itself; asserted end-to-end by
    # test/ggen_igniter_cli_tasks_quirks_test.exs. Here we prove the raw runner exits 0.
    assert status == 0
  end

  # ------------------------------------------------------------------ 5d

  test "5d. 'No proposed content changes!' footer is printed unless quiet_on_no_changes?" do
    out = ExUnit.CaptureIO.capture_io(fn -> Igniter.do_or_dry_run(Igniter.new(), []) end)

    unless out =~ "No proposed content changes!" do
      fixed!(
        "Igniter.do_or_dry_run/2 no longer prints the footer to stdout",
        "System.halt(0) in the --json branch of lib/mix/tasks/ggen_igniter.doctor.ex / .plan.ex (~line 341)"
      )
    end

    quiet =
      ExUnit.CaptureIO.capture_io(fn ->
        Igniter.new() |> Igniter.assign(:quiet_on_no_changes?, true) |> Igniter.do_or_dry_run([])
      end)

    refute quiet =~ "No proposed content changes!"
  end
end
