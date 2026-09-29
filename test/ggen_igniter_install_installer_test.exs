defmodule GgenIgniterInstallInstallerTest do
  # async: false -- File.cd! changes the process-global cwd.
  use ExUnit.Case, async: false

  @moduledoc """
  Chicago-style: proves `ggen_igniter.install` is a thin first-class Igniter installer.
  Real `Igniter.Test` projects and a real tmp project on disk; assertions are on resulting
  file state (`.formatter.exs`, `mix.exs`, config), never on calls.

    * `info/2` declares `example:` and the `--with-ash-domain` flag (default off, E1).
    * Default run imports `:ggen_igniter` into `.formatter.exs` and adds no Ash.
    * `--with-ash-domain` runs the Ash dep/config/child wiring.
    * Second run is a no-op (Igniter.Test `assert_unchanged` + real files).
  """

  import Igniter.Test

  alias Mix.Tasks.GgenIgniter.Install

  @mix_exs """
  defmodule MyApp.MixProject do
    use Mix.Project

    def project do
      [app: :my_app, version: "0.1.0", deps: deps()]
    end

    defp deps do
      [{:ggen_igniter, "~> 26.9"}]
    end
  end
  """

  @mix_exs_without_dep String.replace(@mix_exs, ~s([{:ggen_igniter, "~> 26.9"}]), "[]")

  defp content(igniter, path),
    do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  test "info/2 declares an example, the opt-in flag, and Ash is off by default" do
    info = Install.info([], nil)

    assert is_binary(info.example) and info.example =~ "igniter.install ggen_igniter"
    assert info.schema[:with_ash_domain] == :boolean
    assert info.defaults[:with_ash_domain] == false
  end

  test "default run imports :ggen_igniter into .formatter.exs and adds no Ash" do
    igniter =
      test_project(files: %{"mix.exs" => @mix_exs})
      |> Igniter.compose_task("ggen_igniter.install", [])

    formatter = content(igniter, ".formatter.exs")
    assert formatter =~ "import_deps"
    assert formatter =~ ":ggen_igniter"

    refute content(igniter, "mix.exs") =~ ":ash"
    refute Rewrite.has_source?(igniter.rewrite, "config/config.exs")
  end

  test "--with-ash-domain adds the Ash dep, domain config and formatter import" do
    igniter =
      test_project(files: %{"mix.exs" => @mix_exs})
      |> Igniter.compose_task("ggen_igniter.install", ["--with-ash-domain"])

    assert content(igniter, "mix.exs") =~ ~s({:ash, "~> 3.0"})
    assert content(igniter, "config/config.exs") =~ "ash_domains"
    assert content(igniter, ".formatter.exs") =~ ":ggen_igniter"
  end

  test "a pre-existing import_deps entry is extended, not duplicated" do
    project =
      test_project(
        files: %{
          "mix.exs" => @mix_exs,
          ".formatter.exs" => "[import_deps: [:ecto], inputs: [\"*.exs\"]]\n"
        }
      )

    once = Igniter.compose_task(project, "ggen_igniter.install", [])
    formatter = content(once, ".formatter.exs")
    assert formatter =~ ":ecto"
    assert length(String.split(formatter, ":ggen_igniter")) == 2

    once
    |> apply_igniter!()
    |> Igniter.compose_task("ggen_igniter.install", [])
    |> assert_unchanged()
  end

  test "without the dep in mix.exs the formatter is left alone and a notice is emitted" do
    igniter =
      test_project(files: %{"mix.exs" => @mix_exs_without_dep})
      |> Igniter.compose_task("ggen_igniter.install", [])

    refute Rewrite.has_source?(igniter.rewrite, ".formatter.exs") and
             content(igniter, ".formatter.exs") =~ ":ggen_igniter"

    assert Enum.any?(igniter.notices, &(&1 =~ "ggen_igniter is not in mix.exs"))
  end

  test "second run over an installed Igniter.Test project changes nothing" do
    installed =
      test_project(files: %{"mix.exs" => @mix_exs})
      |> Igniter.compose_task("ggen_igniter.install", [])
      |> apply_igniter!()

    installed
    |> Igniter.compose_task("ggen_igniter.install", [])
    |> assert_unchanged()

    with_ash =
      test_project(files: %{"mix.exs" => @mix_exs})
      |> Igniter.compose_task("ggen_igniter.install", ["--with-ash-domain"])
      |> apply_igniter!()

    with_ash
    |> Igniter.compose_task("ggen_igniter.install", ["--with-ash-domain"])
    |> assert_unchanged()
  end

  describe "real tmp project on disk" do
    setup do
      {:ok, _} = Application.ensure_all_started(:rewrite)
      {:ok, _} = Application.ensure_all_started(:igniter)

      original_cwd = File.cwd!()
      dir = Path.join(System.tmp_dir!(), "gi_installer_#{System.unique_integer([:positive])}")
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "mix.exs"), @mix_exs)

      on_exit(fn ->
        File.cd!(original_cwd)
        File.rm_rf!(dir)
      end)

      %{dir: dir}
    end

    defp run_install(dir, argv) do
      File.cd!(dir)

      Igniter.new()
      |> Igniter.compose_task("ggen_igniter.install", argv)
      |> Igniter.do_or_dry_run(yes: true, quiet_on_no_changes?: true)
    end

    test "writes .formatter.exs to disk, no Ash files", %{dir: dir} do
      assert run_install(dir, ["--yes"]) == :changes_made
      assert File.read!(Path.join(dir, ".formatter.exs")) =~ ":ggen_igniter"
      refute File.read!(Path.join(dir, "mix.exs")) =~ ":ash"
      refute File.exists?(Path.join(dir, "config/config.exs"))
    end
  end
end
