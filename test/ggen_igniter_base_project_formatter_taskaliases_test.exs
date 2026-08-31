Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseProjectFormatterTaskAliasesTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project(files: ...)` seeded with the
  real, unmodified `.formatter.exs` and root `mix.exs` content read from
  `~/ex4pm` (`Ex4pmFixture`), driving `Igniter.Project.Formatter` and
  `Igniter.Project.TaskAliases`. Neither has any test coverage in this repo
  today. Every assertion is on the real resulting `%Igniter{}` file content,
  never on "was this called."
  """

  use ExUnit.Case, async: true

  describe "Igniter.Project.Formatter.import_dep/2 (real ex4pm .formatter.exs)" do
    test "adds a real new import_deps entry to the real ex4pm formatter config" do
      igniter =
        Igniter.Test.test_project(files: %{".formatter.exs" => Ex4pmFixture.read!(".formatter.exs")})

      igniter = Igniter.Project.Formatter.import_dep(igniter, :ash)

      source = igniter.rewrite |> Rewrite.source!(".formatter.exs") |> Rewrite.Source.get(:content)
      assert source =~ "import_deps: [:ash]"
      # the real, pre-existing `inputs:` list from ex4pm is untouched
      assert source =~ ~s(inputs: ["mix.exs", "config/*.exs", "apps/**/*.{ex,exs}"])
    end

    test "remove_imported_dep/2 removes a real just-added import_deps entry" do
      igniter =
        Igniter.Test.test_project(files: %{".formatter.exs" => Ex4pmFixture.read!(".formatter.exs")})

      igniter =
        igniter
        |> Igniter.Project.Formatter.import_dep(:ash)
        |> Igniter.Project.Formatter.remove_imported_dep(:ash)

      source = igniter.rewrite |> Rewrite.source!(".formatter.exs") |> Rewrite.Source.get(:content)
      refute source =~ ":ash"
    end
  end

  describe "Igniter.Project.TaskAliases.add_alias/4 (real ex4pm root mix.exs)" do
    test "appends a real new alias to the real, existing `defp aliases do` list" do
      igniter = Igniter.Test.test_project(files: %{"mix.exs" => Ex4pmFixture.mix_exs_source()})

      igniter =
        Igniter.Project.TaskAliases.add_alias(igniter, "ggen.probe", "run scripts/probe.exs",
          if_exists: :append
        )

      source = igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
      assert source =~ ~s("ggen.probe": "run scripts/probe.exs")
      # every real, pre-existing alias survives untouched
      assert source =~ "test.stress"
      assert source =~ "chicago:"
    end

    test "modify_existing_alias/3 rewrites a real existing alias's real value" do
      igniter = Igniter.Test.test_project(files: %{"mix.exs" => Ex4pmFixture.mix_exs_source()})

      igniter =
        Igniter.Project.TaskAliases.modify_existing_alias(igniter, "chicago", fn zipper ->
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             ~s(["do --app ex4pm test --only chicago --seed 1"])
           )}
        end)

      source = igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
      assert source =~ "--seed 1"
      refute source =~ "--seed 0"
    end
  end
end
