defmodule GgenIgniter.SemanticEpoch do
  @moduledoc """
  Machine-checkable boundary between the last human-readable manufacture
  contract (`v26.9.14`) and graph-generated ephemeral projections
  (`v26.9.15`).

  This module is policy, not actuation. It grants no filesystem, deployment,
  or business-effect authority. The existing reconciliation/actuation path
  remains the only place ggen_igniter may change a consumer tree.
  """

  @v26_9_14 "26.9.14"
  @v26_9_15 "26.9.15"

  @constitutional %{
    canonical_truth: :semantic_graph,
    generated_artifact_role: :projection,
    handwritten_generated_edits: :refused,
    planner_authority: :none,
    generator_authority_ceiling: :construct,
    consequence_do_authority: :external,
    receipt_required: true,
    replay_required: true
  }

  @ephemeral Map.merge(@constitutional, %{
               human_readable_projection_required: false,
               persistent_projection_required: false,
               projection_disposition: :ephemeral
             })

  @type invariant :: atom()
  @type refusal :: {:refused_epoch_invariant, map()}

  @spec version(:constitutional | :ephemeral) :: String.t()
  def version(:constitutional), do: @v26_9_14
  def version(:ephemeral), do: @v26_9_15

  @spec invariants(:constitutional | :ephemeral) :: map()
  def invariants(:constitutional), do: @constitutional
  def invariants(:ephemeral), do: @ephemeral

  @doc """
  Admits an epoch declaration only when every required invariant is present
  with the exact required value. Extra keys are preserved for forward
  extension; they never weaken a required invariant.
  """
  @spec admit(:constitutional | :ephemeral, map()) ::
          {:ok, %{epoch: atom(), version: String.t(), declaration: map()}} | {:error, refusal()}
  def admit(epoch, declaration) when epoch in [:constitutional, :ephemeral] and is_map(declaration) do
    required = invariants(epoch)

    mismatches =
      required
      |> Enum.reduce(%{}, fn {key, expected}, acc ->
        case Map.fetch(declaration, key) do
          {:ok, ^expected} -> acc
          {:ok, observed} -> Map.put(acc, key, %{expected: expected, observed: observed})
          :error -> Map.put(acc, key, %{expected: expected, observed: :missing})
        end
      end)

    if map_size(mismatches) == 0 do
      {:ok, %{epoch: epoch, version: version(epoch), declaration: declaration}}
    else
      {:error, {:refused_epoch_invariant, mismatches}}
    end
  end
end
