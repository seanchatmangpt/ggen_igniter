Code.require_file("support/ex4pm_fixture.ex", __DIR__)

defmodule GgenIgniterBaseCodeKeywordMapListTupleTest do
  @moduledoc """
  Chicago-style: real `Sourceror.parse_string!/1` -> `Sourceror.Zipper` ->
  `Igniter.Code.Keyword`/`.Map`/`.List`/`.Tuple` calls against real source
  from `~/ex4pm` (`Ex4pmFixture`) -- the root umbrella `mix.exs`'s real
  `deps: [{:stream_data, "~> 1.0"}, {:decimal, "~> 3.1", override: true}]`
  list-of-tuples-with-keyword-opts, and `ex4pm_contracts`'s real
  `@artifacts %{ontology: "...", ...}` map literal. Mirrors the exact
  `Igniter.Code.List.list?/1` + `move_to_list_item/2` +
  `Igniter.Code.Tuple.tuple?/1` + `elem_equals?/3` + `tuple_elem/2` +
  `Igniter.Code.Keyword.remove_keyword_key/2` idiom already proven in
  production at `lib/ggen_igniter/doctor_fixes.ex:352-360`, extended here with
  direct, isolated coverage plus `Igniter.Code.Map`, which has no production
  caller and zero test coverage anywhere in this repo before this file.
  """

  use ExUnit.Case, async: true

  require Igniter.Code.Common
  alias Sourceror.Zipper

  describe "Igniter.Code.List / Igniter.Code.Tuple / Igniter.Code.Keyword (real ex4pm mix.exs deps list)" do
    setup do
      zipper =
        Ex4pmFixture.mix_exs_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      # move_to_def/2 lands directly on the real `project/0` body -- the real
      # `[apps_path: "apps", ..., deps: [...], ...]` keyword list itself.
      {:ok, zipper} = Igniter.Code.Module.move_to_module_using(zipper, Mix.Project)
      {:ok, zipper} = Igniter.Code.Function.move_to_def(zipper, :project, 0)

      {:ok, zipper: zipper}
    end

    test "list?/1 confirms the real deps list is a list literal", %{zipper: zipper} do
      {:ok, deps_zipper} =
        Igniter.Code.Keyword.get_key(zipper, :deps)

      assert Igniter.Code.List.list?(deps_zipper)
    end

    test "move_to_list_item/2 + tuple?/1 + elem_equals?/3 finds the real :decimal dep tuple",
         %{zipper: zipper} do
      {:ok, deps_zipper} = Igniter.Code.Keyword.get_key(zipper, :deps)

      assert {:ok, tuple_zipper} =
               Igniter.Code.List.move_to_list_item(deps_zipper, fn item ->
                 Igniter.Code.Tuple.tuple?(item) and
                   Igniter.Code.Tuple.elem_equals?(item, 0, :decimal)
               end)

      assert {:ok, opts_zipper} = Igniter.Code.Tuple.tuple_elem(tuple_zipper, 2)

      # set_keyword_key/4 flips the real `override: true` to `override: false`
      # in place -- kept non-empty deliberately (removing the sole remaining
      # key would leave `[]` as a tuple element, a real Sourceror/Formatter
      # round-trip edge case this repo already works around for the same
      # dependency shape via `collapse_empty_dep_opts/1` in
      # `lib/ggen_igniter/doctor_fixes.ex`).
      {:ok, with_flipped_override} =
        Igniter.Code.Keyword.set_keyword_key(opts_zipper, :override, false, fn z ->
          {:ok, Zipper.replace(z, false)}
        end)

      final = with_flipped_override |> Zipper.topmost_root() |> Sourceror.to_string()
      refute final =~ "override: true"
      assert final =~ ~s({:decimal, "~> 3.1", override: false})
    end

    test "no tuple matches a dep that does not exist", %{zipper: zipper} do
      {:ok, deps_zipper} = Igniter.Code.Keyword.get_key(zipper, :deps)

      assert :error =
               Igniter.Code.List.move_to_list_item(deps_zipper, fn item ->
                 Igniter.Code.Tuple.tuple?(item) and
                   Igniter.Code.Tuple.elem_equals?(item, 0, :nonexistent_dep)
               end)
    end
  end

  describe "Igniter.Code.Map (real ex4pm_contracts @artifacts map)" do
    setup do
      zipper =
        Ex4pmFixture.contracts_source()
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      {:ok, zipper: zipper}
    end

    test "set_map_key/4 patches the real :ontology entry in @artifacts", %{zipper: zipper} do
      {:ok, map_zipper} =
        Igniter.Code.Common.move_to(zipper, fn z ->
          Igniter.Code.Common.node_matches_pattern?(z, {:%{}, _, _})
        end)

      assert {:ok, patched} =
               Igniter.Code.Map.set_map_key(
                 map_zipper,
                 :ontology,
                 "ontology/renamed.ttl",
                 fn z -> {:ok, Zipper.replace(z, "ontology/renamed.ttl")} end
               )

      text = patched |> Zipper.topmost_root() |> Sourceror.to_string()
      assert text =~ "ontology/renamed.ttl"
      assert text =~ "shacl: \"shacl/ex4pm-shapes.ttl\""
    end
  end
end
