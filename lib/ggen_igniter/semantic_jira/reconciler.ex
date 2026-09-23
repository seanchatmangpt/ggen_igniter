defmodule GgenIgniter.SemanticJira.Reconciler do
  @moduledoc """
  Verified receipt -> lawful canonical-state transition.

  `reconcile/4` consumes a receipt map (`definition_digest`, `snapshot_digest`,
  `target`, `candidate_sha`, `evidence`) and the current WorkOrder:

  1. `definition_digest` must equal `SemanticJira.definition_digest/1` of the
     WorkOrder, else `{:error, {:refused, :definition_mismatch}}`.
  2. `snapshot_digest` must be a well-formed digest. It may be stale (standing
     moved since the receipt was made): a stale snapshot with a matching
     definition is admissible, so sibling transitions are not invalidated.
  3. `candidate_sha` must be absent or an exact 40-hex commit SHA (it is the
     attested subject SHA), and must equal the WorkOrder's when the latter is set.
  4. `SemanticJira.promote/3` is the pure admission function (exact subject,
     courts, evidence class/ceiling, falsifiers, replay identity). Dependency
     evidence comes from the log projection, never from the receipt.
  5. On admit an event is appended to the `TransitionLog`; replaying the same
     receipt is idempotent (`:already_recorded`).
  6. Every admitted transition emits an in-toto Statement v1
     (`GgenIgniter.SemanticJira.Attestation`, predicateType
     `https://chatmangpt.com/sj/admission/v1`) next to its event file; an
     `:already_recorded` replay re-emits it only if it is missing (crash
     window between append and emission, or a log written before C11) and
     only if the log prefix before the event still re-derives it.

  Steps 1-4 are the pure `decide/3` (log in, event out, no I/O), which is also
  what `Attestation.verify/3` replays offline over the log prefix before the
  event. Authority stays NONE; this module does not perform DO.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Attestation, TransitionLog}

  @spec reconcile(map(), map(), Path.t(), keyword()) ::
          {:ok, map(), :appended | :already_recorded} | {:error, {:refused, term()}}
  def reconcile(work_order, receipt, dir, _opts \\ []) do
    receipt = stringify(receipt)
    events = TransitionLog.read(dir)

    with {:ok, def_digest} <- refuse(SemanticJira.definition_digest(work_order)),
         :ok <- check(receipt["definition_digest"] == def_digest, :definition_mismatch),
         :ok <- check(digest?(receipt["snapshot_digest"]), :invalid_snapshot_digest),
         nil <- recorded(events, receipt),
         {:ok, decision} <- decide(work_order, receipt, events),
         {:ok, event, status} <- TransitionLog.append(dir, decision["event"]) do
      :ok = Attestation.emit(dir, event, decision)
      {:ok, event, status}
    else
      {:already, event} ->
        # Best-effort backfill: a prefix that no longer re-derives the event
        # writes nothing, and Attestation.verify/3 then has no Statement to admit.
        _ = Attestation.ensure(dir, event, work_order, receipt, events)
        {:ok, event, :already_recorded}

      other ->
        other
    end
  end

  @doc """
  Pure admission decision over `events` (the transition log as read): returns
  the admitted WorkOrder, the stringified receipt, the promotion intent and the
  `standing_transition_event` (without `seq`/`event_digest`) that
  `reconcile/4` appends. No I/O; same inputs give the same decision.
  """
  @spec decide(map(), map(), [map()]) :: {:ok, map()} | {:error, {:refused, term()}}
  def decide(work_order, receipt, events) do
    receipt = stringify(receipt)

    with {:ok, def_digest} <- refuse(SemanticJira.definition_digest(work_order)),
         :ok <- check(receipt["definition_digest"] == def_digest, :definition_mismatch),
         :ok <- check(digest?(receipt["snapshot_digest"]), :invalid_snapshot_digest),
         {:ok, admitted} <- refuse(SemanticJira.admit_work_order(work_order)),
         :ok <- check(sha?(receipt["candidate_sha"]), :invalid_candidate_sha),
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

      {:ok,
       %{
         "admitted" => admitted,
         "definition_digest" => def_digest,
         "receipt" => receipt,
         "intent" => intent,
         "event" => event
       }}
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
  defp refuse({:error, reason}), do: {:error, {:refused, reason}}
  defp check(true, _), do: :ok
  defp check(_, reason), do: {:error, {:refused, reason}}

  defp digest?(v), do: is_binary(v) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, v)
  defp sha?(nil), do: true
  defp sha?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{40}\z/, v)

  defp stringify(v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, x} -> {to_string(k), stringify(x)} end)

  defp stringify(v) when is_list(v), do: Enum.map(v, &stringify/1)
  defp stringify(v), do: v
end
