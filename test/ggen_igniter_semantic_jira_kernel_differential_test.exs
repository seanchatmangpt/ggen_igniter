defmodule GgenIgniter.SemanticJiraKernelDifferentialTest do
  @moduledoc """
  Chicago-style: the one-kernel probe for work order GGEN_IGNITER-26922-19
  (DfCM composition C14) over real collaborators only --

    * the committed v26.9.22 work-order snapshot
      (`test/fixtures/kernel_differential/v26.9.22/orders.json`, a byte copy of
      the v26.9.22 driver's orders.json, preserved in chatman-ecosystem at
      `refs/archive/pre-single-repo-migration/20260924T0600Z/shadow-files`) and the repo identities observed from
      each release/v26.9.22 integration worktree (`repos.json`);
    * the real semantic-jira-pack ontology and shape file;
    * kernel A: this repository's real SHACL court,
      `GgenIgniter.SemanticJira.Shacl`;
    * kernel B: the real vendored `praxis_graphlaw.wasm`, executed in-BEAM by
      `AshA2A.GraphLaw.WasmexHost` (Wasmtime through `wasmex`) -- the same host
      module and the same wasm bytes ash_a2a loads; their sha256 goes into the
      report.

  Both kernels receive byte-identical Turtle for every case: the whole work
  graph, every order, every mutation (with its unmutated baseline), and the
  construct calibration cases. No stub, fake or recorded kernel answer exists
  anywhere in this file (no Mox, meck, Mimic or Patch). The test writes
  `receipts/v26.9.22/kernel-differential.json`. Disagreement between the
  kernels is data: the test asserts that every difference carries a typed
  explanation and that the mutations are non-vacuous under this repository's
  court, never that the kernels agree.
  """

  # async: false -- writes one fixed tracked report path and starts named
  # wasm host processes.
  use ExUnit.Case, async: false

  @moduletag :integration
  # The whole-graph run of the Elixir court alone takes minutes (sparql 0.3
  # self-joins over ~7k triples); the probe is bounded by the 1800 s
  # acceptance budget, not ExUnit's per-test default.
  @moduletag timeout: :infinity

  alias AshA2A.GraphLaw.WasmexHost
  alias GgenIgniter.SemanticJira.KernelDifferential, as: KD

  @fixture_dir "test/fixtures/kernel_differential/v26.9.22"
  @orders_path Path.join(@fixture_dir, "orders.json")
  @repos_path Path.join(@fixture_dir, "repos.json")
  @pack_ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @shapes_path "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
  @report_path "receipts/v26.9.22/kernel-differential.json"

  @shacl "ggen_igniter.semantic_jira.shacl"
  @graphlaw "praxis_graphlaw.wasm"
  @explanation_types ["SLICE_LOCALIZED", "SLICE_LOCALIZED_WITH_RESIDUE", "NON_COMPOSITIONAL"]

  describe "probe/1 (v26.9.22 work graph through both kernels)" do
    test "writes per-order and per-mutation verdicts from both kernels with typed diffs" do
      pool = start_graphlaw_pool(min(System.schedulers_online(), 8))

      orders_json = File.read!(@orders_path)
      repos_json = File.read!(@repos_path)
      orders = Jason.decode!(orders_json)
      repos = Jason.decode!(repos_json)
      pack = GgenIgniter.Ontology.load!(@pack_ontology_path)
      shapes = GgenIgniter.Ontology.load!(@shapes_path)
      data = KD.work_graph(orders, repos["repos"], KD.vocabulary(pack))

      order_meta =
        for {repo, %{"orders" => list}} <- orders, o <- list, do: %{id: o["id"], repo: repo}

      report =
        KD.probe(
          kernels: [KD.shacl_kernel(), graphlaw_kernel(pool)],
          data: data,
          shapes: shapes,
          orders: order_meta,
          max_concurrency: length(pool)
        )

      whole = report.whole_graph.verdicts

      executed = %{
        @shacl => whole[@shacl].status != :error,
        @graphlaw => whole[@graphlaw].status != :error and WasmexHost.available?(hd(pool))
      }

      both_executed = Enum.all?(Map.values(executed))

      document =
        Map.merge(report, %{
          schema: "ggen_igniter.kernel_differential/v1",
          work_order: "GGEN_IGNITER-26922-19",
          composition: "C14",
          inputs: %{
            orders_json: %{path: @orders_path, sha256: KD.sha256(orders_json)},
            repos_json: %{
              path: @repos_path,
              sha256: KD.sha256(repos_json),
              captured_at: repos["captured_at"]
            },
            pack_ontology: %{path: @pack_ontology_path, sha256: file_sha256(@pack_ontology_path)},
            shapes: %{path: @shapes_path, sha256: file_sha256(@shapes_path)},
            work_graph: %{
              turtle_sha256: report.whole_graph.data_sha256,
              triples: RDF.Graph.triple_count(data),
              work_orders: length(order_meta)
            }
          },
          kernels: [
            %{
              name: @shacl,
              module: "GgenIgniter.SemanticJira.Shacl",
              executed: executed[@shacl]
            },
            graphlaw_identity(hd(pool)) |> Map.put(:executed, executed[@graphlaw])
          ],
          both_kernels_executed: both_executed,
          standing: if(both_executed, do: "PARTIAL_ALIVE", else: "UNKNOWN"),
          standing_rule:
            "UNKNOWN -> PARTIAL_ALIVE only if both kernels execute: the wasm engine " <>
              "loaded and neither kernel returned KERNEL_ERROR on the whole-graph case"
        })

      File.mkdir_p!(Path.dirname(@report_path))
      File.write!(@report_path, KD.encode(document) <> "\n")

      written = @report_path |> File.read!() |> Jason.decode!()

      # Both kernels executed on the real work graph.
      assert written["both_kernels_executed"] == true, inspect(written["kernels"])
      assert written["standing"] == "PARTIAL_ALIVE"
      assert Enum.map(written["kernels"], & &1["name"]) == [@shacl, @graphlaw]

      # Per-order verdicts from both kernels, one row per order in the snapshot.
      assert length(written["per_order"]) == length(order_meta)
      assert written["inputs"]["work_graph"]["work_orders"] == length(order_meta)

      for row <- written["per_order"] do
        assert Map.keys(row["verdicts"]) |> Enum.sort() == [@shacl, @graphlaw]
        assert row["id"] in Enum.map(order_meta, & &1.id)

        for {_kernel, verdict} <- row["verdicts"],
            do: assert(verdict["status"] in ["conforms", "refused", "error"])
      end

      # Per-mutation verdicts from both kernels over an admitted base.
      assert written["mutation_base"]["status"] == "SELECTED", inspect(written["mutation_base"])
      assert Enum.map(written["mutations"], & &1["id"]) == KD.mutation_ids()

      target_row =
        Enum.find(written["per_order"], &(&1["iri"] == written["mutation_base"]["target"]))

      for m <- written["mutations"] do
        assert Map.keys(m["verdicts"]) |> Enum.sort() == [@shacl, @graphlaw]
        assert Map.keys(m["baseline"]["verdicts"]) |> Enum.sort() == [@shacl, @graphlaw]

        if m["id"] == "m00_identity" do
          # Anti-vacuity, direction 1: the null mutation reproduces the base
          # and neither kernel "detects" a change that did not happen.
          assert m["classification"] == target_row["classification"]
          assert m["verdicts"][@shacl]["status"] == "conforms"
          assert m["detection"] == %{@shacl => "NOT_DETECTED", @graphlaw => "NOT_DETECTED"}
        else
          # Anti-vacuity, direction 2: every operator really breaks the rule it
          # names under the repository's own court (more violations than the
          # unmutated baseline under the same focused shapes).
          assert m["verdicts"][@shacl]["status"] == "refused",
                 "#{m["id"]} not refused by #{@shacl}"

          assert m["detection"][@shacl] == "DETECTED", "#{m["id"]} not detected by #{@shacl}"
        end
      end

      # Calibration: every construct case ran through both kernels.
      assert Enum.map(written["calibration"], & &1["id"]) ==
               Enum.map(KD.calibration_cases(), & &1.id)

      for row <- written["calibration"] do
        assert Map.keys(row["verdicts"]) |> Enum.sort() == [@shacl, @graphlaw]
      end

      # Every disagreement is a typed diff, never an untyped mismatch; every
      # localized leaf is attributed to calibration evidence or typed
      # UNCALIBRATED.
      assert written["untyped_disagreements"] == 0

      cases = [written["whole_graph"] | written["per_order"]] ++ written["mutations"]
      differing = Enum.filter(cases, & &1["differs"])

      for c <- cases do
        assert c["differs"] ==
                 (c["classification"]["class"] not in ["AGREE_ADMIT", "AGREE_REFUSE"] or
                    (is_map(c["detection"]) and length(Enum.uniq(Map.values(c["detection"]))) > 1))
      end

      for c <- differing do
        assert c["explanation"]["type"] in @explanation_types, inspect(c, limit: 20)

        for leaf <- c["explanation"]["slices"],
            do: assert(leaf["cause_type"] in ["CALIBRATED", "UNCALIBRATED"])
      end

      assert length(written["disagreements"]) == length(differing)
    end
  end

  defp start_graphlaw_pool(size) do
    for i <- 1..size do
      name = :"kernel_differential_graphlaw_#{i}"
      start_supervised!(Supervisor.child_spec({WasmexHost, name: name}, id: name))
      name
    end
  end

  # Kernel B. Round-robins over the pool: one WasmexHost serializes its own
  # wasm-bindgen transactions, so parallel cases need separate instances.
  defp graphlaw_kernel(pool) do
    counter = :atomics.new(1, [])
    size = length(pool)

    {@graphlaw,
     fn %{data_ttl: data, shapes_ttl: shapes} ->
       server = Enum.at(pool, rem(:atomics.add_get(counter, 1, 1), size))

       data
       |> WasmexHost.validate_all("", shapes, "", "", server, 600_000)
       |> graphlaw_verdict()
     end}
  end

  # validate_all/5 reports SHACL as one dialect entry. "Report: N violations"
  # is a verdict (N = report.results.len() in praxis-graphlaw-wasm core.rs);
  # "SHACL validation error: ..." is the engine failing to evaluate, which is
  # a KERNEL_ERROR, not a refusal.
  defp graphlaw_verdict({:ok, %{"dialects" => dialects}}) do
    case Enum.find(dialects, &(&1["dialect"] == "SHACL")) do
      %{"status" => "ADMITTED"} = d ->
        %{status: :conforms, violations: d["triples_out"], detail: d["detail"]}

      %{"status" => "REFUSED", "detail" => "Report: " <> _} = d ->
        %{status: :refused, violations: d["triples_out"], detail: d["detail"]}

      other ->
        %{status: :error, violations: nil, detail: inspect(other)}
    end
  end

  defp graphlaw_verdict(other), do: %{status: :error, violations: nil, detail: inspect(other)}

  defp graphlaw_identity(server) do
    wasm_path = WasmexHost.wasm_path()
    manifest = AshA2A.GraphLaw.manifest_path() |> File.read!() |> Jason.decode!()
    wasm_sha256 = file_sha256(wasm_path)

    version =
      case WasmexHost.version(server) do
        {:ok, v} -> v
        other -> inspect(other)
      end

    %{
      name: @graphlaw,
      host: "AshA2A.GraphLaw.WasmexHost",
      runtime: "wasmex #{Application.spec(:wasmex, :vsn)}",
      ash_a2a: to_string(Application.spec(:ash_a2a, :vsn)),
      graphlaw_version: version,
      wasm_sha256: wasm_sha256,
      manifest_sha256: manifest["artifact"]["sha256"],
      wasm_matches_manifest: wasm_sha256 == manifest["artifact"]["sha256"]
    }
  end

  defp file_sha256(path), do: path |> File.read!() |> KD.sha256()
end
