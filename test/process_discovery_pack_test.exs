defmodule GgenIgniter.ProcessDiscoveryPackTest do
  @moduledoc """
  Chicago-style tests over the real `process-discovery-pack` templates
  (`priv/ggen/process-discovery-pack/`): real `Ontology.load!/1` +
  `Query.run/2` + `Render.render/2` calls against the real pack ontology and
  real `.eex` template files on disk, state-based assertions on the real
  rendered source string (`Code.string_to_quoted!/1` — it must actually
  parse as Elixir — plus real signature substrings). No mocks.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Frontmatter, Ontology, Query, Render}

  @pack_dir "priv/ggen/process-discovery-pack"

  defp render_template!(template_stem, namespace) do
    graph = Ontology.load!(Path.join(@pack_dir, "ontology.ttl"))

    rows =
      Query.run(graph, File.read!(Path.join(@pack_dir, "gates/010_config.rq")))

    assert [%{"namespace" => _}] = rows

    bindings = [namespace: namespace]

    {_frontmatter, _mode, body} =
      Path.join(@pack_dir, "templates/#{template_stem}.ex.eex")
      |> File.read!()
      |> Frontmatter.split_template()

    Render.render(body, bindings)
  end

  test "inductive_miner template renders valid Elixir with the given namespace" do
    source = render_template!("inductive_miner", "Beam4pm.PM")

    assert Code.string_to_quoted!(source)

    assert source =~ "defmodule Beam4pm.PM.Discovery.InductiveMiner do"
    assert source =~ "def mine(log) when is_list(log) do"
    assert source =~ "def directly_follows_graph(log) when is_list(log) do"
    assert source =~ "def detect_exclusive_choice_cut(sigma, dfg) do"
    assert source =~ "def detect_sequence_cut(sigma, dfg) do"
  end

  test "token_replay template renders valid Elixir with the given namespace" do
    source = render_template!("token_replay", "Beam4pm.PM")

    assert Code.string_to_quoted!(source)

    assert source =~ "defmodule Beam4pm.PM.Conformance.TokenReplay do"
    assert source =~ "alias Beam4pm.PM.Discovery.InductiveMiner.ProcessTree"
    assert source =~ "def replay(%ProcessTree{} = tree, trace) when is_list(trace) do"
    assert source =~ "def fitness_from_counts("
  end

  test "rendered inductive_miner + token_replay modules actually compile and run together" do
    miner_src = render_template!("inductive_miner", "Beam4pmSmoke")
    replay_src = render_template!("token_replay", "Beam4pmSmoke")

    miner_compiled = Code.compile_string(miner_src)
    replay_compiled = Code.compile_string(replay_src)

    on_exit(fn ->
      for {mod, _} <- miner_compiled ++ replay_compiled do
        :code.purge(mod)
        :code.delete(mod)
      end
    end)

    assert {Beam4pmSmoke.Discovery.InductiveMiner, _} =
             List.keyfind(miner_compiled, Beam4pmSmoke.Discovery.InductiveMiner, 0)

    assert {Beam4pmSmoke.Conformance.TokenReplay, _} =
             List.keyfind(replay_compiled, Beam4pmSmoke.Conformance.TokenReplay, 0)

    log = [["a", "b"], ["a", "b"]]
    assert {:ok, tree} = Beam4pmSmoke.Discovery.InductiveMiner.mine(log)

    result = Beam4pmSmoke.Conformance.TokenReplay.replay(tree, ["a", "b"])
    assert result.fitness == 1.0
    assert result.missing == 0
    assert result.remaining == 0
  end

  test "mix ggen_igniter.doctor --pack process-discovery-pack passes checks 9-12" do
    {output, 0} =
      System.cmd("mix", ["ggen_igniter.doctor", "--pack", "process-discovery-pack"],
        stderr_to_stdout: true
      )

    assert output =~ "ontology.ttl"
    refute output =~ "FAIL"
  end
end
