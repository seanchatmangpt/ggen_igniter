defmodule GgenIgniter.SemanticJira.CS2Projection do
  @moduledoc """
  Consumer adapter for the canonical ggen-marketplace CS2 semantic-work batch.

  The marketplace pack intentionally carries only source-bound semantic work.
  This adapter expands that projection into the richer SemanticJira WorkOrder
  vocabulary and delegates all admission to the existing kernel. It does not
  grant standing, leases, execution authority, or consequential DO.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.CS2Batch

  @sha ~r/\A[0-9a-f]{40}\z/
  @digest ~r/\A[0-9a-f]{64}\z/
  @repo ~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/
  @default_projections ~w(worker verification machine)

  @spec project_batch(map()) :: {:ok, map()} | {:error, term()}
  def project_batch(raw) when is_map(raw) do
    batch = strings(raw)

    with :ok <- require_batch(batch),
         :ok <- source_shape(batch["source"]),
         :ok <- authority_none(batch),
         {:ok, work_orders} <- project_work(batch) do
      CS2Batch.admit(%{
        "batch_id" => batch["batchId"],
        "subject" => batch["subject"],
        "repository" => batch["source"]["repo"],
        "base_sha" => batch["source"]["sha"],
        "source_digest" => batch["source"]["digest"],
        "work_orders" => work_orders,
        "authority" => "NONE"
      })
    else
      {:error, reason} -> {:error, {:refused_cs2_projection, reason}}
    end
  end

  def project_batch(_), do: {:error, {:refused_cs2_projection, :expected_map}}

  defp project_work(batch) do
    Enum.reduce_while(batch["work"], {:ok, []}, fn raw, {:ok, acc} ->
      row = strings(raw)

      with :ok <- require_work(row),
           {:ok, order} <- SemanticJira.admit_work_order(work_order(batch, row)) do
        {:cont, {:ok, [order | acc]}}
      else
        {:error, reason} ->
          {:halt, {:error, {:work_projection_refused, row["workKey"], reason}}}
      end
    end)
    |> case do
      {:ok, work_orders} -> {:ok, Enum.reverse(work_orders)}
      error -> error
    end
  end

  defp work_order(batch, row) do
    source = batch["source"]
    work_key = row["workKey"]

    %{
      "identity" => work_key,
      "title" => row["title"] || row["objective"],
      "description" => row["description"] || row["objective"],
      "subject" => batch["subject"],
      "repository" => source["repo"],
      "base_sha" => source["sha"],
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "source-bound",
      "promotion_rule" => "explicit-receipt",
      "replay_identity" => batch["batchId"] <> ":" <> work_key,
      "required_courts" => ["semantic_jira"],
      "required_evidence" => ["source_binding"],
      "acceptance" => [row["acceptance"]],
      "falsifiers" => [row["falsifier"]],
      "projections" => row["projections"] || @default_projections,
      "origin_authority" => row["originAuthority"] || batch["subject"],
      "dependencies" =>
        Enum.map(row["dependencies"] || [], fn upstream ->
          %{"upstream" => upstream, "type" => "requiresSemanticIdentity"}
        end),
      "required_receipt_classes" => ["verification", "replay"],
      "path_scope" => row["pathScope"] || [],
      "authority_requirement" => "NONE",
      "source_digest" => source["digest"],
      "next_edge" => row["nextEdge"],
      "authority" => "NONE"
    }
  end

  defp require_batch(batch) do
    missing =
      Enum.reject(~w(batchId subject source work authority), fn field ->
        Map.has_key?(batch, field) and batch[field] not in [nil, "", []]
      end)

    cond do
      missing != [] -> {:error, {:missing_batch_fields, missing}}
      not is_list(batch["work"]) -> {:error, :work_must_be_list}
      batch["work"] == [] -> {:error, :empty_work_batch}
      true -> :ok
    end
  end

  defp require_work(row) do
    missing =
      Enum.reject(~w(workKey objective acceptance falsifier nextEdge), fn field ->
        Map.has_key?(row, field) and row[field] not in [nil, ""]
      end)

    if missing == [], do: :ok, else: {:error, {:missing_work_fields, missing}}
  end

  defp source_shape(%{"repo" => repo, "sha" => sha, "digest" => digest})
       when is_binary(repo) and is_binary(sha) and is_binary(digest) do
    cond do
      not Regex.match?(@repo, repo) -> {:error, {:invalid_repository, repo}}
      not Regex.match?(@sha, sha) -> {:error, {:invalid_base_sha, sha}}
      not Regex.match?(@digest, digest) -> {:error, {:invalid_source_digest, digest}}
      true -> :ok
    end
  end

  defp source_shape(_), do: {:error, :invalid_source}

  defp authority_none(%{"authority" => "NONE"}), do: :ok
  defp authority_none(_), do: {:error, :authority_must_be_none}

  defp strings(v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, x} -> {to_string(k), strings(x)} end)

  defp strings(v) when is_list(v), do: Enum.map(v, &strings/1)
  defp strings(v), do: v
end
