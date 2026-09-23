defmodule GgenIgniter.SemanticJiraVocabularyTest do
  @moduledoc """
  Chicago-style proof for the v26.9.19 vocabulary reduction (W7-A4): the
  work/change/provenance core of semantic-jira-pack is carried in PUBLIC
  vocabularies (OSLC CM 3.0, dcterms, PROV-O) and `sj:` is retained only as
  documented residue (`priv/ggen/semantic-jira-pack/VOCABULARY.md`).

  Every test executes the real RDF loader, the real gate queries through the
  real engine path, the real SHACL admission court, and the real kernel —
  no fixture stubbing, no subprocesses (the full sync path over the
  canonical graph is proven by the pack suite; this suite pins the
  vocabulary deltas in-process).

  The three graph forms proven equivalent here:

    * DUAL (the canonical graph): carried facts asserted in BOTH vocabularies;
    * PUBLIC-ONLY: carried facts asserted ONLY via public terms
      (`oslc_cm:ChangeRequest` / `prov:Activity` / `prov:Entity` typings and
      the PROV relations) — the proof the reduction is real;
    * LEGACY sj-ONLY: carried public assertions stripped — the proof the
      pre-reduction form admits unchanged.

  Engine note: the admitted sparql engine (0.3.12) parses EXISTS/NOT EXISTS
  filter forms to an unsupported expression (see Shacl's moduledoc), so the
  absence checks below use the same OPTIONAL + FILTER(!BOUND()) idiom the
  shipped shapes and gates use.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.{Crown, Ontology, Query, SemanticJira}
  alias GgenIgniter.SemanticJira.Shacl

  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @shapes_path "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
  @vocab_path "priv/ggen/semantic-jira-pack/VOCABULARY.md"
  @pack_dir "priv/ggen/semantic-jira-pack"
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @oslc_cm "http://open-services.net/ns/cm#"
  @prov "http://www.w3.org/ns/prov#"
  @dcterms "http://purl.org/dc/terms/"

  # Gate queries whose row sets must be IDENTICAL across the dual, public-only,
  # and legacy graph forms (the dual-path admission surface).
  @dual_path_gates ~w(010_work_order_subjects 020_work_orders 046_alive_receipt_crown 050_frontier 055_standing_projection)

  # ── Graph-form helpers ──────────────────────────────────────────────────

  defp canonical_graph, do: Ontology.load!(@ontology_path)

  defp canonical_shapes, do: Ontology.load!(@shapes_path)

  # Deletes every triple with predicate `predicate` (rdf 3.0.1 has no
  # predicate-wide graph delete; per-description object-wise deletion only).
  defp strip_predicate(graph, predicate) do
    Enum.reduce(RDF.Graph.descriptions(graph), graph, fn description, acc ->
      objects = RDF.Description.get(description, predicate, [])

      Enum.reduce(objects, acc, fn object, acc2 ->
        RDF.Graph.delete(acc2, {description.subject, predicate, object})
      end)
    end)
  end

  # Deletes every `?s a class` typing triple (rdf 3.0.1 has no graph-wide
  # delete by object; per-subject deletion only).
  defp strip_type(graph, class) do
    graph
    |> RDF.Graph.descriptions()
    |> Enum.filter(&(class in RDF.Description.get(&1, RDF.type(), [])))
    |> Enum.reduce(graph, fn description, acc ->
      RDF.Graph.delete(acc, {description.subject, RDF.type(), class})
    end)
  end

  defp iri(term) when is_binary(term), do: RDF.iri(term)

  # The PUBLIC-ONLY form: carried CLASS typings asserted only via the public
  # term. Residue predicates (sj:standing, sj:transitionId, ...) stay — they
  # are the documented residue, not carried facts.
  defp public_only_graph do
    canonical_graph()
    |> strip_type(iri(@sj <> "WorkOrder"))
    |> strip_type(iri(@sj <> "StandingTransition"))
    |> strip_type(iri(@sj <> "Receipt"))
  end

  # The LEGACY sj-ONLY form: the canonical graph with every carried public
  # assertion stripped (derived from CANONICAL, not from the public-only form,
  # so the work orders keep their sj:WorkOrder typing).
  defp legacy_graph do
    transition_events =
      Query.run(canonical_graph(), """
      PREFIX sj: <#{@sj}>
      SELECT ?event WHERE { ?event sj:transitionId ?id }
      """)
      |> Enum.map(& &1["event"])

    canonical_graph()
    |> strip_type(iri(@oslc_cm <> "ChangeRequest"))
    |> strip_type(iri(@prov <> "Activity"))
    |> strip_type(iri(@prov <> "Entity"))
    |> strip_predicate(iri(@prov <> "used"))
    |> strip_predicate(iri(@prov <> "wasAssociatedWith"))
    |> strip_predicate(iri(@prov <> "wasGeneratedBy"))
    |> strip_dcterms_title_on(transition_events)
    |> strip_predicate_on(iri(@sj <> "receipt-crown-001"), iri(@dcterms <> "title"))
  end

  defp strip_dcterms_title_on(graph, subject_iris) do
    Enum.reduce(subject_iris, graph, fn subject, acc ->
      strip_predicate_on(acc, iri(subject), iri(@dcterms <> "title"))
    end)
  end

  defp strip_predicate_on(graph, subject, predicate) do
    case RDF.Graph.get(graph, subject) do
      nil ->
        graph

      description ->
        RDF.Description.get(description, predicate, [])
        |> Enum.reduce(graph, fn object, acc ->
          RDF.Graph.delete(acc, {subject, predicate, object})
        end)
    end
  end

  defp run_gate(graph, name),
    do: Query.run(graph, File.read!(Path.join(@pack_dir, "gates/#{name}.rq")))

  # Adds one triple to a copy of `graph`. rdf 3.0.1's Graph.put/2 with a
  # triple REPLACES the subject's whole description (measured: gall-001 went
  # from 41 triples to 1), so the smuggling tests add, they never put.
  defp add_triple(graph, triple), do: RDF.Graph.add(graph, triple)

  # Row sets normalized to plain values so the same query result from two
  # graph forms compares equal regardless of row ordering.
  defp normalize_rows(rows) do
    rows
    |> Enum.map(fn row -> row |> Map.new(fn {k, v} -> {k, stringify(v)} end) |> Map.to_list() end)
    |> Enum.map(&Enum.sort/1)
    |> Enum.sort()
  end

  defp stringify(value) do
    cond do
      is_struct(value, RDF.IRI) -> RDF.IRI.to_string(value)
      is_struct(value, RDF.Literal) -> RDF.Literal.value(value) |> to_string()
      is_atom(value) -> Atom.to_string(value)
      true -> to_string(value)
    end
  end

  # ── VOCABULARY.md parsing ───────────────────────────────────────────────

  defp vocabulary_section(doc, header) do
    doc
    |> String.split(header, parts: 2)
    |> List.last()
    |> String.split("\n## ")
    |> List.first()
  end

  # Every `sj:NAME` term named in a VOCABULARY.md section, prefixed to match
  # the graph-side term names.
  defp vocabulary_terms(doc, header) do
    doc
    |> vocabulary_section(header)
    |> then(&Regex.scan(~r/sj:([A-Za-z][A-Za-z0-9-]*)/, &1))
    |> Enum.map(&("sj:" <> List.last(&1)))
    |> MapSet.new()
  end

  defp iri_local(term) do
    string =
      cond do
        is_struct(term, RDF.IRI) -> RDF.IRI.to_string(term)
        is_atom(term) -> Atom.to_string(term)
        true -> to_string(term)
      end

    # String.split drops the "#" separator, so the namespace element is the
    # namespace WITHOUT the trailing hash.
    case String.split(string, "#", parts: 2) do
      ["https://ggen-igniter.dev/ontology/semantic-jira", local] -> "sj:" <> local
      _ -> string
    end
  end

  # ── Dual-typing law ────────────────────────────────────────────────────

  describe "the canonical graph dual-asserts the public carry" do
    test "every work order is dual-typed oslc_cm:ChangeRequest" do
      missing =
        Query.run(canonical_graph(), """
        PREFIX sj: <#{@sj}>
        PREFIX oslc_cm: <#{@oslc_cm}>
        SELECT ?wo WHERE {
          ?wo a sj:WorkOrder .
          OPTIONAL {
            ?wo a ?cmType .
            FILTER(?cmType = oslc_cm:ChangeRequest)
          }
          FILTER(!BOUND(?cmType))
        }
        """)

      assert missing == [],
             "work orders missing the oslc_cm:ChangeRequest carry: #{inspect(missing)}"
    end

    test "every StandingTransition is dual-typed prov:Activity with prov:used mirroring sj:transitionEvidence" do
      graph = canonical_graph()

      untyped =
        Query.run(graph, """
        PREFIX sj: <#{@sj}>
        PREFIX prov: <#{@prov}>
        SELECT ?event WHERE {
          ?event sj:transitionId ?id .
          OPTIONAL {
            ?event a ?activityType .
            FILTER(?activityType = prov:Activity)
          }
          FILTER(!BOUND(?activityType))
        }
        """)

      assert untyped == [], "transitions missing the prov:Activity carry: #{inspect(untyped)}"

      unmirrored =
        Query.run(graph, """
        PREFIX sj: <#{@sj}>
        PREFIX prov: <#{@prov}>
        SELECT ?event ?receipt WHERE {
          ?event sj:transitionEvidence ?receipt .
          OPTIONAL { ?event prov:used ?public . }
          FILTER(!BOUND(?public) || ?public != ?receipt)
        }
        """)

      assert unmirrored == [],
             "transitions where prov:used does not mirror sj:transitionEvidence: #{inspect(unmirrored)}"

      # Carried facts travel together: prov:used targets are prov:Entity.
      untyped_targets =
        Query.run(graph, """
        PREFIX sj: <#{@sj}>
        PREFIX prov: <#{@prov}>
        SELECT ?event WHERE {
          ?event prov:used ?target .
          OPTIONAL {
            ?target a ?entityType .
            FILTER(?entityType = prov:Entity)
          }
          FILTER(!BOUND(?entityType))
        }
        """)

      assert untyped_targets == [],
             "prov:used targets missing the prov:Entity typing: #{inspect(untyped_targets)}"
    end

    test "every Receipt is dual-typed prov:Entity, generated by a prov:Activity run" do
      graph = canonical_graph()

      untyped =
        Query.run(graph, """
        PREFIX sj: <#{@sj}>
        PREFIX prov: <#{@prov}>
        SELECT ?receipt WHERE {
          ?receipt a sj:Receipt .
          OPTIONAL {
            ?receipt a ?entityType .
            FILTER(?entityType = prov:Entity)
          }
          FILTER(!BOUND(?entityType))
        }
        """)

      assert untyped == [], "receipts missing the prov:Entity carry: #{inspect(untyped)}"

      ungenerated =
        Query.run(graph, """
        PREFIX sj: <#{@sj}>
        PREFIX prov: <#{@prov}>
        SELECT ?receipt WHERE {
          ?receipt a sj:Receipt .
          OPTIONAL {
            ?receipt prov:wasGeneratedBy ?run .
            ?run a ?runType .
            FILTER(?runType = prov:Activity)
          }
          FILTER(!BOUND(?run))
        }
        """)

      assert ungenerated == [],
             "receipts without a prov:wasGeneratedBy prov:Activity: #{inspect(ungenerated)}"
    end

    test "the reconciler and worker agents are prov:SoftwareAgent under the public subclass axiom" do
      agents =
        Query.run(canonical_graph(), """
        PREFIX prov: <#{@prov}>
        PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
        SELECT ?agent WHERE {
          ?agent a prov:SoftwareAgent .
          prov:SoftwareAgent rdfs:subClassOf prov:Agent .
        }
        """)

      assert length(agents) >= 2
    end
  end

  describe "the real SHACL court admits the dual graph" do
    test "the canonical graph conforms to the dual-path shapes" do
      report = Shacl.validate(canonical_graph(), canonical_shapes())

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
    end
  end

  # ── Public-only form: the reduction is real ─────────────────────────────

  describe "a PUBLIC-ONLY graph (carried facts asserted only via public terms) admits" do
    test "the public-only graph conforms to the same shapes" do
      public_only = public_only_graph()

      # Sanity: the sj: carry really is stripped.
      assert Query.run(public_only, """
             PREFIX sj: <#{@sj}>
             SELECT ?s WHERE { ?s a sj:WorkOrder }
             """) == []

      # And the public typing really is carried, on the full work-order set.
      carried =
        Query.run(public_only, """
        PREFIX oslc_cm: <#{@oslc_cm}>
        SELECT ?s WHERE { ?s a oslc_cm:ChangeRequest }
        """)

      assert length(carried) >= 33

      report = Shacl.validate(public_only, canonical_shapes())

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
    end

    test "every dual-path gate returns the same rows over the public-only graph" do
      public_only = public_only_graph()

      for gate_name <- @dual_path_gates do
        assert normalize_rows(run_gate(public_only, gate_name)) ==
                 normalize_rows(run_gate(canonical_graph(), gate_name)),
               "gate #{gate_name} diverges between the dual and public-only graphs"
      end
    end

    test "the transition law still targets public-only events through the sj:transitionId residue anchor" do
      # Delete one event's toStanding in the public-only form: the
      # targetSubjectsOf targeting must still catch it (minCount violation),
      # proving the transition law is not loosened when the sj: type is gone.
      broken =
        public_only_graph()
        |> strip_predicate_on(iri(@sj <> "transition-94bce0c9"), iri(@sj <> "toStanding"))

      report = Shacl.validate(broken, canonical_shapes())
      refute report.conforms, "a public-only event missing toStanding must refuse"

      assert Enum.any?(report.violations, fn violation ->
               violation.focus_node =~ "transition-94bce0c9" and
                 violation.constraint == :min_count
             end)
    end
  end

  # ── Legacy sj-only form: no regression ──────────────────────────────────

  describe "a LEGACY sj-only graph (carried public assertions stripped) admits unchanged" do
    test "the legacy graph conforms to the same shapes" do
      legacy = legacy_graph()

      assert Query.run(legacy, """
             PREFIX oslc_cm: <#{@oslc_cm}>
             PREFIX prov: <#{@prov}>
             SELECT ?s WHERE {
               { ?s a oslc_cm:ChangeRequest }
               UNION
               { ?s a prov:Activity }
               UNION
               { ?s a prov:Entity }
             }
             """) == []

      report = Shacl.validate(legacy, canonical_shapes())

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
    end

    test "every dual-path gate returns the same rows over the legacy graph" do
      legacy = legacy_graph()

      for gate_name <- @dual_path_gates do
        assert normalize_rows(run_gate(legacy, gate_name)) ==
                 normalize_rows(run_gate(canonical_graph(), gate_name)),
               "gate #{gate_name} diverges between the dual and legacy graphs"
      end
    end
  end

  # ── Digest stability under dual-assertion ───────────────────────────────

  describe "the definition digest is stable under dual-assertion" do
    test "graph-level: extraction from dual, public-only, and legacy graphs yields IDENTICAL definition digests" do
      {:ok, dual} = Crown.extract_work_orders(@ontology_path)

      assert map_size(dual) >= 33

      for {graph, tag} <- [{public_only_graph(), "public-only"}, {legacy_graph(), "legacy"}] do
        path =
          Path.join(System.tmp_dir!(), "vocab-#{tag}-#{System.unique_integer([:positive])}.ttl")

        File.write!(path, RDF.Turtle.write_string!(graph))
        on_exit(fn -> File.rm(path) end)

        {:ok, extracted} = Crown.extract_work_orders(path)

        assert Map.new(extracted, fn {id, wo} -> {id, wo["definition_digest"]} end) ==
                 Map.new(dual, fn {id, wo} -> {id, wo["definition_digest"]} end),
               "#{tag} graph extraction changed definition digests"
      end
    end

    test "graph-level: a residue/identity fact change still moves the definition digest" do
      {:ok, dual} = Crown.extract_work_orders(@ontology_path)

      # Flip a fact the definition field-set OWNS (the title) in the
      # public-only form: the digest must move exactly as the kernel dictates.
      mutated_title_graph =
        replace_literal(public_only_graph(), @sj <> "gall-001", @dcterms <> "title")

      path =
        Path.join(System.tmp_dir!(), "vocab-mutated-#{System.unique_integer([:positive])}.ttl")

      File.write!(path, RDF.Turtle.write_string!(mutated_title_graph))
      on_exit(fn -> File.rm(path) end)

      {:ok, mutated} = Crown.extract_work_orders(path)

      refute mutated["GALL-001"]["definition_digest"] == dual["GALL-001"]["definition_digest"],
             "changing an identity fact must move the definition digest"

      # ...while the untouched siblings stay byte-identical.
      assert mutated["GALL-002"]["definition_digest"] == dual["GALL-002"]["definition_digest"]
    end

    test "kernel-level: public dual-assertion fields cannot enter the closed @definition_fields take" do
      work_order = %{
        "identity" => "SJ-VOCAB-001",
        "title" => "Vocabulary reduction probe",
        "description" => "Closed-take digest proof.",
        "subject" => "urn:subject:vocab",
        "repository" => "seanchatmangpt/ggen_igniter",
        "base_sha" => String.duplicate("a", 40),
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:vocab:1",
        "dependencies" => [],
        "required_courts" => ["court:test"],
        "required_evidence" => ["source"],
        "acceptance" => ["acceptance:test"],
        "falsifiers" => ["falsifier:test"],
        "projections" => ["jira"],
        "path_scope" => ["priv/ggen/semantic-jira-pack"]
      }

      {:ok, admitted} = SemanticJira.admit_work_order(work_order)

      # The exact public carry, as extra fields a graph extraction could
      # hypothetically hand the kernel: they must not move the digest.
      public_fields = %{
        "rdf_type_oslc_cm" => "oslc_cm:ChangeRequest",
        "prov_used" => "urn:receipt:1",
        "prov_was_associated_with" => "sj:reconciler-agent",
        "prov_was_generated_by" => "sj:fabric-run-1"
      }

      {:ok, with_public} = SemanticJira.admit_work_order(Map.merge(work_order, public_fields))

      assert with_public["definition_digest"] == admitted["definition_digest"]

      # ...while a field the definition OWNS moves it.
      {:ok, with_new_title} =
        SemanticJira.admit_work_order(%{work_order | "title" => "Different definition"})

      refute with_new_title["definition_digest"] == admitted["definition_digest"]
    end
  end

  # Replaces the single dcterms:title literal on a subject with a changed one.
  defp replace_literal(graph, subject_iri, predicate_ns_with_local) do
    subject = iri(subject_iri)
    predicate = iri(predicate_ns_with_local)
    description = RDF.Graph.get(graph, subject)

    RDF.Description.get(description, predicate, [])
    |> Enum.reduce(graph, fn object, acc ->
      acc
      |> RDF.Graph.delete({subject, predicate, object})
      |> RDF.Graph.put({
        subject,
        predicate,
        RDF.literal("CHANGED " <> (RDF.Literal.value(object) || ""))
      })
    end)
  end

  # ── Residue list == VOCABULARY.md ───────────────────────────────────────

  describe "the residue list matches VOCABULARY.md in both directions" do
    test "every sj: term the canonical graph uses is either carried or documented residue" do
      graph = canonical_graph()

      used_predicates =
        graph
        |> RDF.Graph.descriptions()
        |> Enum.flat_map(&RDF.Description.predicates/1)
        |> Enum.map(&iri_local/1)
        |> Enum.filter(&String.starts_with?(&1, "sj:"))
        |> MapSet.new()

      used_classes =
        Query.run(graph, """
        PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
        SELECT DISTINCT ?class WHERE { ?s rdf:type ?class . FILTER(isIRI(?class)) }
        """)
        |> Enum.map(& &1["class"])
        |> Enum.map(&iri_local/1)
        |> Enum.filter(&String.starts_with?(&1, "sj:"))
        |> MapSet.new()

      doc = File.read!(@vocab_path)
      carried = vocabulary_terms(doc, "## Carried (dual-asserted)")
      residue = vocabulary_terms(doc, "## Residue (sj:-only)")

      # The carried set the mapping documents must be exactly the carried set
      # the graph asserts (the three class typings plus the
      # sj:transitionEvidence -> prov:used mirror; the additive prov: nodes
      # have no sj: counterpart to list).
      graph_carried =
        MapSet.new([
          "sj:WorkOrder",
          "sj:StandingTransition",
          "sj:Receipt",
          "sj:transitionEvidence"
        ])

      assert carried == graph_carried,
             "carried drift: documented=#{inspect(MapSet.to_list(carried))} graph=#{inspect(MapSet.to_list(graph_carried))}"

      graph_residue =
        MapSet.union(used_predicates, used_classes)
        # The carried terms are used as classes/predicates too; they are
        # accounted for by the carried assertion above, not residue.
        |> MapSet.difference(carried)

      undocumented = MapSet.difference(graph_residue, residue)

      assert MapSet.size(undocumented) == 0,
             "undocumented residue (sj: terms the graph uses that VOCABULARY.md does not document): #{inspect(MapSet.to_list(undocumented))}"

      # Every sj: term the residue section names must exist in the graph OR be
      # declared vocabulary in the ontology (declared-but-unused classes are
      # lawful fabric; fabricated documentation is not).
      declared =
        graph
        |> RDF.Graph.descriptions()
        |> Enum.map(& &1.subject)
        |> Enum.map(&iri_local/1)
        |> MapSet.new()

      phantom =
        residue
        |> MapSet.difference(graph_residue)
        |> MapSet.difference(declared)
        |> MapSet.to_list()

      assert phantom == [],
             "phantom residue (named in VOCABULARY.md but neither used nor declared): #{inspect(phantom)}"
    end
  end

  # ── The closed-shape law is not loosened by the public carry ────────────

  describe "closed-shape smuggling still refuses with the public typings present" do
    test "an undeclared predicate on a dual-typed work order violates sh:closed" do
      smuggler =
        add_triple(
          canonical_graph(),
          {iri(@sj <> "gall-001"), iri(@sj <> "smuggledPredicate"), RDF.literal("smuggled")}
        )

      report = Shacl.validate(smuggler, canonical_shapes())
      refute report.conforms

      assert Enum.any?(report.violations, fn violation ->
               violation.focus_node =~ "gall-001" and violation.constraint == :closed
             end)
    end

    test "prov:used pointing at an untyped node violates the carried-facts-travel-together law" do
      smuggler =
        add_triple(
          canonical_graph(),
          {iri(@sj <> "transition-94bce0c9"), iri(@prov <> "used"),
           iri(@sj <> "untyped-smuggled-entity")}
        )

      report = Shacl.validate(smuggler, canonical_shapes())
      refute report.conforms

      assert Enum.any?(report.violations, fn violation ->
               violation.focus_node =~ "transition-94bce0c9" and violation.constraint == :class
             end)
    end

    test "prov:wasGeneratedBy pointing at a non-Activity violates ReceiptShape" do
      smuggler =
        add_triple(
          canonical_graph(),
          {iri(@sj <> "receipt-crown-001"), iri(@prov <> "wasGeneratedBy"),
           iri(@sj <> "untyped-smuggled-run")}
        )

      report = Shacl.validate(smuggler, canonical_shapes())
      refute report.conforms

      assert Enum.any?(report.violations, fn violation ->
               violation.focus_node =~ "receipt-crown-001" and violation.constraint == :class
             end)
    end
  end
end
