defmodule GgenIgniter.UpgraderChainTest do
  @moduledoc """
  Chicago-style: the `upgrade` and `upgrader` templates of `priv/ggen/igniter-installer-pack`
  are rendered by a real `mix ggen_igniter.sync` subprocess from
  `test/fixtures/installer-pack/chainlib.ttl` (V0_2_0 renames a config key; V0_3_0 renames it
  again and adds a dep), compiled by the real compiler, and run through the real generated
  `Mix.Tasks.Chainlib.Upgrade` against a real `Igniter.Test.test_project`. Assertions are on
  final project state (config file bytes, mix.exs), never on calls. No doubles.

  Falsifier: running the same two upgrader modules in swapped order (via the generated
  `Chainlib.Upgrades.select/3` with a registry whose versions are exchanged) ends in a
  different config state, proving the chain assertions are order-sensitive.
  """

  use ExUnit.Case, async: false
  @moduletag :integration

  alias GgenIgniter.Test.PackCompile

  @fixture "test/fixtures/installer-pack/chainlib.ttl"
  @config "import Config\n\nconfig :chainlib, old_key: 1\n"

  setup_all do
    render = fn stem, out ->
      PackCompile.render!("igniter-installer-pack:" <> stem, ontology: @fixture, out: out)
    end

    dirs =
      [
        render.("installer", "lib/<%= installer_id %>.ex"),
        render.("upgrade", "lib/<%= installer_id %>_upgrade.ex"),
        render.("upgrader", "lib/<%= upgrader_id %>.ex")
      ]

    files =
      dirs |> Enum.flat_map(& &1.files) |> Enum.filter(&String.ends_with?(&1, ".ex"))

    modules = PackCompile.compile!(files)

    on_exit(fn ->
      PackCompile.purge(modules)
      Enum.each(dirs, &PackCompile.cleanup(&1.out_dir))
    end)

    %{files: files, modules: modules}
  end

  defp project, do: Igniter.Test.test_project(files: %{"config/config.exs" => @config})

  defp upgrade(igniter, from, to),
    do: Igniter.compose_task(igniter, "chainlib.upgrade", [from, to])

  defp content(igniter, path),
    do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  test "generated registry + upgrade task + versioned modules exist", %{modules: modules} do
    assert Mix.Tasks.Chainlib.Upgrade in modules
    assert Chainlib.Upgrades in modules
    assert Chainlib.Upgrades.V0_2_0 in modules
    assert Chainlib.Upgrades.V0_3_0 in modules
    assert Chainlib.Upgrades.registry() |> Map.keys() |> Enum.sort() == ["0.2.0", "0.3.0"]
  end

  test "0.1.0 -> 0.3.0 applies both upgraders in order, re-run is unchanged" do
    applied = project() |> upgrade("0.1.0", "0.3.0") |> Igniter.Test.apply_igniter!()

    config = content(applied, "config/config.exs")
    assert config =~ "final_key: 1"
    refute config =~ "old_key"
    refute config =~ "new_key"
    assert content(applied, "mix.exs") =~ ~s({:jason, "~> 1.4"})

    applied |> upgrade("0.1.0", "0.3.0") |> Igniter.Test.assert_unchanged()
  end

  test "0.2.0 -> 0.3.0 applies only V0_3_0" do
    applied = project() |> upgrade("0.2.0", "0.3.0") |> Igniter.Test.apply_igniter!()
    config = content(applied, "config/config.exs")

    # V0_2_0 (old_key -> new_key) did not run, so V0_3_0's new_key rename found nothing.
    assert config =~ "old_key: 1"
    refute config =~ "final_key"
    assert content(applied, "mix.exs") =~ ":jason"
  end

  test "same version is a no-op" do
    project() |> upgrade("0.3.0", "0.3.0") |> Igniter.Test.assert_unchanged()
  end

  test "downgrade is a typed refusal and writes nothing" do
    igniter = project() |> upgrade("0.3.0", "0.1.0")
    assert Enum.any?(igniter.issues, &(&1 =~ "REFUSED:UPGRADE_DOWNGRADE 0.3.0 -> 0.1.0"))
    Igniter.Test.assert_unchanged(igniter)
  end

  test "invalid version is a typed refusal" do
    igniter = project() |> upgrade("nope", "0.3.0")
    assert Enum.any?(igniter.issues, &(&1 =~ "REFUSED:UPGRADE_INVALID_VERSION nope"))
  end

  test "falsifier: swapped upgrader order ends in a different state" do
    swapped = %{
      "0.2.0" => Chainlib.Upgrades.V0_3_0,
      "0.3.0" => Chainlib.Upgrades.V0_2_0
    }

    {:ok, mods} = Chainlib.Upgrades.select("0.1.0", "0.3.0", swapped)
    assert mods == [Chainlib.Upgrades.V0_3_0, Chainlib.Upgrades.V0_2_0]

    igniter =
      mods
      |> Enum.reduce(project(), fn m, ig -> m.upgrade(ig, []) end)
      |> Igniter.Test.apply_igniter!()

    config = content(igniter, "config/config.exs")
    assert config =~ "new_key: 1"
    refute config =~ "final_key"
  end

  test "an upgrader with missing version is refused, nothing rendered" do
    path = Path.join(System.tmp_dir!(), "chain_bad_#{System.unique_integer([:positive])}.ttl")

    File.write!(
      path,
      File.read!(@fixture) <>
        "\nex:bad a ii:Upgrader ; ii:upgraderOf ex:installer .\n"
    )

    on_exit(fn -> File.rm(path) end)

    assert {:error, %{exit_status: s, output: o}} =
             PackCompile.render("igniter-installer-pack:upgrader",
               ontology: path,
               out: "lib/<%= upgrader_id %>.ex"
             )

    assert s != 0
    assert o =~ "REFUSED(UPGRADER_INCOMPLETE)"
  end

  test "a step of unknown kind is refused" do
    path = Path.join(System.tmp_dir!(), "chain_bad_#{System.unique_integer([:positive])}.ttl")

    File.write!(
      path,
      File.read!(@fixture) <>
        "\nex:badstep a ii:Step ; ii:stepOf ex:v1 ; ii:stepKind \"delete_everything\" ; ii:stepOrder 9 .\n"
    )

    on_exit(fn -> File.rm(path) end)

    assert {:error, %{output: o}} =
             PackCompile.render("igniter-installer-pack:upgrader",
               ontology: path,
               out: "lib/<%= upgrader_id %>.ex"
             )

    assert o =~ "REFUSED(UPGRADER_STEP_INVALID)"
  end

  test "a step whose stepOf is not an upgrader is refused" do
    path = Path.join(System.tmp_dir!(), "chain_orphan_#{System.unique_integer([:positive])}.ttl")

    File.write!(
      path,
      File.read!(@fixture) <>
        "\nex:orphan a ii:Step ; ii:stepOf ex:nonexistent ; ii:stepKind \"add_dep\" ; ii:stepOrder 9 ; ii:stepDep \"x\" ; ii:stepRequirement \"~> 1\" .\n"
    )

    on_exit(fn -> File.rm(path) end)

    assert {:error, %{exit_status: s, output: o}} =
             PackCompile.render("igniter-installer-pack:upgrader",
               ontology: path,
               out: "lib/<%= upgrader_id %>.ex"
             )

    assert s != 0
    assert o =~ "REFUSED(UPGRADER_STEP_INVALID)"
  end

  test "two upgraders sharing a version are refused" do
    path = Path.join(System.tmp_dir!(), "chain_dup_#{System.unique_integer([:positive])}.ttl")

    File.write!(
      path,
      File.read!(@fixture) <>
        "\nex:v1dup a ii:Upgrader ; ii:upgraderOf ex:installer ; ii:version \"0.2.0\" ; ii:upgraderModule \"Chainlib.Upgrades.V0_2_0_Dup\" .\n"
    )

    on_exit(fn -> File.rm(path) end)

    assert {:error, %{exit_status: s, output: o}} =
             PackCompile.render("igniter-installer-pack:upgrade",
               ontology: path,
               out: "lib/<%= installer_id %>_upgrade.ex"
             )

    assert s != 0
    assert o =~ "REFUSED(UPGRADER_VERSION_DUPLICATE)"
  end
end
