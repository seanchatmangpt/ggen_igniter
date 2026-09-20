defmodule GgenIgniter.SemanticJira.Descriptor do
  @moduledoc """
  The two edges between the Semantic Jira frontier and the XaaS/Ultracode
  fabric, both pure and both authority-free:

    * `build/4` projects ONE lawful frontier candidate into the execution
      descriptor `Xaas.Ultracode.SemanticWork.admit/1` consumes;
    * `receipt_from_xaas/2` turns the sealed XaaS receipt of that execution
      back into the receipt `GgenIgniter.SemanticJira.Reconciler.reconcile/3`
      consumes.

  Neither function selects work, grants a lease, verifies an outcome or moves
  standing: the frontier and admission stay in the kernel/reconciler, execution
  and verification stay in XaaS.

  ## Descriptor

  `build/4` returns the exact XaaS key set (`work_order_iri`, `checkpoint_iri`,
  `graph_digest`, `repository_identity`, `execution_repo_alias`, `base_sha`,
  `goal`, `provider`, `verifier_suite`, `execution_policy`, `dependencies`)
  plus one extra key, `"bridge"`. `SemanticWork.admit/1` keeps unknown keys and
  `materialize/2` ignores them, so the whole JSON object can be handed to XaaS
  unchanged. XaaS must echo `"bridge"` verbatim in its receipt export; the
  return edge refuses any receipt whose echo differs.

  `bridge` = `identity`, `definition_digest`, `source_snapshot_digest`,
  `ledger_tail`, `repository`, `base_sha`, `subject`, `evidence_ceiling`,
  `replay_identity`, `requires` (`courts`, `acceptance`, `falsifiers`).

  ## XaaS receipt contract (input of `receipt_from_xaas/2`)

      %{"epoch_id", "run_id", "receipt_id",
        "receipt_digest",   # sha256 of the canonical JSON of this map WITHOUT that key
        "outcome",          # "alive" | "partial_alive" | "build_broken" | "blocked"
        "final_head",       # 40-hex candidate sha
        "head_verified",    # boolean
        "fabric_verifier" => %{
          "status" => "pass" | "fail" | "timeout" | "error",
          "steps" => [%{"id", "status"}],
          "court_receipt" => %{               # optional, structured observations only
            "acceptance_results" => %{acceptance => true | false},
            "falsifier_results" => %{falsifier => "survived" | "killed" | true | false},
            "evidence_types" => [...], "receipt_classes" => [...],
            "evidence_ceiling" => "...", "replay_passed" => bool,
            "replay_identity" => "...", "authority_receipt" => %{...}
          }},
        "bridge" => <the descriptor's bridge, verbatim>}

  "Canonical JSON" is `GgenIgniter.SemanticJira.digest_exact/1`: recursively
  key-sorted, compact, UTF-8 JSON, SHA-256, `"sha256:" <> hex`.

  Standing is never inferred from `outcome` alone. Acceptance and falsifier
  results come only from `court_receipt` and only count when the fabric
  verifier passed; a required court passes only when a fabric-verifier step
  with that exact `id` passed. Fabric-only evidence reaches at most the
  `"repository-local"` ceiling.
  """

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.Reconciler

  @iri_prefix "urn:semantic-jira:work-order:"
  @checkpoint_prefix "urn:semantic-jira:checkpoint:"
  @receipt_prefix "urn:semantic-jira:receipt:"
  @sha ~r/\A[0-9a-f]{40}\z/
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @alias_re ~r/\A[A-Za-z0-9_.-]{1,128}\z/
  @suite_re ~r/\A[a-z0-9][a-z0-9_-]{0,63}\z/
  @fabric_ceiling "repository-local"

  @bridge_keys ~w(identity definition_digest source_snapshot_digest ledger_tail repository base_sha subject evidence_ceiling replay_identity requires)
  @outcomes %{
    "alive" => "ALIVE",
    "partial_alive" => "PARTIAL_ALIVE",
    "build_broken" => "BUILD_BROKEN",
    "blocked" => "BLOCKED"
  }

  @doc """
  Builds the XaaS execution descriptor for `identity`.

  Options: `:verifier_suite` (required, a registered XaaS suite name),
  `:execution_repo_alias` (required unless `:aliases` maps the WorkOrder's
  `repository` to one), `:aliases` (`%{"owner/repo" => alias}`), `:iri_prefix`.
  Nothing is invented: a missing or malformed option is a typed refusal.
  """
  @spec build([map()], [map()], String.t(), keyword()) ::
          {:ok, map()} | {:error, {:descriptor_refused, term()}}
  def build(work_orders, events, identity, opts \\ []) when is_binary(identity) do
    prefix = Keyword.get(opts, :iri_prefix, @iri_prefix)

    with {:ok, projected, evidence} <- project(work_orders, events),
         {:ok, work_order} <- eligible(projected, evidence, identity),
         {:ok, suite} <- verifier_suite(opts),
         {:ok, exec_alias} <- execution_alias(work_order, opts),
         {:ok, dependencies} <- dependencies(work_order, events, prefix) do
      tail = Reconciler.tail_digest(events)

      {:ok,
       %{
         "work_order_iri" => prefix <> identity,
         "checkpoint_iri" => @checkpoint_prefix <> tail,
         "graph_digest" => graph_digest(projected),
         "repository_identity" => work_order["repository"],
         "execution_repo_alias" => exec_alias,
         "base_sha" => work_order["base_sha"],
         "goal" => goal(work_order),
         "provider" => "zcode",
         "verifier_suite" => suite,
         "execution_policy" => "autonomic_wave_attempt",
         "dependencies" => dependencies,
         "bridge" => bridge(work_order, tail)
       }}
    end
  end

  @doc """
  Maps one sealed XaaS receipt onto the receipt the reconciler consumes.

  `bridge` is the `"bridge"` of the descriptor that was executed. Refusals are
  `{:error, {:receipt_refused, reason}}` with distinct reasons: `:not_a_map`,
  `{:bridge_invalid, missing}`, `:invalid_receipt_digest`,
  `:receipt_digest_mismatch`, `:bridge_mismatch`, `:invalid_final_head`,
  `{:unsupported_outcome, outcome}`, `:head_verified_not_boolean`,
  `:alive_without_head_verification`, `:alive_without_verifier_pass`.
  """
  @spec receipt_from_xaas(map(), map()) :: {:ok, map()} | {:error, {:receipt_refused, term()}}
  def receipt_from_xaas(xaas_receipt, bridge) when is_map(xaas_receipt) and is_map(bridge) do
    receipt = stringify(xaas_receipt)
    bridge = stringify(bridge)

    with :ok <- bridge_shape(bridge),
         :ok <- digest_ok(receipt),
         :ok <- refuse_unless(receipt["bridge"] == bridge, :bridge_mismatch),
         :ok <- refuse_unless(sha?(receipt["final_head"]), :invalid_final_head),
         {:ok, target} <- target(receipt["outcome"]),
         :ok <- head_verified_boolean(receipt),
         :ok <- alive_guards(receipt, target) do
      {:ok, reconciler_receipt(receipt, bridge, target)}
    end
  end

  def receipt_from_xaas(_, _), do: refuse(:not_a_map)

  @doc "Digest a XaaS exporter must place in `\"receipt_digest\"`."
  @spec receipt_digest(map()) :: String.t()
  def receipt_digest(xaas_receipt) do
    xaas_receipt
    |> stringify()
    |> Map.delete("receipt_digest")
    |> SemanticJira.digest_exact()
  end

  # --- descriptor -------------------------------------------------------------

  defp project(work_orders, events) do
    case Reconciler.project(work_orders, events) do
      {:ok, projected, evidence} -> {:ok, projected, evidence}
      {:error, reason} -> descriptor_refused(reason)
    end
  end

  defp eligible(projected, evidence, identity) do
    %{eligible: eligible, blocked: blocked} = SemanticJira.frontier(projected, evidence)

    cond do
      Enum.any?(eligible, &(&1["identity"] == identity)) ->
        {:ok, Enum.find(projected, &(&1["identity"] == identity))}

      entry = Enum.find(blocked, &(&1["identity"] == identity)) ->
        descriptor_refused({:not_eligible, identity, entry["reason"]})

      true ->
        descriptor_refused({:not_eligible, identity, "unknown_identity"})
    end
  end

  defp verifier_suite(opts) do
    case Keyword.get(opts, :verifier_suite) do
      nil -> descriptor_refused({:missing_option, :verifier_suite})
      suite -> match_option(suite, @suite_re, :verifier_suite)
    end
  end

  defp execution_alias(work_order, opts) do
    explicit = Keyword.get(opts, :execution_repo_alias)

    mapped =
      opts |> Keyword.get(:aliases, %{}) |> stringify() |> Map.get(work_order["repository"])

    case explicit || mapped do
      nil -> descriptor_refused({:missing_alias, work_order["repository"]})
      value -> match_option(value, @alias_re, :execution_repo_alias)
    end
  end

  defp match_option(value, regex, key) do
    if is_binary(value) and Regex.match?(regex, value),
      do: {:ok, value},
      else: descriptor_refused({:invalid_option, key})
  end

  defp dependencies(work_order, events, prefix) do
    work_order["dependencies"]
    |> Enum.map(&stringify/1)
    |> Enum.uniq_by(& &1["upstream"])
    |> Enum.reduce_while({:ok, []}, fn dep, {:ok, acc} ->
      case dependency(dep, events, prefix) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp dependency(dep, events, prefix) do
    upstream = dep["upstream"]
    required = dep["required_standing"]

    alive =
      events
      |> Enum.map(&stringify/1)
      |> Enum.filter(&(&1["identity"] == upstream and &1["to"] == "ALIVE"))
      |> List.last()

    cond do
      required not in [nil, "ALIVE"] ->
        descriptor_refused({:unsupported_required_standing, upstream, required})

      is_nil(alive) ->
        descriptor_refused({:dependency_not_alive, upstream})

      true ->
        {:ok,
         %{
           "work_order_iri" => prefix <> upstream,
           "required_standing" => "ALIVE",
           "observed_standing" => "ALIVE",
           "receipt_iri" => @receipt_prefix <> alive["receipt_digest"],
           "receipt_digest" => alive["receipt_digest"]
         }}
    end
  end

  defp graph_digest(projected) do
    SemanticJira.digest_exact(%{
      "definition_digests" => projected |> Enum.map(& &1["definition_digest"]) |> Enum.sort()
    })
  end

  defp goal(work_order) do
    [
      "#{work_order["identity"]}: #{work_order["title"]}",
      "",
      work_order["description"],
      "",
      "Acceptance:" | Enum.map(work_order["acceptance"], &"- #{&1}")
    ]
    |> Kernel.++(["", "Falsifiers:" | Enum.map(work_order["falsifiers"], &"- #{&1}")])
    |> Kernel.++(scope_lines(work_order["path_scope"]))
    |> Enum.join("\n")
  end

  defp scope_lines([]), do: []
  defp scope_lines(scope), do: ["", "Path scope:" | Enum.map(scope, &"- #{&1}")]

  defp bridge(work_order, tail) do
    %{
      "identity" => work_order["identity"],
      "definition_digest" => work_order["definition_digest"],
      "source_snapshot_digest" => work_order["work_order_digest"],
      "ledger_tail" => tail,
      "repository" => work_order["repository"],
      "base_sha" => work_order["base_sha"],
      "subject" => work_order["subject"],
      "evidence_ceiling" => work_order["evidence_ceiling"],
      "replay_identity" => work_order["replay_identity"],
      "requires" => %{
        "courts" => work_order["required_courts"],
        "acceptance" => work_order["acceptance"],
        "falsifiers" => work_order["falsifiers"]
      }
    }
  end

  # --- receipt ----------------------------------------------------------------

  defp bridge_shape(bridge) do
    missing = Enum.reject(@bridge_keys, &Map.has_key?(bridge, &1))
    requires = bridge["requires"]

    cond do
      missing != [] ->
        refuse({:bridge_invalid, missing})

      not (is_map(requires) and
               Enum.all?(~w(courts acceptance falsifiers), &is_list(requires[&1]))) ->
        refuse({:bridge_invalid, ["requires"]})

      true ->
        :ok
    end
  end

  defp digest_ok(receipt) do
    cond do
      not (is_binary(receipt["receipt_digest"]) and
               Regex.match?(@digest, receipt["receipt_digest"])) ->
        refuse(:invalid_receipt_digest)

      receipt_digest(receipt) != receipt["receipt_digest"] ->
        refuse(:receipt_digest_mismatch)

      true ->
        :ok
    end
  end

  defp target(outcome) do
    case Map.fetch(@outcomes, outcome) do
      {:ok, target} -> {:ok, target}
      :error -> refuse({:unsupported_outcome, outcome})
    end
  end

  defp head_verified_boolean(receipt),
    do: refuse_unless(is_boolean(receipt["head_verified"]), :head_verified_not_boolean)

  defp alive_guards(receipt, "ALIVE") do
    with :ok <- refuse_unless(receipt["head_verified"] == true, :alive_without_head_verification) do
      refuse_unless(verifier_status(receipt) == "pass", :alive_without_verifier_pass)
    end
  end

  defp alive_guards(_, _), do: :ok

  defp reconciler_receipt(receipt, bridge, target) do
    passed = verifier_status(receipt) == "pass"
    observed = passed and receipt["head_verified"] == true and receipt["outcome"] == "alive"
    court = court_receipt(receipt)
    requires = bridge["requires"]

    base = %{
      "identity" => bridge["identity"],
      "definition_digest" => bridge["definition_digest"],
      "source_snapshot_digest" => bridge["source_snapshot_digest"],
      "repository" => bridge["repository"],
      "base_sha" => bridge["base_sha"],
      "subject" => bridge["subject"],
      "candidate_sha" => receipt["final_head"],
      "target" => target,
      "receipt_digest" => receipt["receipt_digest"],
      "court_results" => court_results(receipt, requires["courts"]),
      "evidence_types" => evidence_types(receipt, court, passed),
      "acceptance_results" => acceptance_results(court, requires["acceptance"], passed),
      "falsifier_results" => falsifier_results(court, requires["falsifiers"], passed),
      "receipt_classes" => receipt_classes(court, passed),
      "evidence_ceiling" => court_string(court, "evidence_ceiling") || @fabric_ceiling,
      "observed_execution" => observed,
      "inherited_standing" => false,
      "xaas" => Map.take(receipt, ~w(epoch_id run_id receipt_id))
    }

    base
    |> put_court_replay(court)
    |> put_court_authority(court)
  end

  defp verifier_status(receipt), do: get_in(receipt, ["fabric_verifier", "status"])

  defp court_receipt(receipt) do
    case get_in(receipt, ["fabric_verifier", "court_receipt"]) do
      %{} = court -> court
      _ -> %{}
    end
  end

  defp court_results(receipt, courts) do
    steps = get_in(receipt, ["fabric_verifier", "steps"]) || []
    overall = verifier_status(receipt) == "pass"

    Map.new(courts, fn court ->
      step_passed =
        Enum.any?(steps, &(is_map(&1) and &1["id"] == court and &1["status"] == "pass"))

      {court, %{"passed" => overall and step_passed}}
    end)
  end

  defp evidence_types(receipt, court, passed) do
    declared = strings(court["evidence_types"])

    derived =
      if(passed, do: ["verification"], else: []) ++
        if passed and receipt["head_verified"] == true, do: ["exact_head_verification"], else: []

    Enum.uniq(declared ++ derived) |> Enum.sort()
  end

  defp receipt_classes(court, passed) do
    declared =
      Enum.filter(strings(court["receipt_classes"]), &(&1 in SemanticJira.receipt_classes()))

    Enum.uniq(declared ++ if(passed, do: ["verification"], else: [])) |> Enum.sort()
  end

  defp acceptance_results(court, acceptance, passed) do
    observed = map_or_empty(court["acceptance_results"])
    Map.new(acceptance, &{&1, passed and observed[&1] == true})
  end

  defp falsifier_results(court, falsifiers, passed) do
    observed = map_or_empty(court["falsifier_results"])

    Map.new(falsifiers, fn falsifier ->
      verdict =
        cond do
          not passed -> "unobserved"
          observed[falsifier] in ["survived", true] -> "survived"
          observed[falsifier] in ["killed", false] -> "killed"
          true -> "unobserved"
        end

      {falsifier, verdict}
    end)
  end

  defp put_court_replay(receipt, court) do
    if court["replay_passed"] == true and is_binary(court["replay_identity"]),
      do:
        Map.merge(receipt, %{
          "replay_passed" => true,
          "replay_identity" => court["replay_identity"]
        }),
      else: receipt
  end

  defp put_court_authority(receipt, court) do
    case court["authority_receipt"] do
      %{} = authority -> Map.put(receipt, "authority_receipt", authority)
      _ -> receipt
    end
  end

  defp court_string(court, key) do
    if is_binary(court[key]) and court[key] != "", do: court[key]
  end

  defp strings(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp strings(_), do: []

  defp map_or_empty(%{} = map), do: map
  defp map_or_empty(_), do: %{}

  # --- helpers ------------------------------------------------------------------

  defp sha?(value), do: is_binary(value) and Regex.match?(@sha, value)
  defp refuse_unless(true, _), do: :ok
  defp refuse_unless(_, reason), do: refuse(reason)
  defp refuse(reason), do: {:error, {:receipt_refused, reason}}
  defp descriptor_refused(reason), do: {:error, {:descriptor_refused, reason}}

  defp stringify(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), stringify(item)} end)

  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)
  defp stringify(value), do: value
end
