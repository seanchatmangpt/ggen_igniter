defmodule GgenIgniterInstallTaskTest do
  @moduledoc """
  Chicago-style: builds real in-memory `%Igniter{}`/`Rewrite` projects via
  `Igniter.Test.test_project/1` (real Igniter machinery, no test doubles), seeded with
  either a real `defp deps do ... end`-shaped `mix.exs` (this task's happy path) or the
  real `~/ex4pm` umbrella `mix.exs` content (via `Ex4pmFixture.mix_exs_source/0`, already
  used by this repo's other base-igniter tests) -- which genuinely declares `deps: [...]`
  inline inside `project/0`, exactly the documented `Igniter.Project.Deps.add_dep/2,3`
  crash shape this task defends against -- then composes `mix ggen_igniter.install` and
  asserts on the real resulting `%Igniter{}` state (patches, issues) via `Igniter.Test`'s
  own assertion helpers.

  Deviation from the original design's test plan: the design assumed
  `Ex4pmFixture.files/0`'s root `mix.exs` was a `defp deps`-shaped, single-app project
  suitable as the happy-path fixture for BOTH `assert_has_patch` on the ash dep AND on a
  supervision-tree child file. In reality ex4pm's real root `mix.exs` is an umbrella
  project that (a) declares `deps: [...]` inline in `project/0` (no `defp deps`) and (b)
  has no `application/0` `mod:` key for `Igniter.Project.Application.app_module/1` to
  resolve, so it cannot exercise the happy path at all -- it IS the inline-deps defect
  case. So: the happy-path test below uses a real, minimal, `defp deps`-shaped
  single-app `mix.exs`/`application.ex` pair (the same generated-project shape
  `Igniter.Project.MixProject`'s own moduledoc documents), and the defect-path test
  below uses `Ex4pmFixture.mix_exs_source/0` directly -- real fixture content, not
  fabricated, and a better fit for that case than the original design's synthetic
  inline-deps heredoc.
  """

  use ExUnit.Case, async: true
  import Igniter.Test

  describe "igniter/1" do
    test "adds ash dep, ash_domains config, and supervision child for a defp-deps project" do
      mix_exs = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :my_app,
            version: "0.1.0",
            elixir: "~> 1.17",
            start_permanent: Mix.env() == :prod,
            deps: deps()
          ]
        end

        def application do
          [
            extra_applications: [:logger],
            mod: {MyApp.Application, []}
          ]
        end

        defp deps do
          []
        end
      end
      """

      application_ex = """
      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          children = []

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end
      """

      igniter =
        test_project(
          files: %{
            "mix.exs" => mix_exs,
            "lib/my_app/application.ex" => application_ex
          }
        )
        |> Igniter.compose_task("ggen_igniter.install", ["--domain", "MyApp.Ash.Domain"])

      assert_has_patch(igniter, "mix.exs", "22 + |    [{:ash, \"~> 3.0\"}]")

      assert_has_patch(
        igniter,
        "config/config.exs",
        "2 |config :my_app, ash_domains: [MyApp.Ash.Domain]"
      )

      assert_has_patch(
        igniter,
        "lib/my_app/application.ex",
        "6 + |    children = [MyApp.Ash.Domain]"
      )
    end

    test "auto-inserts a children = [...] binding when start/2 inlines the list directly" do
      mix_exs = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :my_app,
            version: "0.1.0",
            elixir: "~> 1.17",
            start_permanent: Mix.env() == :prod,
            deps: deps()
          ]
        end

        def application do
          [
            extra_applications: [:logger],
            mod: {MyApp.Application, []}
          ]
        end

        defp deps do
          []
        end
      end
      """

      # Real shape that Igniter.Project.Application.add_new_child/2,3 cannot handle
      # on its own (no `children = [...]` binding to find an insertion point in) --
      # confirmed in test/ggen_igniter_base_project_config_application_test.exs,
      # where this exact shape degrades to a warning and leaves the file untouched.
      application_ex = """
      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          Supervisor.start_link([], strategy: :one_for_one, name: MyApp.Supervisor)
        end
      end
      """

      igniter =
        test_project(
          files: %{
            "mix.exs" => mix_exs,
            "lib/my_app/application.ex" => application_ex
          }
        )
        |> Igniter.compose_task("ggen_igniter.install", ["--domain", "MyApp.Ash.Domain"])

      # Real fix, not a warning: ensure_children_binding/1 introduces the binding
      # first, then add_new_child/3 succeeds normally against it -- the real diff
      # shows the binding introduced with the new child already present (add_new_child
      # runs after ensure_children_binding in the pipeline), not an empty list.
      assert_has_patch(
        igniter,
        "lib/my_app/application.ex",
        "6 + |    children = [MyApp.Ash.Domain]"
      )

      assert_has_patch(
        igniter,
        "lib/my_app/application.ex",
        "7 + |    Supervisor.start_link(children,"
      )

      refute Enum.any?(igniter.warnings, &(&1 =~ "children"))
    end

    test "emits an issue instead of crashing when consumer mix.exs inlines deps: [...] in project/0" do
      igniter =
        test_project(files: %{"mix.exs" => Ex4pmFixture.mix_exs_source()})
        |> Igniter.compose_task("ggen_igniter.install", [
          "--domain",
          "Ex4pm.Ash.Domain",
          "--otp-app",
          "ex4pm"
        ])

      assert_has_issue(igniter, fn issue -> issue =~ "defp deps do" end)
      assert_unchanged(igniter, "mix.exs")
    end
  end
end
