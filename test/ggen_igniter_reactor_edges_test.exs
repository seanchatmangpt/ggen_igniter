Code.require_file("fixtures/reactor-pack/saga_helper.exs", __DIR__)

defmodule GgenIgniter.ReactorEdgesTest do
  @moduledoc """
  Chicago-style: the step graph of a generated reactor equals the RDF `rx:dependsOn` edge set.
  A real `mix ggen_igniter.sync` subprocess renders `reactor-scaffold-pack:saga` into a tmp dir,
  the real compiler builds it against real reactor, and assertions read `Reactor.Info.to_struct!/1`
  (the compiled step/argument structs) - state, never interactions. Cyclic / dangling / malformed
  ontologies must be REFUSED with a non-zero exit and zero files written.
  """
  use ExUnit.Case, async: false
  alias B1d.SagaHelper, as: H
  alias GgenIgniter.Test.PackCompile

  @moduletag :integration
  @moduletag timeout: 600_000

  @diamond_edges %{
    a: MapSet.new(),
    b: MapSet.new([:a]),
    c: MapSet.new([:a]),
    d: MapSet.new([:b, :c])
  }

  test "compiled step graph equals the RDF dependsOn edges (diamond), in topological order" do
    H.with_saga(H.fixture("diamond.ttl"), fn [mod | _], r ->
      assert H.step_graph(mod) == @diamond_edges

      # generated step order is a topological order of the edges
      src = File.read!(hd(r.files))
      pos = fn n -> :binary.match(src, "step :#{n} do") |> elem(0) end
      assert pos.("a") < pos.("b") and pos.("a") < pos.("c")
      assert pos.("b") < pos.("d") and pos.("c") < pos.("d")

      # no wiring literal lives in the ontology
      refute H.fixture("diamond.ttl") =~ "result("
      refute H.fixture("diamond.ttl") =~ "argument"
    end)
  end

  test "FALSIFIER: re-pointing one edge (c: a -> b) flips the compiled graph" do
    ttl =
      String.replace(
        H.fixture("diamond.ttl"),
        "rx:name \"c\" ; rx:kind \"ledger\" ; rx:dependsOn ex:a .",
        "rx:name \"c\" ; rx:kind \"ledger\" ; rx:dependsOn ex:b ."
      )

    refute ttl == H.fixture("diamond.ttl")

    H.with_saga(ttl, fn [mod | _], _r ->
      graph = H.step_graph(mod)
      refute graph == @diamond_edges
      assert graph.c == MapSet.new([:b])
    end)
  end

  test "cyclic ontology is REFUSED:REACTOR_CYCLE, non-zero exit, zero files written" do
    cyclic = H.fixture("diamond.ttl") <> "\nex:a rx:dependsOn ex:d .\n"
    assert {status, out, written} = H.refuse(cyclic)
    assert status != 0
    assert out =~ "REFUSED:REACTOR_CYCLE"
    assert out =~ "a, b, c, d"
    assert written == []
  end

  test "a cycle in ONE reactor refuses the whole run: the healthy second reactor is not written" do
    healthy = """
    @prefix hx: <https://example.test/healthy#> .
    hx:reactor a rx:Reactor ; rx:moduleName "B1dFixture.Healthy" ;
      rx:outPath "lib/b1d_fixture/healthy.ex" ; rx:ledger "b1d_healthy_ledger" .
    hx:only a rx:SagaStep ; rx:inReactor hx:reactor ; rx:name "only" ; rx:kind "ledger" .
    """

    cyclic = H.fixture("diamond.ttl") <> "\nex:a rx:dependsOn ex:d .\n"
    assert {status, out, written} = H.refuse(cyclic <> healthy)
    assert status != 0
    assert out =~ "REFUSED:REACTOR_CYCLE"
    assert written == []
  end

  test "dangling edge (dependsOn a step that is not in the reactor) is REFUSED:REACTOR_DANGLING_EDGE" do
    bad =
      H.fixture("diamond.ttl") <> "\nex:d rx:dependsOn <https://example.test/diamond#ghost> .\n"

    assert {s, out, written} = H.refuse(bad)
    assert s != 0
    assert out =~ "REFUSED:REACTOR_DANGLING_EDGE"
    assert written == []
  end

  test "unknown step kind and orphan step are REFUSED (typed), not silently dropped" do
    kind =
      String.replace(
        H.fixture("diamond.ttl"),
        "rx:name \"a\" ; rx:kind \"ledger\"",
        "rx:name \"a\" ; rx:kind \"mystery\""
      )

    assert {s1, out1, w1} = H.refuse(kind)
    assert s1 != 0 and w1 == []
    assert out1 =~ "REFUSED:REACTOR_UNKNOWN_STEP_KIND"

    orphan =
      H.fixture("diamond.ttl") <>
        "\nex:lost a rx:SagaStep ; rx:name \"lost\" ; rx:kind \"ledger\" .\n"

    assert {s2, out2, w2} = H.refuse(orphan)
    assert s2 != 0 and w2 == []
    assert out2 =~ "REFUSED:REACTOR_MALFORMED"
  end

  describe "fail-closed admission of interpolated facts (REACTOR_MALFORMED, zero files written)" do
    @injections [
      {"rx:maxConcurrency", ~s|rx:returnStep "d" ; rx:maxConcurrency "abc" .|},
      {"rx:moduleName", nil},
      {"rx:ledger", nil},
      {"step rx:name", nil},
      {"rx:maxRetries", nil},
      {"rx:holdMs", nil},
      {"rx:failTimes", nil}
    ]

    defp mutate(label, ttl) do
      case label do
        "rx:maxConcurrency" ->
          String.replace(
            ttl,
            ~s|rx:returnStep "d" .|,
            ~s|rx:returnStep "d" ; rx:maxConcurrency "abc" .|
          )

        "rx:moduleName" ->
          String.replace(ttl, ~s|"B1dFixture.Diamond"|, ~s|"Zz.bad thing"|)

        "rx:ledger" ->
          String.replace(ttl, ~s|"b1d_diamond_ledger"|, ~s|"x); System.halt(); (y"|)

        "step rx:name" ->
          String.replace(ttl, ~s|rx:name "c"|, ~s|rx:name "c d"|)

        "rx:maxRetries" ->
          String.replace(
            ttl,
            ~s|rx:name "b" ; rx:kind "ledger"|,
            ~s|rx:name "b" ; rx:kind "ledger" ; rx:maxRetries "x("|
          )

        "rx:holdMs" ->
          String.replace(
            ttl,
            ~s|rx:name "b" ; rx:kind "ledger"|,
            ~s|rx:name "b" ; rx:kind "ledger" ; rx:holdMs "1); System.halt(); (1"|
          )

        "rx:failTimes" ->
          String.replace(
            ttl,
            ~s|rx:name "b" ; rx:kind "ledger"|,
            ~s|rx:name "b" ; rx:kind "ledger" ; rx:failTimes "-"|
          )
      end
    end

    for {label, _} <- @injections do
      test "malformed #{label} is REFUSED:REACTOR_MALFORMED, non-zero exit, no files" do
        base = H.fixture("diamond.ttl")
        bad = mutate(unquote(label), base)
        refute bad == base
        assert {status, out, written} = H.refuse(bad)
        assert status != 0
        assert out =~ "REFUSED:REACTOR_MALFORMED"
        assert written == []
      end
    end

    test "valid numeric facts still generate and compile" do
      ttl =
        String.replace(
          H.fixture("diamond.ttl"),
          ~s|rx:name "b" ; rx:kind "ledger"|,
          ~s|rx:name "b" ; rx:kind "ledger" ; rx:maxRetries "2" ; rx:holdMs "1" ; rx:failTimes "0"|
        )

      H.with_saga(ttl, fn [mod | _], _r -> assert H.step_graph(mod) == @diamond_edges end)
    end
  end

  test "out path is fact-driven: --dry-run without --out plans exactly the rx:outPath fact" do
    dir = PackCompile.tmp_project!(%{"o.ttl" => H.fixture("diamond.ttl")})

    {out, 0} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--pack",
          "reactor-scaffold-pack:saga",
          "--engine",
          "sparql",
          "--ontology",
          Path.join(dir, "o.ttl"),
          "--dry-run",
          "--manifest-dir",
          dir,
          "--verify-cwd",
          File.cwd!()
        ],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    PackCompile.cleanup(dir)
    assert out =~ "lib/b1d_fixture/diamond.ex"
    refute File.exists?("lib/b1d_fixture/diamond.ex")
  end

  describe "Mermaid diagram template (saga_diagram)" do
    @with_diagram String.replace(
                    File.read!(Path.expand("fixtures/reactor-pack/diamond.ttl", __DIR__)),
                    "rx:returnStep \"d\" .",
                    "rx:returnStep \"d\" ; rx:diagramPath \"docs/diamond.md\" ."
                  )

    defp parse_edges(md) do
      for [_, from, arrow, to] <- Regex.scan(~r/^\s+(\w+) (-->|-\.->) (\w+)$/m, md),
          into: MapSet.new(),
          do: {String.to_atom(from), String.to_atom(to), arrow}
    end

    test "every step and every RDF edge appears in the diagram, and equals the compiled graph" do
      diagram =
        H.render!(@with_diagram, "reactor-scaffold-pack:saga_diagram", "<%= diagram_path %>")

      on_exit(fn -> PackCompile.cleanup(diagram.out_dir) end)
      md = File.read!(Enum.find(diagram.files, &String.ends_with?(&1, "docs/diamond.md")))

      for n <- ~w(a b c d), do: assert(md =~ "#{n}[\"#{n}\"]")

      edges = parse_edges(md)

      assert MapSet.new(edges, fn {f, t, _} -> {f, t} end) ==
               MapSet.new([{:a, :b}, {:a, :c}, {:b, :d}, {:c, :d}])

      H.with_saga(@with_diagram, fn [mod | _], _ ->
        from_graph =
          for {step, ups} <- H.step_graph(mod), up <- ups, into: MapSet.new(), do: {up, step}

        assert MapSet.new(edges, fn {f, t, _} -> {f, t} end) == from_graph
      end)
    end

    test "FALSIFIER: a removed edge disappears from the diagram" do
      ttl = String.replace(@with_diagram, "rx:dependsOn ex:b, ex:c .", "rx:dependsOn ex:b .")
      refute ttl == @with_diagram
      diagram = H.render!(ttl, "reactor-scaffold-pack:saga_diagram", "<%= diagram_path %>")
      on_exit(fn -> PackCompile.cleanup(diagram.out_dir) end)
      md = File.read!(Enum.find(diagram.files, &String.ends_with?(&1, "docs/diamond.md")))
      refute md =~ "c --> d"
      assert md =~ "b --> d"
    end
  end
end
