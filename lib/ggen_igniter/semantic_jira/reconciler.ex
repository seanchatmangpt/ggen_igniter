defmodule  GgenIgniter.SemanticJira.Reconciler  do
  @moduledoc """
  Verified receipt -> lawful canonical-state transition.

  `reconcile/4` consumes a receipt map (`definition_digest`, `snapshot_digest`,
  `target`, `candidate_sha`, `evidence`) and the current WorkOrder:

  1. `definition_digest` must equal `SemanticJira.definition_digest/1` of the
     WorkOrder, else `{:error, {:refused, :definition_mismatch}}`.
  2. `snapshot_digest` must be a well-formed digest. It may be stale (standing
     moved since the receipt was made): a stale snapshot with a matching
     definition is admissible, so sibling transitions are not invalidated.
  3. `candidate_sha` must equal the WorkOrder's when the latter is set.
  4. `SemanticJira.promote/3` is the pure admission function (exact subject,
     courts, evidence class/ceiling, falsifiers, replay identity). Dependency
     evidence comes from the log projection, never from the receipt.
  5. On admit an event is appended to the `TransitionLog`; replaying the same
     receipt is idempotent (`:already_recorded`).

  The ledger is read through `TransitionLog.fetch/1`, so a tampered or
  undecodable ledger is `{:error, {:refused, {:ledger_refused, reason}}}`
  before any admission; the ledger path may be a directory or an ndjson file
  (`TransitionLog.kind/1`).

  Authority stays NONE; this module does not perform DO.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.TransitionLog

  @spec reconcile(map(), map(), Path.t(), keyword()) ::
          {:ok, map(), :appended | :already_recorded} | {:error, {:refused, term()}}
  def reconcile(work_order, receipt, dir, _opts \\ []) do
    receipt = stringify(receipt)

    with {:ok, events} <- refuse(TransitionLog.fetch(dir)),
         {:ok, def_digest} <- refuse(SemanticJira.definition_digest(work_order)),
         :ok <- check(receipt["definition_digest"] == def_digest, :definition_mismatch),
         :ok <- check(digest?(receipt["snapshot_digest"]), :invalid_snapshot_digest),
         nil <- recorded(events, receipt),
         {:ok, admitted} <- refuse(SemanticJira.admit_work_order(work_order)),
         :ok <-
           check(
             is_nil(admitted["candidate_sha"]) or
               receipt["candidate_sha"] == admitted["candidate_sha"],
             :candidate_sha_mismatch
           ),
         {projected, logged} = SemanticJira.project([admitted], events),
         [current] = projected,
         evidence =
           receipt["evidence"]
           |> Kernel.||(%{})
           |> stringify()
           |> Map.put("work_order_digest", admitted["work_order_digest"])
           |> Map.put("dependency_evidence", logged),
         {:ok, intent} <-
           refuse(SemanticJira.promote(admitted, receipt["target"], evidence)) do
      receipt_digest = SemanticJira.digest(receipt)

      event = %{
        "kind" => "standing_transition_event",
        "identity" => admitted["identity"],
        "definition_digest" => def_digest,
        "snapshot_digest" => receipt["snapshot_digest"],
        "from" => current["standing"],
        "to" => receipt["target"],
        "receipt_digest" => receipt_digest,
        "transition_digest" => intent["transition_digest"],
        "authority" => "NONE"
      }

      refuse(TransitionLog.append(dir, event))
    else
      {:already, event} -> {:ok, event, :already_recorded}
      other -> other
    end
  end

  # Replay of a receipt already in the log is idempotent (its `from` was the
  # standing at first admission, so the event digest is not re-derivable).
  defp recorded(events, receipt) do
    digest = SemanticJira.digest(receipt)

    case Enum.find(events, &(&1["receipt_digest"] == digest)) do
      nil -> nil
      event -> {:already, event}
    end
  end

  defp refuse({:ok, v}), do: {:ok, v}
  defp refuse({:ok, _, _} = appended), do: appended
  defp refuse({:error, reason}), do: {:error, {:refused, reason}}
  defp check(true, _), do: :ok
  defp check(_, reason), do: {:error, {:refused, reason}}

  defp digest?(v), do: is_binary(v) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, v)

  defp stringify(v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, x} -> {to_string(k), stringify(x)} end)

  defp stringify(v) when is_list(v), do: Enum.map(v, &stringify/1)
  defp stringify(v), do: v

  # ── Log-projection wrappers (restored union, v26.9.22 WO-03) ─────────────
  # Task-facing helpers over the canonical kernel's event projection. The
  # mix semantic_jira.* tasks (and Xaas.Ultracode.SemanticCrown behind them)
  # consume these instead of touching SemanticJira internals.

  @genesis "sha256:" <> String.duplicate("0", 64)

  @doc "Projects the log over the work orders: `{:ok, projected, evidence}`."
  @spec project([map()], [map()]) :: {:ok, [map()], map()}
  def project(work_orders, events) do
    {projected, evidence} = SemanticJira.project(work_orders, events)
    {:ok, projected, evidence}
  end

  @doc """
  Frontier over the projection: UNKNOWN work whose typed dependencies are
  satisfied by *ledger* evidence. Settled work (e.g. ALIVE) is reported by
  the kernel as blocked with `standing=<value>`, never eligible.
  """
  @spec frontier([map()], [map()]) ::
          {:ok, %{eligible: [map()], blocked: [map()]}} | {:error, term()}
  def frontier(work_orders, events) do
    {:ok, SemanticJira.frontier_from_events(work_orders, events)}
  end

  @doc "Chain tail: the last event's digest, or the genesis digest for an empty log."
  @spec tail_digest([map()]) :: String.t()
  def tail_digest([]), do: @genesis

  def tail_digest(events),
    do: events |> List.last() |> stringify() |> Map.fetch!("event_digest")
end
