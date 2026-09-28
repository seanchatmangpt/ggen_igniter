defmodule GgenIgniterInstallRealFilesTest do
  @moduledoc """
  Chicago-style first-mile proof for the consumer-facing install edge
  (`mix ggen_igniter.install`). `ggen_igniter_install_task_test.exs` drives the
  task over an in-memory `Igniter.Test` project; this file drives the SAME task
  through the real Igniter write path (`Igniter.do_or_dry_run/2` with `yes: true`)
  against REAL files in a unique tmp Mix project, then asserts on the bytes left
  on disk: `mix.exs`, `config/config.exs`, and the application supervisor.

  Real collaborators: real tmp dir + files, real Igniter/Rewrite/Sourceror
  codemods, the real install task. No test doubles.

  `async: false`: Igniter resolves project files relative to the process cwd, so
  each test `File.cd!/1`s into its tmp project and restores cwd in `on_exit`.
  """
  use ExUnit.Case, async: false

  @app_source """
  defmodule MyApp.Application do
    use Application

    @impl true
    def start(_type, _args) do
      children = []
      Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
    end
  end
  """

  @mix_exs """
  defmodule MyApp.MixProject do
    use Mix.Project

    def project do
      [app: :my_app, version: "0.1.0", elixir: "~> 1.17", deps: deps()]
    end

    def application do
      [extra_applications: [:logger], mod: {MyApp.Application, []}]
    end

    defp deps do
      []
    end
  end
  """

  # The documented Igniter.Project.Deps.add_dep crash shape: `deps: [...]`
  # inlined in project/0, no `defp deps`.
  @inline_deps_mix_exs """
  defmodule MyApp.MixProject do
    use Mix.Project

    def project do
      [app: :my_app, version: "0.1.0", elixir: "~> 1.17", deps: [{:jason, "~> 1.4"}]]
    end

    def application do
      [extra_applications: [:logger], mod: {MyApp.Application, []}]
    end
  end
  """

  setup do
    {:ok, _} = Application.ensure_all_started(:rewrite)
    {:ok, _} = Application.ensure_all_started(:igniter)

    original_cwd = File.cwd!()
    dir = Path.join(System.tmp_dir!(), "gi_install_real_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(Path.join(dir, "lib/my_app"))
    File.write!(Path.join(dir, "lib/my_app/application.ex"), @app_source)

    on_exit(fn ->
      File.cd!(original_cwd)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp install!(dir, mix_exs, argv \\ ["--yes"]) do
    File.write!(Path.join(dir, "mix.exs"), mix_exs)
    File.cd!(dir)

    Igniter.new()
    |> Igniter.compose_task("ggen_igniter.install", argv)
    |> Igniter.do_or_dry_run(yes: true, quiet_on_no_changes?: true)
  end

  test "writes the ash dep, ash_domains config and supervision child to real files", %{dir: dir} do
    assert install!(dir, @mix_exs) == :changes_made

    assert File.read!(Path.join(dir, "mix.exs")) =~ ~s({:ash, "~> 3.0"})

    config = File.read!(Path.join(dir, "config/config.exs"))
    assert config =~ "config :my_app, ash_domains: [MyApp.Ash.Domain]"

    assert File.read!(Path.join(dir, "lib/my_app/application.ex")) =~
             "children = [MyApp.Ash.Domain]"
  end

  test "a second run over the installed project changes nothing on disk", %{dir: dir} do
    assert install!(dir, @mix_exs) == :changes_made
    before = snapshot(dir)

    File.cd!(dir)

    result =
      Igniter.new()
      |> Igniter.compose_task("ggen_igniter.install", ["--yes"])
      |> Igniter.do_or_dry_run(yes: true, quiet_on_no_changes?: true)

    refute result == :changes_made
    assert snapshot(dir) == before
  end

  test "--domain overrides the default domain module in every written file", %{dir: dir} do
    assert install!(dir, @mix_exs, ["--yes", "--domain", "MyApp.Custom.Domain"]) ==
             :changes_made

    assert File.read!(Path.join(dir, "config/config.exs")) =~ "MyApp.Custom.Domain"
    assert File.read!(Path.join(dir, "lib/my_app/application.ex")) =~ "MyApp.Custom.Domain"
  end

  test "an inline `deps: [...]` mix.exs is refused with no file modified", %{dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), @inline_deps_mix_exs)
    before = snapshot(dir) |> Map.put("mix.exs", @inline_deps_mix_exs)
    File.cd!(dir)

    result =
      Igniter.new()
      |> Igniter.compose_task("ggen_igniter.install", ["--yes"])
      |> Igniter.do_or_dry_run(yes: true, quiet_on_no_changes?: true)

    refute result == :changes_made
    assert snapshot(dir) == before
    refute File.exists?(Path.join(dir, "config/config.exs"))
  end

  defp snapshot(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn p -> {Path.relative_to(p, dir), File.read!(p)} end)
  end
end
