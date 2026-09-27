defmodule GgenIgniter.GenerationalResilienceTest do
  use ExUnit.Case, async: true

  alias GgenIgniter.GenerationalResilience

  @a "sha256:" <> String.duplicate("a", 64)
  @b "sha256:" <> String.duplicate("b", 64)
  @c "sha256:" <> String.duplicate("c", 64)
  @d "sha256:" <> String.duplicate("d", 64)

  defp profile(generation_id \\ "v26.10") do
    %{
      generation_id: generation_id,
      semantic_authority_digest: @a,
      source_snapshot_digest: @b,
      manufacture_policy_digest: @c,
      receipt_digest: @d,
      implementation_inheritance: false,
      compatibility_obligation: false,
      authority_ceiling: :construct,
      disposition: :replaceable,
      techniques: %{
        adaptive_response: %{
          max_attempts: 3,
          max_privilege_scope: "bounded-capability-set",
          max_blast_radius: "single-cell",
          receipt_required: true
        },
        analytic_monitoring: monitoring_policy(),
        contextual_awareness: monitoring_policy(),
        coordinated_protection: %{
          safeguard_count: 3,
          safeguard_independence_digest: @a
        },
        deception: %{deception_boundary_digest: @b, production_authority: false},
        diversity: %{variant_count: 3, variant_set_digest: @c},
        dynamic_positioning: %{
          change_dimensions: [:placement, :route, :topology],
          max_static_duration_seconds: 86_400,
          strategy_digest: @d
        },
        non_persistence: %{max_artifact_lifetime_seconds: 2_678_400},
        privilege_restriction: %{capability_set_digest: @a, least_privilege: true},
        realignment: %{before_topology_digest: @b, after_topology_digest: @c},
        redundancy: %{replica_count: 3, failure_domain_count: 3, failure_domain_digest: @d},
        segmentation: %{segmentation_boundary_digest: @a},
        substantiated_integrity: %{
          immutable_source_digest: @a,
          build_provenance_digest: @b,
          sbom_digest: @c,
          security_validation_digest: @d
        },
        unpredictability: %{strategy_digest: @a, defender_replay_digest: @b}
      }
    }
  end

  defp monitoring_policy do
    %{
      event_model_digest: @a,
      monitoring_evidence_digest: @b,
      context_evidence_digest: @c
    }
  end

  test "admits all fourteen NIST resiliency technique policies without granting DO" do
    assert {:ok, admitted} = GenerationalResilience.admit(profile())
    assert map_size(admitted.techniques) == 14
    assert admitted.authority_ceiling == :construct
    assert admitted.implementation_inheritance == false
    assert admitted.compatibility_obligation == false
  end

  test "refuses implementation inheritance" do
    bad = put_in(profile(), [:implementation_inheritance], true)

    assert {:error, {:refused_generational_resilience, :implementation_inheritance, true}} =
             GenerationalResilience.admit(bad)
  end

  test "refuses compatibility obligation" do
    bad = put_in(profile(), [:compatibility_obligation], true)

    assert {:error, {:refused_generational_resilience, :compatibility_obligation, true}} =
             GenerationalResilience.admit(bad)
  end

  test "dynamic positioning is admitted only with a bounded static lifetime" do
    bad = put_in(profile(), [:techniques, :dynamic_positioning, :max_static_duration_seconds], 0)

    assert {:error,
            {:refused_generational_resilience, :dynamic_positioning,
             %{max_static_duration_seconds: 0}}} = GenerationalResilience.admit(bad)
  end

  test "unknown technique vocabulary fails closed" do
    bad = put_in(profile(), [:techniques, :imaginary_resilience], %{})

    assert {:error, {:refused_generational_resilience, :unknown_technique, :imaginary_resilience}} =
             GenerationalResilience.admit(bad)
  end

  test "transition retires prior implementation without synthesizing compatibility" do
    assert {:ok, plan} = GenerationalResilience.transition(profile("v26.9"), profile("v26.10"))

    assert plan.operation == :remanufacture_generation
    assert plan.from_generation == "v26.9"
    assert plan.to_generation == "v26.10"
    assert plan.preserve == [:semantic_capital, :source_provenance, :receipts]
    assert plan.retire == [:prior_implementation]
    assert plan.implementation_inheritance == false
    assert plan.compatibility_obligation == false
    assert plan.authority == :none
  end

  test "a generation cannot remanufacture into itself" do
    assert {:error, {:refused_generational_resilience, :same_generation, "v26.10"}} =
             GenerationalResilience.transition(profile(), profile())
  end

  test "cost classes preserve the physical-resource boundary" do
    for technique <- [
          :dynamic_positioning,
          :non_persistence,
          :realignment,
          :diversity,
          :unpredictability
        ] do
      assert GenerationalResilience.cost_class(technique) == :high_manufacturing_leverage
    end

    assert GenerationalResilience.cost_class(:redundancy) == :intrinsic_resource_cost
    assert GenerationalResilience.cost_class(:segmentation) == :control_dependent
  end

  test "receipt metadata exposes the bounded contract, not private generative theory" do
    assert {:ok, admitted} = GenerationalResilience.admit(profile())
    metadata = GenerationalResilience.receipt_metadata(admitted)

    assert metadata["generation_id"] == "v26.10"
    assert metadata["implementation_inheritance"] == false
    assert metadata["compatibility_obligation"] == false
    assert metadata["authority_ceiling"] == "construct"
    assert length(metadata["resiliency_techniques"]) == 14
  end

  test "public module does not publish private generative terminology" do
    source =
      Path.expand("../lib/ggen_igniter/generational_resilience.ex", __DIR__)
      |> File.read!()

    refute source =~ "Chatman Equation"
    refute source =~ "Chatman Equilibrium"
    refute source =~ "A = μ"
    refute source =~ "A=μ"
  end
end
