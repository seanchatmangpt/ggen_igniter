defmodule GgenIgniter.SemanticJira.CS2Batch do
  @moduledoc "Exact-bound admission and dependency layering for generated CS2 work-order batches."
  alias GgenIgniter.SemanticJira
  @sha ~r/\A[0-9a-f]{40}\z/
  @repo ~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/

  def admit(raw) when is_map(raw) do
    batch = strings(raw)
    with :ok <- required(batch),
         :ok <- binding_shape(batch),
         :ok <- exact_bindings(batch),
         :ok <- unique_identities(batch["work_orders"]),
         {:ok, orders} <- admit_orders(batch["work_orders"]) do
      value = batch |> Map.put("work_orders", orders) |> Map.put("authority", "NONE")
      {:ok, value |> Map.put("admitted", true) |> Map.put("batch_digest", SemanticJira.digest(value))}
    else
      {:error, reason} -> {:error, {:refused_cs2_batch, reason}}
    end
  end
  def admit(_), do: {:error, {:refused_cs2_batch, :expected_map}}

  def dependency_layers(raw) do
    with {:ok, batch} <- admit(raw), do: layer(batch["work_orders"], [], MapSet.new())
  end

  def projection_candidates(raw) do
    with {:ok, batch} <- admit(raw), {:ok, layers} <- dependency_layers(batch) do
      {:ok, layers |> Enum.with_index() |> Enum.flat_map(fn {orders, layer} ->
        Enum.map(orders, fn order -> %{
          "batch_id" => batch["batch_id"], "batch_digest" => batch["batch_digest"],
          "layer" => layer, "identity" => order["identity"],
          "work_order_digest" => order["work_order_digest"],
          "definition_digest" => order["definition_digest"],
          "subject" => batch["subject"], "repository" => batch["repository"],
          "base_sha" => batch["base_sha"], "authority" => "NONE"
        } end)
      end)}
    end
  end

  defp required(batch) do
    case Enum.find(~w(batch_id subject repository base_sha work_orders), &(batch[&1] in [nil, "", []])) do
      nil -> :ok
      field -> {:error, {:missing_required_field, field}}
    end
  end
  defp binding_shape(%{"repository" => repo, "base_sha" => sha, "work_orders" => orders})
       when is_binary(repo) and is_binary(sha) and is_list(orders) and orders != [] do
    cond do
      not Regex.match?(@repo, repo) -> {:error, {:invalid_repository, repo}}
      not Regex.match?(@sha, sha) -> {:error, {:invalid_base_sha, sha}}
      true -> :ok
    end
  end
  defp binding_shape(_), do: {:error, :invalid_batch_shape}

  defp exact_bindings(batch) do
    expected = Map.take(batch, ~w(subject repository base_sha))
    case Enum.find(batch["work_orders"], &(Map.take(strings(&1), ~w(subject repository base_sha)) != expected)) do
      nil -> :ok
      order -> {:error, {:binding_mismatch, strings(order)["identity"]}}
    end
  end

  defp unique_identities(orders) do
    ids = Enum.map(orders, &(strings(&1)["identity"]))
    cond do
      Enum.any?(ids, &(&1 in [nil, ""])) -> {:error, :missing_work_identity}
      length(ids) != MapSet.size(MapSet.new(ids)) -> {:error, :duplicate_work_identity}
      true -> :ok
    end
  end

  defp admit_orders(orders) do
    Enum.reduce_while(orders, {:ok, []}, fn raw, {:ok, acc} ->
      case SemanticJira.admit_work_order(raw) do
        {:ok, order} -> {:cont, {:ok, [order | acc]}}
        {:error, reason} -> {:halt, {:error, {:work_order_refused, strings(raw)["identity"], reason}}}
      end
    end) |> case do {:ok, xs} -> {:ok, Enum.reverse(xs)}; error -> error end
  end

  defp layer([], layers, _done), do: {:ok, Enum.reverse(layers)}
  defp layer(remaining, layers, done) do
    local = MapSet.new(Enum.map(remaining, & &1["identity"]))
    {ready, blocked} = Enum.split_with(remaining, fn order ->
      order |> Map.get("dependencies", []) |> Enum.map(&(strings(&1)["upstream"]))
      |> Enum.reject(&MapSet.member?(local, &1)) |> Enum.all?(&MapSet.member?(done, &1))
    end)
    if ready == [] do
      {:error, {:refused_cs2_batch, {:cyclic_or_external_dependencies, Enum.map(blocked, & &1["identity"])}}}
    else
      next = Enum.reduce(ready, done, &MapSet.put(&2, &1["identity"]))
      layer(blocked, [ready | layers], next)
    end
  end

  defp strings(v) when is_map(v) and not is_struct(v), do: Map.new(v, fn {k,x} -> {to_string(k), strings(x)} end)
  defp strings(v) when is_list(v), do: Enum.map(v, &strings/1)
  defp strings(v), do: v
end
