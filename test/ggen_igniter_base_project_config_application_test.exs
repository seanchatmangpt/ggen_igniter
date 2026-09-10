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
        Igniter.Test.test_project(files: %{"config/config.exs" => real_config_exs()})

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

  describe "Igniter.Project.Application.add_new_child/2,3 (real Ex4pm.Application)" do
    test "finds the real, already-declared app_module via mix.exs's real `mod:` tuple" do
      igniter =
        Igniter.Test.test_project(
          files: %{
            "mix.exs" => real_ex4pm_mix_exs(),
            "lib/ex4pm/application.ex" => Ex4pmFixture.read!("lib/ex4pm/application.ex")
          }
        )

      assert Igniter.Project.Application.app_module(igniter) == Ex4pm.Application
    end

    # Real behavior against ex4pm's current (post-umbrella-merge) code: since
    # the umbrella's separate per-app `Application` callbacks were merged
    # into one installed OTP application, `Ex4pm.Application.start/2` now
    # assigns its child list to a real `children = [...]` binding before
    # passing it to `Supervisor.start_link/2` (see the module's own
    # moduledoc: "formerly `Ex4pm.Runtime.Application`"). `add_new_child/2,3`
    # can find that binding and successfully injects the new child --
    # confirmed by running this exact call against real, current ex4pm
    # content.
    test "adds the new child to the real `children = [...]` binding" do
      igniter =
        Igniter.Test.test_project(
          files: %{
            "mix.exs" => real_ex4pm_mix_exs(),
            "lib/ex4pm/application.ex" => Ex4pmFixture.read!("lib/ex4pm/application.ex")
          }
        )

      igniter = Igniter.Project.Application.add_new_child(igniter, MyNewRealChild)

      assert igniter.warnings == []

      source =
        igniter.rewrite
        |> Rewrite.source!("lib/ex4pm/application.ex")
        |> Rewrite.Source.get(:content)

      assert source =~ "MyNewRealChild"
      # and the real, pre-existing child is untouched
      assert source =~ "Ex4pm.Evidence.Store"
    end
  end

  defp real_config_exs, do: Ex4pmFixture.read!("config/config.exs")

  defp real_ex4pm_mix_exs, do: Ex4pmFixture.read!("mix.exs")
end
