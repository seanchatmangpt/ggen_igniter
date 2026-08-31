Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseCodeFunctionTest do
  @moduledoc """
  Chicago-style: real `Sourceror.parse_string!/1` -> `Sourceror.Zipper` ->
  `Igniter.Code.Function` calls against the real, unmodified source of
  `~/ex4pm/apps/ex4pm_contracts/lib/ex4pm/contracts.ex` (`Ex4pmFixture.contracts_source/0`).
  Every assertion is on the real resulting zipper/source text, never on "was
  this called" -- `Igniter.Code.Function` has zero test coverage in this repo
  today; its only real production caller is
  `lib/ggen_igniter/doctor_fixes.ex`'s `move_to_defp/3`/`move_to_def/2` calls
  (lines 351, 945), which this file extends with direct, isolated coverage of
  the same real primitives against a second, differently-shaped real project
  (ex4pm's plain RDFS ontology contracts module vs. beam4pm's
  `bpm:RecordType`-manufactured code, which ggen_igniter has never been
  tested against).
  """

  use ExUnit.Case, async: true

  alias Sourceror.Zipper

  setup do
    zipper =
      Ex4pmFixture.contracts_source()
      |> Sourceror.parse_string!()
      |> Zipper.zip()

    {:ok, zipper: zipper}
  end

  describe "move_to_def/2 (real Ex4pm.Contracts source)" do
    test "finds the real public manifest/0 function's real body", %{zipper: zipper} do
      # move_to_def/2 lands the zipper on the function's real body expression
      # (not the enclosing `def ... do ... end` node) -- confirmed against
      # this real file: manifest/0's body is the real `@artifacts |> Enum.sort() |> ...` pipeline.
      assert {:ok, found} = Igniter.Code.Function.move_to_def(zipper, :manifest, 0)

      text = found |> Zipper.node() |> Sourceror.to_string()
      assert text =~ "@artifacts"
      assert text =~ "Enum.reduce_while"
    end

    test "finds the real public version/0 function's real body", %{zipper: zipper} do
      assert {:ok, found} = Igniter.Code.Function.move_to_def(zipper, :version, 0)

      text = found |> Zipper.node() |> Sourceror.to_string()
      assert text == "@contract_version"
    end

    test "refuses (returns :error) for a function that does not exist", %{zipper: zipper} do
      assert :error = Igniter.Code.Function.move_to_def(zipper, :does_not_exist_at_all, 3)
    end
  end

  describe "move_to_defp/3 (real Ex4pm.Contracts source)" do
    test "finds the real private artifact_path/1 function's real body", %{zipper: zipper} do
      assert {:ok, found} = Igniter.Code.Function.move_to_defp(zipper, :artifact_path, 1)

      text = found |> Zipper.node() |> Sourceror.to_string()
      assert text =~ "Application.app_dir"
    end

    test "does not find a public function via move_to_defp/3", %{zipper: zipper} do
      assert :error = Igniter.Code.Function.move_to_defp(zipper, :manifest, 0)
    end
  end
end
