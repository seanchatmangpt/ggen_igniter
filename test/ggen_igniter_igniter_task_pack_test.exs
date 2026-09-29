defmodule GgenIgniter.IgniterTaskPackTest.RenameDelegate do
  @moduledoc """
  Real (not mocked) delegate for the rendered fixture task: records the options the
  rendered `igniter/1` handed over into the Igniter assigns, so tests assert on state.
  """
  def run(igniter, options), do: Igniter.assign(igniter, :task_options, options)
end

defmodule GgenIgniter.IgniterTaskPackTest do
  @moduledoc """
  Chicago-style: a real `mix ggen_igniter.sync` subprocess renders
  `priv/ggen/igniter-task-pack` from real fixture ontologies into a real tmp dir; the
  real compiler loads the result under a different module name than the hand-written
  `Mix.Tasks.GgenIgniter.Rename`; assertions are on the rendered source, the compiled
  task's `info/2` struct, real option validation (`Igniter.Mix.Task.__options__!/2`), a
  real `--help` subprocess, and the Igniter assigns after `igniter/1` runs. No doubles.

  Falsifiers: (1) rename an ontology option -> rendered schema changes; (2) delete the
  delegate facts -> the gate query yields a typed refusal row AND a real sync run refuses
  and writes nothing (non-vacuous: the same gate is empty on the complete fixture).
  """

  use ExUnit.Case, async: false
  # async: false -- shells out to `mix` against one shared _build root.

  @pack "priv/ggen/igniter-task-pack"
  @fixture "test/fixtures/igniter-task/fixture.ttl"
  @broken "test/fixtures/igniter-task/missing_delegate.ttl"
  @real_rename "lib/mix/tasks/ggen_igniter.rename.ex"

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "igniter_task_pack_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    RealDir.real_dir!(dir)
  end

  defp render(ontology) do
    dir = tmp_dir()

    {output, status} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--pack",
          "igniter-task-pack:igniter_task",
          "--ontology",
          ontology,
          "--out",
          Path.join(dir, "<%= task_name %>.ex"),
          "--manifest-dir",
          dir,
          "--verify-cwd",
          File.cwd!()
        ],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    {dir, output, status}
  end

  defp rendered!(ontology \\ @fixture, file \\ "igniter_task_fixture.rename.ex") do
    {dir, output, status} = render(ontology)
    assert status == 0, output
    path = Path.join(dir, file)
    assert File.exists?(path), output
    {path, File.read!(path)}
  end

  defp load(source, path) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      [{module, _}] = Code.compile_string(source, path)
      module
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  defp gate(ontology, file) do
    GgenIgniter.Query.run(
      GgenIgniter.Ontology.load!(ontology),
      File.read!(Path.join([@pack, "gates", file]))
    )
  end

  describe "render + structural comparison against lib/mix/tasks/ggen_igniter.rename.ex" do
    test "rendered task has the same info/2 struct as the hand-written rename task" do
      {path, source} = rendered!()
      module = load(source, path)
      assert module == Mix.Tasks.IgniterTaskFixture.Rename

      generated = module.info([], "igniter_task_fixture.rename")
      handwritten = Mix.Tasks.GgenIgniter.Rename.info([], "ggen_igniter.rename")

      assert %Igniter.Mix.Task.Info{} = generated
      assert generated.schema == handwritten.schema
      assert generated.aliases == handwritten.aliases
      assert generated.required == handwritten.required
      assert generated.positional == handwritten.positional
      assert generated.example =~ "igniter_task_fixture.rename --from OldMod.old_fun"
      assert generated.group == :igniter_task_fixture
    end

    test "source uses Igniter.Mix.Task, delegates --help to TaskShell, never declares Ash" do
      {_path, source} = rendered!()
      assert source =~ "use Igniter.Mix.Task"
      assert source =~ "GgenIgniter.TaskShell.run_with_help("
      assert source =~ ~s|["--help", "-h"]|

      assert source =~
               "GgenIgniter.IgniterTaskPackTest.RenameDelegate.run(igniter, igniter.args.options)"

      refute source =~ ~r/^\s*use Ash\./m
    end

    test "option validation: required flags enforced, unknown flag rejected, values typed" do
      {path, source} = rendered!()
      module = load(source, path)

      opts =
        Igniter.Mix.Task.__options__!(module, ["--from", "A.b", "--to", "A.c", "--arity", "2"])

      assert opts[:from] == "A.b" and opts[:to] == "A.c" and opts[:arity] == 2

      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert catch_exit(Igniter.Mix.Task.__options__!(module, ["--to", "A.c"])) ==
                 {:shutdown, 1}
      end)

      assert_raise OptionParser.ParseError, fn ->
        Igniter.Mix.Task.__options__!(module, ["--from", "A.b", "--to", "A.c", "--arity", "x"])
      end
    end

    test "igniter/1 calls the ontology's delegate MFA with the parsed options" do
      {path, source} = rendered!()
      module = load(source, path)
      opts = Igniter.Mix.Task.__options__!(module, ["--from", "A.b", "--to", "A.c"])

      igniter =
        Igniter.Test.test_project()
        |> Map.update!(:args, &%{&1 | options: opts})
        |> module.igniter()

      assert igniter.assigns.task_options[:from] == "A.b"
      assert igniter.assigns.task_options[:to] == "A.c"
    end

    test "real subprocess: --help and -h print the rendered help and exit 0 via TaskShell" do
      {path, source} = rendered!()
      dir = Path.dirname(path)
      # Compile the rendered task in a fresh VM, then invoke run/1 for real.
      script = """
      Code.compile_file(#{inspect(path)})
      Mix.Tasks.IgniterTaskFixture.Rename.run(System.argv())
      """

      File.write!(Path.join(dir, "run_help.exs"), script)

      for flag <- ["--help", "-h"] do
        {out, status} =
          System.cmd("mix", ["run", "--no-start", Path.join(dir, "run_help.exs"), flag],
            cd: File.cwd!(),
            stderr_to_stdout: true
          )

        assert status == 0, out
        assert out =~ "mix igniter_task_fixture.rename -- renames a function"
        assert out =~ "--from MODULE.function[/arity]   (required) existing module + function"
        assert out =~ "--dry-run"
        assert out =~ "--help, -h"
      end

      assert source =~ "System.halt(0)"
    end

    test "byte-identity: rendering the pack's own ontology reproduces lib/mix/tasks/ggen_igniter.rename.ex" do
      dir = tmp_dir()

      {output, status} =
        System.cmd(
          "mix",
          [
            "ggen_igniter.sync",
            "--pack",
            "igniter-task-pack:igniter_task",
            "--out",
            Path.join(dir, "<%= task_name %>.ex"),
            "--manifest-dir",
            dir,
            "--verify-cwd",
            File.cwd!()
          ],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      assert status == 0, output
      rendered = File.read!(Path.join(dir, "ggen_igniter.rename.ex"))
      assert rendered == File.read!(@real_rename)
      assert rendered =~ "# GENERATED by ggen_igniter"
      # The hand-written body lives in the arity-2 delegate, not in the shell.
      refute rendered =~ "defp parse_target!"
      assert File.read!("lib/ggen_igniter/refactors/rename_options.ex") =~ "defp parse_target!"
    end

    test "F3: mutating a prose fact breaks byte-identity (the comparison is not vacuous)" do
      dir = tmp_dir()
      ontology = Path.join(dir, "mutated_rename.ttl")
      original = File.read!(Path.join(@pack, "ontology.ttl"))
      mutated = String.replace(original, "`0` -- rename applied", "`0` -- rename APPLIED")
      refute mutated == original
      File.write!(ontology, mutated)

      {_p, source} = rendered!(ontology, "ggen_igniter.rename.ex")
      refute source == File.read!(@real_rename)
      assert source =~ "rename APPLIED"
    end
  end

  describe "falsifiers" do
    test "F1: renaming an ontology option changes the rendered schema" do
      mutated_path = Path.join(tmp_dir(), "mutated.ttl")
      original = File.read!(@fixture)
      mutated = String.replace(original, ~s|ig:optName "path"|, ~s|ig:optName "root"|)
      refute mutated == original
      File.write!(mutated_path, mutated)

      {_p, base} = rendered!()
      {_p2, changed} = rendered!(mutated_path)

      assert base =~ "path: :string"
      refute base =~ "root: :string"
      assert changed =~ "root: :string"
      refute changed =~ "path: :string"
      assert changed =~ "--root DIR"
    end

    test "F2: gate 030 is empty on the complete fixture and refuses the broken one" do
      assert gate(@fixture, "030_refusals.rq") == []

      assert [%{"refused_task_name" => "igniter_task_fixture.rename"}] =
               gate(@broken, "030_refusals.rq")
    end

    test "F2: a real sync over the broken fixture refuses with a typed refusal and writes no task" do
      {dir, output, status} = render(@broken)
      assert status != 0, output
      assert output =~ "REFUSED(TASK_DELEGATE_MISSING)"
      refute File.exists?(Path.join(dir, "igniter_task_fixture.rename.ex"))
    end
  end

  test "pack shape: fixed convention paths exist" do
    assert File.exists?(Path.join(@pack, "ontology.ttl"))
    assert File.exists?(Path.join(@pack, "templates/igniter_task.ex.eex"))
    assert File.exists?(Path.join(@pack, "gates/010_tasks.rq"))
  end
end
