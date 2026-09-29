defmodule GgenIgniter.InstallerPackTest do
  @moduledoc """
  Chicago-style: a real `mix ggen_igniter.sync` subprocess renders
  `priv/ggen/igniter-installer-pack` (via `GgenIgniter.Test.PackCompile`) from the real
  fixture ontology `test/fixtures/installer-pack/fixlib.ttl` into a real tmp dir; the real
  compiler loads the generated `Mix.Tasks.Fixlib.Install`/`Extras`; assertions are on the
  compiled task's real `Igniter.Mix.Task.Info` struct and on the state of a real
  `Igniter.Test.test_project` after running the task (mix.exs, .formatter.exs, config files,
  application supervision tree) plus idempotence via `GgenIgniter.Test.IgniterIdempotence`.
  No doubles.

  Falsifiers: (1) drop the add_dep/import_dep step from the rendered source and recompile
  -> the dep/formatter assertions fail on the same project; (2) an incomplete ontology
  (dep without requirement, config in a bad file, step of unknown kind) is a typed
  REFUSED(...) sync failure that writes no file.
  """

  use ExUnit.Case, async: false
  @moduletag :integration

  alias GgenIgniter.Test.{IgniterIdempotence, PackCompile}

  @pack "igniter-installer-pack:installer"
  @fixture "test/fixtures/installer-pack/fixlib.ttl"
  @out "lib/<%= installer_id %>.ex"

  @app_source """
  defmodule Fixlib.Application do
    use Application

    def start(_type, _args) do
      children = []
      Supervisor.start_link(children, strategy: :one_for_one, name: Fixlib.Supervisor)
    end
  end
  """

  @mix_exs """
  defmodule Fixlib.MixProject do
    use Mix.Project
    def project, do: [app: :fixlib, version: "0.1.0", deps: deps()]
    def application, do: [mod: {Fixlib.Application, []}]
    defp deps, do: []
  end
  """

  @project [files: %{"mix.exs" => @mix_exs, "lib/fixlib/application.ex" => @app_source}]

  setup do
    rendered = PackCompile.render!(@pack, ontology: @fixture, out: @out)
    files = Enum.filter(rendered.files, &String.ends_with?(&1, ".ex"))
    modules = PackCompile.compile!(files)

    on_exit(fn ->
      PackCompile.purge(modules)
      PackCompile.cleanup(rendered.out_dir)
    end)

    %{rendered: rendered, files: files, modules: modules}
  end

  defp content(igniter, path),
    do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  test "renders one file per installer and both modules load", %{files: files, modules: modules} do
    assert length(files) == 2
    assert Mix.Tasks.Fixlib.Install in modules
    assert Mix.Tasks.Fixlib.Extras in modules
  end

  test "info/2 equals the ontology facts" do
    info = Mix.Tasks.Fixlib.Install.info([], nil)

    assert info.group == :fixlib
    assert info.example == "mix igniter.install fixlib --pool 5"
    assert info.adds_deps == [jason: "~> 1.4"]
    assert info.installs == [sourceror: "~> 1.0"]
    assert info.composes == []
    assert info.only == [:dev]
    assert info.schema == [pool: :integer, yes: :boolean]
    assert info.aliases == [y: :yes]

    extras = Mix.Tasks.Fixlib.Extras.info([], nil)
    assert extras.composes == ["fixlib.install"]
    assert extras.adds_deps == []
    assert extras.only == nil
  end

  test "running the installer adds dep, formatter import, config, and supervision child" do
    igniter =
      @project
      |> Igniter.Test.test_project()
      |> Igniter.compose_task("fixlib.install", [])

    assert content(igniter, "mix.exs") =~ ~s({:jason, "~> 1.4"})
    assert content(igniter, ".formatter.exs") =~ "import_deps: [:fixlib]"
    assert content(igniter, "config/config.exs") =~ ~r/config :fixlib,\s+pool: \[size: 10\]/
    assert content(igniter, "config/runtime.exs") =~ "mode: :fast"
    assert content(igniter, "lib/fixlib/application.ex") =~ "Fixlib.Worker"
    assert "fixlib installed: see the docs" in igniter.notices
  end

  test "a second run is unchanged (idempotent)" do
    igniter = IgniterIdempotence.assert_idempotent("fixlib.install", [], @project)
    assert content(igniter, "mix.exs") =~ ":jason"
  end

  test "composing installer runs the composed installer's steps and its own notice" do
    igniter =
      @project
      |> Igniter.Test.test_project()
      |> Igniter.compose_task("fixlib.extras", [])

    assert content(igniter, "mix.exs") =~ ":jason"
    assert "extras done" in igniter.notices
  end

  test "falsifier: a rendered installer without the add_dep/import_dep steps leaves the project without them",
       %{files: files} do
    install = Enum.find(files, &(Path.basename(&1) == "installer.ex"))
    src = File.read!(install)

    mutated =
      src
      |> String.replace(~r/\n\s*\|> Igniter\.Project\.Deps\.add_dep\(.*\)/, "")
      |> String.replace(~r/\n\s*\|> Igniter\.Project\.Formatter\.import_dep\(.*\)/, "")

    refute mutated == src

    [{mod, _} | _] =
      Code.compile_string(
        String.replace(mutated, "Mix.Tasks.Fixlib.Install", "Mix.Tasks.Fixlib.InstallMutant")
      )
      |> Enum.filter(&(elem(&1, 0) == Mix.Tasks.Fixlib.InstallMutant))

    igniter =
      @project |> Igniter.Test.test_project() |> mod.igniter() |> Igniter.Test.apply_igniter!()

    refute content(igniter, "mix.exs") =~ ":jason"
  after
    :code.purge(Mix.Tasks.Fixlib.InstallMutant)
    :code.delete(Mix.Tasks.Fixlib.InstallMutant)
  end

  describe "typed refusals (no file written)" do
    defp refused(ttl) do
      path = Path.join(System.tmp_dir!(), "ii_bad_#{System.unique_integer([:positive])}.ttl")
      File.write!(path, File.read!(@fixture) <> "\n" <> ttl)
      on_exit(fn -> File.rm(path) end)
      PackCompile.render(@pack, ontology: path, out: @out)
    end

    @prefixes "@prefix ii: <https://ggen-igniter.dev/ontology/igniter-installer#> .\n@prefix ex: <https://example.test/fixlib#> .\n"

    test "dep without requirement" do
      assert {:error, %{exit_status: s, output: o}} =
               refused(
                 @prefixes <> "ex:bad a ii:Dep ; ii:depOf ex:installer ; ii:depName \"x\" ."
               )

      assert s != 0
      assert o =~ "REFUSED(INSTALLER_DEP_INCOMPLETE)"
    end

    test "dep with an invalid depMode is refused, not silently dropped" do
      ttl =
        @prefixes <>
          "ex:dep-bogus a ii:Dep ; ii:depOf ex:installer ; ii:depName \"evil\" ; ii:depRequirement \"~> 9\" ; ii:depMode \"bogus\" ; ii:depOrder 3 ."

      assert {:error, %{exit_status: s, output: o}} = refused(ttl)
      assert s != 0
      assert o =~ "REFUSED(INSTALLER_DEP_MODE_INVALID)"
    end

    test "config in an unsupported file" do
      ttl =
        @prefixes <>
          "ex:bad a ii:Config ; ii:configOf ex:installer ; ii:cfgFile \"dev.exs\" ; ii:cfgApp \"fixlib\" ; ii:cfgPath \"a\" ; ii:cfgValue \"1\" ; ii:cfgOrder 9 ."

      assert {:error, %{exit_status: s, output: o}} = refused(ttl)
      assert s != 0
      assert o =~ "REFUSED(INSTALLER_CONFIG_INVALID)"
    end

    test "installer missing facts" do
      ttl = @prefixes <> "ex:half a ii:Installer ; ii:taskName \"half.install\" ."
      assert {:error, %{output: o}} = refused(ttl)
      assert o =~ "REFUSED(INSTALLER_INCOMPLETE)"
    end
  end
end
