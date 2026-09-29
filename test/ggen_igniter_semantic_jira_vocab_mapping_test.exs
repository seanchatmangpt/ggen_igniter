defmodule GgenIgniter.SemanticJiraVocabMappingTest do
  @moduledoc """
  Chicago-style proof for ADR-011 step 4 (additive sj: -> public mappings).

  Real ontology file, real shapes file, real SHACL validator; assertions are
  on the resulting graph and validation-report state. Nothing is stubbed.

  Falsifier (ADR-011): a mapped term whose semantics diverge from the public
  term MUST NOT be asserted. The reject list below pins the candidates
  recorded in VOCABULARY.md "ADR-011 step 4 mappings".
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Ontology
  alias GgenIgniter.SemanticJira.Shacl

  @pack "priv/ggen/semantic-jira-pack"
  @ontology "#{@pack}/ontology.ttl"
  @shapes_dir "#{@pack}/shapes"
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @oslc_cm "http://open-services.net/ns/cm#"
  @prov "http://www.w3.org/ns/prov#"
  @dcterms "http://purl.org/dc/terms/"
  @sub_class "http://www.w3.org/2000/01/rdf-schema#subClassOf"
  @sub_prop "http://www.w3.org/2000/01/rdf-schema#subPropertyOf"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @sh_target_class "http://www.w3.org/ns/shacl#targetClass"

  @public_ns [@oslc_cm, @prov, @dcterms]

  # The complete asserted set: sj: term => public term.
  @mapped [
    {@sj <> "WorkOrder", @oslc_cm <> "ChangeRequest"},
    {@sj <> "Receipt", @prov <> "Entity"}
  ]

  # Candidates rejected with a recorded reason (VOCABULARY.md): each must be absent.
  @rejected [
    {@sj <> "StandingTransition", @prov <> "Activity"},
    {@sj <> "ProseObservation", @prov <> "Entity"},
    {@sj <> "EvidenceRequirement", @prov <> "Entity"},
    {@sj <> "Action", @prov <> "Plan"},
    {@sj <> "ProjectionSpec", @prov <> "Plan"},
    {@sj <> "CodeWorkAuthority", @prov <> "Agent"},
    {@sj <> "PreparedAuthorityReceipt", @prov <> "Entity"},
    {@sj <> "Checkpoint", @prov <> "Entity"}
  ]

  @rejected_props [
    {@sj <> "replayIdentity", @dcterms <> "identifier"},
    {@sj <> "subject", @dcterms <> "subject"},
    {@sj <> "dependsOn", @oslc_cm <> "relatedChangeRequest"},
    {@sj <> "receipt", @prov <> "wasInfluencedBy"},
    {@sj <> "originObservation", @prov <> "wasDerivedFrom"},
    {@sj <> "originAuthority", @prov <> "wasAttributedTo"}
  ]

  defp triples(graph),
    do: for({s, p, o} <- RDF.Graph.triples(graph), do: {to_string(s), to_string(p), to_string(o)})

  defp graph, do: Ontology.load!(@ontology)

  defp shapes_graphs, do: for(f <- Path.wildcard("#{@shapes_dir}/*.ttl"), do: Ontology.load!(f))

  test "the two argued mappings are asserted in the pack ontology" do
    ts = triples(graph())

    for {sj, public} <- @mapped do
      assert {sj, @sub_class, public} in ts, "missing #{sj} subClassOf #{public}"
    end
  end

  test "falsifier: divergent-semantics candidates are NOT asserted" do
    ts = triples(graph())

    for {sj, public} <- @rejected,
        do:
          refute({sj, @sub_class, public} in ts, "divergent mapping asserted: #{sj} -> #{public}")

    for {sj, public} <- @rejected_props,
        do:
          refute({sj, @sub_prop, public} in ts, "divergent mapping asserted: #{sj} -> #{public}")
  end

  test "exactly the argued mapping set reaches public namespaces (no unargued edge)" do
    edges =
      for {s, p, o} <- triples(graph()),
          p in [@sub_class, @sub_prop],
          String.starts_with?(s, @sj),
          Enum.any?(@public_ns, &String.starts_with?(o, &1)),
          do: {s, o}

    assert Enum.sort(edges) == Enum.sort(@mapped)
  end

  test "additive: no edge points from a public class down to an sj: class" do
    down =
      for {s, p, o} <- triples(graph()),
          p == @sub_class,
          Enum.any?(@public_ns, &String.starts_with?(s, &1)),
          String.starts_with?(o, @sj),
          do: {s, o}

    assert down == []
  end

  test "additive: every sj: class/property declared at git HEAD is still declared" do
    {head, 0} = System.cmd("git", ["show", "HEAD:#{@pack}/ontology.ttl"])

    tmp =
      Path.join(System.tmp_dir!(), "vocab_mapping_head_#{System.unique_integer([:positive])}.ttl")

    File.write!(tmp, head)
    on_exit(fn -> File.rm(tmp) end)

    declared = fn g ->
      for {s, p, _} <- triples(g), p == @rdf_type, String.starts_with?(s, @sj), uniq: true, do: s
    end

    before = MapSet.new(declared.(Ontology.load!(tmp)))
    now = MapSet.new(declared.(graph()))

    assert MapSet.size(before) > 0
    assert MapSet.subset?(before, now), "removed: #{inspect(MapSet.difference(before, now))}"
  end

  test "SJ-002 R3: no shape targets a public class (subClassOf* cannot drag instances in)" do
    targets =
      for g <- shapes_graphs(), {_, p, o} <- triples(g), p == @sh_target_class, do: o

    assert targets != []

    for t <- targets,
        do:
          refute(
            Enum.any?(@public_ns, &String.starts_with?(t, &1)),
            "shape targets public class #{t}"
          )
  end

  test "SJ-002 R3: public-typed nodes are not pulled under closed sj: shapes" do
    base = graph()
    shapes = Path.join(@shapes_dir, "work-order.shacl.ttl")
    baseline = Shacl.validate_file(base, shapes)
    assert baseline.conforms

    # Nodes typed ONLY with the public superclasses, carrying arbitrary
    # properties a closed WorkOrderShape would reject if it reached them.
    junk = RDF.iri(@sj <> "public-only-junk")
    junk2 = RDF.iri(@sj <> "public-only-junk2")
    type = RDF.iri(@rdf_type)
    extra = RDF.iri("https://example.test/anything")

    poked =
      base
      |> RDF.Graph.add({junk, type, RDF.iri(@oslc_cm <> "ChangeRequest")})
      |> RDF.Graph.add({junk, extra, RDF.literal("x")})
      |> RDF.Graph.add({junk2, type, RDF.iri(@prov <> "Entity")})
      |> RDF.Graph.add({junk2, extra, RDF.literal("y")})

    report = Shacl.validate_file(poked, shapes)

    assert report.conforms, inspect(report.violations, pretty: true)
    assert report.focus_node_count == baseline.focus_node_count
    assert report.shapes_checked == baseline.shapes_checked
  end

  test "shape verdict is identical with and without the mapping triples" do
    with_map = graph()
    shapes = Path.join(@shapes_dir, "work-order.shacl.ttl")

    without =
      Enum.reduce(@mapped, with_map, fn {s, o}, g ->
        RDF.Graph.delete(g, {RDF.iri(s), RDF.iri(@sub_class), RDF.iri(o)})
      end)

    assert length(triples(without)) < length(triples(with_map))

    a = Shacl.validate_file(with_map, shapes)
    b = Shacl.validate_file(without, shapes)

    assert a.conforms == b.conforms
    assert a.violations == b.violations
    assert a.focus_node_count == b.focus_node_count
    assert a.shapes_checked == b.shapes_checked
  end

  test "VOCABULARY.md records every rejected candidate under the step-4 heading" do
    doc = File.read!("#{@pack}/VOCABULARY.md")
    assert doc =~ "## ADR-011 step 4 mappings"
    [_, section] = String.split(doc, "## ADR-011 step 4 mappings", parts: 2)

    for name <- ~w(StandingTransition ProseObservation EvidenceRequirement replayIdentity
                   ProjectionSpec CodeWorkAuthority sj:WorkOrder sj:Receipt) do
      assert section =~ name, "step-4 section does not mention #{name}"
    end
  end
end
