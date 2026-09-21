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
  3. `candidate_sha` must equal the WorkOrder's when the latter is set.
  4. `SemanticJira.promote/3` is the pure admission function (exact subject,
     courts, evidence class/ceiling, falsifiers, replay identity). Dependency
     evidence comes from the log projection, never from the receipt.
  5. On admit an event is appended to the `TransitionLog`; replaying the same
     receipt is idempotent (`:already_recorded`).

  ## Emitted receipts

  A receipt produced by `GgenIgniter.SemanticJira.ReceiptEmitter` (`"kind"` is
  `"brce_receipt"`, or any receipt carrying a `"receipt_digest"`) is verified
  BEFORE admission and before idempotent replay is consulted:

    * `{:refused, {:receipt_invalid, reason}}` -- seal does not match the body
      (`:seal_mismatch`), a derived field (per-step `passed`, `success`,
      `exit_code`, `evidence`) does not re-derive from the consequence, or the
      requirements do not match the WorkOrder (`ReceiptEmitter.verify/2`).
    * `{:refused, {:non_success_receipt, exit_code}}` -- a valid receipt of a run
      that did not succeed never transitions standing.

  Options (all default off; hand-built receipts keep working unchanged):

    * `require_sealed: true` -- refuse any receipt that is not an emitted,
      verified one (`{:refused, :unsealed_receipt}`): caller-supplied receipts
      are eliminated for this call.
    * `replay_plan: plan` -- additionally re-run the caller-TRUSTED `plan` (its
      digest must equal the receipt's `replay.plan_digest`) and refuse with
      `{:refused, {:replay_refused, reason}}` when the fresh consequence differs.
      The receipt's own embedded argv is never executed.

  Authority stays NONE; this module does not perform DO.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{ReceiptEmitter, TransitionLog}

  @spec reconcile(map(), map(), Path.t(), keyword()) ::
          {:ok, map(), :appended | :already_recorded} | {:error, {:refused, term()}}
  def reconcile(work_order, receipt, dir, opts \\ []) do
    receipt = stringify(receipt)
    events = TransitionLog.read(dir)

    with {:ok, def_digest} <- refuse(SemanticJira.definition_digest(work_order)),
         :ok <- check(receipt["definition_digest"] == def_digest, :definition_mismatch),
         :ok <- check(digest?(receipt["snapshot_digest"]), :invalid_snapshot_digest),
         :ok <- verify_emitted(receipt, work_order, opts),
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

      TransitionLog.append(dir, event)
    else
      {:already, event} -> {:ok, event, :already_recorded}
      other -> other
    end
  end

  # Emitted (or self-declared sealed) receipts are verified; everything else is
  # a caller-supplied map, admitted only when `require_sealed` is off.
  defp verify_emitted(receipt, work_order, opts) do
    emitted? =
      receipt["kind"] == ReceiptEmitter.kind() or Map.has_key?(receipt, "receipt_digest")

    cond do
      emitted? ->
        with :ok <- wrap(ReceiptEmitter.verify(receipt, work_order), :receipt_invalid),
             :ok <- ReceiptEmitter.check_success(receipt) |> refuse_tuple() do
          verify_replay(receipt, work_order, opts)
        end

      Keyword.get(opts, :require_sealed, false) ->
        {:error, {:refused, :unsealed_receipt}}

      true ->
        :ok
    end
  end

  defp verify_replay(receipt, work_order, opts) do
    case Keyword.fetch(opts, :replay_plan) do
      :error ->
        :ok

      {:ok, plan} ->
        case ReceiptEmitter.replay(receipt, plan: plan, work_order: work_order) do
          {:ok, _replay_receipt} -> :ok
          {:error, {:replay_refused, reason}} -> {:error, {:refused, {:replay_refused, reason}}}
          {:error, reason} -> {:error, {:refused, {:replay_refused, reason}}}
        end
    end
  end

  defp wrap(:ok, _), do: :ok
  defp wrap({:error, reason}, tag), do: {:error, {:refused, {tag, reason}}}

  defp refuse_tuple(:ok), do: :ok
  defp refuse_tuple({:error, reason}), do: {:error, {:refused, reason}}

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

  defp stringify(v) when is_map(v) and not is_struct(v),
    do: Map.new(v, fn {k, x} -> {to_string(k), stringify(x)} end)

  defp stringify(v) when is_list(v), do: Enum.map(v, &stringify/1)
  defp stringify(v), do: v
end
