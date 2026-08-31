Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseProjectTestTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project(files: ...)` seeded with the
  real, unmodified `apps/ex4pm_contracts/mix.exs` content read from
  `~/ex4pm` (`Ex4pmFixture`), driving `Igniter.Project.Test.ensure_test_support/1`
  -- zero test coverage or production caller anywhere in this repo before
  this file. Every assertion is on the real resulting `%Igniter{}` file
  content, never on "was this called."
  """

  use ExUnit.Case, async: true

  describe "Igniter.Project.Test.ensure_test_support/1 (real ex4pm_contracts mix.exs, no prior elixirc_paths)" do
    test "adds a real elixirc_paths key plus the real per-env private functions" do
      igniter =
        Igniter.Test.test_project(
          files: %{"mix.exs" => Ex4pmFixture.read!("apps/ex4pm_contracts/mix.exs")}
        )

      igniter = Igniter.Project.Test.ensure_test_support(igniter)

      source = igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
      assert source =~ "elixirc_paths: elixirc_paths(Mix.env())"
      assert source =~ "defp elixirc_paths(:test),"
      assert source =~ "elixirc_paths(:dev) ++ [\"test/support\"]"
      assert source =~ "defp elixirc_paths(_),"
      assert source =~ "do: [\"lib\"]"

      # the real, pre-existing `deps:`/`package()` config from
      # ex4pm_contracts survives byte-for-byte
      assert source =~ "deps: [{:ex4pm_core, \"~> 26.8.22\", in_umbrella: true}]"
      assert source =~ "defp package,"
    end

    test "is idempotent against a real project that already has elixirc_paths" do
      once =
        Igniter.Test.test_project(
          files: %{"mix.exs" => Ex4pmFixture.read!("apps/ex4pm_contracts/mix.exs")}
        )
        |> Igniter.Project.Test.ensure_test_support()

      already_configured_source =
        once.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)

      twice =
        Igniter.Test.test_project(files: %{"mix.exs" => already_configured_source})
        |> Igniter.Project.Test.ensure_test_support()

      twice_source = twice.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
      assert twice_source == already_configured_source
    end
  end
end
