defmodule GgenIgniter.SemanticA2A do
  @moduledoc """
  Pure-Elixir A2A (agent-to-agent) projection of a Semantic Jira work order.

  Depends on nothing Ash- or A2A-specific: the Ash/`ash_a2a` surface is
  MANUFACTURED from the ontology (`a2a_manufacture.ex.eex`), and this module
  only derives the *task view* of a work order from the same ontology.

  ## What is derived, and from what

    * The standing -> A2A task-state map is read from the ontology through the
      pack's SPARQL gate `061_a2a_state_map.rq` (`state_map/1`). There is no
      hardcoded `case` over standings here.
    * `task_from_work_order/2` builds a task whose `taskId` is the work
      order's replay identity URN, `contextId` the graph digest, and whose
      input is the `SemanticWorkOrder.execution_package/3` (schema
      `execution-package/v1`) as a data part. `baseSha`, `graphDigest` and the
      package schema travel in `metadata`.
    * `receipt/3` is a sha256 digest over canonical JSON with a `prev_digest`
      chain, so a replay of the same work order yields an identical digest.

  ## Boundaries (falsifiers)

    * Standing is never inferred from task state: no function here takes a
      task state as input.
    * A task reaches `completed` only through the ontology's receipt-bound
      ALIVE mapping; `admit_completion/3` refuses otherwise.
    * `UNSUPPORTED` and `REFUSED` both map to `rejected` but keep distinct
      reason codes.
    * Authority of every projection here is `NONE`.
  """

  alias GgenIgniter.{Digest, Ontology, Query, SemanticWorkOrder}
  alias GgenIgniter.SemanticJira.Authority

  @pack_dir "semantic-jira-pack"
  @receipt_schema "semantic-jira/a2a-receipt/v1"

  @type state_row :: %{
          standing: String.t(),
          receipted: String.t(),
          state: String.t(),
          reason_code: String.t()
        }

  @doc "Absolute path of the semantic-jira pack directory."
  @spec pack_dir() :: String.t()
  def pack_dir, do: Path.join([priv_ggen_dir(), @pack_dir])

  @doc "Absolute path of the pack's canonical ontology."
  @spec ontology_path() :: String.t()
  def ontology_path, do: Path.join(pack_dir(), "ontology.ttl")

  @doc "Load the standing -> task-state map from the ontology through SPARQL."
  @spec state_map(RDF.Graph.t() | String.t()) :: [state_row()]
  def state_map(graph \\ ontology_path()) do
    graph
    |> gate_rows("061_a2a_state_map.rq")
    |> Enum.map(fn row ->
      %{
        standing: row["standing"],
        receipted: row["receipted"],
        state: row["state"],
        reason_code: row["reason_code"]
      }
    end)
  end

  @doc """
  The wire spelling ash_a2a 26.9.17 serves for a task state, e.g.
  `"input-required"` -> `"TASK_STATE_INPUT_REQUIRED"`. The ontology keeps the
  A2A v0.3 lifecycle names; this is the only place the two spellings meet.
  """
  @spec wire_state(String.t()) :: String.t()
  def wire_state(state) when is_binary(state),
    do: "TASK_STATE_" <> (state |> String.replace("-", "_") |> String.upcase())

  @doc "Exposed skills (gate 060): actions admitted as A2A skills, minus forbidden capabilities."
  @spec skills(RDF.Graph.t() | String.t()) :: [map()]
  def skills(graph \\ ontology_path()), do: gate_rows(graph, "060_a2a_skills.rq")

  @doc "Typed refusals (gate 062): actions deliberately not exposed as skills."
  @spec refusals(RDF.Graph.t() | String.t()) :: [map()]
  def refusals(graph \\ ontology_path()), do: gate_rows(graph, "062_a2a_refusals.rq")

  @doc """
  Derive the A2A task state for a standing.

  `receipts` is the list of receipts (as produced by `receipt/3`) bound to the
  subject; ALIVE is *receipted* only when at least one carries a valid digest.
  `REFUSED(reason)` is normalised to `REFUSED`. Returns
  `{:ok, %{state:, reason_code:}}` or `{:error, {:unmapped_standing, standing}}`.
  """
  @spec state_for(String.t(), [map()], [state_row()]) ::
          {:ok, %{state: String.t(), reason_code: String.t()}}
          | {:error, {:unmapped_standing, String.t()}}
  def state_for(standing, receipts, map \\ state_map())
      when is_binary(standing) and is_list(receipts) and is_list(map) do
    key = normalise_standing(standing)
    receipted = if Enum.any?(receipts, &valid_receipt?/1), do: "true", else: "false"

    rows = Enum.filter(map, &(&1.standing == key))

    match =
      Enum.find(rows, &(&1.receipted == receipted)) ||
        Enum.find(rows, &(&1.receipted == "any"))

    case match do
      nil -> {:error, {:unmapped_standing, standing}}
      row -> {:ok, %{state: row.state, reason_code: row.reason_code}}
    end
  end

  @doc """
  Build the A2A task view of an admitted work order.

  Options: `:graph_digest` (required), `:package` (an
  `execution-package/v1` map), `:receipts` (default `[]`), `:state_map`
  (default: loaded from the ontology), `:identity` (descriptor graph identity;
  `definition_digest` and `snapshot_digest` land in metadata), `:authority`
  (origin-authority index; the work order's `origin_authority` must resolve in
  the pinned index, `Authority.require_origin/2`, G1).
  """
  @spec task_from_work_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def task_from_work_order(work_order, opts) when is_map(work_order) and is_list(opts) do
    graph_digest = Keyword.fetch!(opts, :graph_digest)
    receipts = Keyword.get(opts, :receipts, [])
    map = Keyword.get_lazy(opts, :state_map, &state_map/0)
    package = Keyword.get(opts, :package)
    identity = opts |> Keyword.get(:identity, %{}) |> stringify()

    with {:ok, replay} <- fetch(work_order, "replay_identity"),
         {:ok, standing} <- fetch(work_order, "standing"),
         {:ok, base_sha} <- fetch(work_order, "base_sha"),
         {:ok, _origin_digest} <- Authority.require_origin(work_order, opts),
         {:ok, %{state: state, reason_code: reason}} <- state_for(standing, receipts, map) do
      {:ok,
       %{
         "taskId" => "urn:" <> replay,
         "contextId" => graph_digest,
         "status" => %{"state" => state, "reasonCode" => reason},
         "input" => input_parts(package),
         "metadata" =>
           %{
             "baseSha" => base_sha,
             "graphDigest" => graph_digest,
             "schema" => package_schema(package),
             "authority" => "NONE"
           }
           |> put_if("definitionDigest", identity["definition_digest"])
           |> put_if("snapshotDigest", identity["snapshot_digest"])
       }}
    end
  end

  @doc """
  Admit a request to mark a task `completed`.

  Refuses (typed) unless the standing maps to `completed`, which the ontology
  only allows for ALIVE with a valid receipt.
  """
  @spec admit_completion(String.t(), [map()], [state_row()]) ::
          :ok | {:error, {:refused, atom()}}
  def admit_completion(standing, receipts, map \\ state_map()) do
    case state_for(standing, receipts, map) do
      {:ok, %{state: "completed"}} -> :ok
      _ -> {:error, {:refused, :completed_requires_alive_with_receipt}}
    end
  end

  @doc "Chained sha256 receipt over canonical JSON of `subject`."
  @spec receipt(map(), String.t() | nil, keyword()) :: map()
  def receipt(subject, prev_digest \\ nil, opts \\ []) when is_map(subject) do
    body = %{
      "schema" => @receipt_schema,
      "class" => Keyword.get(opts, :class, "verification"),
      "subject" => stringify(subject),
      "prev_digest" => prev_digest
    }

    Map.put(body, "digest", digest_of(body))
  end

  @doc "True when the receipt's digest matches its canonical body."
  @spec valid_receipt?(term()) :: boolean()
  def valid_receipt?(%{"digest" => digest} = receipt) when is_binary(digest) do
    digest_of(Map.delete(receipt, "digest")) == digest
  end

  def valid_receipt?(_), do: false

  @doc "Replay a receipt chain: every digest valid and every `prev_digest` links to its predecessor."
  @spec verify_chain([map()]) :: :ok | {:error, {:broken_chain, non_neg_integer()}}
  def verify_chain(chain) when is_list(chain) do
    chain
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, nil}, fn {receipt, index}, {:ok, prev} ->
      if valid_receipt?(receipt) and receipt["prev_digest"] == prev do
        {:cont, {:ok, receipt["digest"]}}
      else
        {:halt, {:error, {:broken_chain, index}}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc "Execution package for a task input (delegates to `SemanticWorkOrder`)."
  @spec execution_package(String.t(), [map()], keyword()) :: map()
  def execution_package(base_dir, artifacts, opts \\ []),
    do: SemanticWorkOrder.execution_package(base_dir, artifacts, opts)

  # -- internals -------------------------------------------------------------

  defp gate_rows(%{__struct__: _} = graph, gate) do
    Query.run(graph, File.read!(Path.join([pack_dir(), "gates", gate])))
  end

  defp gate_rows(path, gate) when is_binary(path), do: path |> Ontology.load!() |> gate_rows(gate)

  defp normalise_standing("REFUSED(" <> _), do: "REFUSED"
  defp normalise_standing(standing), do: standing

  defp fetch(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_field, key}}
    end
  end

  # Descriptor graph identity travels verbatim in task metadata.
  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp input_parts(nil), do: []
  defp input_parts(package), do: [%{"kind" => "data", "data" => stringify(package)}]

  defp package_schema(nil), do: nil
  defp package_schema(package), do: Map.get(package, :schema) || Map.get(package, "schema")

  defp digest_of(body), do: body |> canonical() |> Jason.encode!() |> Digest.sha256()

  # Canonical form: maps become key-sorted ordered objects, recursively.
  defp canonical(%{} = map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), canonical(v)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(atom) when is_atom(atom) and atom not in [nil, true, false], do: to_string(atom)
  defp canonical(other), do: other

  defp stringify(%{} = map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp priv_ggen_dir, do: Path.join(:code.priv_dir(:ggen_igniter) |> to_string(), "ggen")
end
