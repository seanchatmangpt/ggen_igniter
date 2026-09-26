defmodule GgenIgniter.DoctrineHddlPackTest do
  @moduledoc """
  Chicago-style test over the real `doctrine-hddl-pack`
  (`priv/ggen/doctrine-hddl-pack/`): the real pinned strategic-doctrine graph
  (byte copies of ggen-marketplace `packs/strategic-doctrine-pack` at
  c0f27e5b, sha256-checked here), the real entrant-world fixture, the pack's
  real gates run by the real default sync engine
  (`GgenIgniter.Query.Oxigraph.run/2`; the `sparql` 0.3.12 engine cannot
  evaluate gate 030's `FILTER NOT EXISTS` admission law), bindings built by the
  real `Mix.Tasks.GgenIgniter.Sync.build_bindings/1`, and the real templates
  rendered by `GgenIgniter.Render.render/2`. No doubles.

  The `:ferroplan` describe block runs the REAL ferroplan HDDL gate
  (`crates/ferroplan-hddl/examples/validate_files.rs` at ferroplan b3f86717,
  materialized with `git archive` into `FERROPLAN_DIR`) as a subprocess on the
  rendered files and on mutants. It is skipped, with the reason named, when
  `cargo` is absent or `FERROPLAN_DIR` does not hold that example.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.Query.Oxigraph
  alias Mix.Tasks.GgenIgniter.Sync

  @pack_dir Path.join([__DIR__, "..", "priv", "ggen", "doctrine-hddl-pack"])
  @fixtures Path.join([__DIR__, "fixtures", "doctrine"])

  @sd "https://ggen.dev/ontology/strategic-doctrine#"
  @ew "https://ggen.dev/fixture/entrant-world#"
  @sosa "http://www.w3.org/ns/sosa/"

  # sha256 of the upstream bytes: git -C ggen-marketplace cat-file -p
  # c0f27e5b:packs/strategic-doctrine-pack/<path> | shasum -a 256
  @pins %{
    "entrant-world.ttl" => "91db146e103893b0e41413e2a34a828406f5852835bc510537137335c6c6381d",
    "strategic-doctrine.ttl" =>
      "c30f23a756951a6be9b2495ab6f2abd4c33e7aa335bd9ec976ede22c24a7d3c6",
    "doctrine-33.ttl" => "1fd42c2f778a2570b451518902d91872ecea0f6a5d76f1929f7000d72bd05ec2"
  }

  @ferroplan_dir System.get_env("FERROPLAN_DIR")
  @ferroplan_skip (cond do
                     is_nil(System.find_executable("cargo")) ->
                       "cargo not on PATH: ferroplan validate_files cannot be built"

                     is_nil(@ferroplan_dir) or
                         not File.exists?(
                           Path.join(
                             @ferroplan_dir || "",
                             "crates/ferroplan-hddl/examples/validate_files.rs"
                           )
                         ) ->
                       "FERROPLAN_DIR unset or lacks crates/ferroplan-hddl/examples/validate_files.rs " <>
                         "(materialize ferroplan b3f86717 with git archive and set FERROPLAN_DIR)"

                     true ->
                       false
                   end)

  # ── real pipeline ─────────────────────────────────────────────────────────

  defp base_graph do
    ["strategic-doctrine.ttl", "doctrine-33.ttl", "entrant-world.ttl"]
    |> Enum.map(&GgenIgniter.Ontology.load!(Path.join(@fixtures, &1)))
    |> Enum.reduce(
      GgenIgniter.Ontology.load!(Path.join(@pack_dir, "ontology.ttl")),
      &RDF.Graph.add(&2, &1)
    )
  end

  defp bindings(graph) do
    @pack_dir
    |> GgenIgniter.Pack.discover_queries()
    |> Enum.map(fn {name, path} ->
      {name, Oxigraph.run(graph, File.read!(path))}
    end)
    |> Sync.build_bindings()
  end

  defp render(graph, stem) do
    template =
      [@pack_dir, "templates", stem]
      |> Path.join()
      |> File.read!()
      |> strip_frontmatter()

    GgenIgniter.Render.render(template, bindings(graph))
  end

  defp strip_frontmatter(content) do
    ["", _frontmatter, body] = String.split(content, "---\n", parts: 3)
    body
  end

  defp count(haystack, needle), do: length(String.split(haystack, needle)) - 1

  defp iri(s), do: RDF.iri(s)

  # ── pins ──────────────────────────────────────────────────────────────────

  test "every doctrine fixture is a byte copy of the pinned upstream (sha256)" do
    for {file, pin} <- @pins do
      digest =
        :crypto.hash(:sha256, File.read!(Path.join(@fixtures, file)))
        |> Base.encode16(case: :lower)

      assert digest == pin, "#{file} drifted from ggen-marketplace c0f27e5b"
    end
  end

  test "the pack ontology references sd: IRIs only and redefines nothing" do
    graph = GgenIgniter.Ontology.load!(Path.join(@pack_dir, "ontology.ttl"))

    iris =
      graph
      |> RDF.Graph.triples()
      |> Enum.flat_map(&Tuple.to_list/1)
      |> Enum.filter(&match?(%RDF.IRI{}, &1))
      |> Enum.map(&RDF.IRI.to_string/1)
      |> Enum.uniq()

    vocab = ~w(http://www.w3.org/2002/07/owl# http://www.w3.org/2000/01/rdf-schema#
               http://www.w3.org/1999/02/22-rdf-syntax-ns#)

    for i <- iris do
      assert String.starts_with?(i, "https://ggen.dev/ontology/strategic-doctrine") or
               Enum.any?(vocab, &String.starts_with?(i, &1)),
             "non-sd: IRI #{i}"
    end

    # No subject in sd: -- the pack declares no class/property/individual of sd:.
    refute Enum.any?(RDF.Graph.subjects(graph), fn s ->
             match?(%RDF.IRI{}, s) and String.starts_with?(RDF.IRI.to_string(s), @sd)
           end)
  end

  # ── gates ─────────────────────────────────────────────────────────────────

  test "gate 010 yields one action per primitive (14) and gate 030 admits exactly 11, 17, 27" do
    b = bindings(base_graph())

    assert b[:domain_actions] |> Enum.map(& &1["name"]) |> Enum.sort() ==
             Enum.sort(
               ~w(shape probe conceal reveal concentrate disperse delay accelerate commit withdraw divide combine substitute transform)
             )

    admitted = b[:methods] |> Enum.map(& &1["strategy"]) |> Enum.uniq() |> Enum.sort()
    assert admitted == Enum.map(~w(strategy-11 strategy-17 strategy-27), &(@sd <> &1))
  end

  # ── rendered projections ──────────────────────────────────────────────────

  test "domain.hddl: a hierarchical typed domain with exactly 3 methods in sd:order" do
    domain = render(base_graph(), "domain.hddl.eex")

    assert domain =~ "(define (domain strategic-doctrine)"
    # :non-deterministic is declared because falsifier observations use oneof
    assert domain =~
             "(:requirements :hierarchy :typing :negative-preconditions :non-deterministic)"

    assert count(domain, "(:method ") == 3
    assert count(domain, "(:task ") == 2
    # 14 primitive actions + one observation action per admitted falsifier (3)
    assert count(domain, "(:action ") == 17

    for m <- ~w(m-strategy-11 m-strategy-17 m-strategy-27), do: assert(domain =~ m)
    refute domain =~ "m-strategy-14"

    # strategy-11 = withdraw, delay, conceal, probe, then its falsifier observation
    assert domain =~
             "(s1 (withdraw ?a))\n      (s2 (delay ?a))\n      (s3 (conceal ?a))\n      (s4 (probe ?a))\n      (s5 (observe-falsifier-11 ?a)))"

    assert domain =~ ":ordering (and (< s1 s2) (< s2 s3) (< s3 s4) (< s4 s5))"
    # numeric thresholds as predicates, as method preconditions
    assert domain =~ ":precondition (and (win-rate-lt-0p35 ?a) (not (refuted ?a)))"
    assert domain =~ "(runway-months-lt-18 ?a) (not (refuted ?a))"
    refute domain =~ ":constraints"
  end

  test "oneof is only ever the WHOLE effect in domain.hddl and contingency.fond.pddl" do
    graph = base_graph()

    for stem <- ["domain.hddl.eex", "contingency.fond.pddl.eex"] do
      text = render(graph, stem)
      assert count(text, "(oneof") == 3, stem
      assert count(text, ":effect (oneof") == 3, stem
      refute text =~ "(and (oneof", stem
      refute text =~ ":constraints", stem
    end
  end

  test "problem.hddl: roots the admitted objectives and inits only thresholds that hold" do
    problem = render(base_graph(), "problem.hddl.eex")

    assert problem =~ "(define (problem strategic-doctrine-acme)"
    assert problem =~ "(:domain strategic-doctrine)"
    assert problem =~ "(:objects acme - actor)"
    assert problem =~ "(g1 (pursue-objective-gain-share acme))"
    assert problem =~ "(g2 (pursue-objective-survive acme))"

    for fact <- ~w(win-rate-lt-0p35 rival-count-gte-3 runway-months-lt-18),
        do: assert(problem =~ "(#{fact} acme)")

    # 11 months of runway: the long-runway threshold does not hold
    refute problem =~ "runway-months-gte-18"
  end

  test "contingency.fond.pddl: one observation and one replan per admitted falsifier" do
    text = render(base_graph(), "contingency.fond.pddl.eex")

    assert text =~ "(define (domain strategic-doctrine-contingency)"
    assert count(text, "(:action observe-falsifier-") == 3
    assert count(text, "(:action replan-after-falsifier-") == 3
    refute text =~ "falsifier-14"
    assert text =~ "(oneof\n      (segment-share-lt-0p05 ?a)\n      (held-falsifier-11 ?a))"
    # strategy-17 is countered by strategy-27: its refutation flags the counter
    assert text =~ "(suspect-counter-strategy-27 ?a)"
  end

  # ── graph-level falsifiers (the template refuses) ─────────────────────────

  test "a step without sd:order is refused, never silently reordered" do
    graph =
      RDF.Graph.delete(
        base_graph(),
        {iri(@sd <> "strategy-17-step-2"), iri(@sd <> "order"), RDF.literal(2)}
      )

    error = assert_raise ArgumentError, fn -> render(graph, "domain.hddl.eex") end
    assert error.message =~ "REFUSED:DOCTRINE_HDDL"
    assert error.message =~ "strategy-17-step-2 of strategy-17 has no integer sd:order"
  end

  # Every method's :ordering must be the total chain s1 < s2 < ... < sn over
  # exactly its subtasks. ferroplan admits a method with NO :ordering (it is
  # then partially ordered), so step order is this pack's law, checked here on
  # the rendered text, not delegated to the HDDL gate.
  defp ordering_is_total_chain?(domain) do
    methods =
      domain
      |> String.split("(:method ")
      |> tl()
      |> Enum.map(&(&1 |> String.split("(:action ") |> hd()))

    methods != [] and
      Enum.all?(methods, fn m ->
        ids = Regex.scan(~r/\((s\d+) \(/, m, capture: :all_but_first) |> List.flatten()
        edges = Regex.scan(~r/\(< (s\d+) (s\d+)\)/, m, capture: :all_but_first)
        expected = Enum.chunk_every(Enum.map(1..length(ids), &"s#{&1}"), 2, 1, :discard)
        ids == Enum.map(1..length(ids), &"s#{&1}") and edges == expected
      end)
  end

  test "every rendered method is totally ordered over exactly its subtasks" do
    domain = render(base_graph(), "domain.hddl.eex")
    assert ordering_is_total_chain?(domain)

    # anti-vacuity: the check rejects a method whose :ordering was dropped
    unordered =
      String.replace(domain, ~r/\n    :ordering \(and[^\n]*\)\)/, ")", global: false)

    assert unordered != domain, "mutation must apply"
    refute ordering_is_total_chain?(unordered)
  end

  test "a step whose operator is not a primitive is refused by name, even as the last step" do
    for {step, op} <- [{"strategy-11-step-4", "probe"}, {"strategy-11-step-1", "withdraw"}] do
      graph =
        base_graph()
        |> RDF.Graph.delete({iri(@sd <> step), iri(@sd <> "operator"), iri(@sd <> op)})
        |> RDF.Graph.add({iri(@sd <> step), iri(@sd <> "operator"), iri(@sd <> "teleport")})

      error = assert_raise ArgumentError, fn -> render(graph, "domain.hddl.eex") end
      assert error.message =~ "REFUSED:DOCTRINE_HDDL"

      assert error.message =~
               "step #{step} of strategy-11 uses teleport, which is not a labelled sd:PrimitiveOperator"
    end
  end

  test "a step with no sd:operator is refused, never dropped" do
    graph =
      RDF.Graph.delete(
        base_graph(),
        {iri(@sd <> "strategy-11-step-4"), iri(@sd <> "operator"), iri(@sd <> "probe")}
      )

    error = assert_raise ArgumentError, fn -> render(graph, "domain.hddl.eex") end
    assert error.message =~ "step strategy-11-step-4 of strategy-11 has no sd:operator"
  end

  test "a primitive outside gate 010's action set is refused (unknown primitive)" do
    # typed and labelled as sd:PrimitiveOperator but with no sd:ordinal, so
    # gate 010 yields no action for it while gate 030 names it: the template's
    # cross-gate check must fire
    teleport = iri(@sd <> "teleport")
    step = iri(@sd <> "strategy-11-step-4")

    graph =
      base_graph()
      |> RDF.Graph.add({teleport, RDF.type(), iri(@sd <> "PrimitiveOperator")})
      |> RDF.Graph.add(
        {teleport, RDF.iri("http://www.w3.org/2000/01/rdf-schema#label"), RDF.literal("teleport")}
      )
      |> RDF.Graph.delete({step, iri(@sd <> "operator"), iri(@sd <> "probe")})
      |> RDF.Graph.add({step, iri(@sd <> "operator"), teleport})

    refute "teleport" in Enum.map(bindings(graph)[:domain_actions], & &1["name"])

    error = assert_raise ArgumentError, fn -> render(graph, "domain.hddl.eex") end

    assert error.message =~
             "REFUSED:DOCTRINE_HDDL: strategy-11 uses unknown primitive \"teleport\""
  end

  test "a step with two sd:order or two sd:operator values is refused as ambiguous" do
    step = iri(@sd <> "strategy-11-step-1")

    two_orders = RDF.Graph.add(base_graph(), {step, iri(@sd <> "order"), RDF.literal(9)})
    error = assert_raise ArgumentError, fn -> render(two_orders, "domain.hddl.eex") end
    assert error.message =~ "step strategy-11-step-1 of strategy-11 has 2 sd:order values"

    two_ops = RDF.Graph.add(base_graph(), {step, iri(@sd <> "operator"), iri(@sd <> "reveal")})
    error = assert_raise ArgumentError, fn -> render(two_ops, "domain.hddl.eex") end
    assert error.message =~ "step strategy-11-step-1 of strategy-11 has 2 sd:operator values"
  end

  test "a strategy with two sd:ordinal values is refused, never ordered by row order" do
    graph =
      RDF.Graph.add(
        base_graph(),
        {iri(@sd <> "strategy-11"), iri(@sd <> "ordinal"), RDF.literal(99)}
      )

    error = assert_raise ArgumentError, fn -> render(graph, "domain.hddl.eex") end

    assert error.message =~
             "REFUSED:DOCTRINE_HDDL: strategy-11 has 2 sd:ordinal values [11, 99]; the method order is ambiguous"
  end

  test "two admitted strategies sharing one sd:ordinal are refused as an ambiguous method order" do
    s27 = iri(@sd <> "strategy-27")

    graph =
      base_graph()
      |> RDF.Graph.delete({s27, iri(@sd <> "ordinal"), RDF.literal(27)})
      |> RDF.Graph.add({s27, iri(@sd <> "ordinal"), RDF.literal(17)})

    error = assert_raise ArgumentError, fn -> render(graph, "domain.hddl.eex") end

    assert error.message =~
             "REFUSED:DOCTRINE_HDDL: admitted strategies share an sd:ordinal [11, 17, 17]"
  end

  test "an admitted strategy with no sd:hasFalsifier refuses domain and contingency" do
    graph =
      RDF.Graph.delete(
        base_graph(),
        {iri(@sd <> "strategy-11"), iri(@sd <> "hasFalsifier"), iri(@sd <> "falsifier-11")}
      )

    error = assert_raise ArgumentError, fn -> render(graph, "domain.hddl.eex") end

    assert error.message =~
             "REFUSED:DOCTRINE_HDDL: strategy-11 has no sd:hasFalsifier; an unfalsifiable strategy is not decomposed"

    error = assert_raise ArgumentError, fn -> render(graph, "contingency.fond.pddl.eex") end

    assert error.message =~
             "REFUSED:DOCTRINE_HDDL: strategy-11 has no sd:hasFalsifier; an unfalsifiable commitment has no contingency"
  end

  test "admission is data-driven: 20 months of runway admits 14 and refuses 27" do
    obs = iri(@ew <> "obs-acme-runway")
    result = iri(@sosa <> "hasSimpleResult")

    graph =
      base_graph()
      |> RDF.Graph.delete({obs, result, RDF.XSD.decimal("11.0")})
      |> RDF.Graph.add({obs, result, RDF.XSD.decimal("20.0")})

    domain = render(graph, "domain.hddl.eex")
    assert count(domain, "(:method ") == 3
    assert domain =~ "m-strategy-14"
    refute domain =~ "m-strategy-27"
  end

  test "no admitted applicability refuses every projection" do
    graph =
      Enum.reduce(~w(app-acme-11 app-acme-17 app-acme-27 app-acme-14), base_graph(), fn app, g ->
        RDF.Graph.delete(g, {iri(@ew <> app), RDF.type(), iri(@sd <> "DoctrineApplicability")})
      end)

    for stem <- ~w(domain.hddl.eex problem.hddl.eex contingency.fond.pddl.eex) do
      error = assert_raise ArgumentError, fn -> render(graph, stem) end
      assert error.message =~ "REFUSED:DOCTRINE_HDDL", stem
    end
  end

  # ── ferroplan HDDL gate (real subprocess) ─────────────────────────────────

  describe "ferroplan validate_files" do
    @describetag :ferroplan
    if @ferroplan_skip, do: @describetag(skip: @ferroplan_skip)

    setup do
      dir = Path.join(System.tmp_dir!(), "doctrine_hddl_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      graph = base_graph()

      %{
        dir: dir,
        domain: render(graph, "domain.hddl.eex"),
        problem: render(graph, "problem.hddl.eex")
      }
    end

    defp validate(dir, domain, problem) do
      d = Path.join(dir, "domain.hddl")
      p = Path.join(dir, "problem.hddl")
      File.write!(d, domain)
      File.write!(p, problem)

      System.cmd(
        "cargo",
        ~w(run -q -p ferroplan-hddl --example validate_files --) ++ [d, p],
        cd: @ferroplan_dir,
        stderr_to_stdout: true
      )
    end

    test "admits the rendered domain + problem (exit 0)", ctx do
      {out, code} = validate(ctx.dir, ctx.domain, ctx.problem)
      assert code == 0, out
      assert out =~ "ok domain=strategic-doctrine problem=strategic-doctrine-acme"
      assert out =~ "actions=17 tasks=2 methods=3"
    end

    test "refuses a method whose ordering names a removed subtask (exit 2)", ctx do
      mutant = String.replace(ctx.domain, "\n      (s2 (delay ?a))", "", global: false)
      assert mutant != ctx.domain, "mutation must apply"
      {out, code} = validate(ctx.dir, mutant, ctx.problem)
      assert code == 2, out
      assert out =~ "refused: domain validation:"
      assert out =~ "'s2'"
    end

    test "refuses a cyclic method ordering (exit 2)", ctx do
      mutant =
        String.replace(
          ctx.domain,
          "(< s1 s2) (< s2 s3) (< s3 s4) (< s4 s5))",
          "(< s1 s2) (< s2 s3) (< s3 s4) (< s4 s5) (< s5 s1))",
          global: false
        )

      assert mutant != ctx.domain, "mutation must apply"
      {out, code} = validate(ctx.dir, mutant, ctx.problem)
      assert code == 2, out
      assert out =~ "cycle"
    end

    test "refuses oneof wrapped in and (exit 2)", ctx do
      mutant =
        ctx.domain
        |> String.replace(":effect (oneof", ":effect (and (oneof", global: false)
        |> String.replace("(effect-held ?a)))\n", "(effect-held ?a))))\n", global: false)

      assert mutant != ctx.domain, "mutation must apply"
      {out, code} = validate(ctx.dir, mutant, ctx.problem)
      assert code == 2, out
      assert out =~ "refused: domain parse:"
      assert out =~ "oneof"
    end
  end
end
