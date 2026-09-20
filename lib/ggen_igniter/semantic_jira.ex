defmodule GgenIgniter.SemanticJira do
  @moduledoc """
  DfCM semantic kernel for ontology-native work orders.

  This module owns representation, admission, bounded selection, and
  construction. It composes RuntimeShape and Digest instead of duplicating
  their portable-shape and content-identity machinery.

  It does not issue runtime leases, grant authority, perform BRCE/CommandBus
  DO, merge, publish, deploy, or self-promote standing. Lease objects remain
  XaaS/Ultracode-owned; consequential DO remains BRCE-owned.
  """

  alias GgenIgniter.{Digest, RuntimeShape}

  @standings ~w(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED)
  @dimensions ~w(observed admitted inferred selected constructed executed changed verified receipted replayed merged published deployed)

  @dependency_types ~w(requiresSemanticIdentity requiresProjection requiresCapability requiresReceipt requiresRuntime requiresVerifier requiresObservation requiresPostcondition requiresPublication)

  @receipt_classes ~w(manufacture projection authority_preparation actuation verification postcondition replay publication deployment)

  @projection_types ~w(jira wbpr prd ard vision fond hddl sa2a worker verification executive machine receipt replay)

  @semantic_fields ~w(subject repository base_sha candidate_sha dependencies acceptance falsifiers authority_requirement evidence_ceiling promotion_rule required_courts required_evidence required_receipt_classes projections expected_consequence path_scope)

  @required ~w(identity title description subject repository base_sha standing evidence_ceiling promotion_rule replay_identity required_courts required_evidence acceptance falsifiers projections)

  @sha ~r/\A[0-9a-f]{40}\z/
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @repo ~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/

  @type json_map :: %{optional(String.t()) => term()}
  @type refusal :: {:error, term()}

  @doc "Canonical semantic standing values."
  @spec standings() :: [String.t()]
  def standings, do: @standings

  @doc "Orthogonal evidence and consequence dimensions."
  @spec dimensions() :: [String.t()]
  def dimensions, do: @dimensions

  @doc "Typed dependency-edge vocabulary."
  @spec dependency_types() :: [String.t()]
  def dependency_types, do: @dependency_types

  @doc "Independent receipt classes."
  @spec receipt_classes() :: [String.t()]
  def receipt_classes, do: @receipt_classes

  @doc "The fourteen deterministic Semantic Jira projection classes."
  @spec projection_types() :: [String.t()]
  def projection_types, do: @projection_types

  @doc "Stable digest of JSON-safe semantic data, independent of map insertion order."
  @spec digest(term()) :: String.t()
  def digest(value) do
    value
    |> drop_digest_fields()
    |> canonical()
    |> Jason.encode!()
    |> Digest.sha256()
  end

  @doc "Admits and normalizes one map-shaped WorkOrder without creating authority."
  @spec admit_work_order(map()) :: {:ok, json_map()} | refusal()
  def admit_work_order(value) when is_map(value) do
    work_order = strings(value)

    with :ok <- required(work_order, @required),
         :ok <- repository(work_order["repository"]),
         :ok <- sha(:base_sha, work_order["base_sha"]),
         :ok <- optional_sha(:candidate_sha, work_order["candidate_sha"]),
         :ok <- standing(work_order["standing"]),
         :ok <-
           nonempty_lists(
             work_order,
             ~w(required_courts required_evidence acceptance falsifiers projections)
           ),
         :ok <- dependencies(Map.get(work_order, "dependencies", [])),
         :ok <- projection_types(Map.get(work_order, "projections", [])),
         :ok <- receipt_classes(Map.get(work_order, "required_receipt_classes", [])),
         :ok <- path_scope(Map.get(work_order, "path_scope", [])) do
      normalized =
        work_order
        |> Map.put_new("candidate_sha", nil)
        |> Map.put_new("dependencies", [])
        |> Map.put_new("required_receipt_classes", [])
        |> Map.put_new("path_scope", [])
        |> Map.put_new("authority_requirement", "NONE")
        |> Map.put_new("replay_required", false)
        |> Map.put_new("dimensions", Map.new(@dimensions, &{&1, false}))
        |> Map.put("admitted", true)
        |> Map.put("authority", "NONE")

      {:ok, Map.put(normalized, "work_order_digest", digest(normalized))}
    end
  end

  def admit_work_order(_), do: {:error, {:refused_work_order, :expected_map}}

  @doc "Raising admission helper for deterministic manufacture boundaries."
  @spec admit_work_order!(map()) :: json_map()
  def admit_work_order!(value) do
    case admit_work_order(value) do
      {:ok, work_order} ->
        work_order

      {:error, reason} ->
        raise ArgumentError, "REFUSED:SEMANTIC_JIRA: #{inspect(reason)}"
    end
  end

  @doc "Selects UNKNOWN work whose typed dependency requirements are satisfied."
  @spec frontier([map()], map()) :: %{eligible: [map()], blocked: [map()]}
  def frontier(work_orders, evidence_by_id \\ %{}) do
    Enum.reduce(work_orders, %{eligible: [], blocked: []}, fn raw, acc ->
      case admit_work_order(raw) do
        {:error, reason} ->
          block(acc, %{"reason" => inspect(reason)})

        {:ok, %{"standing" => current} = work_order} when current != "UNKNOWN" ->
          block(acc, %{
            "identity" => work_order["identity"],
            "reason" => "standing=#{current}"
          })

        {:ok, work_order} ->
          missing =
            Enum.reject(
              work_order["dependencies"],
              &dependency_satisfied?(&1, evidence_by_id)
            )

          if missing == [] do
            candidate =
              work_order
              |> Map.take(
                ~w(identity title subject repository base_sha candidate_sha path_scope work_order_digest)
              )
              |> Map.put("authority", "NONE")

            %{acc | eligible: [candidate | acc.eligible]}
          else
            block(acc, %{
              "identity" => work_order["identity"],
              "reason" => "dependencies_unsatisfied",
              "dependencies" => missing
            })
          end
      end
    end)
    |> then(fn result ->
      %{
        eligible: Enum.reverse(result.eligible),
        blocked: Enum.reverse(result.blocked)
      }
    end)
  end

  @doc "Adds active-lease conflict fencing to frontier selection."
  @spec schedule([map()], [map()], map()) :: %{eligible: [map()], blocked: [map()]}
  def schedule(work_orders, active_leases, evidence_by_id \\ %{}) do
    selected = frontier(work_orders, evidence_by_id)

    {ready, collisions} =
      Enum.split_with(selected.eligible, fn candidate ->
        not Enum.any?(active_leases, &conflict?(candidate, &1))
      end)

    blocked =
      Enum.map(collisions, fn candidate ->
        Map.put(candidate, "reason", "conflicting_active_lease")
      end)

    %{eligible: ready, blocked: selected.blocked ++ blocked}
  end

  @doc "Constructs an XaaS/Ultracode lease request; it is not an issued Lease."
  @spec lease_request(map(), map()) :: {:ok, json_map()} | refusal()
  def lease_request(work_order, attrs) when is_map(attrs) do
    attrs = strings(attrs)

    with {:ok, admitted} <- admit_work_order(work_order),
         :ok <-
           required(
             attrs,
             ~w(run_id epoch_id worker_identity scope allowed_operations expiration concurrency_key)
           ),
         :ok <- scope_subset(attrs["scope"], admitted["path_scope"]),
         true <-
           is_list(attrs["allowed_operations"]) and attrs["allowed_operations"] != [] do
      request = %{
        "kind" => "lease_request",
        "owner" => "XaaS/Ultracode",
        "run_id" => attrs["run_id"],
        "epoch_id" => attrs["epoch_id"],
        "work_order_id" => admitted["identity"],
        "work_order_digest" => admitted["work_order_digest"],
        "subject_digest" =>
          digest(Map.take(admitted, ~w(subject repository base_sha candidate_sha))),
        "repository" => admitted["repository"],
        "base_sha" => admitted["base_sha"],
        "worker_identity" => attrs["worker_identity"],
        "scope" => Enum.sort(attrs["scope"]),
        "allowed_operations" => Enum.sort(attrs["allowed_operations"]),
        "expiration" => attrs["expiration"],
        "concurrency_key" => attrs["concurrency_key"],
        "authority" => "NONE"
      }

      {:ok, Map.put(request, "lease_request_id", digest(request))}
    else
      {:error, reason} -> {:error, {:refused_lease_request, reason}}
      false -> {:error, {:refused_lease_request, :invalid_operations}}
    end
  end

  @doc "Manufactures a portable RuntimeShape worker package from a WorkOrder."
  @spec execution_package(map(), map()) :: {:ok, RuntimeShape.t()} | {:error, term()}
  def execution_package(work_order, attrs) when is_map(attrs) do
    attrs = strings(attrs)

    with {:ok, admitted} <- admit_work_order(work_order),
         :ok <- required(attrs, ~w(graph_digest source_digest worker_identity verifier_identity)),
         :ok <- digest_value(:graph_digest, attrs["graph_digest"]),
         :ok <- digest_value(:source_digest, attrs["source_digest"]) do
      RuntimeShape.new(%{
        subject_id: admitted["subject"],
        source_digest: attrs["source_digest"],
        graph_digest: attrs["graph_digest"],
        relationships: admitted["dependencies"],
        actions: [
          %{
            "kind" => "bounded_transition",
            "work_order_id" => admitted["identity"],
            "authority" => "NONE"
          }
        ],
        policies: [
          %{"rule" => "base_must_not_move", "base_sha" => admitted["base_sha"]},
          %{
            "rule" => "worker_not_verifier",
            "worker" => attrs["worker_identity"],
            "verifier" => attrs["verifier_identity"]
          }
        ],
        bindings: [
          %{
            "repository" => admitted["repository"],
            "base_sha" => admitted["base_sha"]
          }
        ],
        projections:
          Enum.map(admitted["projections"], fn kind ->
            %{"kind" => kind, "standing" => "CANDIDATE", "authority" => "NONE"}
          end),
        admission: %{
          "work_order_digest" => admitted["work_order_digest"],
          "standing" => admitted["standing"],
          "admitted" => true
        },
        provenance: %{"replay_identity" => admitted["replay_identity"]}
      })
    end
  end

  @doc "Constructs a BRCE DO intent; this function never performs DO."
  @spec do_intent(map(), map()) :: {:ok, json_map()} | refusal()
  def do_intent(work_order, attrs) when is_map(attrs) do
    attrs = strings(attrs)

    with {:ok, admitted} <- admit_work_order(work_order),
         "available" <- attrs["claim_store_status"],
         %{} = authority <- attrs["prepared_authority_receipt"],
         "prepared" <- authority["status"],
         true <- authority["work_order_digest"] == admitted["work_order_digest"],
         true <- authority["subject"] == admitted["subject"],
         true <- authority["replay_identity"] == admitted["replay_identity"],
         lease when is_binary(lease) and lease != "" <- attrs["lease_id"],
         capability when is_binary(capability) and capability != "" <-
           attrs["capability_identity"],
         command when is_binary(command) and command != "" <- attrs["command_identity"] do
      intent = %{
        "kind" => "brce_do_intent",
        "owner" => "BRCE/CommandBus",
        "work_order_digest" => admitted["work_order_digest"],
        "subject" => admitted["subject"],
        "lease_id" => lease,
        "authority_identity" => authority["authority_identity"],
        "capability_identity" => capability,
        "command_identity" => command,
        "replay_identity" => admitted["replay_identity"],
        "executed" => false
      }

      {:ok, Map.put(intent, "idempotency_identity", digest(intent))}
    else
      status when status in [nil, "error", "unavailable"] ->
        {:error, {:refused_do, :claim_store_unavailable}}

      _ ->
        {:error, {:refused_do, :missing_or_mismatched_precondition}}
    end
  end

  @doc "Classifies the crash window without optimistic retry."
  @spec reconcile_crash_window(map()) :: {:ok, json_map()} | refusal()
  def reconcile_crash_window(attrs) when is_map(attrs) do
    attrs = strings(attrs)

    with :ok <-
           required(
             attrs,
             ~w(effect_identity claim_state consequence_observed receipt_state)
           ) do
      state =
        case {
          attrs["claim_state"],
          attrs["consequence_observed"],
          attrs["receipt_state"]
        } do
          {"prepared", false, "absent"} ->
            "SAFE_TO_RELEASE_CLAIM"

          {"committed", true, "durable"} ->
            "CLOSED"

          {claim, true, "absent"} when claim in ["prepared", "committed"] ->
            "EFFECT_OBSERVED_RECEIPT_MISSING"

          {"committed", false, "absent"} ->
            "CLAIM_COMMITTED_CONSEQUENCE_UNKNOWN"

          _ ->
            "MANUAL_COURT_REQUIRED"
        end

      {:ok, Map.put(attrs, "reconciliation_state", state)}
    end
  end

  @doc "Builds content-addressed exact-head verification evidence."
  @spec exact_head_verification_evidence(map()) :: {:ok, json_map()} | refusal()
  def exact_head_verification_evidence(attrs) when is_map(attrs) do
    attrs = strings(attrs)

    keys =
      ~w(repository base_sha candidate_sha work_order_digest projection_digest command exit_code toolchain_identity environment_identity validator_identity test_result_digest falsifier_results)

    with :ok <- required(attrs, keys),
         :ok <- repository(attrs["repository"]),
         :ok <- sha(:base_sha, attrs["base_sha"]),
         :ok <- sha(:candidate_sha, attrs["candidate_sha"]),
         :ok <- digest_value(:work_order_digest, attrs["work_order_digest"]),
         :ok <- digest_value(:projection_digest, attrs["projection_digest"]),
         :ok <- digest_value(:test_result_digest, attrs["test_result_digest"]),
         true <- is_integer(attrs["exit_code"]),
         true <- is_list(attrs["falsifier_results"]) do
      passed =
        attrs["exit_code"] == 0 and
          Enum.all?(attrs["falsifier_results"], fn result ->
            result = strings(result)
            result["verdict"] in ["survived", true]
          end)

      evidence =
        attrs
        |> Map.put("kind", "exact_head_verification_evidence")
        |> Map.put("receipt_class", "verification")
        |> Map.put("standing_authority", "NONE")
        |> Map.put("passed", passed)

      {:ok, Map.put(evidence, "evidence_digest", digest(evidence))}
    else
      false -> {:error, {:refused_verification_evidence, :invalid_fields}}
      {:error, reason} -> {:error, {:refused_verification_evidence, reason}}
    end
  end

  @doc "Evaluates promotion calculus and returns a transition intent."
  @spec promote(map(), String.t(), map()) :: {:ok, json_map()} | refusal()
  def promote(work_order, target, evidence) when is_map(evidence) do
    evidence = strings(evidence)

    with {:ok, admitted} <- admit_work_order(work_order),
         :ok <- standing(target) do
      checks = [
        subject_exact:
          evidence["work_order_digest"] == admitted["work_order_digest"] and
            evidence["subject"] == admitted["subject"] and
            evidence["repository"] == admitted["repository"] and
            evidence["base_sha"] == admitted["base_sha"],
        dependencies:
          Enum.all?(
            admitted["dependencies"],
            &dependency_satisfied?(&1, Map.get(evidence, "dependency_evidence", %{}))
          ),
        courts:
          Enum.all?(
            admitted["required_courts"],
            &(get_in(evidence, ["court_results", &1, "passed"]) == true)
          ),
        evidence:
          subset?(admitted["required_evidence"], Map.get(evidence, "evidence_types", [])),
        acceptance:
          Enum.all?(
            admitted["acceptance"],
            &(get_in(evidence, ["acceptance_results", &1]) == true)
          ),
        falsifiers:
          Enum.all?(
            admitted["falsifiers"],
            &(get_in(evidence, ["falsifier_results", &1]) in ["survived", true])
          ),
        authority:
          admitted["authority_requirement"] == "NONE" or
            get_in(evidence, ["authority_receipt", "status"]) == "prepared",
        receipts:
          subset?(
            admitted["required_receipt_classes"],
            Map.get(evidence, "receipt_classes", [])
          ),
        replay:
          not admitted["replay_required"] or
            (evidence["replay_passed"] == true and
               evidence["replay_identity"] == admitted["replay_identity"]),
        ceiling:
          target != "ALIVE" or
            (evidence["evidence_ceiling"] == admitted["evidence_ceiling"] and
               evidence["observed_execution"] == true),
        no_inherited_crown: evidence["inherited_standing"] != true
      ]

      failed = for {name, false} <- checks, do: name

      if failed == [] do
        transition = %{
          "kind" => "standing_transition_intent",
          "work_order_digest" => admitted["work_order_digest"],
          "from" => admitted["standing"],
          "to" => target,
          "checks" => Map.new(checks),
          "authority" => "NONE"
        }

        {:ok, Map.put(transition, "transition_digest", digest(transition))}
      else
        {:error, {:promotion_refused, failed}}
      end
    end
  end

  @doc "Manufactures MachineExperience only from receipted observed execution."
  @spec machine_experience(map()) :: {:ok, json_map()} | refusal()
  def machine_experience(attrs) when is_map(attrs) do
    attrs = strings(attrs)

    with :ok <-
           required(
             attrs,
             ~w(subject work_order_digest execution_receipt observation_refs verification resulting_state replay_identity)
           ),
         :ok <- digest_value(:work_order_digest, attrs["work_order_digest"]),
         %{} = receipt <- attrs["execution_receipt"],
         true <- receipt["executed"] == true,
         :ok <- digest_value(:receipt_hash, receipt["receipt_hash"]),
         refs when is_list(refs) and refs != [] <- attrs["observation_refs"],
         true <- attrs["verification"]["passed"] == true,
         false <- attrs["prediction_only"] == true do
      experience = %{
        "kind" => "MachineExperience",
        "subject" => attrs["subject"],
        "work_order_digest" => attrs["work_order_digest"],
        "execution_receipt_hash" => receipt["receipt_hash"],
        "observation_refs" => refs,
        "verification_digest" => digest(attrs["verification"]),
        "resulting_state_digest" => digest(attrs["resulting_state"]),
        "replay_identity" => attrs["replay_identity"],
        "standing" => "CANDIDATE",
        "authority" => "NONE"
      }

      {:ok, Map.put(experience, "experience_digest", digest(experience))}
    else
      true -> {:error, {:refused_machine_experience, :prediction_only}}
      _ -> {:error, {:refused_machine_experience, :incomplete_receipted_evidence}}
    end
  end

  @doc "Builds a composition subject from exact upstream receipt and subject identities."
  @spec composition_subject([map()]) :: {:ok, json_map()} | refusal()
  def composition_subject(upstreams) when is_list(upstreams) and upstreams != [] do
    rows = Enum.map(upstreams, &strings/1)

    invalid =
      Enum.find(rows, fn row ->
        not (is_binary(row["work_order_id"]) and
               is_binary(row["repository"]) and
               valid_digest?(row["receipt_digest"]) and
               valid_digest?(row["subject_digest"]) and
               valid_sha?(row["subject_sha"]))
      end)

    if invalid do
      {:error, {:refused_composition, {:invalid_upstream, invalid}}}
    else
      composition = %{
        "kind" => "typed_composition_subject",
        "upstreams" =>
          Enum.sort_by(rows, &{&1["work_order_id"], &1["receipt_digest"]}),
        "standing" => "UNKNOWN",
        "inherited_standing" => false,
        "authority" => "NONE"
      }

      {:ok, Map.put(composition, "composition_digest", digest(composition))}
    end
  end

  def composition_subject(_), do: {:error, {:refused_composition, :requires_upstreams}}

  @doc "Fresh replay compares exact manufacture identities and subject selection."
  @spec replay_check(map(), map()) :: {:ok, json_map()} | refusal()
  def replay_check(expected, observed) when is_map(expected) and is_map(observed) do
    expected = strings(expected)
    observed = strings(observed)

    keys =
      ~w(pack_subject dependency_set graph_digest consequence_set toolchain_identity environment_identity)

    with :ok <- required(expected, keys),
         :ok <- required(observed, keys),
         :ok <- single_subject(observed) do
      mismatches =
        for key <- keys,
            canonical(expected[key]) != canonical(observed[key]) do
          %{
            "field" => key,
            "expected" => expected[key],
            "observed" => observed[key]
          }
        end

      if mismatches == [] do
        receipt = %{
          "kind" => "replay_receipt",
          "receipt_class" => "replay",
          "status" => "KNOWN_REPLAY",
          "replay_identity" =>
            observed["replay_identity"] || expected["replay_identity"],
          "subject_digest" => digest(Map.take(observed, keys)),
          "authority" => "NONE"
        }

        {:ok, Map.put(receipt, "receipt_digest", digest(receipt))}
      else
        {:error, {:replay_refused, {:identity_mismatch, mismatches}}}
      end
    else
      {:error, reason} -> {:error, {:replay_refused, reason}}
    end
  end

  @doc "Typed semantic diff; prose-only fields are deliberately excluded."
  @spec semantic_diff(map(), map()) :: json_map()
  def semantic_diff(before_value, after_value) do
    before_value = strings(before_value)
    after_value = strings(after_value)

    changes =
      for key <- @semantic_fields,
          canonical(before_value[key]) != canonical(after_value[key]) do
        %{
          "field" => key,
          "before" => before_value[key],
          "after" => after_value[key]
        }
      end

    %{
      "semantic_changes" => changes,
      "semantic_change_count" => length(changes),
      "semantic_equal" => changes == [],
      "before_digest" => digest(Map.take(before_value, @semantic_fields)),
      "after_digest" => digest(Map.take(after_value, @semantic_fields))
    }
  end

  @doc "Constructs bounded repair lineage from preserved failure evidence."
  @spec repair_work_order(map(), map()) :: {:ok, json_map()} | refusal()
  def repair_work_order(work_order, attrs) when is_map(attrs) do
    attrs = strings(attrs)

    with {:ok, admitted} <- admit_work_order(work_order),
         :ok <-
           required(
             attrs,
             ~w(failed_receipt_digest hypothesis smallest_repair permanent_guard changed_identities verifier)
           ),
         :ok <- digest_value(:failed_receipt_digest, attrs["failed_receipt_digest"]) do
      repair = %{
        "kind" => "repair_work_order_candidate",
        "repair_of" => admitted["identity"],
        "repair_of_digest" => admitted["work_order_digest"],
        "failed_receipt_digest" => attrs["failed_receipt_digest"],
        "hypothesis" => attrs["hypothesis"],
        "smallest_repair" => attrs["smallest_repair"],
        "permanent_guard" => attrs["permanent_guard"],
        "changed_identities" => attrs["changed_identities"],
        "verifier" => attrs["verifier"],
        "blind_rerun_allowed" => false,
        "standing" => "UNKNOWN",
        "authority" => "NONE"
      }

      {:ok, Map.put(repair, "repair_digest", digest(repair))}
    end
  end

  @doc "Constructs an observed-process finding while preserving normative law."
  @spec process_finding(map()) :: {:ok, json_map()} | refusal()
  def process_finding(attrs) when is_map(attrs) do
    attrs = strings(attrs)

    with :ok <-
           required(
             attrs,
             ~w(normative_model_digest observed_model_digest delta observation_receipt_digest)
           ),
         :ok <- digest_value(:normative_model_digest, attrs["normative_model_digest"]),
         :ok <- digest_value(:observed_model_digest, attrs["observed_model_digest"]),
         :ok <- digest_value(:observation_receipt_digest, attrs["observation_receipt_digest"]) do
      finding = %{
        "kind" => "process_finding",
        "normative_model_digest" => attrs["normative_model_digest"],
        "observed_model_digest" => attrs["observed_model_digest"],
        "delta" => attrs["delta"],
        "observation_receipt_digest" => attrs["observation_receipt_digest"],
        "normative_model_mutated" => false,
        "admission_state" => "CANDIDATE",
        "authority" => "NONE"
      }

      {:ok, Map.put(finding, "finding_digest", digest(finding))}
    end
  end

  @doc "Returns bounded engineering, executive, agent, or machine views."
  @spec view(map(), :engineering | :executive | :agent | :machine) :: json_map()
  def view(work_order, kind) when kind in [:engineering, :executive, :agent, :machine] do
    work_order = strings(work_order)

    keys =
      case kind do
        :engineering ->
          ~w(identity title subject repository base_sha standing evidence_ceiling dependencies acceptance falsifiers required_courts latest_receipt blockers)

        :executive ->
          ~w(identity title standing evidence_ceiling authority_requirement blockers next_actions latest_receipt expected_consequence)

        :agent ->
          ~w(identity subject repository base_sha candidate_sha path_scope next_actions acceptance falsifiers required_courts exclusions replay_identity)

        :machine ->
          Map.keys(work_order)
      end

    %{
      "view" => Atom.to_string(kind),
      "canonical_work_order_digest" =>
        work_order["work_order_digest"] || digest(work_order),
      "authority" => "NONE",
      "data" => Map.take(work_order, keys)
    }
  end

  @doc "Renders all fourteen projection classes deterministically."
  @spec render_projection(String.t(), map(), map()) :: String.t()
  def render_projection(type, work_order, context \\ %{})
      when type in @projection_types do
    work_order = admit_work_order!(work_order)
    context = strings(context)

    header =
      "<!-- GENERATED Semantic Jira projection; type=#{type}; " <>
        "work_order=#{work_order["identity"]}; digest=#{work_order["work_order_digest"]}; " <>
        "graph=#{context["graph_digest"] || "UNKNOWN"}; authority=NONE -->\n"

    body =
      case type do
        "jira" ->
          "# #{work_order["identity"]} — #{work_order["title"]}\n\n" <>
            "Subject: #{work_order["subject"]}\n" <>
            "Standing: #{work_order["standing"]}\n" <>
            "Evidence ceiling: #{work_order["evidence_ceiling"]}\n"

        "wbpr" ->
          "# WBPR — #{work_order["identity"]}\n\n" <>
            "Work backward from courts, receipts, acceptance, and falsifiers.\n"

        "prd" ->
          "# PRD — #{work_order["identity"]}\n\n#{work_order["description"]}\n"

        "ard" ->
          "# ARD — #{work_order["identity"]}\n\n" <>
            "SELECT != CONSTRUCT != DO. Base SHA: #{work_order["base_sha"]}.\n"

        "vision" ->
          "# Vision — #{work_order["identity"]}\n\n" <>
            "UNKNOWN → represented → admitted → receipted → replayed → KNOWN.\n"

        "fond" ->
          "; candidate FOND projection; authority NONE\n" <>
            "(define (problem #{symbol(work_order["identity"])}) " <>
            "(:domain semantic-jira))\n"

        "hddl" ->
          "; candidate HDDL projection; authority NONE\n" <>
            "(:task advance-#{symbol(work_order["identity"])} :parameters ())\n"

        other ->
          kind = projection_kind(other)

          "{\n" <>
            "  \"kind\": #{Jason.encode!(kind)},\n" <>
            "  \"authority\": \"NONE\",\n" <>
            "  \"work_order_pairs\": " <>
            "#{Jason.encode!(canonical(Map.take(work_order, projection_fields())))},\n" <>
            "  \"context_pairs\": #{Jason.encode!(canonical(context))}\n" <>
            "}\n"
      end

    header <> body <> "\n"
  end

  defp projection_fields do
    ~w(identity title subject repository base_sha candidate_sha standing evidence_ceiling dependencies required_courts required_evidence acceptance falsifiers required_receipt_classes replay_identity path_scope authority_requirement work_order_digest)
  end

  defp projection_kind("sa2a"), do: "sa2a_work_package"
  defp projection_kind("worker"), do: "bounded_worker_package"
  defp projection_kind("verification"), do: "verification_plan"
  defp projection_kind("executive"), do: "executive_status"
  defp projection_kind("machine"), do: "machine_status"
  defp projection_kind("receipt"), do: "receipt_requirements"
  defp projection_kind("replay"), do: "replay_manifest"

  defp block(acc, item), do: %{acc | blocked: [item | acc.blocked]}

  defp dependency_satisfied?(dependency, evidence) do
    dependency = strings(dependency)
    observed = strings(Map.get(evidence, dependency["upstream"], %{}))

    observed != %{} and
      (is_nil(dependency["required_standing"]) or
         observed["standing"] == dependency["required_standing"]) and
      (is_nil(dependency["required_receipt_digest"]) or
         observed["receipt_digest"] == dependency["required_receipt_digest"])
  end

  defp conflict?(candidate, lease) do
    lease = strings(lease)

    lease["status"] in [nil, "active"] and
      lease["repository"] == candidate["repository"] and
      overlap?(candidate["path_scope"] || [], lease["scope"] || [])
  end

  defp overlap?([], _), do: true
  defp overlap?(_, []), do: true

  defp overlap?(left, right) do
    Enum.any?(left, fn a ->
      Enum.any?(right, fn b -> within?(a, b) or within?(b, a) end)
    end)
  end

  defp within?(parent, child) do
    normalized = String.trim_trailing(parent, "/")
    child == normalized or String.starts_with?(child, normalized <> "/")
  end

  defp scope_subset(scope, allowed)
       when is_list(scope) and scope != [] and is_list(allowed) do
    if Enum.all?(scope, fn item -> Enum.any?(allowed, &within?(&1, item)) end) do
      :ok
    else
      {:error, :scope_expansion}
    end
  end

  defp scope_subset(_, _), do: {:error, :invalid_scope}

  defp subset?(need, have),
    do: MapSet.subset?(MapSet.new(need), MapSet.new(have))

  defp single_subject(%{"candidate_subjects" => [_]}), do: :ok

  defp single_subject(%{"candidate_subjects" => subjects}) when is_list(subjects),
    do: {:error, {:ambiguous_subject_selection, length(subjects)}}

  defp single_subject(_), do: :ok

  defp required(map, keys) do
    case Enum.find(keys, &blank?(map[&1])) do
      nil -> :ok
      key -> {:error, {:missing_required_field, key}}
    end
  end

  defp nonempty_lists(map, keys) do
    case Enum.find(keys, fn key ->
           not (is_list(map[key]) and map[key] != [] and
                  Enum.all?(map[key], &(is_binary(&1) and &1 != "")))
         end) do
      nil -> :ok
      key -> {:error, {:invalid_list, key}}
    end
  end

  defp repository(value) when is_binary(value) do
    if Regex.match?(@repo, value),
      do: :ok,
      else: {:error, {:invalid_repository, value}}
  end

  defp repository(value), do: {:error, {:invalid_repository, value}}

  defp sha(field, value) when is_binary(value) do
    if valid_sha?(value),
      do: :ok,
      else: {:error, {:invalid_sha, field, value}}
  end

  defp sha(field, value), do: {:error, {:invalid_sha, field, value}}

  defp optional_sha(_, nil), do: :ok
  defp optional_sha(field, value), do: sha(field, value)

  defp standing(value) when value in @standings, do: :ok

  defp standing("REFUSED(" <> rest) do
    if String.ends_with?(rest, ")") and byte_size(rest) > 1,
      do: :ok,
      else: {:error, {:invalid_standing, rest}}
  end

  defp standing(value), do: {:error, {:invalid_standing, value}}

  defp dependencies(values) when is_list(values) do
    bad =
      Enum.find(values, fn raw ->
        dependency = strings(raw)

        not (is_binary(dependency["upstream"]) and
               dependency["type"] in @dependency_types and
               (is_nil(dependency["required_receipt_digest"]) or
                  valid_digest?(dependency["required_receipt_digest"])))
      end)

    if bad, do: {:error, {:invalid_dependency, bad}}, else: :ok
  end

  defp dependencies(value), do: {:error, {:invalid_dependencies, value}}

  defp projection_types(values) when is_list(values) do
    case Enum.find(values, &(&1 not in @projection_types)) do
      nil -> :ok
      value -> {:error, {:unsupported_projection_type, value}}
    end
  end

  defp projection_types(value), do: {:error, {:invalid_projection_types, value}}

  defp receipt_classes(values) when is_list(values) do
    case Enum.find(values, &(&1 not in @receipt_classes)) do
      nil -> :ok
      value -> {:error, {:unsupported_receipt_class, value}}
    end
  end

  defp receipt_classes(value), do: {:error, {:invalid_receipt_classes, value}}

  defp path_scope(values) when is_list(values) do
    if Enum.all?(
         values,
         &(is_binary(&1) and &1 != "" and not String.starts_with?(&1, "/"))
       ) do
      :ok
    else
      {:error, {:invalid_path_scope, values}}
    end
  end

  defp path_scope(value), do: {:error, {:invalid_path_scope, value}}

  defp digest_value(field, value) do
    if valid_digest?(value),
      do: :ok,
      else: {:error, {:invalid_digest, field, value}}
  end

  defp valid_sha?(value), do: is_binary(value) and Regex.match?(@sha, value)
  defp valid_digest?(value), do: is_binary(value) and Regex.match?(@digest, value)
  defp blank?(value), do: value in [nil, "", []]

  defp strings(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, item} -> {to_string(key), strings(item)} end)
  end

  defp strings(value) when is_list(value), do: Enum.map(value, &strings/1)
  defp strings(value), do: value

  defp drop_digest_fields(value) when is_map(value) do
    Map.drop(
      value,
      ~w(work_order_digest transition_digest evidence_digest receipt_digest experience_digest repair_digest finding_digest composition_digest)
    )
  end

  defp drop_digest_fields(value), do: value

  defp canonical(value) when is_map(value) and not is_struct(value) do
    value
    |> strings()
    |> Enum.map(fn {key, item} -> [key, canonical(item)] end)
    |> Enum.sort_by(&hd/1)
  end

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value) when is_boolean(value) or is_nil(value), do: value
  defp canonical(value) when is_atom(value), do: Atom.to_string(value)
  defp canonical(value), do: value

  defp symbol(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
  end
end
