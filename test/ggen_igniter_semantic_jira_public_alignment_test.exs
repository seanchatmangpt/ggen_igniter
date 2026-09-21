defmodule GgenIgniter.SemanticJiraPublicAlignmentTest do
  @moduledoc """
  Chicago-style proofs for ADR-011 (reduce `sj:` toward oslc_cm / dcterms /
  PROV-O / SKOS): every declared `sj:` class and property of the shipped
  `semantic-jira-pack` ontology is EITHER aligned to a public term OR declared
  sj-native residue with a reason, and the anti-join gate
  (`gates/047_public_vocab_alignment.rq`) plus `PackHealth` enforce it.

  Everything here runs against the real Turtle loader and the real query
  engines (`oxigraph` NIF and the pure-Elixir `sparql` engine), real files on
  disk, and real mutated copies of the shipped ontology/pack -- no test
  doubles. Partition assertions are computed in Elixir from independent
  queries, not by trusting the gate's own verdict, so a defect in the gate
  cannot certify itself.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.{Engine, Ontology}
  alias GgenIgniter.SemanticJira.{PackHealth, Shacl}

  @moduletag :integration

  @pack_dir "priv/ggen/semantic-jira-pack"
  @ontology_path Path.join(@pack_dir, "ontology.ttl")
  @gate_path Path.join(@pack_dir, "gates/047_public_vocab_alignment.rq")
  @shapes_path Path.join(@pack_dir, "shapes/work-order.shacl.ttl")
  @gate_name "public_vocab_alignment"

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @engines ~w(oxigraph sparql)

  # Public namespaces an alignment may target. A pack-local a2a: target (the
  # pre-existing `sj:WorkOrder rdfs:subClassOf a2a:Task`) is deliberately NOT
  # public.
  @public_namespaces [
    "http://open-services.net/ns/cm#",
    "http://open-services.net/ns/core#",
    "http://purl.org/dc/terms/",
    "http://www.w3.org/ns/prov#",
    "http://www.w3.org/2004/02/skos/core#",
    "http://www.w3.org/ns/shacl#"
  ]

  @prefixes """
  PREFIX sj: <#{@sj}>
  PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  PREFIX owl: <http://www.w3.org/2002/07/owl#>
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  """

  @terms_query @prefixes <>
                 """
                 SELECT DISTINCT ?term WHERE {
                   ?term a ?kind .
                   FILTER(?kind = rdfs:Class || ?kind = rdf:Property)
                   FILTER(STRSTARTS(STR(?term), "#{@sj}"))
                 }
                 """

  @alignments_query @prefixes <>
                      """
                      SELECT DISTINCT ?term ?align ?public WHERE {
                        ?term ?align ?public .
                        FILTER(?align = rdfs:subClassOf || ?align = rdfs:subPropertyOf ||
                               ?align = owl:equivalentClass || ?align = owl:equivalentProperty ||
                               ?align = skos:exactMatch || ?align = skos:closeMatch)
                        FILTER(STRSTARTS(STR(?term), "#{@sj}"))
                      }
                      """

  @reasons_query @prefixes <>
                   """
                   SELECT ?term ?reason WHERE {
                     ?term sj:residueReason ?reason .
                   }
                   """

  @used_predicates_query @prefixes <>
                           """
                           SELECT DISTINCT ?term WHERE {
                             ?s ?term ?o .
                             FILTER(STRSTARTS(STR(?term), "#{@sj}"))
                           }
                           """

  @used_types_query @prefixes <>
                      """
                      SELECT DISTINCT ?term WHERE {
                        ?s a ?term .
                        FILTER(STRSTARTS(STR(?term), "#{@sj}"))
                      }
                      """

  @alignment_block ~r/# BEGIN sj-public-alignment \(ADR-011\).*?# END sj-public-alignment \(ADR-011\)\n/s

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sj_alignment_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir = RealDir.real_dir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # Runs `query` over the ontology at `path` through the named real engine.
  defp run(engine_name, path, query) do
    engine = Engine.fetch!(engine_name)
    context = engine.prepare!(Ontology.load!(path), [])
    engine.run(context, query)
  end

  # Writes `source` to a scratch ontology file and returns its path.
  defp write_ontology!(dir, name, source) do
    path = Path.join(dir, name)
    File.write!(path, source)
    path
  end

  # The shipped ontology plus extra Turtle (its own prefixes) appended.
  defp with_extra!(dir, name, extra) do
    prefixes = """
    @prefix sj: <#{@sj}> .
    @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
    @prefix owl: <http://www.w3.org/2002/07/owl#> .
    @prefix skos: <http://www.w3.org/2004/02/skos/core#> .
    @prefix prov: <http://www.w3.org/ns/prov#> .
    @prefix dcterms: <http://purl.org/dc/terms/> .
    @prefix oslc_cm: <http://open-services.net/ns/cm#> .
    @prefix a2a: <https://ggen-igniter.dev/ontology/a2a#> .
    """

    write_ontology!(dir, name, File.read!(@ontology_path) <> "\n" <> prefixes <> extra <> "\n")
  end

  defp public?(iri), do: Enum.any?(@public_namespaces, &String.starts_with?(iri, &1))

  defp gate_rows(engine_name, path), do: run(engine_name, path, File.read!(@gate_path))

  defp sorted(rows), do: Enum.sort_by(rows, &Map.to_list/1)

  defp values(rows, key), do: rows |> Enum.map(& &1[key]) |> MapSet.new()

  describe "the shipped ontology: every sj: term is aligned XOR sj-native residue" do
    test "independent partition: aligned and residue are disjoint and cover every declared sj: term" do
      terms = run("oxigraph", @ontology_path, @terms_query) |> values("term")

      aligned =
        run("oxigraph", @ontology_path, @alignments_query)
        |> Enum.filter(&public?(&1["public"]))
        |> values("term")

      reasons = run("oxigraph", @ontology_path, @reasons_query)
      residue = values(reasons, "term")

      # Scope tripwire: dropping terms from the ontology cannot make this
      # vacuous. 22 classes + 45 properties at the time of writing; the floor
      # is deliberately below the exact count so adding terms stays legal
      # (the partition assertions below then force each new term to be
      # aligned or residue).
      assert MapSet.size(terms) >= 60

      assert MapSet.disjoint?(aligned, residue),
             "terms both aligned and residue: #{inspect(MapSet.intersection(aligned, residue))}"

      assert MapSet.union(aligned, residue) == terms,
             "neither aligned nor residue: #{inspect(MapSet.difference(terms, MapSet.union(aligned, residue)))}"

      assert MapSet.subset?(aligned, terms)
      assert MapSet.subset?(residue, terms)

      # Exactly one reason per residue term, each substantive (not a stub).
      assert length(reasons) == MapSet.size(residue)

      for %{"term" => term, "reason" => reason} <- reasons do
        assert String.length(reason) >= 40,
               "residue reason for #{term} is a stub: #{inspect(reason)}"
      end

      # The reduction is real, not a rename of everything to residue.
      assert MapSet.size(aligned) >= 10
    end

    test "ADR-011's named anchors: WorkOrder aligns to oslc_cm:ChangeRequest; Court, Falsifier, evidence ceiling and standing stay residue" do
      alignments = run("oxigraph", @ontology_path, @alignments_query)

      assert %{
               "term" => @sj <> "WorkOrder",
               "align" => "http://www.w3.org/2000/01/rdf-schema#subClassOf",
               "public" => "http://open-services.net/ns/cm#ChangeRequest"
             } in alignments

      residue = run("oxigraph", @ontology_path, @reasons_query) |> values("term")

      for local <- ~w(Court Falsifier evidenceCeiling standing) do
        assert (@sj <> local) in residue, "ADR-011 names #{local} irreducible; it must be residue"
      end
    end

    test "no sj: term is used in the graph without being declared (the gate's scope has no escape hatch)" do
      declared = run("oxigraph", @ontology_path, @terms_query) |> values("term")

      used =
        MapSet.union(
          values(run("oxigraph", @ontology_path, @used_predicates_query), "term"),
          values(run("oxigraph", @ontology_path, @used_types_query), "term")
        )

      # Individuals such as sj:semantic-jira-mvp are subjects, never
      # predicates or rdf:type objects, so they do not appear in `used`.
      undeclared = MapSet.difference(used, declared)

      # sj:residueReason is declared and used; every other used term must be
      # declared too.
      assert MapSet.size(undeclared) == 0,
             "sj: terms used but never declared as rdfs:Class/rdf:Property: #{inspect(undeclared)}"
    end

    for engine <- @engines do
      test "gate 047 returns zero violation rows on the shipped ontology (#{engine} engine)" do
        assert run(unquote(engine), @ontology_path, File.read!(@gate_path)) == []
      end
    end
  end

  describe "gate 047 fails on real mutations (both engines, identical rows)" do
    # Every case writes a real mutated ontology, runs the gate through BOTH
    # engines and asserts identical rows, then asserts the specific rows.
    defp assert_gate!(dir, name, extra, expected_rows) do
      path = with_extra!(dir, name, extra)
      oxigraph = gate_rows("oxigraph", path) |> sorted()
      sparql = gate_rows("sparql", path) |> sorted()

      assert oxigraph == sparql,
             "engine divergence on #{name}: oxigraph=#{inspect(oxigraph)} sparql=#{inspect(sparql)}"

      assert oxigraph == sorted(expected_rows),
             "unexpected rows for #{name}: #{inspect(oxigraph)}"
    end

    test "an unaligned, reason-less sj: class is a violation" do
      dir = scratch_dir!("unmapped_class")

      assert_gate!(dir, "unmapped_class.ttl", "sj:UnmappedProbe a rdfs:Class .", [
        %{"term" => @sj <> "UnmappedProbe"}
      ])
    end

    test "an unaligned, reason-less sj: property is a violation" do
      dir = scratch_dir!("unmapped_property")

      assert_gate!(dir, "unmapped_property.ttl", "sj:unmappedProbe a rdf:Property .", [
        %{"term" => @sj <> "unmappedProbe"}
      ])
    end

    test "aligning to a public term clears the violation (subClassOf, closeMatch)" do
      dir = scratch_dir!("aligned")

      assert_gate!(
        dir,
        "aligned.ttl",
        """
        sj:AlignedProbeA a rdfs:Class ; rdfs:subClassOf prov:Entity .
        sj:AlignedProbeB a rdf:Property ; skos:closeMatch dcterms:relation .
        """,
        []
      )
    end

    test "a pack-local a2a: target is not public: still a violation" do
      dir = scratch_dir!("a2a_target")

      assert_gate!(
        dir,
        "a2a_target.ttl",
        "sj:LocalOnlyProbe a rdfs:Class ; rdfs:subClassOf a2a:Task .",
        [%{"term" => @sj <> "LocalOnlyProbe"}]
      )
    end

    test "skos:relatedMatch is not an alignment kind: still a violation" do
      dir = scratch_dir!("related_match")

      assert_gate!(
        dir,
        "related_match.ttl",
        "sj:RelatedProbe a rdf:Property ; skos:relatedMatch dcterms:relation .",
        [%{"term" => @sj <> "RelatedProbe"}]
      )
    end

    test "a residue term with an empty reason is a violation; a real reason clears it" do
      dir = scratch_dir!("residue_reason")

      assert_gate!(
        dir,
        "empty_reason.ttl",
        ~s(sj:EmptyReasonProbe a rdfs:Class ; sj:residueReason "" .),
        [%{"term" => @sj <> "EmptyReasonProbe"}]
      )

      assert_gate!(
        dir,
        "real_reason.ttl",
        ~s(sj:ReasonedProbe a rdfs:Class ; sj:residueReason "No public counterpart found among oslc_cm, dcterms, PROV-O." .),
        []
      )
    end

    test "residue claimed while a public alignment exists is a contradiction row (public and reason both bound)" do
      dir = scratch_dir!("contradiction")

      assert_gate!(
        dir,
        "contradiction.ttl",
        """
        sj:ContradictionProbe a rdfs:Class ;
            rdfs:subClassOf prov:Entity ;
            sj:residueReason "Claims no public counterpart although prov:Entity is aligned." .
        """,
        [
          %{
            "term" => @sj <> "ContradictionProbe",
            "public" => "http://www.w3.org/ns/prov#Entity",
            "reason" => "Claims no public counterpart although prov:Entity is aligned."
          }
        ]
      )
    end

    test "deleting a real alignment axiom from the shipped ontology surfaces exactly that term" do
      dir = scratch_dir!("delete_axiom")
      axiom = "sj:WorkOrder rdfs:subClassOf oslc_cm:ChangeRequest .\n"
      source = File.read!(@ontology_path)

      assert String.contains?(source, axiom)

      path = write_ontology!(dir, "no_workorder_alignment.ttl", String.replace(source, axiom, ""))

      for engine <- @engines do
        assert gate_rows(engine, path) == [%{"term" => @sj <> "WorkOrder"}],
               "#{engine}: deleting the WorkOrder alignment must flag exactly sj:WorkOrder"
      end
    end
  end

  describe "ADR-011 falsifier: no gate or shape result differs between the sj: form and the mapped form" do
    setup do
      dir = scratch_dir!("forms")
      source = File.read!(@ontology_path)
      stripped = Regex.replace(@alignment_block, source, "")

      # Non-vacuity: the block exists and stripping it changes the bytes.
      assert Regex.match?(@alignment_block, source)
      refute stripped == source
      refute String.contains?(stripped, "residueReason")
      refute String.contains?(stripped, "oslc_cm:")

      %{
        sj_only: write_ontology!(dir, "sj-only.ttl", stripped),
        mapped: @ontology_path
      }
    end

    test "every pre-existing gate returns identical rows on both forms, on both engines", %{
      sj_only: sj_only,
      mapped: mapped
    } do
      gates =
        @pack_dir
        |> Path.join("gates/*.rq")
        |> Path.wildcard()
        |> Enum.sort()
        |> Enum.reject(&(&1 == @gate_path))

      assert length(gates) >= 12

      nonempty =
        for gate <- gates, engine <- @engines, reduce: 0 do
          count ->
            query = File.read!(gate)
            a = run(engine, sj_only, query) |> sorted()
            b = run(engine, mapped, query) |> sorted()

            assert a == b,
                   "#{Path.basename(gate)} on #{engine} differs between the sj: form and the mapped form"

            if a == [], do: count, else: count + 1
        end

      # Equality of empty results everywhere would prove nothing.
      assert nonempty >= 10
    end

    test "the SHACL admission report is identical on both forms", %{
      sj_only: sj_only,
      mapped: mapped
    } do
      a = Shacl.validate_file(sj_only, @shapes_path)
      b = Shacl.validate_file(mapped, @shapes_path)

      assert a.conforms and b.conforms
      assert a.violations == b.violations
      assert a.focus_node_count == b.focus_node_count
      assert a.shapes_checked == b.shapes_checked
      assert b.focus_node_count > 0
    end

    test "the sj:-only form fails the alignment gate for every declared term (the block is what the gate reads)",
         %{sj_only: sj_only} do
      terms = run("oxigraph", sj_only, @terms_query) |> values("term")
      rows = gate_rows("oxigraph", sj_only)

      assert MapSet.size(terms) >= 60
      assert values(rows, "term") == terms
      assert length(rows) == MapSet.size(terms)
    end
  end

  describe "PackHealth registers the gate: doctor's semantic_jira_pack check refuses on any violation row" do
    defp pack_copy!(tag) do
      root = scratch_dir!("pack_" <> tag)
      dest = Path.join(root, "semantic-jira-pack")
      File.cp_r!(@pack_dir, dest)
      dest
    end

    test "the real shipped pack is healthy and its summary counts the alignment gate" do
      gate_count = @pack_dir |> Path.join("gates/*.rq") |> Path.wildcard() |> length()

      assert {:ok, summary} = PackHealth.check(@pack_dir)
      assert summary =~ "#{gate_count} gate queries executed clean"
    end

    test "the gate file is discovered under its stripped name, which PackHealth treats as a violation gate" do
      names =
        @pack_dir |> GgenIgniter.Pack.discover_queries() |> Enum.map(&elem(&1, 0))

      assert @gate_name in names
    end

    test "fail-closed: an unaligned sj: term makes the health check an honest error naming the gate and term" do
      pack_dir = pack_copy!("unmapped")
      ontology = Path.join(pack_dir, "ontology.ttl")

      File.write!(
        ontology,
        File.read!(ontology) <>
          "\n<#{@sj}HealthProbeClass> a <http://www.w3.org/2000/01/rdf-schema#Class> .\n"
      )

      assert {:error, detail} = PackHealth.check(pack_dir)
      assert detail =~ "gate #{@gate_name} ("
      assert detail =~ "1 violation row"
      assert detail =~ "#{@sj}HealthProbeClass (neither aligned nor declared residue)"
    end

    test "fail-closed: stripping the whole alignment block fails health and names how many terms" do
      pack_dir = pack_copy!("stripped")
      ontology = Path.join(pack_dir, "ontology.ttl")
      File.write!(ontology, Regex.replace(@alignment_block, File.read!(ontology), ""))

      assert {:error, detail} = PackHealth.check(pack_dir)
      assert detail =~ "gate #{@gate_name} ("
      assert detail =~ ~r/returned \d+ violation rows/
      assert detail =~ "(+"
    end

    test "fail-closed: a contradiction (aligned AND residue) is reported as such" do
      pack_dir = pack_copy!("contradiction")
      ontology = Path.join(pack_dir, "ontology.ttl")

      File.write!(
        ontology,
        File.read!(ontology) <>
          """

          <#{@sj}HealthContradiction> a <http://www.w3.org/2000/01/rdf-schema#Class> ;
              <http://www.w3.org/2000/01/rdf-schema#subClassOf> <http://www.w3.org/ns/prov#Entity> ;
              <#{@sj}residueReason> "Claims no public counterpart although prov:Entity is aligned." .
          """
      )

      assert {:error, detail} = PackHealth.check(pack_dir)
      assert detail =~ "#{@sj}HealthContradiction (aligned AND declared residue)"
    end
  end
end
