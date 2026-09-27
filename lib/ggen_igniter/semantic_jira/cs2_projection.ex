defmodule GgenIgniter.SemanticJira.CS2Projection do
  @moduledoc "Schema-bound CS2 projection consumer."
  alias GgenIgniter.SemanticJira

  def from_map(%{"issues" => issues} = batch) when is_list(issues) and issues != [] do
    Enum.reduce_while(issues, {:ok, [], MapSet.new()}, fn issue, {:ok, acc, seen} ->
      id = issue["identity"]
      cond do
        not is_binary(id) or id == "" -> {:halt, refusal(:identity_missing)}
        MapSet.member?(seen, id) -> {:halt, refusal({:duplicate_identity, id})}
        true ->
          case SemanticJira.admit_work_order(work_order(batch, issue)) do
            {:ok, order} -> {:cont, {:ok, [order | acc], MapSet.put(seen, id)}}
            {:error, reason} -> {:halt, refusal(reason)}
          end
      end
    end)
    |> case do
      {:ok, orders, _seen} -> {:ok, Enum.reverse(orders)}
      other -> other
    end
  end

  def from_map(_), do: refusal(:invalid_batch)

  def from_json(bytes) when is_binary(bytes) do
    with {:ok, value} <- Jason.decode(bytes), do: from_map(value)
  end

  defp work_order(batch, issue) do
    %{
      "identity" => issue["identity"], "title" => issue["title"],
      "description" => issue["description"], "subject" => batch["subject"],
      "repository" => batch["repository"], "base_sha" => batch["base_sha"],
      "standing" => "UNKNOWN", "evidence_ceiling" => Map.get(issue, "evidence_ceiling", "CONSTRUCT"),
      "promotion_rule" => Map.get(issue, "promotion_rule", "explicit_evidence_required"),
      "replay_identity" => Map.get(issue, "replay_identity", issue["identity"]),
      "required_courts" => Map.get(issue, "required_courts", ["producer_projection"]),
      "required_evidence" => Map.get(issue, "required_evidence", ["exact_subject"]),
      "acceptance" => issue["acceptance"], "falsifiers" => issue["falsifiers"],
      "projections" => issue["projections"], "origin_authority" => issue["origin_authority"],
      "dependencies" => Map.get(issue, "dependencies", [])
    }
  end

  defp refusal(reason), do: {:error, {:refused_cs2_projection, reason}}
end
