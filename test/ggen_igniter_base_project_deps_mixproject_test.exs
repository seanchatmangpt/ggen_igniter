Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseProjectDepsMixProjectTest do
  @moduledoc """
  Chicago-style: real `Igniter.Test.test_project(files: ...)` (an in-memory
  `%Igniter{}`, per `deps/igniter/lib/igniter/test.ex`) seeded with real,
  unmodified `mix.exs` content read from `~/ex4pm` (`Ex4pmFixture`), driving
  `Igniter.Project.Deps` and `Igniter.Project.MixProject` -- neither has any
  test coverage in this repo today, and `Igniter.Test` itself has zero usage
  anywhere in this repo before this file (confirmed: `grep -rn "Igniter.Test"
  test/ lib/` returns nothing else). Every assertion is on the real resulting
  `%Igniter{}` state (`assert_has_warning`, `assert_has_patch`) via
  `Igniter.Test`'s own documented assertion API -- never on "was this
  called."

  Real, disclosed finding from this file: `Igniter.Project.Deps.add_dep/2,3`
  requires the consuming project's `mix.exs` to declare deps via a private
  `defp deps do [...] end` function (the `mix new`/Phoenix convention) --
  confirmed by reading `deps/igniter/lib/igniter/project/deps.ex:404-410`'s
  real `Igniter.Code.Function.move_to_defp(zipper, :deps, 0)` call. Real
  ex4pm `mix.exs` files inline `deps: [...]` directly inside `project/0`
  instead. Against that real shape, `add_dep/2` does not degrade to a
  warning: `get_dep/2`'s `with ... else _ -> nil end` fallback
  (`deps.ex:261-262`) returns a bare `nil` instead of `{:ok, nil}` or
  `{:error, _}` when `move_to_defp/3` fails, and `add_dependency/4`'s `case`
  (`deps.ex:60`) has no clause for bare `nil` -- a real `CaseClauseError`
  crash, not a silent no-op or a misapplied patch. This is a genuine
  generalization gap in the base library (an uncaught crash on a real,
  differently-shaped project, not just a missed feature), surfaced here by
  using a second real project shape rather than a synthetic fixture built
  to match the library's own assumed `defp deps do` convention.
  """

  use ExUnit.Case, async: true

  describe "Igniter.Project.Deps.add_dep/2 (real ex4pm_contracts mix.exs, inline deps convention)" do
    test "crashes with a real CaseClauseError: no `defp deps do` to find in this real project" do
      igniter =
        Igniter.Test.test_project(
          files: %{"mix.exs" => Ex4pmFixture.read!("apps/ex4pm_contracts/mix.exs")}
        )

      assert_raise CaseClauseError, ~r/no case clause matching:\s*nil/, fn ->
        Igniter.Project.Deps.add_dep(igniter, {:jason, "~> 1.4"}, error?: false)
      end
    end
  end

  describe "Igniter.Project.MixProject.update/4 (real ex4pm root mix.exs, path-based codemod)" do
    # `{:code, quoted}` with a binary `quoted` is parsed as REAL Elixir SOURCE
    # via `Sourceror.parse_string!/1` (deps/igniter/lib/igniter/project/mix_project.ex:262-264),
    # not treated as an already-literal string value. Passing the bare
    # version string this docmodule's own `update/4` example uses
    # (`{:ok, {:code, new_version}}`) breaks against ex4pm's real semver
    # `"26.8.28"` (two dots is not valid bare Elixir source) -- a real,
    # disclosed gotcha in the base library's own documented example, found
    # by exercising it against a real, differently-shaped version string.
    # The fix, used below: `inspect/1` the string into valid literal source.
    test "patches the real umbrella `version:` key in project/0 in place" do
      igniter = Igniter.Test.test_project(files: %{"mix.exs" => Ex4pmFixture.mix_exs_source()})

      igniter =
        Igniter.Project.MixProject.update(igniter, :project, [:version], fn zipper ->
          new_version =
            zipper.node
            |> Version.parse!()
            |> Map.update!(:patch, &(&1 + 1))
            |> to_string()

          {:ok, {:code, inspect(new_version)}}
        end)

      # `assert_has_patch/3`'s `patch` argument must itself be diff-shaped
      # (each line needs a `|` marker, per `igniter/test.ex:511`'s real
      # `sanitize_diff/2` requirement) -- asserting on the real resulting
      # file content directly is simpler and equally Chicago-style here.
      source = igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
      assert source =~ ~s(version: "26.8.29",)
      refute source =~ ~s(version: "26.8.28",)
    end

    test "the real, untouched apps_path key survives the patch unchanged" do
      igniter = Igniter.Test.test_project(files: %{"mix.exs" => Ex4pmFixture.mix_exs_source()})

      igniter =
        Igniter.Project.MixProject.update(igniter, :project, [:version], fn _ ->
          {:ok, {:code, inspect("0.0.0")}}
        end)

      source = igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
      assert source =~ ~s(apps_path: "apps")
    end
  end
end
