defmodule GgenIgniter.InstallerGeneratedTestsTest do
  @moduledoc """
  Chicago-style: the `installer_test` template of `priv/ggen/igniter-installer-pack` renders an
  `Igniter.Test`-based suite for a generated installer. Both the installer and the suite are
  rendered by real `mix ggen_igniter.sync` subprocesses from
  `test/fixtures/installer-pack/badlib.ttl`, copied into a real tmp Mix project, and executed
  by a real `mix test` subprocess (igniter and friends come from this repo's build via
  `ERL_LIBS`; the tmp project has no deps of its own). Assertions are exit statuses and the
  suite's own output.

  Falsifier: a mutated installer (the `add_dep` step deleted) makes the SAME generated suite
  fail (exit != 0), so the generated tests are not vacuous.
  """

  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag timeout: 600_000

  alias GgenIgniter.Test.PackCompile

  @fixture "test/fixtures/installer-pack/badlib.ttl"

  @mix_exs """
  defmodule Tmp.MixProject do
    use Mix.Project
    def project, do: [app: :tmp, version: "0.1.0", elixir: "~> 1.15", deps: [], prune_code_paths: false]
    def application, do: [extra_applications: [:logger]]
  end
  """

  @test_helper "{:ok, _} = Application.ensure_all_started(:igniter)\nExUnit.start()\n"

  defp render!(stem, out) do
    r = PackCompile.render!("igniter-installer-pack:" <> stem, ontology: @fixture, out: out)
    on_exit(fn -> PackCompile.cleanup(r.out_dir) end)
    r.files |> Enum.find(&(not String.ends_with?(&1, ".toml"))) |> File.read!()
  end

  defp mix_test(installer_source, test_source) do
    dir =
      PackCompile.tmp_project!(%{
        "mix.exs" => @mix_exs,
        "lib/installer.ex" => installer_source,
        "test/installer_test.exs" => test_source,
        "test/test_helper.exs" => @test_helper
      })

    on_exit(fn -> PackCompile.cleanup(dir) end)
    libs = Path.join(Path.expand(Mix.Project.build_path()), "lib")

    System.cmd("mix", ["test"],
      cd: dir,
      stderr_to_stdout: true,
      env: [
        {"MIX_ENV", "test"},
        {"MIX_BUILD_ROOT", nil},
        {"MIX_BUILD_PATH", nil},
        {"ERL_LIBS", libs},
        {"HEX_OFFLINE", "1"}
      ]
    )
  end

  setup do
    %{
      installer: render!("installer", "lib/<%= installer_id %>.ex"),
      suite: render!("installer_test", "test/<%= installer_id %>_test.exs")
    }
  end

  test "rendered suite is Igniter.Test based and asserts the ontology facts", %{suite: suite} do
    assert suite =~ "defmodule Mix.Tasks.Badlib.InstallTest"
    assert suite =~ "import Igniter.Test"
    assert suite =~ "assert_has_patch(igniter, \"mix.exs\""
    assert suite =~ ~s({:jason, \\"~> 1.4\\"})
    assert suite =~ "assert_unchanged()"
  end

  test "generated suite passes against the generated installer (mix test exit 0)",
       %{installer: installer, suite: suite} do
    {out, status} = mix_test(installer, suite)
    assert status == 0, out
    assert out =~ "2 tests, 0 failures"
  end

  test "falsifier: mutated installer (add_dep step dropped) fails the generated suite",
       %{installer: installer, suite: suite} do
    mutated = String.replace(installer, ~r/\n\s*\|> Igniter\.Project\.Deps\.add_dep\(.*\)/, "")
    refute mutated == installer

    {out, status} = mix_test(mutated, suite)
    assert status != 0, out
    assert out =~ "Expected `mix.exs` to contain the following patch"
  end
end
