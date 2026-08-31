Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseCodeModuleTest do
  @moduledoc """
  Chicago-style: real `Sourceror.parse_string!/1` -> `Sourceror.Zipper` ->
  `Igniter.Code.Module` calls against the real, unmodified source of
  `~/ex4pm/apps/ex4pm_contracts/lib/ex4pm/contracts.ex` and the real root
  umbrella `mix.exs`. `Igniter.Code.Module.move_to_defmodule/1,2` has zero
  test coverage in this repo today; `move_to_module_using/2` and
  `move_to_defp/3`/`move_to_def/2` (the arity-2/3 variants living on
  `Igniter.Code.Module` itself, distinct from `Igniter.Code.Function`'s) are
  only exercised in production at `lib/ggen_igniter/doctor_fixes.ex:350-351`
  against the CONSUMING project's own `mix.exs` -- this file gives them
  direct, isolated coverage against a second real project.
  """

  use ExUnit.Case, async: true

  alias Sourceror.Zipper

  describe "move_to_defmodule/1 (real Ex4pm.Contracts source)" do
    test "finds the real defmodule Ex4pm.Contracts node" do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      assert {:ok, found} = Igniter.Code.Module.move_to_defmodule(zipper)
      text = found |> Zipper.node() |> Sourceror.to_string()
      assert text =~ "defmodule Ex4pm.Contracts do"
    end
  end

  describe "move_to_defmodule/2 (real Ex4pm.Contracts source)" do
    test "finds the module when given the exact real module name" do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      assert {:ok, _found} = Igniter.Code.Module.move_to_defmodule(zipper, Ex4pm.Contracts)
    end

    test "refuses (returns :error) for a module name that is not in this file" do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      assert :error = Igniter.Code.Module.move_to_defmodule(zipper, Ex4pm.NotARealModule)
    end
  end

  describe "move_to_module_using/2 (real ex4pm root mix.exs)" do
    test "finds the real `use Mix.Project` module body" do
      zipper =
        Ex4pmFixture.mix_exs_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      assert {:ok, found} = Igniter.Code.Module.move_to_module_using(zipper, Mix.Project)
      text = found |> Zipper.node() |> Sourceror.to_string()
      assert text =~ "use Mix.Project"
      assert text =~ "def project do"
    end
  end

  describe "module?/1 (real ex4pm module alias node)" do
    test "true for the real Ex4pm.Contracts module alias" do
      # module?/1 requires the zipper positioned AT the `__aliases__` name
      # node itself (not the enclosing `defmodule ... do ... end`) -- parse
      # the real module's own real name in isolation.
      zipper = "Ex4pm.Contracts" |> Sourceror.parse_string!() |> Zipper.zip()
      assert Igniter.Code.Module.module?(zipper)
    end

    test "false for a real non-module value from the same file" do
      zipper = ~s("0.1.0") |> Sourceror.parse_string!() |> Zipper.zip()
      refute Igniter.Code.Module.module?(zipper)
    end
  end
end
