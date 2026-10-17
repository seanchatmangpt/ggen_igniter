defmodule GgenIgniter.AiroWiringPinW686Test do
  @moduledoc """
  Lane W686 AIRo wiring pin (xaas v26.10.6 campaign) — hardens the W618 court row in
  /Users/sac/xaas/docs/cro/artifacts/airo-wiring-ledger.md into a byte/structure pin.

  Chicago-style: real file reads, no mocks. Pins the exact bytes of
  priv/airo_risk_description.ttl (sha256 + size), asserts every `airo:` term used
  belongs to the AIRo 1.0 vocabulary, and that the cited repo paths on disk back the
  descriptions in the TTL.
  """

  use ExUnit.Case, async: true

  @ttl_path Path.join([__DIR__, "..", "priv", "airo_risk_description.ttl"])

  # sha256 of priv/airo_risk_description.ttl at pin time (branch feat/adr-0010-gate-convention,
  # HEAD b78a73e9ae65c4435f06a81c3276147c17018f44, 2026-10-06).
  @sha256 "81ddec22d581411d47e2d72d3a8802671376e3efbeb1866cad1945ca1366e3cf"
  @bytes 10_296

  # AIRo 1.0 vocabulary (classes + relations used by the risk-description graph).
  @airo_vocab ~w(AISystem AIComponent AIUser AILifecyclePhase Output Hazard Risk RiskSource
                 Consequence Impact Stakeholder Likelihood Severity RiskControl
                 hasPurpose hasComponent producesOutput hasAIUser hasLifecyclePhase
                 hasRisk hasResidualRisk isRiskSourceFor hasConsequence hasImpact
                 hasImpactOnStakeholder hasLikelihood hasSeverity hasRiskControl
                 mitigatesRiskConcept detectsRiskConcept) |> MapSet.new()

  @cited_paths ~w(
    priv/ggen/ash-manufacture-pack/ontology.ttl
    priv/ggen/ash-manufacture-pack/gates
    priv/ggen/ash-manufacture-pack/bin
    priv/ggen/ash-manufacture-pack/bin/citation_check.py
    priv/ggen/ash-manufacture-pack/bin/drift_check.py
    priv/ggen/ash-manufacture-pack/bin/evidence_check.py
    priv/ggen/ash-manufacture-pack/bin/conformance.py
    priv/ggen/ash-manufacture-pack/README.md
    priv/ggen/ash-manufacture-pack/verify
    priv/ggen/ash-manufacture-pack/verify/cardinality.json
    scripts/forbid_generated_output_dir_once.py
    lib/ggen_igniter/verify_mutation.ex
    test/e2e/igniter_install_path_dep_test.exs
    test/airo_risk_description_test.exs
  )

  defp sha256(path) do
    :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
  end

  test "TTL bytes are pinned: exact sha256 and size" do
    assert File.exists?(@ttl_path)
    assert sha256(@ttl_path) == @sha256, "priv/airo_risk_description.ttl drifted from the pinned digest"
    assert byte_size(File.read!(@ttl_path)) == @bytes
  end

  test "every airo: term used is drawn from the AIRo 1.0 vocabulary" do
    used =
      @ttl_path
      |> File.read!()
      |> then(&Regex.scan(~r/airo:([A-Za-z]+)/, &1))
      |> Enum.map(&hd(tl(&1)))
      |> MapSet.new()

    unknown = MapSet.difference(used, @airo_vocab) |> MapSet.to_list()
    assert unknown == [], "unknown airo: terms: #{inspect(unknown)}"
    assert MapSet.size(used) >= 20
  end

  test "W618 court still passes its own structural assertions (metadata + subjects)" do
    content = File.read!(@ttl_path)

    for prefix <- ~w(airo dcterms rdfs) do
      assert content =~ ~s(@prefix #{prefix}:)
    end

    assert content =~ "airo:AISystem"
    assert content =~ ~s(airo:hasRisk)
    assert content =~ ~s(airo:hasResidualRisk)
    assert content =~ ~s(dcterms:description)
  end

  test "every repo path the TTL relies on exists on disk" do
    for path <- @cited_paths do
      assert File.exists?(Path.join([__DIR__, "..", path])), "missing cited path #{path}"
    end
  end
end
