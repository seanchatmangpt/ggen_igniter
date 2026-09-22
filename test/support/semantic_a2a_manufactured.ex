defmodule GgenIgniter.Test.SemanticA2AManufactured do
  @moduledoc """
  Test support: manufactures the Semantic Jira Ash/ash_a2a surface for real,
  once per VM, and hands the resulting sources to the tests that consume them.

  Chicago-style, no test doubles. The chain is entirely real:

    1. a real `mix ggen_igniter.sync` subprocess renders
       `templates/a2a_manufacture.ex.eex` from the real pack ontology into a
       real file (the rendered task is DERIVED from ontology facts);
    2. that file is compiled with the real compiler;
    3. the resulting `Igniter.Mix.Task` is composed through `Igniter.Test`,
       which drives the REAL `ash.gen.domain`, `ash.gen.resource --extend ets`
       and `ash_a2a.install` generators against an in-memory project;
    4. the generated Ash sources are read back off the Igniter's Rewrite and
       (by the consuming tests) compiled -- no Ash resource is hand-written
       anywhere in this repository.

  The ETS data layer replaces Postgres because `ash.gen.resource --extend ets`
  is a supported upstream extension and needs no database server; it is the
  same Ash action machinery either way.
  """

  import ExUnit.CaptureIO

  @app :semantic_jira
  @task_name "semantic_jira.a2a.manufacture"

  def app, do: @app

  @resource_path "lib/semantic_jira/work/task.ex"
  @domain_path "lib/semantic_jira/work.ex"

  @doc """
  Render, compile and compose once per VM (cached); returns a map with the
  rendered task `:module`/`:source`/`:path`, the composed `:igniter`, and the
  generated `:resource_source`/`:domain_source`.
  """
  def manufactured! do
    case :persistent_term.get({__MODULE__, :manufactured}, nil) do
      nil ->
        {path, source} = render_task!()
        module = load_task!(source, path)
        igniter = compose(Igniter.Test.test_project(app_name: @app), module, [])

        built = %{
          module: module,
          source: source,
          path: path,
          igniter: igniter,
          resource_path: @resource_path,
          domain_path: @domain_path,
          resource_source: content!(igniter, @resource_path),
          domain_source: content!(igniter, @domain_path)
        }

        :persistent_term.put({__MODULE__, :manufactured}, built)
        built

      built ->
        built
    end
  end

  @doc "Render the manufacture task with the real sync subprocess; returns `{path, source}`."
  def render_task! do
    dir =
      Path.join(System.tmp_dir!(), "semantic_a2a_render_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir = RealDir.real_dir!(dir)

    {output, 0} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--pack",
          "semantic-jira-pack:a2a_manufacture",
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

    path = Path.join(dir, @task_name <> ".ex")
    unless File.exists?(path), do: raise("render produced no #{path}:\n#{output}")
    {path, File.read!(path)}
  end

  @doc "Compile the rendered task source and return its single `Mix.Tasks.*` module."
  def load_task!(source, path) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    compiled =
      try do
        Code.compile_string(source, path)
      after
        Code.put_compiler_option(:ignore_module_conflict, previous)
      end

    [module] =
      for {module, _} <- compiled, match?(["Mix", "Tasks" | _], Module.split(module)), do: module

    module
  end

  @doc "Compose `task` (module or name) on `igniter`, capturing generator chatter."
  def compose(igniter, task, argv) do
    parent = self()

    _stderr =
      capture_io(:stderr, fn ->
        _stdout =
          capture_io(fn ->
            send(parent, {:igniter, Igniter.compose_task(igniter, task, argv)})
          end)
      end)

    receive do
      {:igniter, value} -> value
    after
      5_000 -> raise "compose timed out"
    end
  end

  @doc "Current content of `path` in the Igniter's in-memory project."
  def content!(igniter, path) do
    igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)
  end
end
