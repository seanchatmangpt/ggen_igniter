defmodule GgenIgniter.SemanticJira.CS2Ingest do
  @moduledoc """
  Boundary adapter from generated CS2 projection batches into Semantic Jira.

  The adapter preserves exact repository/base/subject identity, derives a
  deterministic dependency layer, and delegates admission/scheduling to the
  canonical SemanticJira kernel. It never manufactures execution authority.
  """

  alias GgenIgniter.SemanticJira

  @required ~w(subject repository base_sha work)
  @sha ~r/\A[0-9a-f]{40}\z/

  @spec ingest(map()) :: {:ok, map()} | {:error, term()}
  def ingest(raw) when is_map(raw) do
    batch = stringify(raw)

    with :ok <- require_fields(batch),
         :ok <- validate_sha(batch["base_sha"]),
         {:ok, orders} <- project_orders(batch),
         :ok <- unique_identities(orders) do
      {:ok, %{
        "subject" => batch["subject"],
        "repository" => batch["repository"],
        "base_sha" => batch["base_sha"],
        "orders" => orders,
        "layers" => dependency_layers(orders),
        "authority" => "NONE"
      }}
    end
  end

  def ingest(_), do: {:error, {:refused_cs2_batch, :expected_map}}

  @spec schedule(map(), [map()], map(), keyword()) :: {:ok, map()} | {:error, term()}
  def schedule(raw, active_leases \\ [], evidence \\ %{}, opts \\ []) do
    with {:ok, batch} <- ingest(raw) do
      result = SemanticJira.schedule(batch["orders"], active_leases, evidence, opts)
      {:ok, Map.put(result, :layers, batch["layers"])}
    end
  end

  defp project_orders(batch) do
    batch["work"]
    |> List.wrap()
    |> Enum.reduce_while({:ok, []}, fn raw, {:ok, acc} ->
      candidate =
        raw
        |> stringify()
        |> Map.put("subject", batch["subject"])
        |> Map.put("repository", batch["repository"])
        |> Map.put("base_sha", batch["base_sha"])
        |> Map.put_new("standing", "UNKNOWN")
        |> Map.put_new("authority", "NONE")

      case SemanticJira.admit_work_order(candidate) do
        {:ok, order} -> {:cont, {:ok, [order | acc]}}
        {:error, reason} -> {:halt, {:error, {:refused_cs2_work, candidate["identity"], reason}}}
      end
    end)
    |> case do
      {:ok, orders} -> {:ok, Enum.reverse(orders)}
      error -> error
    end
  end

  defp dependency_layers(orders) do
    ids = MapSet.new(orders, & &1["identity"])

    deps =
      Map.new(orders, fn order ->
        local =
          order
          |> Map.get("dependencies", [])
          |> Enum.map(&stringify/1)
          |> Enum.map(&(&1["identity"] || &1["work_order_id"] || &1["subject"]))
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&MapSet.member?(ids, &1))
          |> MapSet.new()

        {order["identity"], local}
      end)

    layer(deps, [], 0)
  end

  defp layer(deps, acc, n) when map_size(deps) == 0, do: Enum.reverse(acc)

  defp layer(deps, acc, n) do
    ready =
      deps
      |> Enum.filter(fn {_id, requirements} -> MapSet.size(requirements) == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if ready == [] do
      unresolved = deps |> Map.keys() |> Enum.sort()
      Enum.reverse([%{"layer" => n, "cycle_or_external" => unresolved} | acc])
    else
      removed = MapSet.new(ready)

      next =
        deps
        |> Map.drop(ready)
        |> Map.new(fn {id, requirements} -> {id, MapSet.difference(requirements, removed)} end)

      layer(next, [%{"layer" => n, "work" => ready} | acc], n + 1)
    end
  end

  defp unique_identities(orders) do
    ids = Enum.map(orders, & &1["identity"])
    if length(ids) == MapSet.size(MapSet.new(ids)),
      do: :ok,
      else: {:error, {:refused_cs2_batch, :duplicate_identity}}
  end

  defp require_fields(batch) do
    missing = Enum.reject(@required, &(Map.has_key?(batch, &1) and batch[&1] not in [nil, "", []]))
    if missing == [], do: :ok, else: {:error, {:refused_cs2_batch, {:missing, missing}}}
  end

  defp validate_sha(value) when is_binary(value) do
    if Regex.match?(@sha, value), do: :ok, else: {:error, {:refused_cs2_batch, :invalid_base_sha}}
  end
  defp validate_sha(_), do: {:error, {:refused_cs2_batch, :invalid_base_sha}}

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
