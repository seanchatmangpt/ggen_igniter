defmodule GgenIgniter.GenerationalResilience do
  @moduledoc """
  Authority-free BEAM admission for generation-bound cyber-resiliency manufacture.

  This module consumes the customer-visible contract projected from
  `nist-cyber-resiliency-generational-pack`. It does **not** implement NIST,
  deploy infrastructure, mutate a project, or grant runtime DO authority.

  Its job is narrower:

    * admit an explicit generation identity and semantic/source/manufacture closure;
    * refuse implementation inheritance and compatibility obligation;
    * validate bounded policies for selected SP 800-160 cyber-resiliency techniques;
    * classify which techniques have high software-manufacturing leverage versus
      intrinsic independent-resource cost;
    * produce an authority-free transition plan for the existing reconciliation /
      BRCE consequence boundary.

  Prior implementation may be observed evidence. Mere prior existence never grants
  it standing in the next generation.
  """

  @sha256 ~r/\Asha256:[0-9a-f]{64}\z/
  @generation ~r/\Av\d{2}\.\d{1,2}(?:\.\d+)?\z/

  @techniques [
    :adaptive_response,
    :analytic_monitoring,
    :contextual_awareness,
    :coordinated_protection,
    :deception,
    :diversity,
    :dynamic_positioning,
    :non_persistence,
    :privilege_restriction,
    :realignment,
    :redundancy,
    :segmentation,
    :substantiated_integrity,
    :unpredictability
  ]

  @high_manufacturing_leverage MapSet.new([
                                 :diversity,
                                 :dynamic_positioning,
                                 :non_persistence,
                                 :realignment,
                                 :unpredictability
                               ])

  @enforce_keys [
    :generation_id,
    :semantic_authority_digest,
    :source_snapshot_digest,
    :manufacture_policy_digest,
    :receipt_digest,
    :techniques
  ]
  defstruct @enforce_keys ++
              [
                implementation_inheritance: false,
                compatibility_obligation: false,
                authority_ceiling: :construct,
                disposition: :replaceable
              ]

  @type technique ::
          :adaptive_response
          | :analytic_monitoring
          | :contextual_awareness
          | :coordinated_protection
          | :deception
          | :diversity
          | :dynamic_positioning
          | :non_persistence
          | :privilege_restriction
          | :realignment
          | :redundancy
          | :segmentation
          | :substantiated_integrity
          | :unpredictability

  @type t :: %__MODULE__{
          generation_id: String.t(),
          semantic_authority_digest: String.t(),
          source_snapshot_digest: String.t(),
          manufacture_policy_digest: String.t(),
          receipt_digest: String.t(),
          techniques: %{optional(technique()) => map()},
          implementation_inheritance: false,
          compatibility_obligation: false,
          authority_ceiling: :construct,
          disposition: :replaceable
        }

  @type refusal ::
          {:refused_generational_resilience, atom()}
          | {:refused_generational_resilience, atom(), term()}

  @doc "The fourteen NIST SP 800-160 Vol. 2 Rev. 1 technique identifiers."
  @spec techniques() :: [technique()]
  def techniques, do: @techniques

  @doc """
  Admits one generation profile.

  The profile must name every identity needed to reproduce the decision surface,
  explicitly refuse implementation inheritance and compatibility obligation, stay
  below DO authority, and provide a bounded policy for every selected technique.
  """
  @spec admit(map()) :: {:ok, t()} | {:error, refusal()}
  def admit(profile) when is_map(profile) do
    with {:ok, generation_id} <- fetch(profile, :generation_id),
         :ok <- validate_generation(generation_id),
         {:ok, semantic} <- fetch_digest(profile, :semantic_authority_digest),
         {:ok, source} <- fetch_digest(profile, :source_snapshot_digest),
         {:ok, manufacture} <- fetch_digest(profile, :manufacture_policy_digest),
         {:ok, receipt} <- fetch_digest(profile, :receipt_digest),
         :ok <- exact_false(profile, :implementation_inheritance),
         :ok <- exact_false(profile, :compatibility_obligation),
         :ok <- exact_value(profile, :authority_ceiling, :construct),
         :ok <- exact_value(profile, :disposition, :replaceable),
         {:ok, policies} <- fetch(profile, :techniques),
         :ok <- validate_techniques(policies) do
      {:ok,
       %__MODULE__{
         generation_id: generation_id,
         semantic_authority_digest: semantic,
         source_snapshot_digest: source,
         manufacture_policy_digest: manufacture,
         receipt_digest: receipt,
         techniques: policies
       }}
    end
  end

  def admit(_),
    do: {:error, {:refused_generational_resilience, :profile_not_map}}

  @doc """
  Produces the authority-free transition from one admitted generation to another.

  No source tree is copied and no compatibility requirement is synthesized. The
  transition explicitly retains knowledge/evidence identities while retiring the
  prior implementation as an authority-free intent.
  """
  @spec transition(map() | t(), map() | t()) :: {:ok, map()} | {:error, refusal()}
  def transition(previous, next) do
    with {:ok, previous} <- normalize(previous),
         {:ok, next} <- normalize(next),
         :ok <- generation_changed(previous, next) do
      {:ok,
       %{
         operation: :remanufacture_generation,
         from_generation: previous.generation_id,
         to_generation: next.generation_id,
         semantic_authority_digest: next.semantic_authority_digest,
         source_snapshot_digest: next.source_snapshot_digest,
         manufacture_policy_digest: next.manufacture_policy_digest,
         receipt_digest: next.receipt_digest,
         technique_parameters: next.techniques,
         preserve: [:semantic_capital, :source_provenance, :receipts],
         retire: [:prior_implementation],
         implementation_inheritance: false,
         compatibility_obligation: false,
         authority: :none
       }}
    end
  end

  @doc """
  Returns the local software-manufacturing cost class for a resiliency technique.

  This is an implementation-economics annotation, not a NIST claim.
  """
  @spec cost_class(technique()) ::
          :high_manufacturing_leverage | :intrinsic_resource_cost | :control_dependent
  def cost_class(:redundancy), do: :intrinsic_resource_cost

  def cost_class(technique) when technique in @techniques do
    if MapSet.member?(@high_manufacturing_leverage, technique),
      do: :high_manufacturing_leverage,
      else: :control_dependent
  end

  @doc "Receipt metadata for a downstream consequence path; this function performs no DO."
  @spec receipt_metadata(t()) :: map()
  def receipt_metadata(%__MODULE__{} = profile) do
    %{
      "generation_id" => profile.generation_id,
      "semantic_authority_digest" => profile.semantic_authority_digest,
      "source_snapshot_digest" => profile.source_snapshot_digest,
      "manufacture_policy_digest" => profile.manufacture_policy_digest,
      "generation_receipt_digest" => profile.receipt_digest,
      "implementation_inheritance" => false,
      "compatibility_obligation" => false,
      "authority_ceiling" => "construct",
      "disposition" => "replaceable",
      "resiliency_techniques" =>
        profile.techniques
        |> Map.keys()
        |> Enum.sort()
        |> Enum.map(&Atom.to_string/1)
    }
  end

  defp normalize(%__MODULE__{} = profile), do: {:ok, profile}
  defp normalize(profile) when is_map(profile), do: admit(profile)

  defp generation_changed(%__MODULE__{generation_id: id}, %__MODULE__{generation_id: id}),
    do: {:error, {:refused_generational_resilience, :same_generation, id}}

  defp generation_changed(_, _), do: :ok

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:refused_generational_resilience, :missing_field, key}}
    end
  end

  defp fetch_digest(map, key) do
    with {:ok, value} <- fetch(map, key),
         :ok <- validate_digest(key, value) do
      {:ok, value}
    end
  end

  defp validate_generation(value) when is_binary(value) do
    if Regex.match?(@generation, value),
      do: :ok,
      else: {:error, {:refused_generational_resilience, :invalid_generation_id, value}}
  end

  defp validate_generation(value),
    do: {:error, {:refused_generational_resilience, :invalid_generation_id, value}}

  defp validate_digest(_key, value) when is_binary(value) do
    if Regex.match?(@sha256, value),
      do: :ok,
      else: {:error, {:refused_generational_resilience, :invalid_digest, value}}
  end

  defp validate_digest(key, _value),
    do: {:error, {:refused_generational_resilience, :invalid_digest, key}}

  defp exact_false(map, key) do
    case Map.fetch(map, key) do
      {:ok, false} -> :ok
      {:ok, value} -> {:error, {:refused_generational_resilience, key, value}}
      :error -> {:error, {:refused_generational_resilience, :missing_field, key}}
    end
  end

  defp exact_value(map, key, expected) do
    case Map.fetch(map, key) do
      {:ok, ^expected} -> :ok
      {:ok, value} -> {:error, {:refused_generational_resilience, key, value}}
      :error -> {:error, {:refused_generational_resilience, :missing_field, key}}
    end
  end

  defp validate_techniques(policies) when is_map(policies) and map_size(policies) > 0 do
    policies
    |> Enum.reduce_while(:ok, fn {technique, policy}, :ok ->
      cond do
        technique not in @techniques ->
          {:halt, {:error, {:refused_generational_resilience, :unknown_technique, technique}}}

        not is_map(policy) ->
          {:halt, {:error, {:refused_generational_resilience, :policy_not_map, technique}}}

        true ->
          case validate_policy(technique, policy) do
            :ok -> {:cont, :ok}
            {:error, _} = error -> {:halt, error}
          end
      end
    end)
  end

  defp validate_techniques(_),
    do: {:error, {:refused_generational_resilience, :techniques_empty_or_invalid}}

  defp validate_policy(:non_persistence, policy),
    do: require_positive(policy, :max_artifact_lifetime_seconds, :non_persistence)

  defp validate_policy(:dynamic_positioning, policy) do
    with :ok <- require_nonempty_list(policy, :change_dimensions, :dynamic_positioning),
         :ok <- require_positive(policy, :max_static_duration_seconds, :dynamic_positioning),
         :ok <- require_digest(policy, :strategy_digest, :dynamic_positioning) do
      :ok
    end
  end

  defp validate_policy(:diversity, policy) do
    with :ok <- require_integer_at_least(policy, :variant_count, 2, :diversity),
         :ok <- require_digest(policy, :variant_set_digest, :diversity) do
      :ok
    end
  end

  defp validate_policy(:unpredictability, policy) do
    with :ok <- require_digest(policy, :strategy_digest, :unpredictability),
         :ok <- require_digest(policy, :defender_replay_digest, :unpredictability) do
      :ok
    end
  end

  defp validate_policy(:deception, policy) do
    with :ok <- require_digest(policy, :deception_boundary_digest, :deception),
         :ok <- require_exact(policy, :production_authority, false, :deception) do
      :ok
    end
  end

  defp validate_policy(:realignment, policy) do
    with :ok <- require_digest(policy, :before_topology_digest, :realignment),
         :ok <- require_digest(policy, :after_topology_digest, :realignment),
         :ok <-
           require_distinct(
             policy,
             :before_topology_digest,
             :after_topology_digest,
             :realignment
           ) do
      :ok
    end
  end

  defp validate_policy(:redundancy, policy) do
    with :ok <- require_integer_at_least(policy, :replica_count, 2, :redundancy),
         :ok <- require_integer_at_least(policy, :failure_domain_count, 2, :redundancy),
         :ok <- require_digest(policy, :failure_domain_digest, :redundancy) do
      :ok
    end
  end

  defp validate_policy(:segmentation, policy),
    do: require_digest(policy, :segmentation_boundary_digest, :segmentation)

  defp validate_policy(:privilege_restriction, policy) do
    with :ok <- require_digest(policy, :capability_set_digest, :privilege_restriction),
         :ok <- require_exact(policy, :least_privilege, true, :privilege_restriction) do
      :ok
    end
  end

  defp validate_policy(:analytic_monitoring, policy),
    do: validate_monitoring_context(policy, :analytic_monitoring)

  defp validate_policy(:contextual_awareness, policy),
    do: validate_monitoring_context(policy, :contextual_awareness)

  defp validate_policy(:substantiated_integrity, policy) do
    with :ok <- require_digest(policy, :immutable_source_digest, :substantiated_integrity),
         :ok <- require_digest(policy, :build_provenance_digest, :substantiated_integrity),
         :ok <- require_digest(policy, :sbom_digest, :substantiated_integrity),
         :ok <- require_digest(policy, :security_validation_digest, :substantiated_integrity) do
      :ok
    end
  end

  defp validate_policy(:adaptive_response, policy) do
    with :ok <- require_positive(policy, :max_attempts, :adaptive_response),
         :ok <- require_nonempty(policy, :max_privilege_scope, :adaptive_response),
         :ok <- require_nonempty(policy, :max_blast_radius, :adaptive_response),
         :ok <- require_exact(policy, :receipt_required, true, :adaptive_response) do
      :ok
    end
  end

  defp validate_policy(:coordinated_protection, policy) do
    with :ok <- require_integer_at_least(policy, :safeguard_count, 2, :coordinated_protection),
         :ok <-
           require_digest(
             policy,
             :safeguard_independence_digest,
             :coordinated_protection
           ) do
      :ok
    end
  end

  defp validate_monitoring_context(policy, technique) do
    with :ok <- require_digest(policy, :event_model_digest, technique),
         :ok <- require_digest(policy, :monitoring_evidence_digest, technique),
         :ok <- require_digest(policy, :context_evidence_digest, technique) do
      :ok
    end
  end

  defp require_digest(policy, key, technique) do
    case Map.fetch(policy, key) do
      {:ok, value} when is_binary(value) ->
        if Regex.match?(@sha256, value),
          do: :ok,
          else: policy_refusal(technique, key, value)

      {:ok, value} ->
        policy_refusal(technique, key, value)

      :error ->
        policy_refusal(technique, key, :missing)
    end
  end

  defp require_positive(policy, key, technique) do
    case Map.fetch(policy, key) do
      {:ok, value} when is_number(value) and value > 0 -> :ok
      {:ok, value} -> policy_refusal(technique, key, value)
      :error -> policy_refusal(technique, key, :missing)
    end
  end

  defp require_integer_at_least(policy, key, floor, technique) do
    case Map.fetch(policy, key) do
      {:ok, value} when is_integer(value) and value >= floor -> :ok
      {:ok, value} -> policy_refusal(technique, key, value)
      :error -> policy_refusal(technique, key, :missing)
    end
  end

  defp require_nonempty(policy, key, technique) do
    case Map.fetch(policy, key) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 -> :ok
      {:ok, value} -> policy_refusal(technique, key, value)
      :error -> policy_refusal(technique, key, :missing)
    end
  end

  defp require_nonempty_list(policy, key, technique) do
    case Map.fetch(policy, key) do
      {:ok, value} when is_list(value) and value != [] -> :ok
      {:ok, value} -> policy_refusal(technique, key, value)
      :error -> policy_refusal(technique, key, :missing)
    end
  end

  defp require_exact(policy, key, expected, technique) do
    case Map.fetch(policy, key) do
      {:ok, ^expected} -> :ok
      {:ok, value} -> policy_refusal(technique, key, value)
      :error -> policy_refusal(technique, key, :missing)
    end
  end

  defp require_distinct(policy, left, right, technique) do
    if Map.fetch!(policy, left) != Map.fetch!(policy, right),
      do: :ok,
      else: policy_refusal(technique, :distinct_topology_digests, false)
  end

  defp policy_refusal(technique, key, value),
    do: {:error, {:refused_generational_resilience, technique, %{key => value}}}
end
