defmodule GgenIgniterGateVerifyTest do
  @moduledoc """
  Chicago-school tests for `GgenIgniter.GateVerify`'s fail-CLOSED additions
  (WS07): the per-gate cardinality contract on `run/3`, the contract loader,
  and the inverted companion queries in
  `test/fixtures/ash_manufacture_pack/verify/`.

  Real collaborators throughout. Real `RDF.Graph` values built with RDF.ex,
  serialised to real Turtle files, loaded back by `GgenIgniter.Ontology.load!/1`
  and queried by the real `sparql` hex engine through `GgenIgniter.Query.run/2`.
  Real `.rq` files on disk discovered by the real
  `GgenIgniter.Pack.discover_queries/1`. No doubles: every collaborator here is
  genuinely runnable in-process.

  ## What is under test

  Every gate in `test/fixtures/ash_manufacture_pack/gates/` is a conjunctive
  `SELECT`, and `GateVerify`'s documented rule is `[] -> :fail` /
  `[_|_] -> :pass`. So one missing triple silently drops an individual from the
  plan while the gate still scores `:pass` -- it FAILS OPEN. The synthetic case
  below reproduces that in miniature and pins BOTH halves of the fix: the new
  refusal fires, and the old default is preserved for a gate with no contract.

  ## Faker, and the four things that are not test data

  Class names, predicate names, individual names and property values are drawn
  from `Faker` so an assertion can only pass by way of the property it names,
  never by coincidence with a hand-picked literal. A test asserting "a
  conjunctive gate drops the individual missing a conjunct" must hold for
  `Faker.Lorem.word()` exactly as it would for `"primaryKeyKind"`.

  Fixed values survive only where they are an external CONTRACT:

    * `@rdf_type` -- the RDF 1.1 `rdf:type` IRI.
    * `@amp` and `@primary_key_kind` -- the real pack ontology's own namespace
      and one of `gates/030_resources.rq`'s own required conjuncts. Contracts
      with files this test reads, not values it chose.
    * `"ROWS"` / `"VALUES"`, `"class"` / `"predicate"` -- the contract with
      `verify/cardinality.json`'s own schema, which `load_cardinality/1` parses.
    * `"subject"` / `"missing_property"` -- the columns every
      `verify/*.unbound.rq` projects.

  Faker's lorem pool is small enough that two draws collide often at this
  sample size, and a collision between a class name and a predicate name would
  make an assertion ambiguous rather than false. `names/1` enforces
  distinctness rather than hoping for it.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.GateVerify

  @real_pack Path.join(__DIR__, "fixtures/ash_manufacture_pack")

  # RDF 1.1's own type IRI. A contract, not test data.
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

  # The real pack ontology's namespace, and one conjunct that
  # `gates/030_resources.rq` requires. Contracts with files read below.
  @amp "http://seanchatmangpt.github.io/packs/ash-manufacture-pack#"
  @primary_key_kind @amp <> "primaryKeyKind"

  describe "run/3 cardinality contract: the new refusal and the preserved default" do
    test "a conjunctive gate silently drops an individual; run/2 passes, run/3 refuses" do
      %{class: class, required: required, anchor: anchor} = vocab()
      [complete, incomplete] = names(2)

      # Both individuals carry the ANCHOR predicate, so the graph says two
      # subjects should reach the plan. Only `complete` carries the second
      # conjunct, so the conjunctive gate emits one row -- the fail-open.
      graph =
        RDF.Graph.new()
        |> add_individual(complete, class, %{anchor => complete, required => value()})
        |> add_individual(incomplete, class, %{anchor => incomplete})

      pack = scratch_pack("drops_one", conjunctive_gate(class, anchor, required))
      ontology = write_ontology!(pack, graph)

      # The documented default, unchanged: one row is still a pass, so the
      # dropped individual is invisible. This is the bug, pinned.
      assert {:ok, [{"things", :pass}]} = GateVerify.run(pack, ontology)

      # The same run WITH a contract refuses, and names the real numbers:
      # two anchored subjects in the graph, one row out of the gate.
      assert GateVerify.run(pack, ontology, cardinality: rows_contract("things", anchor)) ==
               {:error, {:gate_cardinality, "things", 2, 1}}
    end

    test "a healthy graph passes with and without the contract" do
      %{class: class, required: required, anchor: anchor} = vocab()

      graph =
        Enum.reduce(names(2), RDF.Graph.new(), fn name, g ->
          add_individual(g, name, class, %{anchor => name, required => value()})
        end)

      pack = scratch_pack("healthy", conjunctive_gate(class, anchor, required))
      ontology = write_ontology!(pack, graph)

      assert {:ok, [{"things", :pass}]} = GateVerify.run(pack, ontology)

      assert {:ok, [{"things", :pass}]} =
               GateVerify.run(pack, ontology, cardinality: rows_contract("things", anchor))
    end

    test "a gate absent from the contract map keeps the >= 1-row default" do
      %{class: class, required: required, anchor: anchor} = vocab()
      [complete, incomplete] = names(2)

      graph =
        RDF.Graph.new()
        |> add_individual(complete, class, %{anchor => complete, required => value()})
        |> add_individual(incomplete, class, %{anchor => incomplete})

      pack = scratch_pack("uncontracted", conjunctive_gate(class, anchor, required))
      ontology = write_ontology!(pack, graph)

      # A contract map keyed for some OTHER gate must not reach this one.
      # Packs authored before contracts existed depend on exactly this.
      other = Faker.Lorem.word() <> "_gate"

      assert {:ok, [{"things", :pass}]} =
               GateVerify.run(pack, ontology, cardinality: rows_contract(other, anchor))
    end

    test "VALUES mode counts (subject, value) pairs, not subjects" do
      %{class: class, anchor: anchor} = vocab()
      [one, two] = names(2)
      [v1, v2, v3] = names(3)

      # Three pairs across two subjects: a ROWS contract would say 2 here, so
      # this asserts the mode field actually changes the derived count.
      graph =
        RDF.Graph.new()
        |> add_individual(one, class, %{anchor => v1})
        |> RDF.Graph.add({iri(iri_of(one)), iri(iri_of(anchor)), RDF.literal(v2)})
        |> add_individual(two, class, %{anchor => v3})

      pack = scratch_pack("values_mode", values_gate(class, anchor))
      ontology = write_ontology!(pack, graph)

      assert {:ok, [{"things", :pass}]} =
               GateVerify.run(pack, ontology,
                 cardinality: %{
                   "things" => %{mode: :values, anchor: {:predicate, iri_of(anchor)}}
                 }
               )

      # The same graph under a ROWS contract disagrees (2 subjects vs 3 rows),
      # which is what makes the mode load-bearing rather than decorative.
      assert GateVerify.run(pack, ontology, cardinality: rows_contract("things", anchor)) ==
               {:error, {:gate_cardinality, "things", 2, 3}}
    end
  end

  describe "load_cardinality/1" do
    test "loads the real pack's contract; every entry is predicate-anchored" do
      path = GateVerify.default_cardinality_path(@real_pack)
      assert {:ok, contracts} = GateVerify.load_cardinality(path)
      assert map_size(contracts) > 0

      for {stem, contract} <- contracts do
        assert contract.mode in [:rows, :values], "gate #{stem} has an unparsed mode"

        assert match?({:predicate, _}, contract.anchor),
               "gate #{stem} is class-anchored; a class anchor shares the inverted " <>
                 "queries' rdf:type blind spot (see the ANCHOR note in cardinality.json)"
      end
    end

    test "an absent contract file is a typed :enoent, not a crash" do
      missing = Path.join(System.tmp_dir!(), "ws07_absent_#{unique()}.json")
      assert GateVerify.load_cardinality(missing) == {:error, {:enoent, missing}}
    end

    test "an unrecognised mode is refused rather than silently skipped" do
      stem = Faker.Lorem.word()
      # A silently-ignored contract would reintroduce the fail-open this
      # module exists to close, so the refusal is the property under test.
      path = write_contract!(%{stem => %{"mode" => String.upcase(Faker.Lorem.word())}})

      assert GateVerify.load_cardinality(path) ==
               {:error, {:invalid_contract, stem, :unknown_mode}}
    end

    test "a ROWS entry carrying both anchors is refused as ambiguous" do
      stem = Faker.Lorem.word()

      path =
        write_contract!(%{
          stem => %{
            "mode" => "ROWS",
            "class" => iri_of(Faker.Lorem.word()),
            "predicate" => iri_of(Faker.Lorem.word())
          }
        })

      assert GateVerify.load_cardinality(path) ==
               {:error, {:invalid_contract, stem, :ambiguous_anchor}}
    end

    test "a ROWS entry with no anchor at all is refused" do
      stem = Faker.Lorem.word()
      path = write_contract!(%{stem => %{"mode" => "ROWS"}})

      assert GateVerify.load_cardinality(path) ==
               {:error, {:invalid_contract, stem, :missing_anchor}}
    end
  end

  describe "inverted companion queries against the real ash_manufacture_pack" do
    test "every verify/*.unbound.rq returns zero rows against the real ontology" do
      # Zero rows is the pass condition: a row means a fact one of the gates
      # requires is missing. A failure here is a real pack defect, not a
      # brittle assertion.
      assert GateVerify.verify_unbound(@real_pack, real_ontology_path()) == {:ok, []}
    end

    test "the verify/ directory names the gates it refutes" do
      stems = @real_pack |> GateVerify.discover_unbound() |> Enum.map(&elem(&1, 0))
      gates = @real_pack |> GgenIgniter.Pack.discover_queries() |> Enum.map(&elem(&1, 0))

      assert stems != [], "no verify/*.unbound.rq found under #{@real_pack}"

      for stem <- stems do
        assert stem in gates,
               "verify/ query maps to gate stem #{inspect(stem)}, which has no gates/*.rq"
      end
    end

    test "the real pack satisfies every declared cardinality contract" do
      {:ok, contracts} =
        GateVerify.load_cardinality(GateVerify.default_cardinality_path(@real_pack))

      assert {:ok, results} =
               GateVerify.run(@real_pack, real_ontology_path(), cardinality: contracts)

      # Contracts are additive: gates without an entry must still be scored.
      assert length(results) >= map_size(contracts)
    end

    test "deleting one required conjunct: the query names it, the gate stays silent" do
      graph = GgenIgniter.Ontology.load!(real_ontology_path())

      # Pick a real subject carrying the conjunct rather than hardcoding an
      # individual, so a concurrent edit to the ontology cannot make this test
      # assert against a resource that no longer exists.
      [%{"s" => subject, "v" => value} | _] =
        GgenIgniter.Query.run(graph, "SELECT ?s ?v WHERE { ?s <#{@primary_key_kind}> ?v }")

      broken = RDF.Graph.delete(graph, {iri(subject), iri(@primary_key_kind), RDF.literal(value)})
      path = Path.join(System.tmp_dir!(), "ws07_broken_#{unique()}.ttl")
      on_exit(fn -> File.rm(path) end)
      RDF.Turtle.write_file!(broken, path, force: true)

      # The refutation names the exact subject and the exact predicate.
      assert {:error, {:unbound_facts, findings}} = GateVerify.verify_unbound(@real_pack, path)

      assert Enum.any?(findings, fn f ->
               f.subject == subject and f.missing_property == "amp:primaryKeyKind"
             end),
             "expected a finding naming #{subject}, got #{inspect(findings)}"

      # ...while the gate itself stays silent. This is the fail-open, executed:
      # the gate still returns rows, so `run/2` still scores it a pass.
      {_, gate_path} =
        @real_pack
        |> GgenIgniter.Pack.discover_queries()
        |> Enum.find(&(elem(&1, 0) == "resources"))

      broken_graph = GgenIgniter.Ontology.load!(path)
      gate_rows = GgenIgniter.Query.run(broken_graph, File.read!(gate_path))

      assert gate_rows != [],
             "the resources gate returned zero rows, so this ontology no longer " <>
               "demonstrates the fail-open the verify/ queries exist to close"

      assert {:ok, _} = GateVerify.run(@real_pack, path)
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp real_ontology_path, do: Path.join(@real_pack, "ontology.ttl")

  defp unique, do: System.unique_integer([:positive])

  defp iri(name), do: RDF.IRI.new(name)

  # A synthetic namespace per call keeps concurrently-running async tests from
  # sharing IRIs even when Faker draws the same word twice.
  defp iri_of(name), do: "http://example.test/ws07##{name}"

  defp value, do: Faker.Lorem.sentence(3)

  # Faker's lorem pool is small; a collision between a class name and a
  # predicate name would make an assertion ambiguous rather than false.
  defp names(n) do
    Stream.repeatedly(&Faker.Lorem.word/0)
    |> Stream.uniq()
    |> Enum.take(n)
  end

  defp vocab do
    [class, required, anchor] = names(3)
    %{class: class, required: required, anchor: anchor}
  end

  defp add_individual(graph, name, class, properties) do
    graph = RDF.Graph.add(graph, {iri(iri_of(name)), iri(@rdf_type), iri(iri_of(class))})

    Enum.reduce(properties, graph, fn {predicate, object}, g ->
      RDF.Graph.add(g, {iri(iri_of(name)), iri(iri_of(predicate)), RDF.literal(object)})
    end)
  end

  # A real conjunctive gate of the same shape as gates/030_resources.rq: two
  # required predicates on one subject, neither projected as a subject IRI.
  defp conjunctive_gate(class, anchor, required) do
    """
    SELECT ?anchor ?required
    WHERE {
      ?s a <#{iri_of(class)}> ;
         <#{iri_of(anchor)}> ?anchor ;
         <#{iri_of(required)}> ?required .
    }
    """
  end

  # The shape of gates/035_default_actions.rq: one row per repeated value.
  defp values_gate(class, anchor) do
    """
    SELECT ?value
    WHERE {
      ?s a <#{iri_of(class)}> ;
         <#{iri_of(anchor)}> ?value .
    }
    """
  end

  defp rows_contract(stem, anchor) do
    %{stem => %{mode: :rows, anchor: {:predicate, iri_of(anchor)}}}
  end

  defp scratch_pack(label, gate_query) do
    dir = Path.join(System.tmp_dir!(), "ws07_#{label}_#{unique()}")
    File.mkdir_p!(Path.join(dir, "gates"))
    on_exit(fn -> File.rm_rf!(dir) end)
    # `010_things.rq` -> gate stem "things", per Pack.discover_queries/1.
    File.write!(Path.join(dir, "gates/010_things.rq"), gate_query)
    dir
  end

  defp write_ontology!(pack_dir, graph) do
    path = Path.join(pack_dir, "ontology.ttl")
    RDF.Turtle.write_file!(graph, path, force: true)
    path
  end

  defp write_contract!(gates) do
    path = Path.join(System.tmp_dir!(), "ws07_contract_#{unique()}.json")
    on_exit(fn -> File.rm(path) end)
    File.write!(path, Jason.encode!(%{"gates" => gates}))
    path
  end
end
