defmodule GgenIgniter.SemanticJiraAuthorityTest do
  @moduledoc """
  Chicago-style proof for the semantic-jira-pack origin-authority admission
  layer (`GgenIgniter.SemanticJira.Authority`).

  The SHACL court (see `GgenIgniter.SemanticJiraShaclTest`) sees types and
  shapes only; it cannot distinguish an admitted strategic objective from a
  fresh self-declared one whose digest merely matches ^sha256:[0-9a-f]{64}$.
  This file executes the second law: `admission_digest/2` over the exact
  canonical node, the `admit/2` stamp and its idempotency, and
  `verify_origin/3`, which refuses what the court admits.

  The replay-gate test recomputes each committed objective witness from the
  ontology graph: a stale digest (the objective's text edited without
  re-stamping) or a self-declared placeholder fails here -- deliberately: a
  green suite on an unverified witness would manufacture a standing.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.Digest
  alias GgenIgniter.Ontology
  alias GgenIgniter.SemanticJira.Authority
  alias GgenIgniter.SemanticJira.Shacl

  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @shapes_path "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
  @sj_base "https://ggen-igniter.dev/ontology/semantic-jira#"
  @dcterms_base "http://purl.org/dc/terms/"
  @digest_predicate @sj_base <> "admissionDigest"
  @code_work_authority @sj_base <> "objective-code-work-authority"

  @objective_iris [
    @sj_base <> "objective-semantic-jira-mvp",
    @sj_base <> "objective-project-manufacturer",
    @code_work_authority
  ]

  describe "admission_digest/2" do
    test "is deterministic over the same graph and IRI and matches the sha256 shape" do
      graph = fixture_objective_graph()
      iri = fixture_iri()

      d1 = Authority.admission_digest(graph, iri)
      d2 = Authority.admission_digest(graph, iri)

      assert d1 == d2
      assert d1 =~ ~r/^sha256:[0-9a-f]{64}$/
    end

    test "the exclusion law: stated sj:admissionDigest literals never enter the digest" do
      graph = fixture_objective_graph()
      iri = fixture_iri()
      pristine = Authority.admission_digest(graph, iri)

      with_one =
        graph
        |> RDF.Graph.add(
          {RDF.iri(iri), RDF.iri(@digest_predicate), RDF.literal(well_formed_digest("1"))}
        )
        |> Authority.admission_digest(iri)

      with_two =
        graph
        |> RDF.Graph.add(
          {RDF.iri(iri), RDF.iri(@digest_predicate), RDF.literal(well_formed_digest("1"))}
        )
        |> RDF.Graph.add(
          {RDF.iri(iri), RDF.iri(@digest_predicate), RDF.literal(well_formed_digest("2"))}
        )
        |> Authority.admission_digest(iri)

      assert with_one == pristine
      assert with_two == pristine
    end

    test "content sensitivity: changing the node's dcterms:description changes the digest" do
      graph = fixture_objective_graph()
      iri = fixture_iri()
      pristine = Authority.admission_digest(graph, iri)

      changed =
        graph
        |> delete_predicates_about(RDF.iri(iri), RDF.iri(@dcterms_base <> "description"))
        |> RDF.Graph.add(
          {RDF.iri(iri), RDF.iri(@dcterms_base <> "description"),
           RDF.literal("A changed description; the digest must move.")}
        )
        |> Authority.admission_digest(iri)

      refute changed == pristine
    end
  end

  describe "replay gate" do
    test "each pinned objective's stated digest matches the pattern AND the recomputed digest" do
      graph = Ontology.load!(@ontology_path)

      for iri_string <- @objective_iris do
        objective = RDF.Graph.get(graph, RDF.iri(iri_string))

        assert objective,
               "#{iri_string} absent from #{@ontology_path}: the objective facts have not landed"

        stated =
          objective
          |> RDF.Description.first(RDF.iri(@digest_predicate))
          |> literal_value()

        placeholder_message =
          "#{iri_string}: sha256:PENDING-SJ-002 placeholder is a self-declared digest -- run Authority.admit/2 over the ontology before merge"

        assert stated =~ ~r/^sha256:[0-9a-f]{64}$/, placeholder_message

        assert Authority.admission_digest(graph, iri_string) == stated, placeholder_message
      end
    end
  end

  describe "admit/2" do
    test "stamps the real ontology and returns a report of every pinned objective digest" do
      graph = Ontology.load!(@ontology_path)

      assert {:ok, stamped, report} = Authority.admit(graph)

      for iri_string <- @objective_iris do
        precomputed = Authority.admission_digest(graph, iri_string)
        assert Map.fetch!(report, iri_string) == precomputed

        stamped_digests =
          stamped
          |> RDF.Graph.get(RDF.iri(iri_string))
          |> RDF.Description.get(RDF.iri(@digest_predicate), [])
          |> Enum.map(&literal_value/1)

        assert stamped_digests == [precomputed]
      end
    end

    test "admit over an already-stamped graph is idempotent (byte-identical N-Triples)" do
      graph = Ontology.load!(@ontology_path)

      assert {:ok, stamped, _report} = Authority.admit(graph)
      assert {:ok, restamped, _report2} = Authority.admit(stamped)

      assert ntriples_lines(stamped) == ntriples_lines(restamped)
    end
  end

  describe "verify_origin/3" do
    test "accepts SJ-002 when the candidate restates no objective (order names origin; no restatement)" do
      # Every objective digest is stripped, and the origin node carries no
      # description at all: the order names its origin as an IRI and restates
      # nothing about it, so canonical stands. (A candidate that KEEPS the
      # origin node but strips its digest set is a different case -- a
      # restatement contradicting canonical -- and is refused as
      # authority_digest_mismatch; the forged-restatement test below pins that.)
      canonical = Ontology.load!(@ontology_path)
      sj002 = sjira_002_iri!(canonical)

      candidate =
        @objective_iris
        |> Enum.reduce(canonical, fn iri_string, acc ->
          strip_admission_digest(acc, iri_string)
        end)
        |> RDF.Graph.delete_descriptions([RDF.iri(@code_work_authority)])

      assert :ok = Authority.verify_origin(candidate, canonical, RDF.IRI.to_string(sj002))
    end

    test "accepts SJ-002 against the canonical graph verbatim" do
      canonical = Ontology.load!(@ontology_path)
      sj002 = sjira_002_iri!(canonical)

      assert :ok = Authority.verify_origin(canonical, canonical, RDF.IRI.to_string(sj002))
    end

    test "refuses a fresh self-declared objective with a forged digest" do
      canonical = Ontology.load!(@ontology_path)
      sj002 = sjira_002_iri!(canonical)
      rogue = @sj_base <> "rogue-self-declared-objective"

      candidate =
        canonical
        |> set_origin_authority(sj002, RDF.iri(rogue))
        |> RDF.Graph.add({RDF.iri(rogue), RDF.type(), RDF.iri(@sj_base <> "StrategicObjective")})
        |> RDF.Graph.add(
          {RDF.iri(rogue), RDF.iri(@digest_predicate), forged_digest_literal("rogue")}
        )

      assert {:error, {:refused_origin, {:authority_not_admitted, ^rogue}}} =
               Authority.verify_origin(candidate, canonical, RDF.IRI.to_string(sj002))
    end

    test "refuses a forged digest restated on the canonical code-work-authority IRI" do
      canonical = Ontology.load!(@ontology_path)
      sj002 = sjira_002_iri!(canonical)
      forged = "sha256:" <> Digest.hex("forged restatement on the canonical IRI")

      candidate = replace_admission_digest(canonical, @code_work_authority, forged)

      assert {:error, {:refused_origin, {:authority_digest_mismatch, @code_work_authority}}} =
               Authority.verify_origin(candidate, canonical, RDF.IRI.to_string(sj002))
    end
  end

  describe "the centerpiece falsifier — typed is not admitted" do
    test "a typed, well-formed rogue passes the SHACL court and is still refused by verify_origin/3" do
      canonical = Ontology.load!(@ontology_path)
      shapes = Ontology.load!(@shapes_path)
      sj002 = sjira_002_iri!(canonical)
      rogue = @sj_base <> "rogue-typed-not-admitted"

      candidate =
        canonical
        |> set_origin_authority(sj002, RDF.iri(rogue))
        |> RDF.Graph.add({RDF.iri(rogue), RDF.type(), RDF.iri(@sj_base <> "StrategicObjective")})
        |> RDF.Graph.add(
          {RDF.iri(rogue), RDF.iri("http://www.w3.org/2000/01/rdf-schema#label"),
           RDF.literal("Rogue objective")}
        )
        |> RDF.Graph.add(
          {RDF.iri(rogue), RDF.iri(@digest_predicate), forged_digest_literal("centerpiece rogue")}
        )

      # The court sees types and shapes, never admission history: the rogue is
      # a typed strategic objective carrying a well-formed digest, so every
      # shape admits it and SJ-002's origin reference resolves cleanly.
      report = Shacl.validate(candidate, shapes)

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"

      # The admission layer closes the hole the court cannot see: the rogue
      # IRI was never admitted, so its self-declared digest carries no weight.
      assert {:error, {:refused_origin, {:authority_not_admitted, ^rogue}}} =
               Authority.verify_origin(candidate, canonical, RDF.IRI.to_string(sj002))
    end
  end

  ## Helpers

  # Minimal inline fixture: one typed objective with label and description,
  # no stated digest -- digest laws must not depend on one.
  defp fixture_objective_graph do
    RDF.Turtle.read_string!("""
    @prefix sj: <#{@sj_base}> .
    @prefix dcterms: <#{@dcterms_base}> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

    sj:objective-fixture a sj:StrategicObjective ;
        rdfs:label "Fixture strategic objective" ;
        dcterms:description "A minimal inline objective for the digest laws; nothing here is admitted." .
    """)
  end

  defp fixture_iri, do: @sj_base <> "objective-fixture"

  defp well_formed_digest(hex_char), do: "sha256:" <> String.duplicate(hex_char, 64)

  defp forged_digest_literal(context) do
    RDF.literal("sha256:" <> Digest.hex("forged: " <> context))
  end

  # Resolves SJ-002 by dcterms:identifier, never by IRI: the order's IRI is a
  # projection detail, its identifier is the contract.
  defp sjira_002_iri!(graph) do
    found =
      graph
      |> RDF.Graph.descriptions()
      |> Enum.find_value(fn description ->
        case RDF.Description.first(description, RDF.iri(@dcterms_base <> "identifier")) do
          %RDF.Literal{} = identifier ->
            if RDF.Term.equal?(identifier, RDF.literal("SJ-002")), do: description.subject

          _other ->
            nil
        end
      end)

    found || flunk("no WorkOrder carries dcterms:identifier \"SJ-002\" in #{@ontology_path}")
  end

  defp set_origin_authority(graph, subject, origin_iri) do
    graph
    |> delete_predicates_about(subject, RDF.iri(@sj_base <> "originAuthority"))
    |> RDF.Graph.add({subject, RDF.iri(@sj_base <> "originAuthority"), origin_iri})
  end

  defp strip_admission_digest(graph, iri_string) do
    delete_predicates_about(graph, RDF.iri(iri_string), RDF.iri(@digest_predicate))
  end

  defp replace_admission_digest(graph, iri_string, digest) do
    graph
    |> strip_admission_digest(iri_string)
    |> RDF.Graph.add({RDF.iri(iri_string), RDF.iri(@digest_predicate), RDF.literal(digest)})
  end

  defp delete_predicates_about(graph, subject, predicate) do
    case RDF.Graph.get(graph, subject) do
      nil ->
        graph

      description ->
        graph
        |> RDF.Graph.delete_descriptions([subject])
        |> RDF.Graph.add(RDF.Description.delete_predicates(description, predicate))
    end
  end

  defp ntriples_lines(%RDF.Graph{} = graph) do
    graph
    |> RDF.NTriples.write_string!()
    |> String.split("\n", trim: true)
    |> Enum.sort()
  end

  defp literal_value(nil), do: nil
  defp literal_value(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  defp literal_value(other), do: other
end
