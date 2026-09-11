defmodule AshEx4pm.Info do
  @moduledoc """
  Real companion "Info" module for
  `test/ggen_igniter_ash_notifier_load2_pack_test.exs`'s ash_ex4pm-precedent
  case, named `AshEx4pm.Info` on purpose: the pack's ontology individual
  binds `nlp:infoModule` to the literal string `"AshEx4pm.Info"`, so the
  rendered `load/2` calls `AshEx4pm.Info.activities/1` verbatim -- this
  fixture gives that exact module a real, compiled definition rather than
  aliasing/renaming it, so the compiled-and-executed test exercises the
  real call the rendered code makes. `~/ash_ex4pm` is a separate,
  out-of-scope repo this session did not touch; this module exists only in
  this repo's `test/support/` tree, is not a runtime dependency of `lib/`,
  and never ships.

  Not a Spark-DSL extension (building a full `Spark.Dsl.Extension` with
  transformers/entity schemas for a test fixture was judged out of scope
  for this pass -- see `docs/integrations/ash/notifier-load2.md`'s
  disclosure) -- a plain module returning plain structs shaped exactly like
  `AshEx4pm.Info.activities/1`'s real return value (one entity per
  `on:`-matched action, each holding an `object_relationships` list of
  `relationship:`-named items), which is everything the rendered `load/2`
  function actually touches (`Enum.find/2` + `Enum.map/2` over plain field
  access -- no Spark introspection API is called).

  Mirrors `~/ash_ex4pm`'s real `AshEx4pm.Activity`/
  `AshEx4pm.ObjectRelationship` shape (commit `d4ffb71`): two activities,
  `:create` (loads `:owner` and `:team`) and `:archive` (loads only
  `:owner`), with `:destroy` deliberately left undeclared to exercise the
  `nil -> []` branch.
  """

  defmodule Activity do
    @moduledoc false
    defstruct [:on, :object_relationships]
  end

  defmodule ObjectRelationship do
    @moduledoc false
    defstruct [:relationship]
  end

  def activities(_resource) do
    [
      %Activity{
        on: :create,
        object_relationships: [
          %ObjectRelationship{relationship: :owner},
          %ObjectRelationship{relationship: :team}
        ]
      },
      %Activity{
        on: :archive,
        object_relationships: [
          %ObjectRelationship{relationship: :owner}
        ]
      }
    ]
  end
end
