defmodule GgenIgniter.SyncBeam4pmBenchPackTest do
  @moduledoc """
  Chicago-style, no-mocks proof that `priv/ggen/beam4pm-bench-pack`'s three
  real templates (`virtual_cost.ex.eex`, `topology.ex.eex`,
  `wasm_engine_benchmark_test.exs.eex`) render, via real
  `mix ggen_igniter.sync` subprocess invocations, into real, valid,
  namespace-parameterized Elixir source containing the expected function
  signatures ported from ex4pm's own real reference benchmarks -- and that
  the Wasm template's required `wasm_adapter_module` binding is real and
  load-bearing (rendering without it fails fast; rendering with it produces
  source referencing exactly the supplied adapter module).
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @pack "priv/ggen/beam4pm-bench-pack"

  defp tmp_out_dir(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_beam4pm_bench_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  test "virtual_cost.ex.eex renders a real, valid, namespace-parameterized VirtualCost module" do
    out_dir = tmp_out_dir("virtual_cost")
    out_path = Path.join(out_dir, "virtual_cost.ex")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--ontology",
      "#{@pack}/ontology.ttl",
      "--query",
      "virtual_cost=#{@pack}/gates/010_virtual_cost.rq",
      "--template",
      "#{@pack}/templates/virtual_cost.ex.eex",
      "--out",
      out_path,
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync (virtual_cost) failed:\n#{output}"
    assert File.exists?(out_path)

    content = File.read!(out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "defmodule Beam4pm.Bench.VirtualCost do"
    assert content =~ "def new, do: %__MODULE__{compute: 0, store: 0, send: 0}"
    assert content =~ "def compute(%__MODULE__{} = c, n \\\\ 1)"
    assert content =~ "def store(%__MODULE__{} = c, n \\\\ 1)"
    assert content =~ "def send_op(%__MODULE__{} = c, n \\\\ 1)"
    assert content =~ "def merge(%__MODULE__{} = a, %__MODULE__{} = b)"
    assert content =~ "def sum(counters)"
    assert content =~ "def total(%__MODULE__{compute: c, store: s, send: sd})"

    # Prove it's real, loadable Elixir with the expected real behavior, not
    # just text that happens to parse.
    [{mod, _bin}] = Code.compile_file(out_path)
    assert mod == Beam4pm.Bench.VirtualCost
    fresh = mod.new()
    assert mod.total(fresh) == 0
    incremented = fresh |> mod.compute(2) |> mod.store(1) |> mod.send_op()
    assert mod.total(incremented) == 4
  end

  test "topology.ex.eex renders a real, valid, namespace-parameterized Topology module aliasing VirtualCost" do
    out_dir = tmp_out_dir("topology")
    out_path = Path.join(out_dir, "topology.ex")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--ontology",
      "#{@pack}/ontology.ttl",
      "--query",
      "topology=#{@pack}/gates/020_topology.rq",
      "--template",
      "#{@pack}/templates/topology.ex.eex",
      "--out",
      out_path,
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync (topology) failed:\n#{output}"
    assert File.exists?(out_path)

    content = File.read!(out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "defmodule Beam4pm.Bench.Topology do"
    assert content =~ "alias Beam4pm.Bench.VirtualCost"
    assert content =~ "def run_centralized(events) when is_list(events)"
    assert content =~ "def run_edge(events, node_count)"
    assert content =~ "def synthetic_log(case_count)"
  end

  test "virtual_cost.ex.eex and topology.ex.eex compile and run together as real collaborators" do
    out_dir = tmp_out_dir("combined")
    vc_path = Path.join(out_dir, "virtual_cost.ex")
    topo_path = Path.join(out_dir, "topology.ex")

    for {query_name, query_file, template, out_path} <- [
          {"virtual_cost", "010_virtual_cost.rq", "virtual_cost.ex.eex", vc_path},
          {"topology", "020_topology.rq", "topology.ex.eex", topo_path}
        ] do
      args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--ontology",
        "#{@pack}/ontology.ttl",
        "--query",
        "#{query_name}=#{@pack}/gates/#{query_file}",
        "--template",
        "#{@pack}/templates/#{template}",
        "--out",
        out_path,
        "--manifest-dir",
        out_dir,
        "--verify-cwd",
        File.cwd!()
      ]

      {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
      assert exit_code == 0, "mix ggen_igniter.sync (#{query_name}) failed:\n#{output}"
    end

    [{vc_mod, _}] = Code.compile_file(vc_path)
    [{topo_mod, _}] = Code.compile_file(topo_path)
    assert vc_mod == Beam4pm.Bench.VirtualCost
    assert topo_mod == Beam4pm.Bench.Topology

    log = topo_mod.synthetic_log(6)
    assert log != []

    {centralized_dfg, centralized_cost} = topo_mod.run_centralized(log)
    {edge_dfg, edge_cost} = topo_mod.run_edge(log, 3)

    # Real correctness invariant this harness exists to check (mirrors
    # ex4pm's own reference topology.ex moduledoc claim): both topologies
    # produce the same merged DFG for the same input log.
    assert centralized_dfg == edge_dfg
    assert vc_mod.total(centralized_cost) > 0
    assert vc_mod.total(edge_cost) > 0
  end

  test "wasm_engine_benchmark_test.exs.eex renders real source referencing the supplied wasm_adapter_module" do
    out_dir = tmp_out_dir("wasm_ok")
    out_path = Path.join(out_dir, "wasm_engine_benchmark_test.exs")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--ontology",
      "test/fixtures/beam4pm-bench-pack-wasm-adapter/ontology.ttl",
      "--query",
      "wasm_bench=#{@pack}/gates/030_wasm_bench.rq",
      "--query",
      "adapter=test/fixtures/beam4pm-bench-pack-wasm-adapter/adapter.rq",
      "--template",
      "#{@pack}/templates/wasm_engine_benchmark_test.exs.eex",
      "--out",
      out_path,
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    assert exit_code == 0, "mix ggen_igniter.sync (wasm bench, with adapter) failed:\n#{output}"
    assert File.exists?(out_path)

    content = File.read!(out_path)
    assert {:defmodule, _, _} = Code.string_to_quoted!(content)
    assert content =~ "defmodule Beam4pm.WasmEngineBenchmarkTest do"
    assert content =~ "alias Beam4pm.Engine"
    assert content =~ "Code.ensure_loaded?(Elixir.String)"
    assert content =~ "BENCHMARK 6a: Wasmtime instantiation + call wall-clock over N iterations"

    assert content =~
             "BENCHMARK 6b: Wasmex.call_function/4 honors a real bounded timeout against a real infinite-loop export"
  end

  test "wasm_engine_benchmark_test.exs.eex refuses to render without a wasm_adapter_module binding" do
    out_dir = tmp_out_dir("wasm_missing")
    out_path = Path.join(out_dir, "wasm_engine_benchmark_test.exs")

    args = [
      "ggen_igniter.sync",
      "--engine",
      "sparql",
      "--ontology",
      "#{@pack}/ontology.ttl",
      "--query",
      "wasm_bench=#{@pack}/gates/030_wasm_bench.rq",
      "--template",
      "#{@pack}/templates/wasm_engine_benchmark_test.exs.eex",
      "--out",
      out_path,
      "--manifest-dir",
      out_dir,
      "--verify-cwd",
      File.cwd!()
    ]

    {output, exit_code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    refute exit_code == 0,
           "expected sync to fail fast without a wasm_adapter_module binding, but it exited 0:\n#{output}"

    refute File.exists?(out_path)
  end
end
