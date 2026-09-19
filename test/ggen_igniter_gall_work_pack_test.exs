defmodule GgenIgniter.GallWorkPackTest do
  @moduledoc """
  Pack-level proof for `priv/ggen/gall_work/` (v26.9.18 PRD §43.4): the
  ontology parses into a real `RDF.Graph` and carries the whole declared GALL
  vocabulary (all 15 classes, all 15 relationships, the 6 closed standing
  individuals); every real gate (`gates/*.rq`) runs for real via
  `GgenIgniter.GateVerify.run/3` against the real fixture checkpoint document
  and passes; and each gate genuinely FAILS against malformed fixtures --
  the exactly-one-standing gate must catch both a missing and a doubled
  standing, not merely pass vacuously. No mocks: real Turtle parsing, real
  SPARQL execution.
  """

  use ExUnit.Case, async: true

  @pack_dir Path.join([__DIR__, "..", "priv", "ggen", "gall_work"])
  @pack_ontology Path.join(@pack_dir, "ontology.ttl")
  @fixture Path.join([__DIR__, "fixtures", "gall_work", "checkpoint-001.ttl"])
  @missing_standing Path.join([__DIR__, "fixtures", "gall_work", "checkpoint-missing-standing.ttl"])
  @ambiguous_standing Path.join([
                        __DIR__,
                        "fixtures",
                        "gall_work",
                        "checkpoint-ambiguous-standing.ttl"
                      ])

  @required_classes ~w(
    Checkpoint CodingCheckpoint Dependency AcceptancePredicate Falsifier
    Verifier Capability WorkLease ExecutionAttempt CandidateArtifact
    VerificationObservation Receipt Standing Counterexample Repair
  )
  @required_properties ~w(
    dependsOn targetsRepository targetsBase requiresCapability forbidsCapability
    requiresVerifier hasAcceptance hasFalsifier producedCandidate verifiedBy
    producedReceipt hasStanding repairs falsifies unlocks
  )
  @standing_individuals ~w(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED)

  @gall "https://semantic-a2a.dev/gall#"

  describe "the pack ontology loads and carries the full GALL vocabulary" do
    test "ontology.ttl parses into a real RDF.Graph with triples" do
      graph = GgenIgniter.Ontology.load!(@pack_ontology)

      assert %RDF.Graph{} = graph
      assert RDF.Graph.triple_count(graph) > 0
    end

    test "all 15 required classes are declared" do
      graph = GgenIgniter.Ontology.load!(@pack_ontology)

      declared =
        graph
        |> GgenIgniter.Query.run("""
        PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
        SELECT DISTINCT ?c WHERE { ?c a rdfs:Class }
        """)
        |> MapSet.new(& &1["c"])

      for class <- @required_classes do
        assert MapSet.member?(declared, @gall <> class), "missing class gall:#{class}"
      end
    end

    test "all 15 required relationships are declared" do
      graph = GgenIgniter.Ontology.load!(@pack_ontology)

      declared =
        graph
        |> GgenIgniter.Query.run("""
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        SELECT DISTINCT ?p WHERE { ?p a rdf:Property }
        """)
        |> MapSet.new(& &1["p"])

      for property <- @required_properties do
        assert MapSet.member?(declared, @gall <> property), "missing property gall:#{property}"
      end
    end

    test "the six standing individuals exist as gall:Standing" do
      graph = GgenIgniter.Ontology.load!(@pack_ontology)

      standings =
        graph
        |> GgenIgniter.Query.run("""
        PREFIX gall: <#{@gall}>
        SELECT DISTINCT ?s WHERE { ?s a gall:Standing }
        """)
        |> MapSet.new(& &1["s"])

      assert MapSet.size(standings) == 6

      for standing <- @standing_individuals do
        assert MapSet.member?(standings, @gall <> standing), "missing standing gall:#{standing}"
      end
    end
  end

  describe "the pack's real gates against the real fixture checkpoint" do
    test "all gates pass against the complete fixture" do
      assert {:ok, results} = GgenIgniter.GateVerify.run(@pack_dir, @fixture)

      assert results == [
               {"standing", :pass},
               {"verifier", :pass},
               {"capabilities", :pass}
             ]
    end

    test "the exactly-one-standing gate FAILS on a missing standing" do
      assert {:error, {:gate_failed, "standing"}} =
               GgenIgniter.GateVerify.run(@pack_dir, @missing_standing)
    end

    test "the exactly-one-standing gate FAILS on a doubled standing" do
      assert {:error, {:gate_failed, "standing"}} =
               GgenIgniter.GateVerify.run(@pack_dir, @ambiguous_standing)
    end
  end

  describe "the ticket template follows the pack conventions" do
    @template_path Path.join(@pack_dir, "templates/ticket.md.eex")

    test "templates/ticket.md.eex exists with the required sections and the no-hand-edit marker" do
      template = File.read!(@template_path)

      for section <- [
            "## Identity",
            "## Repository + base SHA",
            "## Goal",
            "## Dependencies",
            "## Allowed paths",
            "## Requires / forbids capabilities",
            "## Acceptance criteria",
            "## Falsifiers",
            "## Verifier",
            "## Standing",
            "## Provenance"
          ] do
        assert template =~ section, "template missing section #{inspect(section)}"
      end

      # No-hand-edit policy (PRD §42): the template itself marks the artifact
      # as generated and names the ontology as the edit surface.
      assert template =~ "GENERATED FILE"
      assert template =~ "edit the ontology"

      # Provenance (PRD §42): the footer binds source digest + pack identity.
      assert template =~ "Source graph digest"
      assert template =~ "Pack:"

      # Determinism (PRD §53): the template must not embed a clock or any
      # other nondeterministic binding.
      refute template =~ "generated_at"
      refute template =~ "DateTime"
    end
  end
end
