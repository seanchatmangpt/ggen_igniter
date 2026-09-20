defmodule GgenIgniter.SemanticJira.Reconciler do
  @moduledoc """
  Receipts are the clock: a verified receipt becomes a lawful, append-only
  standing transition, and the resulting projection feeds the next frontier.

  A WorkOrder's `standing` is never mutated. The WorkOrder definition is
  immutable (`definition_digest` is stable across every transition); its
  current standing is a *projection* of a hash-chained event ledger:

      WorkOrder definitions + ordered events  -->  project/2  -->  current state

  This module is pure. It performs no I/O and grants no authority
  (`"authority" => "NONE"` on every event); `GgenIgniter.SemanticJira.promote/3`
  remains the only admission function and is called unchanged on the projected
  WorkOrder. Persisting an event is `GgenIgniter.SemanticJira.Ledger`'s job, and
  any consequential write remains BRCE-owned.

  ## Concurrency

  Each receipt binds the stable `definition_digest` plus the snapshot digest the
  worker observed. Because the definition never changes, a sibling worker's
  completed transition does not invalidate the others' receipts: a receipt is
  accepted while its `source_snapshot_digest` is any snapshot in that WorkOrder's
  own history. `ALIVE` is terminal; replaying the same `receipt_digest` is
  idempotent, a different receipt for a settled WorkOrder is `:stale_transition`.

  ## What the chain does and does not prove

  The chain (contiguous `seq`, `prev_event_digest`, recomputed `event_digest`)
  detects any edit, reorder, duplication or removal of a non-final event, and
  every event's `from`, definition and snapshot bindings are re-verified against
  the WorkOrder definitions. It is not a signature: truncating the tail yields a
  valid shorter ledger, and a party able to rewrite the whole ledger consistently
  can forge one.
  """

  alias GgenIgniter.SemanticJira

  @genesis "sha256:" <> String.duplicate("0", 64)
  @settleable ~w(UNKNOWN PARTIAL_ALIVE BUILD_BROKEN BLOCKED)
  @sha ~r/\A[0-9a-f]{40}\z/
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @evidence_keys ~w(court_results evidence_types acceptance_results falsifier_results receipt_classes evidence_ceiling observed_execution inherited_standing replay_passed replay_identity authority_receipt)

  @type events :: [map()]

  @doc "The `prev_event_digest` of the first event."
  @spec genesis_digest() :: String.t()
  def genesis_digest, do: @genesis

  @doc "Digest a new event must chain to: the last `event_digest`, or genesis."
  @spec tail_digest(events()) :: String.t()
  def tail_digest([]), do: @genesis
  def tail_digest(events), do: events |> List.last() |> stringify() |> Map.fetch!("event_digest")

  @doc """
  Latest observed `%{"standing", "receipt_digest"}` per identity, in the shape
  `GgenIgniter.SemanticJira.frontier/2` expects. Assumes `events` was verified
  by `project/2`; only identities with at least one transition appear.
  """
  @spec evidence_by_id(events()) :: %{String.t() => map()}
  def evidence_by_id(events) do
    Enum.reduce(events, %{}, fn raw, acc ->
      event = stringify(raw)

      Map.put(acc, event["identity"], %{
        "standing" => event["to"],
        "receipt_digest" => event["receipt_digest"]
      })
    end)
  end

  @doc """
  Verifies the ledger against the WorkOrder definitions and returns the current
  projection: `{:ok, projected_work_orders, evidence_by_id}` (input order), or
  `{:error, {:ledger_invalid, reason}}` / `{:error, {:work_orders_invalid, reason}}`.
  """
  @spec project([map()], events()) ::
          {:ok, [map()], %{String.t() => map()}} | {:error, term()}
  def project(work_orders, events) do
    with {:ok, state} <- fold(work_orders, events) do
      {:ok, projected(state), state.evidence}
    end
  end

  @doc """
  Frontier over the projection: UNKNOWN work whose typed dependencies are
  satisfied by *ledger* evidence. Settled work (e.g. ALIVE) is reported by the
  kernel as blocked with `standing=<value>`, never eligible.
  """
  @spec frontier([map()], events()) ::
          {:ok, %{eligible: [map()], blocked: [map()]}} | {:error, term()}
  def frontier(work_orders, events) do
    with {:ok, projected, evidence} <- project(work_orders, events) do
      {:ok, SemanticJira.frontier(projected, evidence)}
    end
  end

  @doc """
  Turns one receipt into the next ledger event, or refuses with a typed reason.

  Returns `{:ok, event}` (not yet persisted), `{:ok, :already_applied, event}`
  when the same `receipt_digest` was already applied to that WorkOrder, or
  `{:error, {:reconcile_refused, reason}}`.

  Receipt fields: `identity`, `definition_digest`, `source_snapshot_digest`,
  `repository`, `base_sha`, `subject`, `candidate_sha`, `receipt_digest`,
  optional `target` (default `"ALIVE"`), plus the promotion evidence
  (`court_results`, `evidence_types`, `acceptance_results`, `falsifier_results`,
  `receipt_classes`, `evidence_ceiling`, `observed_execution`,
  `inherited_standing`, ...). Dependency evidence is taken from the ledger,
  never from the receipt.
  """
  @spec reconcile([map()], events(), map()) ::
          {:ok, map()} | {:ok, :already_applied, map()} | {:error, term()}
  def reconcile(work_orders, events, receipt) when is_map(receipt) do
    receipt = stringify(receipt)

    with {:ok, state} <- fold(work_orders, events),
         {:ok, id, work_order} <- receipt_subject(state, receipt),
         :ok <- bind(state, id, work_order, receipt) do
      settle(state, id, work_order, receipt)
    end
  end

  def reconcile(_, _, _), do: refuse(:receipt_not_a_map)

  defp settle(state, id, work_order, receipt) do
    receipt_digest = receipt["receipt_digest"]
    standing = state.standing[id]

    cond do
      receipt_digest in state.receipts[id] ->
        {:ok, :already_applied, applied_event(state, id, receipt_digest)}

      standing not in @settleable ->
        refuse(:stale_transition)

      true ->
        promote(state, id, work_order, receipt)
    end
  end

  defp promote(state, id, work_order, receipt) do
    target = Map.get(receipt, "target", "ALIVE")

    with :ok <- valid_target(target),
         {:ok, projected} <- snapshot(work_order, state.standing[id], state.candidate[id]) do
      evidence =
        receipt
        |> Map.take(@evidence_keys)
        |> Map.merge(%{
          "work_order_digest" => projected["work_order_digest"],
          "subject" => receipt["subject"],
          "repository" => receipt["repository"],
          "base_sha" => receipt["base_sha"],
          "dependency_evidence" => state.evidence
        })

      case SemanticJira.promote(projected, target, evidence) do
        {:ok, transition} ->
          {:ok,
           build_event(state, id, work_order, projected, receipt, target, evidence, transition)}

        {:error, {:promotion_refused, failed}} ->
          refuse({:promotion_refused, failed})

        {:error, other} ->
          refuse(other)
      end
    end
  end

  defp build_event(state, id, work_order, projected, receipt, target, evidence, transition) do
    event = %{
      "kind" => "standing_transition",
      "seq" => state.seq + 1,
      "identity" => id,
      "definition_digest" => work_order["definition_digest"],
      "source_snapshot_digest" => receipt["source_snapshot_digest"],
      "projected_snapshot_digest" => projected["work_order_digest"],
      "from" => state.standing[id],
      "to" => target,
      "candidate_sha" => receipt["candidate_sha"],
      "transition_digest" => transition["transition_digest"],
      "receipt_digest" => receipt["receipt_digest"],
      "evidence_digest" => SemanticJira.digest_exact(evidence),
      "prev_event_digest" => state.prev,
      "authority" => "NONE"
    }

    Map.put(event, "event_digest", SemanticJira.digest_exact(event))
  end

  defp applied_event(state, id, receipt_digest) do
    Enum.find(state.events, &(&1["identity"] == id and &1["receipt_digest"] == receipt_digest))
  end

  defp receipt_subject(state, receipt) do
    id = receipt["identity"]

    cond do
      not is_binary(id) -> refuse(:receipt_identity_missing)
      not Map.has_key?(state.work_orders, id) -> refuse({:unknown_work_order, id})
      true -> {:ok, id, state.work_orders[id]}
    end
  end

  defp bind(state, id, work_order, receipt) do
    target = Map.get(receipt, "target", "ALIVE")

    [
      {receipt["definition_digest"] == work_order["definition_digest"], :definition_mismatch},
      {receipt["repository"] == work_order["repository"], :repository_mismatch},
      {receipt["base_sha"] == work_order["base_sha"], :base_sha_mismatch},
      {receipt["subject"] == work_order["subject"], :subject_mismatch},
      {digest?(receipt["receipt_digest"]), :invalid_receipt_digest},
      {digest?(receipt["source_snapshot_digest"]), :invalid_source_snapshot},
      {receipt["source_snapshot_digest"] in state.snapshots[id], :unknown_source_snapshot},
      {candidate_ok?(target, receipt["candidate_sha"]), :invalid_candidate_sha}
    ]
    |> Enum.find_value(:ok, fn
      {true, _} -> nil
      {_, reason} -> refuse(reason)
    end)
  end

  defp candidate_ok?("ALIVE", sha), do: sha?(sha)
  defp candidate_ok?(_, nil), do: true
  defp candidate_ok?(_, sha), do: sha?(sha)

  defp valid_target(target) do
    if target in SemanticJira.standings() and target != "UNKNOWN",
      do: :ok,
      else: refuse({:invalid_target, target})
  end

  # --- ledger verification ---------------------------------------------------

  defp fold(work_orders, events) do
    with {:ok, admitted} <- admit_all(work_orders) do
      state = %{
        order: Enum.map(admitted, & &1["identity"]),
        work_orders: Map.new(admitted, &{&1["identity"], &1}),
        standing: Map.new(admitted, &{&1["identity"], &1["standing"]}),
        candidate: Map.new(admitted, &{&1["identity"], &1["candidate_sha"]}),
        snapshots: Map.new(admitted, &{&1["identity"], [&1["work_order_digest"]]}),
        receipts: Map.new(admitted, &{&1["identity"], []}),
        evidence: %{},
        events: [],
        prev: @genesis,
        seq: 0
      }

      Enum.reduce_while(events, {:ok, state}, fn raw, {:ok, acc} ->
        case apply_event(stringify(raw), acc) do
          {:ok, next} -> {:cont, {:ok, next}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp admit_all(work_orders) when is_list(work_orders) do
    work_orders
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn raw, {:ok, acc, seen} ->
      case SemanticJira.admit_work_order(raw) do
        {:ok, wo} ->
          if MapSet.member?(seen, wo["identity"]) do
            {:halt, {:error, {:work_orders_invalid, {:duplicate_identity, wo["identity"]}}}}
          else
            {:cont, {:ok, [wo | acc], MapSet.put(seen, wo["identity"])}}
          end

        {:error, reason} ->
          {:halt, {:error, {:work_orders_invalid, reason}}}
      end
    end)
    |> case do
      {:ok, acc, _} -> {:ok, Enum.reverse(acc)}
      {:error, _} = error -> error
    end
  end

  defp admit_all(_), do: {:error, {:work_orders_invalid, :expected_list}}

  defp apply_event(event, state) do
    seq = state.seq + 1
    id = event["identity"]
    work_order = Map.get(state.work_orders, id)
    current = Map.get(state.standing, id)

    with :ok <- ledger(event["kind"] == "standing_transition", {:bad_kind, seq}),
         :ok <- ledger(event["seq"] == seq, {:bad_seq, seq}),
         :ok <- ledger(event["prev_event_digest"] == state.prev, {:chain_broken, seq}),
         :ok <- ledger(event_digest_ok?(event), {:event_digest_mismatch, seq}),
         :ok <- ledger(event["authority"] == "NONE", {:authority_not_none, seq}),
         :ok <- ledger(work_order != nil, {:unknown_work_order, seq}),
         :ok <-
           ledger(
             event["definition_digest"] == work_order["definition_digest"],
             {:definition_mismatch, seq}
           ),
         :ok <- ledger(event["from"] == current, {:from_mismatch, seq}),
         :ok <- ledger(current in @settleable, {:from_terminal, seq}),
         :ok <-
           ledger(
             event["to"] in SemanticJira.standings() and event["to"] != "UNKNOWN",
             {:invalid_to, seq}
           ),
         :ok <-
           ledger(
             candidate_ok?(event["to"], event["candidate_sha"]),
             {:invalid_candidate_sha, seq}
           ),
         :ok <-
           ledger(
             Enum.all?(
               ~w(source_snapshot_digest projected_snapshot_digest transition_digest receipt_digest evidence_digest),
               &digest?(event[&1])
             ),
             {:malformed_digest, seq}
           ),
         {:ok, before} <- snapshot(work_order, current, state.candidate[id]),
         :ok <-
           ledger(
             event["projected_snapshot_digest"] == before["work_order_digest"],
             {:snapshot_mismatch, seq}
           ),
         {:ok, settled} <- snapshot(work_order, event["to"], event["candidate_sha"]) do
      {:ok,
       %{
         state
         | standing: Map.put(state.standing, id, event["to"]),
           candidate: Map.put(state.candidate, id, event["candidate_sha"]),
           snapshots: Map.update!(state.snapshots, id, &(&1 ++ [settled["work_order_digest"]])),
           receipts: Map.update!(state.receipts, id, &(&1 ++ [event["receipt_digest"]])),
           evidence:
             Map.put(state.evidence, id, %{
               "standing" => event["to"],
               "receipt_digest" => event["receipt_digest"]
             }),
           events: state.events ++ [event],
           prev: event["event_digest"],
           seq: seq
       }}
    end
  end

  defp event_digest_ok?(event) do
    is_binary(event["event_digest"]) and
      SemanticJira.digest_exact(Map.delete(event, "event_digest")) == event["event_digest"]
  end

  defp ledger(true, _), do: :ok
  defp ledger(_, reason), do: {:error, {:ledger_invalid, reason}}

  defp snapshot(work_order, standing, candidate_sha) do
    work_order
    |> Map.put("standing", standing)
    |> Map.put("candidate_sha", candidate_sha)
    |> SemanticJira.admit_work_order()
    |> case do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:ledger_invalid, {:snapshot_refused, reason}}}
    end
  end

  defp projected(state) do
    Enum.map(state.order, fn id ->
      {:ok, snapshot} = snapshot(state.work_orders[id], state.standing[id], state.candidate[id])
      snapshot
    end)
  end

  defp refuse(reason), do: {:error, {:reconcile_refused, reason}}
  defp digest?(value), do: is_binary(value) and Regex.match?(@digest, value)
  defp sha?(value), do: is_binary(value) and Regex.match?(@sha, value)

  defp stringify(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), stringify(item)} end)

  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)
  defp stringify(value), do: value
end
