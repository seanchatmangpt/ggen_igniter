defmodule GgenIgniter.SemanticJira.CS2Ingest do
  @moduledoc """
  Runtime-facing ingestion boundary for canonical CS2 marketplace batches.

  Projection is owned by CS2Projection, exact batch admission and topological
  layering by CS2Batch, and scheduling by SemanticJira. This module composes
  those mechanisms and adds no independent semantic representation.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{CS2Batch, CS2Projection}

  @spec ingest(map()) :: {:ok, map()} | {:error, term()}
  def ingest(raw) when is_map(raw) do
    with {:ok, batch} <- CS2Projection.project_batch(raw),
         {:ok, layers} <- CS2Batch.dependency_layers(batch),
         {:ok, candidates} <- CS2Batch.projection_candidates(batch) do
      {:ok,
       %{
         "batch_id" => batch["batch_id"],
         "batch_digest" => batch["batch_digest"],
         "subject" => batch["subject"],
         "repository" => batch["repository"],
         "base_sha" => batch["base_sha"],
         "source_digest" => batch["source_digest"],
         "orders" => batch["work_orders"],
         "layers" => layers,
         "candidates" => candidates,
         "authority" => "NONE"
       }}
    end
  end

  def ingest(_), do: {:error, {:refused_cs2_batch, :expected_map}}

  @spec schedule(map(), [map()], map(), keyword()) :: {:ok, map()} | {:error, term()}
  def schedule(raw, active_leases \\ [], evidence \\ %{}, opts \\ []) do
    with {:ok, batch} <- ingest(raw) do
      result = SemanticJira.schedule(batch["orders"], active_leases, evidence, opts)

      {:ok,
       result
       |> Map.put(:batch_id, batch["batch_id"])
       |> Map.put(:batch_digest, batch["batch_digest"])
       |> Map.put(:layers, batch["layers"])
       |> Map.put(:candidates, batch["candidates"])}
    end
  end
end
