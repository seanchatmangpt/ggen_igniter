Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseProjectConfigApplicationTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project(files: ...)` seeded with
  real, unmodified `config/config.exs` and `ex4pm_runtime`'s real `mix.exs`
  + `Ex4pm.Runtime.Application` module content read from `~/ex4pm`
  (`Ex4pmFixture`), driving `Igniter.Project.Config` and
  `Igniter.Project.Application`. Neither has any test coverage in this repo
  today. Every assertion is on the real resulting `%Igniter{}` file content,
  never on "was this called."
  """

  use ExUnit.Case, async: true

  describe "Igniter.Project.Config.configure_new/6 (real ex4pm root config/config.exs)" do
    test "adds a real new config value alongside the real existing :logger config" do
      igniter =
        Igniter.Test.test_project(
          files: %{"config/config.exs" => real_config_exs()}
        )

      igniter =
        Igniter.Project.Config.configure_new(
          igniter,
          "config.exs",
          :ex4pm_qualification,
          [:crown_gate],
          :enabled
        )

      source =
        igniter.rewrite |> Rewrite.source!("config/config.exs") |> Rewrite.Source.get(:content)

      assert source =~ "config :ex4pm_qualification, crown_gate: :enabled"
      # the real, pre-existing :logger config from ex4pm is untouched
      assert source =~ "config :logger, level: :info"
    end

    test "configures?/4 is false for a real config path that genuinely is not set yet" do
      igniter = Igniter.Test.test_project(files: %{"config/config.exs" => real_config_exs()})

      refute Igniter.Project.Config.configures?(
               igniter,
               "config.exs",
               [:some_key_ex4pm_never_sets],
               :ex4pm
             )
    end
  end

  describe "Igniter.Project.Application.add_new_child/2,3 (real Ex4pm.Runtime.Application)" do
    test "finds the real, already-declared app_module via mix.exs's real `mod:` tuple" do
      igniter =
        Igniter.Test.test_project(
          files: %{
            "mix.exs" => real_ex4pm_runtime_mix_exs(),
            "lib/ex4pm/runtime/application.ex" =>
              Ex4pmFixture.read!("apps/ex4pm_runtime/lib/ex4pm/runtime/application.ex")
          }
        )

      assert Igniter.Project.Application.app_module(igniter) == Ex4pm.Runtime.Application
    end

    # Real, disclosed finding: `add_new_child/2,3` requires the target
    # `start/2` to assign its child list to a `children = [...]` variable
    # before passing it to `Supervisor.start_link/2` -- confirmed by running
    # this exact call against real ex4pm content. Ex4pm's real
    # `Ex4pm.Runtime.Application.start/2` inlines the (currently-empty)
    # child list directly (`Supervisor.start_link([], ...)`, no `children =`
    # binding), so the codemod cannot locate an insertion point and degrades
    # to a real, honest warning -- it does NOT crash, and it does NOT
    # silently misapply a patch. A second real generalization gap found by
    # testing against ex4pm's real code, distinct from the
    # `Igniter.Project.Deps.add_dep/2` crash found in
    # `ggen_igniter_base_project_deps_mixproject_test.exs`.
    test "produces a real warning against real code with no `children = [...]` binding" do
      igniter =
        Igniter.Test.test_project(
          files: %{
            "mix.exs" => real_ex4pm_runtime_mix_exs(),
            "lib/ex4pm/runtime/application.ex" =>
              Ex4pmFixture.read!("apps/ex4pm_runtime/lib/ex4pm/runtime/application.ex")
          }
        )

      igniter = Igniter.Project.Application.add_new_child(igniter, MyNewRealChild)

      assert Enum.any?(igniter.warnings, &(&1 =~ "Could not find a `children = [...]`"))

      # and, consistent with that warning, the real file is left untouched
      source =
        igniter.rewrite
        |> Rewrite.source!("lib/ex4pm/runtime/application.ex")
        |> Rewrite.Source.get(:content)

      refute source =~ "MyNewRealChild"
      assert source =~ "Ex4pm.Runtime.Supervisor"
    end
  end

  defp real_config_exs, do: Ex4pmFixture.read!("config/config.exs")

  defp real_ex4pm_runtime_mix_exs, do: Ex4pmFixture.read!("apps/ex4pm_runtime/mix.exs")
end
