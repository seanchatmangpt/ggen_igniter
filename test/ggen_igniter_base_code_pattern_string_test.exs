Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseCodePatternStringTest do
  @moduledoc """
  Chicago-style: real `Sourceror.parse_string!/1` -> `Sourceror.Zipper` ->
  `Igniter.Code.Pattern` (ExAST pattern syntax) + `Igniter.Code.String` calls
  against the real, unmodified source of
  `~/ex4pm/apps/ex4pm_contracts/lib/ex4pm/contracts.ex`. Neither module has
  any test coverage or production caller anywhere in this repo today --
  genuinely new ground, not an extension of `doctor_fixes.ex`'s existing
  bare-zipper idiom.
  """

  use ExUnit.Case, async: true

  alias Sourceror.Zipper

  describe "Igniter.Code.Pattern.matches?/2 (real Application.app_dir/2 call)" do
    test "matches the real Application.app_dir(_, _) call inside artifact_path/1" do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      {:ok, found} = Igniter.Code.Function.move_to_defp(zipper, :artifact_path, 1)

      assert Igniter.Code.Pattern.matches?(found, "Application.app_dir(_, _)")
      refute Igniter.Code.Pattern.matches?(found, "File.read(_)")
    end
  end

  describe "Igniter.Code.Pattern.move_to/3 (real File.read/1 call inside manifest/0)" do
    test "moves to the real File.read(path) call site" do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      assert {:ok, found} = Igniter.Code.Pattern.move_to(zipper, "File.read(path)")
      text = found |> Zipper.node() |> Sourceror.to_string()
      assert text == "File.read(path)"
    end
  end

  describe "Igniter.Code.Pattern.find_all/3 (real literal string patterns)" do
    test "finds every real occurrence of the literal ontology path string" do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      matches = Igniter.Code.Pattern.find_all(zipper, ~s("ontology/ex4pm.ttl"))
      assert length(matches) == 1
      assert hd(matches) |> Zipper.node() |> Sourceror.to_string() == ~s("ontology/ex4pm.ttl")
    end
  end

  describe "Igniter.Code.Pattern.replace/4 (real literal string patterns)" do
    test "replaces the real ontology path literal with a real new literal" do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      assert {:ok, replaced} =
               Igniter.Code.Pattern.replace(
                 zipper,
                 ~s("ontology/ex4pm.ttl"),
                 ~s("ontology/renamed.ttl")
               )

      final = replaced |> Zipper.topmost_root() |> Sourceror.to_string()
      assert final =~ "ontology/renamed.ttl"
      refute final =~ "\"ontology/ex4pm.ttl\""
      # every other real artifact path is left byte-for-byte untouched
      assert final =~ "shacl/ex4pm-shapes.ttl"
    end
  end

  describe "Igniter.Code.String.string?/1 + update_string/2 (real ontology path string literal)" do
    test "confirms the string node and rewrites its real content in place" do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      {:ok, found} = Igniter.Code.Pattern.move_to(zipper, ~s("ontology/ex4pm.ttl"))

      assert Igniter.Code.String.string?(found)

      {:ok, updated} =
        Igniter.Code.String.update_string(found, fn s -> {:ok, s <> ".renamed"} end)

      assert updated |> Zipper.node() |> Sourceror.to_string() ==
               ~s("ontology/ex4pm.ttl.renamed")
    end
  end
end
