defmodule GgenIgniter.SemanticJira.Descriptor do
  @moduledoc """
  XaaS execution descriptor generated from the admitted frontier.

  A descriptor exists only for a work order that `SemanticJira.frontier/4`
  (or `frontier_from_events/4` when `:events` is given) currently lists as
  eligible. Any other work order (unadmitted, non-UNKNOWN standing, unmet
  dependencies, not present) yields a typed
  `{:error, {:refused_descriptor, reason}}` and no descriptor.

  Graph identity is carried unchanged, ggen -> XaaS -> ash_a2a:

    * `definition_digest` - stable identity of the definition
    * `snapshot_digest`   - the admitted `work_order_digest`
    * `base_sha`          - the exact base commit
    * `graph_digest`      - digest of the ontology graph

  The same values are copied verbatim into the descriptor, its rendered JSON
  (`runtime-templates/descriptor.json.eex` of `semantic-jira-pack`) and the A2A task
  metadata (`to_a2a_task/3`). Authority is always `NONE`; the descriptor grants
  no lease, does no DO, and never promotes standing.
  """

  alias GgenIgniter.{Render, RuntimeShape, SemanticA2A, SemanticJira}
  alias GgenIgniter.SemanticJira.Authority

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
  `verifier_identity`; optional `provider` (default `@default_provider`,
  `"recipe"`: the deterministic XaaS RecipeWorker, so an absent provider never
  falls back to an LLM (PRD PR-009, ARD section 9); an LLM provider such as
  `"zcode"` is bound only when named explicitly), validated against the same
  provider-name pattern `build_xaas_contract/4` enforces: a malformed provider
  is `{:error, {:refused_descriptor, {:invalid_option, :provider}}}`.
  Options: `:events` (transition log), `:evidence` (dependency evidence map),
  `:authority` (origin-authority index, graph or Turtle path; default the
  canonical index -- `SemanticJira.frontier/4`). An order whose origin does
  not resolve is `{:not_on_frontier, "origin_not_admitted"}`.
  """
  @spec build([map()], String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(work_orders, identity, attrs, opts \\ [])
      when is_list(work_orders) and is_binary(identity) and is_map(attrs) do
    evidence = Keyword.get(opts, :evidence, %{})
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    authority = Keyword.take(opts, [:authority])

    {projected, front} =
      case Keyword.get(opts, :events) do
        nil ->
          {work_orders, SemanticJira.frontier(work_orders, evidence, nil, authority)}

        events ->
          {p, _} = SemanticJira.project(work_orders, events)
          {p, SemanticJira.frontier_from_events(work_orders, events, evidence, authority)}
      end

    with {:ok, provider} <- build_provider(attrs),
         {:ok, candidate} <- eligible(front, identity),
         {:ok, raw} <- find(projected, identity),
         {:ok, admitted} <- refuse(SemanticJira.admit_work_order(raw)),
         :ok <- same_snapshot(admitted, candidate),
         {:ok, definition} <- refuse(SemanticJira.definition_digest(raw)),
         {:ok, package} <- refuse(SemanticJira.execution_package(raw, attrs)) do
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
         "provider" => provider,
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

    [SemanticA2A.pack_dir(), "runtime-templates", "descriptor.json.eex"]
    |> Path.join()
    |> File.read!()
    |> Render.render(bindings)
  end

  @doc """
  A2A task envelope for the descriptor. Refuses when the descriptor's graph
  identity disagrees with the work order it claims to describe, or when the
  work order's origin does not resolve in the pinned authority index named by
  `opts[:authority]` (`Authority.require_origin/2`, G1).
  """
  @spec to_a2a_task(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def to_a2a_task(descriptor, work_order, opts \\ []) do
    with {:ok, admitted} <- refuse(SemanticJira.admit_work_order(work_order)),
         {:ok, _origin_digest} <- Authority.require_origin(admitted, opts),
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

  alias GgenIgniter.SemanticJira.Reconciler

  @bridge_keys ~w(identity definition_digest source_snapshot_digest ledger_tail repository base_sha subject evidence_ceiling replay_identity requires)
  @iri_prefix "urn:semantic-jira:work-order:"
  @checkpoint_prefix "urn:semantic-jira:checkpoint:"
  @receipt_prefix "urn:semantic-jira:receipt:"
  @sha ~r/\A[0-9a-f]{40}\z/
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @alias_re ~r/\A[A-Za-z0-9_.-]{1,128}\z/
  @suite_re ~r/\A[a-z0-9][a-z0-9_-]{0,63}\z/
  @fabric_ceiling "repository-local"
  # PRD PR-009 (no LLM fallback) / ARD section 9 (a deterministic admitted
  # provider outranks an LLM for KNOWN work): the default is the XaaS
  # RecipeWorker provider id; "zcode" stays selectable by naming it.
  @default_provider "recipe"
  @evidence_keys ~w(subject repository base_sha court_results evidence_types acceptance_results
                    falsifier_results receipt_classes evidence_ceiling observed_execution
                    inherited_standing replay_passed replay_identity authority_receipt)

  # build/4's provider: the same default and name pattern as
  # build_xaas_contract/4's `provider/1`, refused in build/4's own vocabulary.
  defp build_provider(attrs) do
    case Map.get(attrs, "provider", @default_provider) do
      provider when is_binary(provider) ->
        if Regex.match?(@suite_re, provider),
          do: {:ok, provider},
          else: {:error, {:refused_descriptor, {:invalid_option, :provider}}}

      _ ->
        {:error, {:refused_descriptor, {:invalid_option, :provider}}}
    end
  end

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
  `repository` to one), `:aliases` (`%{"owner/repo" => alias}`), `:iri_prefix`,
  `:provider` (the XaaS construction provider, default `"recipe"`, the
  deterministic RecipeWorker; an LLM provider such as `"zcode"` only when named),
  `:authority` (origin-authority index, graph or Turtle path; default the
  canonical index -- an unresolved origin is
  `{:not_eligible, identity, "origin_not_admitted"}`).
  Nothing is invented: a missing or malformed option is a typed refusal.

  The eligible row is ADMITTED (`SemanticJira.admit_work_order/1`) before it
  is projected, so the bridge's `definition_digest` / `source_snapshot_digest`
  are the kernel's digests (the reconciler's `definition_mismatch` check binds
  to exactly these) and the admission defaults (`dependencies`, `path_scope`)
  are present. `graph_digest` is over every row's admitted definition digest.
  """
  @spec build_xaas_contract([map()], [map()], String.t(), keyword()) ::
          {:ok, map()} | {:error, {:descriptor_refused, term()}}
  def build_xaas_contract(work_orders, events, identity, opts \\ []) when is_binary(identity) do
    prefix = Keyword.get(opts, :iri_prefix, @iri_prefix)

    with {:ok, projected, evidence} <- project(work_orders, events),
         {:ok, row} <- eligible(projected, evidence, identity, Keyword.take(opts, [:authority])),
         {:ok, work_order} <- admit(row),
         {:ok, provider} <- provider(opts),
         {:ok, suite} <- verifier_suite(opts),
         {:ok, exec_alias} <- execution_alias(work_order, opts),
         {:ok, dependencies} <- dependencies(work_order, events, prefix),
         {:ok, court_map} <- court_map(opts, work_order) do
      tail = Reconciler.tail_digest(events)

      descriptor = %{
        "work_order_iri" => prefix <> identity,
        "checkpoint_iri" => @checkpoint_prefix <> tail,
        "graph_digest" => graph_digest(projected),
        "repository_identity" => work_order["repository"],
        "execution_repo_alias" => exec_alias,
        "base_sha" => work_order["base_sha"],
        "goal" => goal(work_order),
        "provider" => provider,
        "verifier_suite" => suite,
        "execution_policy" => "autonomic_wave_attempt",
        "dependencies" => dependencies,
        "bridge" => bridge(work_order, tail)
      }

      {:ok, maybe_put_court_map(descriptor, court_map)}
    end
  end

  @doc """
  Maps one sealed XaaS receipt onto the receipt the reconciler consumes.

  `bridge` is the `"bridge"` of the descriptor that was executed. The result
  carries `Reconciler.reconcile/4`'s contract keys (`snapshot_digest`, nested
  `evidence`) alongside the flat bridge/evidence keys. Refusals are
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

  def receipt_from_xaas(_, _), do: receipt_refuse(:not_a_map)

  @doc "Digest a XaaS exporter must place in `\"receipt_digest\"`."
  @spec receipt_digest(map()) :: String.t()
  def receipt_digest(xaas_receipt) do
    xaas_receipt
    |> stringify()
    |> Map.delete("receipt_digest")
    |> SemanticJira.digest_exact()
  end

  # --- descriptor -------------------------------------------------------------

  defp project(work_orders, events), do: Reconciler.project(work_orders, events)

  defp eligible(projected, evidence, identity, authority) do
    %{eligible: eligible, blocked: blocked} =
      SemanticJira.frontier(projected, evidence, nil, authority)

    cond do
      Enum.any?(eligible, &(&1["identity"] == identity)) ->
        {:ok, Enum.find(projected, &(&1["identity"] == identity))}

      entry = Enum.find(blocked, &(&1["identity"] == identity)) ->
        descriptor_refused({:not_eligible, identity, entry["reason"]})

      true ->
        descriptor_refused({:not_eligible, identity, "unknown_identity"})
    end
  end

  defp admit(row) do
    case SemanticJira.admit_work_order(row) do
      {:ok, admitted} -> {:ok, admitted}
      {:error, {:refused_work_order, reason}} -> descriptor_refused({:unadmitted, reason})
    end
  end

  defp provider(opts) do
    opts
    |> Keyword.get(:provider, @default_provider)
    |> match_option(@suite_re, :provider)
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

  @court_map_keys ~w(acceptance falsifiers courts)

  # The optional court map: upstream, minted with the work order (mix
  # semantic_jira.court_map projects it from the ontology's sj:witnessedBy
  # facts) and consumed by the fabric's court-receipt producer. Every IRI it
  # binds must belong to THIS work order; every predicate is v1-exactly one
  # named test. A malformed or foreign map is refused, never trimmed.
  defp court_map(opts, work_order) do
    case Keyword.get(opts, :court_map) do
      nil ->
        {:ok, nil}

      raw when is_map(raw) ->
        raw = stringify(raw)

        with :ok <- court_map_keys(raw),
             :ok <- court_map_nonempty(raw),
             :ok <- court_map_group(raw["acceptance"], work_order["acceptance"], "acceptance"),
             :ok <- court_map_group(raw["falsifiers"], work_order["falsifiers"], "falsifiers"),
             :ok <- court_map_courts(raw["courts"], work_order["required_courts"]) do
          {:ok, Map.take(raw, @court_map_keys)}
        end

      _ ->
        descriptor_refused({:court_map_refused, :not_a_map})
    end
  end

  defp court_map_keys(raw) do
    case Map.keys(raw) -- @court_map_keys do
      [] -> :ok
      unknown -> descriptor_refused({:court_map_refused, {:unknown_keys, unknown}})
    end
  end

  defp court_map_nonempty(raw) do
    if raw["acceptance"] in [nil, %{}] and raw["falsifiers"] in [nil, %{}] and
         raw["courts"] in [nil, []] do
      descriptor_refused({:court_map_refused, :empty})
    else
      :ok
    end
  end

  defp court_map_group(group, _allowed, _kind) when group in [nil, %{}], do: :ok

  defp court_map_group(group, allowed, kind) when is_map(group) do
    Enum.reduce_while(group, :ok, fn
      {iri, %{"test" => test_id}}, :ok when is_binary(test_id) and test_id != "" ->
        if iri in allowed do
          {:cont, :ok}
        else
          {:halt, descriptor_refused({:court_map_refused, {:foreign_iri, kind, iri}})}
        end

      {iri, predicate}, :ok ->
        {:halt,
         descriptor_refused({:court_map_refused, {:invalid_predicate, kind, iri, predicate}})}

      _, _acc ->
        {:halt, descriptor_refused({:court_map_refused, {:invalid_group, kind}})}
    end)
  end

  defp court_map_group(_group, _allowed, kind),
    do: descriptor_refused({:court_map_refused, {:invalid_group, kind}})

  defp court_map_courts(courts, _allowed) when courts in [nil, []], do: :ok

  defp court_map_courts(courts, allowed) when is_list(courts) do
    if Enum.all?(courts, &(&1 in allowed)) do
      :ok
    else
      foreign = Enum.reject(courts, &(&1 in allowed))
      descriptor_refused({:court_map_refused, {:foreign_iri, "courts", foreign}})
    end
  end

  defp court_map_courts(_courts, _allowed),
    do: descriptor_refused({:court_map_refused, {:invalid_group, "courts"}})

  defp maybe_put_court_map(descriptor, nil), do: descriptor
  defp maybe_put_court_map(descriptor, court_map), do: Map.put(descriptor, "court_map", court_map)

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

  # Every row contributes its ADMITTED definition digest; a row the kernel
  # refuses contributes the exact digest of its raw content, so no row -- not
  # even an unadmittable one -- can change without moving the graph digest.
  defp graph_digest(projected) do
    SemanticJira.digest_exact(%{
      "definition_digests" => projected |> Enum.map(&row_definition_digest/1) |> Enum.sort()
    })
  end

  defp row_definition_digest(row) do
    case SemanticJira.definition_digest(row) do
      {:ok, digest} -> digest
      {:error, _} -> SemanticJira.digest_exact(row)
    end
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
        "falsifiers" => work_order["falsifiers"],
        "evidence" => work_order["required_evidence"]
      }
    }
  end

  # --- receipt ----------------------------------------------------------------

  defp bridge_shape(bridge) do
    missing = Enum.reject(@bridge_keys, &Map.has_key?(bridge, &1))
    requires = bridge["requires"]

    cond do
      missing != [] ->
        receipt_refuse({:bridge_invalid, missing})

      not (is_map(requires) and
               Enum.all?(~w(courts acceptance falsifiers evidence), &is_list(requires[&1]))) ->
        receipt_refuse({:bridge_invalid, ["requires"]})

      true ->
        :ok
    end
  end

  defp digest_ok(receipt) do
    cond do
      not (is_binary(receipt["receipt_digest"]) and
               Regex.match?(@digest, receipt["receipt_digest"])) ->
        receipt_refuse(:invalid_receipt_digest)

      receipt_digest(receipt) != receipt["receipt_digest"] ->
        receipt_refuse(:receipt_digest_mismatch)

      true ->
        :ok
    end
  end

  defp target(outcome) do
    case Map.fetch(@outcomes, outcome) do
      {:ok, target} -> {:ok, target}
      :error -> receipt_refuse({:unsupported_outcome, outcome})
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
    courts = court_results(receipt, requires["courts"])

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
      "court_results" => courts,
      "evidence_types" => evidence_types(receipt, court, passed, requires["evidence"], courts),
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
    |> put_reconciler_contract()
  end

  # `Reconciler.reconcile/4`'s receipt contract is `definition_digest`,
  # `snapshot_digest`, `target`, `candidate_sha` and a nested `evidence` map
  # (what `SemanticJira.promote/3` judges). The flat keys above stay for
  # existing consumers; the contract keys are derived from them verbatim, so
  # `mix semantic_jira.xaas_receipt | mix semantic_jira.reconcile` composes.
  defp put_reconciler_contract(receipt) do
    Map.merge(receipt, %{
      "snapshot_digest" => receipt["source_snapshot_digest"],
      "evidence" => Map.take(receipt, @evidence_keys)
    })
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
    sealed = court_receipt(receipt)

    Map.new(courts, fn court ->
      step_passed =
        Enum.any?(steps, &(is_map(&1) and &1["id"] == court and &1["status"] == "pass"))

      witnessed = step_passed or witnessed_court?(sealed, court, steps, receipt)

      {court, %{"passed" => overall and witnessed}}
    end)
  end

  # The fabric's own court receipt (produced by a `receipt:` verifier step and
  # published by Lease.close -- worker-supplied values are dropped at close, so
  # this map is fabric-owned) binds each court IRI to the suite step that judged
  # it. The binding is verified against THIS receipt's own step list and sealed
  # head: a court receipt whose binding does not resolve here is not a court
  # pass, and an unwitnessed required court is a promote/3 refusal, never a
  # silent omission.
  defp witnessed_court?(sealed, court, steps, receipt) do
    case get_in(sealed, ["court_results", court]) do
      %{"passed" => true, "step_id" => step_id, "head" => head} when is_binary(step_id) ->
        head == receipt["final_head"] and
          Enum.any?(steps, &(is_map(&1) and &1["id"] == step_id and &1["status"] == "pass"))

      _ ->
        false
    end
  end

  defp evidence_types(receipt, court, passed, required_evidence, courts) do
    declared = strings(court["evidence_types"])

    # A witnessed required court is what elevates the fabric's local execution
    # + sealed receipt into the work order's own evidence classes; the IRIs are
    # the bridge's echo of required_evidence, never invented here.
    witnessed =
      if Enum.any?(Map.values(courts), &(&1["passed"] == true)),
        do: strings(required_evidence),
        else: []

    derived =
      if(passed, do: ["verification"], else: []) ++
        if passed and receipt["head_verified"] == true, do: ["exact_head_verification"], else: []

    Enum.uniq(declared ++ witnessed ++ derived) |> Enum.sort()
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
  defp refuse_unless(_, reason), do: receipt_refuse(reason)
  defp receipt_refuse(reason), do: {:error, {:receipt_refused, reason}}
  defp descriptor_refused(reason), do: {:error, {:descriptor_refused, reason}}

  defp stringify(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), stringify(item)} end)

  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)
  defp stringify(value), do: value
end
