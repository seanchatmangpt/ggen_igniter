defmodule GgenIgniter.SemanticJira.Descriptor do
  @moduledoc """
  XaaS/zcode execution descriptor generated from the admitted frontier.

  A descriptor exists only for a work order that `SemanticJira.frontier/2`
  (or `frontier_from_events/3` when `:events` is given) currently lists as
  eligible. Any other work order (unadmitted, non-UNKNOWN standing, unmet
  dependencies, not present) yields a typed
  `{:error, {:refused_descriptor, reason}}` and no descriptor.

  Graph identity is carried unchanged, ggen -> XaaS -> ash_a2a:

    * `definition_digest` - stable identity of the definition
    * `snapshot_digest`   - the admitted `work_order_digest`
    * `base_sha`          - the exact base commit
    * `graph_digest`      - digest of the ontology graph

  The same values are copied verbatim into the descriptor, its rendered JSON
  (`templates/descriptor.json.eex` of `semantic-jira-pack`) and the A2A task
  metadata (`to_a2a_task/3`). Authority is always `NONE`; the descriptor grants
  no lease, does no DO, and never promotes standing.
  """

  alias GgenIgniter.{Render, RuntimeShape, SemanticA2A, SemanticJira}

  @schema "semantic-jira/execution-descriptor/v1"
  @identity_keys ~w(definition_digest snapshot_digest base_sha graph_digest)
  @render_keys ~w(schema work_order_id subject repository provider worker_identity
                  verifier_identity replay_identity authority)

  @doc "Schema id of descriptors produced here."
  @spec schema() :: String.t()
  def schema, do: @schema

  @doc """
  Build the descriptor for `identity` from `work_orders`.

  `attrs` needs `graph_digest`, `source_digest`, `worker_identity`,
  `verifier_identity`; optional `provider` (default `"zcode"`).
  Options: `:events` (transition log), `:evidence` (dependency evidence map).
  """
  @spec build([map()], String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(work_orders, identity, attrs, opts \\ [])
      when is_list(work_orders) and is_binary(identity) and is_map(attrs) do
    evidence = Keyword.get(opts, :evidence, %{})

    {projected, front} =
      case Keyword.get(opts, :events) do
        nil ->
          {work_orders, SemanticJira.frontier(work_orders, evidence)}

        events ->
          {p, _} = SemanticJira.project(work_orders, events)
          {p, SemanticJira.frontier_from_events(work_orders, events, evidence)}
      end

    with {:ok, candidate} <- eligible(front, identity),
         {:ok, raw} <- find(projected, identity),
         {:ok, admitted} <- refuse(SemanticJira.admit_work_order(raw)),
         :ok <- same_snapshot(admitted, candidate),
         {:ok, definition} <- refuse(SemanticJira.definition_digest(raw)),
         {:ok, package} <- refuse(SemanticJira.execution_package(raw, attrs)) do
      attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

      {:ok,
       %{
         "schema" => @schema,
         "work_order_id" => admitted["identity"],
         "subject" => admitted["subject"],
         "repository" => admitted["repository"],
         "base_sha" => admitted["base_sha"],
         "definition_digest" => definition,
         "snapshot_digest" => admitted["work_order_digest"],
         "graph_digest" => attrs["graph_digest"],
         "source_digest" => attrs["source_digest"],
         "provider" => Map.get(attrs, "provider", "zcode"),
         "worker_identity" => attrs["worker_identity"],
         "verifier_identity" => attrs["verifier_identity"],
         "replay_identity" => admitted["replay_identity"],
         "package" => package |> RuntimeShape.to_map() |> json_safe(),
         "authority" => "NONE"
       }}
    else
      {:error, {:refused_descriptor, _}} = e -> e
      {:error, reason} -> {:error, {:refused_descriptor, reason}}
    end
  end

  @doc "The graph-identity values carried through every projection."
  @spec identity(map()) :: map()
  def identity(descriptor), do: Map.take(descriptor, @identity_keys)

  @doc "Render the descriptor as JSON through the pack's `descriptor.json.eex` template."
  @spec render(map()) :: String.t()
  def render(descriptor) when is_map(descriptor) do
    bindings =
      descriptor
      |> Map.take(@render_keys ++ @identity_keys)
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.put(:package_json, Jason.encode!(descriptor["package"]))

    [SemanticA2A.pack_dir(), "templates", "descriptor.json.eex"]
    |> Path.join()
    |> File.read!()
    |> Render.render(bindings)
  end

  @doc """
  A2A task envelope for the descriptor. Refuses when the descriptor's graph
  identity disagrees with the work order it claims to describe.
  """
  @spec to_a2a_task(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def to_a2a_task(descriptor, work_order, opts \\ []) do
    with {:ok, admitted} <- refuse(SemanticJira.admit_work_order(work_order)),
         {:ok, definition} <- refuse(SemanticJira.definition_digest(work_order)),
         :ok <-
           same(descriptor, %{
             "definition_digest" => definition,
             "snapshot_digest" => admitted["work_order_digest"],
             "base_sha" => admitted["base_sha"]
           }) do
      SemanticA2A.task_from_work_order(
        work_order,
        Keyword.merge(opts,
          graph_digest: descriptor["graph_digest"],
          package: descriptor,
          identity: identity(descriptor)
        )
      )
    else
      {:error, {:refused_descriptor, _}} = e -> e
      {:error, reason} -> {:error, {:refused_descriptor, reason}}
    end
  end

  # -- internals -------------------------------------------------------------

  defp eligible(front, identity) do
    case Enum.find(front.eligible, &(&1["identity"] == identity)) do
      nil ->
        reason =
          case Enum.find(front.blocked, &(&1["identity"] == identity)) do
            nil -> :not_found
            blocked -> {:not_on_frontier, blocked["reason"]}
          end

        {:error, {:refused_descriptor, reason}}

      candidate ->
        {:ok, candidate}
    end
  end

  defp find(work_orders, identity) do
    case Enum.find(work_orders, &(Map.get(&1, "identity") == identity)) do
      nil -> {:error, {:refused_descriptor, :not_found}}
      wo -> {:ok, wo}
    end
  end

  defp same_snapshot(%{"work_order_digest" => d}, %{"work_order_digest" => d}), do: :ok
  defp same_snapshot(_, _), do: {:error, {:refused_descriptor, :snapshot_drift}}

  defp same(descriptor, expected) do
    case Enum.find(expected, fn {k, v} -> descriptor[k] != v end) do
      nil -> :ok
      {k, _} -> {:error, {:refused_descriptor, {:identity_mismatch, k}}}
    end
  end

  defp refuse({:error, {:refused_work_order, reason}}),
    do: {:error, {:refused_descriptor, {:unadmitted, reason}}}

  defp refuse(other), do: other

  defp json_safe(value), do: value |> Jason.encode!() |> Jason.decode!()
end
