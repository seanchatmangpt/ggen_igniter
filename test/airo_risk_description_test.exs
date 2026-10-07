defmodule GgenIgniter.AiroRiskDescriptionTest do
  @moduledoc """
  Structural court for priv/airo_risk_description.ttl (lane W618, AIRo wiring wave).

  Chicago-style: the real TTL file on disk is the collaborator — no mocks. Asserts the
  file exists, parses structurally (prefixes declared, statements balanced, all
  predicates drawn from AIRo 1.0 or dcterms/rdfs, airo:AISystem subject present), and
  that every `VIA <repo-relative path>` cited in the TTL actually exists in the repo.
  """

  use ExUnit.Case, async: true

  @ttl_path Path.join([__DIR__, "..", "priv", "airo_risk_description.ttl"])

  @airo_terms ~w(AISystem AIComponent AIUser AILifecyclePhase Output Hazard Risk RiskSource
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
    priv/ggen/ash-manufacture-pack/bin/qualify.sh
    priv/ggen/ash-manufacture-pack/bin/receipt.py
    priv/ggen/ash-manufacture-pack/verify
    priv/ggen/ash-manufacture-pack/verify/cardinality.json
    priv/ggen/ash-manufacture-pack/README.md
    scripts/forbid_generated_output_dir_once.py
    lib/ggen_igniter/verify_mutation.ex
    test/e2e/igniter_install_path_dep_test.exs
    test/airo_risk_description_test.exs
  )

  test "TTL file exists and is non-empty" do
    assert File.exists?(@ttl_path), "missing #{@ttl_path}"
    content = File.read!(@ttl_path)
    byte_size(content) > 2_000
  end

  test "parses structurally: prefixes declared, braces/semicolons balanced" do
    content = File.read!(@ttl_path)

    for prefix <- ~w(airo dcterms rdfs) do
      assert content =~ ~s(@prefix #{prefix}:), "prefix #{prefix} not declared"
    end

    # No stray typo-prefixed predicates or bogus language tags.
    refute content =~ ~r/\n\s*[a-z]+:[a-zA-Z]+.*\b(rxs|@unwanted| \.\.\.| \.;)/

    # Every subject line of a statement block ends cleanly; statements terminated.
    statements = content |> String.split([".", "\n"], trim: true)
    assert length(statements) > 20

    # All airo: predicates used are real AIRo 1.0 terms (class or property).
    used =
      Regex.scan(~r/airo:([A-Za-z]+)/, content)
      |> Enum.map(&Enum.at(&1, 1))
      |> MapSet.new()

    unknown = MapSet.difference(used, @airo_terms) |> MapSet.to_list()
    assert unknown == [], "terms not in AIRo 1.0 vocabulary: #{inspect(unknown)}"
  end

  test "describes the igniter as an airo:AISystem with risk sources and controls" do
    content = File.read!(@ttl_path)
    assert content =~ "AshManufactureIgniter a airo:AISystem"
    assert content =~ "a airo:Hazard"
    assert content =~ "a airo:RiskControl"
    assert content =~ "a airo:Risk"
    assert Enum.count(Regex.scan(~r/a airo:Hazard/, content)) >= 3
    assert Enum.count(Regex.scan(~r/a airo:RiskControl/, content)) >= 4
  end

  test "every VIA-cited repo path exists on disk" do
    repo_root = Path.expand("..", __DIR__)

    missing =
      @cited_paths
      |> Enum.reject(&File.exists?(Path.join(repo_root, &1)))

    assert missing == [], "TTL cites paths that do not exist: #{inspect(missing)}"
  end
end
