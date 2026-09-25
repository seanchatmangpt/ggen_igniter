defmodule GgenIgniter.SemanticJiraGoalCheckpointTest do
  @moduledoc """
  Chicago-style: proof of the Friday GoalCheckpoint vocabulary contract
  (GC-FRI-0800, v26.9.22 G4) in semantic-jira-pack.

  Real collaborators only: the real SHACL court
  (`GgenIgniter.SemanticJira.Shacl`) over the real shipped
  `shapes/work-order.shacl.ttl`; the real pack `ontology.ttl` merged with the
  real fixture goal graph `test/fixtures/semantic-jira-goal-checkpoint/goal.ttl`
  written to a unique tmp file and read back through the real Turtle loader;
  the real `GgenIgniter.SemanticJira.KernelDifferential.work_graph/3`
  projection of the committed v26.9.22 `orders.json` (the pre-Friday legacy
  orders); the real `GgenIgniter.SemanticJira.machine_experience/1`; the real
  `GgenIgniter.Reactors.ReconcileReactor.plan/1` admission path; the real pack
  gates through `GgenIgniter.Query.run/2` and the real `jira.md.eex` through
  `GgenIgniter.Render.render/2`; and one real `mix ggen_igniter.sync`
  subprocess. No mocks, stubs or test doubles.
  """

  # async: false -- the sync subprocess shares this checkout's _build and the
  # tests write merged graphs under System.tmp_dir!().
  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.{Pack, Query, Receipt, Render, SemanticJira}
  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.SemanticJira.{KernelDifferential, Shacl}

  @pack_dir "priv/ggen/semantic-jira-pack"
  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @shapes_path "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
  @goal_path "test/fixtures/semantic-jira-goal-checkpoint/goal.ttl"
  @kd_dir "test/fixtures/kernel_differential/v26.9.22"
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @order @sj <> "gc-fixture-wo-1"
  @root @sj <> "gc-fixture-root"
  @gate @sj <> "gc-fixture-g4"

  @friday_shapes ~w(checkpoint_shape goal_checkpoint_shape boundary_class_value_shape
                    capability_shape friday_work_order_shape machine_experience_shape)

  # The full tuple of a Friday order: removing any one required field must
  # refuse and name that field as the violation path. Fields already
  # sh:minCount 1 on sj:WorkOrderShape refuse there; the Friday additions
  # refuse on sj:FridayWorkOrderShape's per-field SPARQL constraints.
  # sj:exclusion is deliberately absent: the shared vocabulary contract makes
  # it 0..n (see "zero sj:exclusion admits" below).
  @mutation_table [
    {"subject", "work_order_shape", :min_count},
    {"repository", "work_order_shape", :min_count},
    {"baseSha", "work_order_shape", :min_count},
    {"pathScope", "work_order_shape", :min_count},
    {"evidenceCeiling", "work_order_shape", :min_count},
    {"authorityCeiling", "work_order_shape", :min_count},
    {"postcondition", "friday_work_order_shape", :sparql},
    {"requiresCapability", "friday_work_order_shape", :sparql},
    {"evidenceHorizon", "friday_work_order_shape", :sparql},
    {"consequenceClass", "friday_work_order_shape", :sparql},
    {"successorPolicy", "friday_work_order_shape", :sparql},
    # SJ-002: sh:minCount 1 on sj:WorkOrderShape itself (R2 global minCount),
    # so the removal refuses there, not on a Friday SPARQL constraint (R8).
    {"originAuthority", "work_order_shape", :min_count}
  ]

  describe "Shacl.validate_file/2 (goal graph merged with the pack ontology)" do
    test "a GoalCheckpoint graph with one tuple-complete Friday order admits" do
      report = validate_goal!(goal_source())

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
      assert report.violations == []

      for shape <- @friday_shapes do
        assert shape in report.shapes_checked, "#{shape} was not checked"
      end

      assert {:ok, results} = Shacl.run(@pack_dir, write_merged!(goal_source()))
      assert {"friday_work_order_shape", :pass} in results
      assert {"goal_checkpoint_shape", :pass} in results
      # 19 pre-SJ-002 shapes + work_order_origin_shape + admission_digest_shape
      # (v26.9.24 R10) + authority_trust_root_shape (G1, v26.9.25); the same
      # count Shacl.run reports here.
      assert length(results) == 22
    end

    for {field, shape, constraint} <- @mutation_table do
      test "removing sj:#{field} from the Friday order refuses and names the field" do
        field = unquote(field)
        line = ~r/^    sj:#{field} [^\n]*;\n/m
        source = goal_source()

        assert length(Regex.scan(line, source)) == 1,
               "fixture must carry exactly one sj:#{field} line on the order"

        report = validate_goal!(Regex.replace(line, source, "", global: false))

        refute report.conforms

        violation =
          fetch_violation!(report,
            focus_node: @order,
            path: @sj <> field,
            shape: unquote(shape),
            constraint: unquote(constraint)
          )

        if unquote(constraint) == :sparql, do: assert(violation.message =~ "sj:#{field}")
      end
    end

    test "a second sj:postcondition violates the tuple's sh:maxCount" do
      report =
        goal_source()
        |> replace_once!(
          "    sj:evidenceHorizon \"EXECUTED_VERIFIED\" ;\n",
          "    sj:evidenceHorizon \"EXECUTED_VERIFIED\" ;\n    sj:postcondition \"a second, competing postcondition\" ;\n"
        )
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @order,
        path: @sj <> "postcondition",
        constraint: :max_count
      )
    end

    test "a consequence class outside the receipt-class vocabulary refuses" do
      report =
        goal_source()
        |> replace_once!("sj:consequenceClass \"verification\"", "sj:consequenceClass \"merge\"")
        |> validate_goal!()

      violation =
        fetch_violation!(report, path: @sj <> "consequenceClass", constraint: :pattern)

      assert violation.value == "merge"
    end

    test "a whitespace-only exclusion refuses (an exclusion must state a premise)" do
      report =
        goal_source()
        |> replace_once!("\"no network access during the episode\"", "\"   \"")
        |> validate_goal!()

      fetch_violation!(report, focus_node: @order, path: @sj <> "exclusion", constraint: :pattern)
    end

    test "a Friday order with zero sj:exclusion admits (the contract's 0..n)" do
      source = replace_once!(goal_source(), ~r/^    sj:exclusion [^\n]*;\n/m, "")
      refute source =~ "sj:exclusion"

      report = validate_goal!(source)

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
      assert "friday_work_order_shape" in report.shapes_checked
      refute Enum.any?(report.violations, &(&1.path == @sj <> "exclusion"))
    end

    test "a non-literal sj:exclusion refuses (each exclusion present is an xsd:string)" do
      report =
        goal_source()
        |> replace_once!(
          "sj:exclusion \"no LLM on the KNOWN path\", \"no network access during the episode\"",
          "sj:exclusion sj:gc-fixture-root"
        )
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @order,
        path: @sj <> "exclusion",
        constraint: :datatype,
        shape: "work_order_shape"
      )
    end

    test "sj:checkpointOf must point at a GoalCheckpoint" do
      report =
        goal_source()
        |> replace_once!(
          "    sj:checkpointOf sj:gc-fixture-g4 ;\n",
          "    sj:checkpointOf sj:cap-recipe-mix-format ;\n"
        )
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @order,
        path: @sj <> "checkpointOf",
        constraint: :class
      )
    end

    test "sj:originAuthority must point at a GoalCheckpoint (SJ-002 origin type law)" do
      report =
        goal_source()
        |> replace_once!(
          "    sj:originAuthority sj:gc-fixture-root ;\n",
          "    sj:originAuthority sj:cap-recipe-mix-format ;\n"
        )
        |> validate_goal!()

      violation =
        fetch_violation!(report,
          focus_node: @order,
          path: @sj <> "originAuthority",
          shape: "work_order_origin_shape"
        )

      assert violation.message =~ "NON_SEMANTIC_WORK_AUTHORITY"
    end

    test "sj:requiresCapability must point at a typed sj:Capability" do
      report =
        goal_source()
        |> replace_once!(
          "sj:requiresCapability sj:cap-recipe-mix-format",
          "sj:requiresCapability sj:cap-untyped"
        )
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @order,
        path: @sj <> "requiresCapability",
        constraint: :class
      )
    end
  end

  describe "Shacl.validate_file/2 (GoalCheckpoint laws)" do
    test "a root GoalCheckpoint without sj:stopQuery is refused" do
      stop_query = ~r/^    sj:stopQuery """.*?""" ;\n/ms
      source = goal_source()
      assert length(Regex.scan(stop_query, source)) == 1

      report = validate_goal!(Regex.replace(stop_query, source, "", global: false))

      refute report.conforms

      violation =
        fetch_violation!(report,
          focus_node: @root,
          shape: "goal_checkpoint_shape",
          path: @sj <> "stopQuery",
          constraint: :sparql
        )

      assert violation.message =~ "root GoalCheckpoint"
    end

    test "a stop query that is not a SPARQL ASK is refused" do
      report =
        goal_source()
        |> replace_once!("sj:stopQuery \"ASK { }\"", "sj:stopQuery \"SELECT * WHERE { }\"")
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @sj <> "gc-fixture-successor",
        path: @sj <> "stopQuery",
        constraint: :pattern
      )
    end

    test "a non-root GoalCheckpoint without sj:courtCommand is refused" do
      report =
        goal_source()
        |> replace_once!(
          " ;\n    sj:courtCommand \"mix test test/ggen_igniter_semantic_jira_goal_checkpoint_test.exs\" .\n",
          " .\n"
        )
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @gate,
        shape: "goal_checkpoint_shape",
        path: @sj <> "courtCommand",
        constraint: :sparql
      )
    end

    test "a non-root GoalCheckpoint without sj:boundaryClass is refused" do
      report =
        goal_source()
        |> replace_once!("    sj:boundaryClass sj:Core ;\n", "")
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @gate,
        shape: "goal_checkpoint_shape",
        path: @sj <> "boundaryClass",
        constraint: :sparql
      )
    end

    test "a boundary class outside the closed enumeration is refused" do
      report =
        goal_source()
        |> replace_once!("sj:boundaryClass sj:Core", "sj:boundaryClass sj:Somewhere")
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @gate,
        shape: "boundary_class_value_shape",
        path: @sj <> "boundaryClass",
        constraint: :sparql
      )
    end

    test "every declared boundary class individual is inside the enumeration" do
      # sj:Core is the fixture's own value (admitted by the base-graph test).
      for boundary <- ~w(Bootstrap FirstMile LastMile Successor) do
        report =
          goal_source()
          |> replace_once!("sj:boundaryClass sj:Core", "sj:boundaryClass sj:#{boundary}")
          |> validate_goal!()

        assert report.conforms,
               "#{boundary}: #{inspect(report.violations, pretty: true)}"
      end
    end

    test "a GoalCheckpoint that is its own parent is refused" do
      report =
        goal_source()
        |> replace_once!(
          "    sj:checkpointOf sj:gc-fixture-root ;\n",
          "    sj:checkpointOf sj:gc-fixture-g4 ;\n"
        )
        |> validate_goal!()

      violation =
        fetch_violation!(report,
          focus_node: @gate,
          shape: "goal_checkpoint_shape",
          constraint: :sparql,
          path: nil
        )

      assert violation.message =~ "its own parent"
    end

    test "a capability without a well-formed sj:capabilityId is refused" do
      report =
        goal_source()
        |> replace_once!(
          "sj:capabilityId \"recipe:mix-format\"",
          "sj:capabilityId \"mix format\""
        )
        |> validate_goal!()

      fetch_violation!(report,
        focus_node: @sj <> "cap-recipe-mix-format",
        shape: "capability_shape",
        path: @sj <> "capabilityId",
        constraint: :pattern
      )
    end

    # The G5 hop's capability grammar, copied verbatim from xaas
    # lib/xaas/sa2a/route.ex @capability (friday/gc-fri-0800 f8bca07, merged
    # FRI-T4). The G4 SHACL court must admit exactly the ids this admits.
    @sa2a_capability ~r/\A([a-z0-9][a-z0-9_.-]*):([a-z0-9][a-z0-9_.:-]*)\z/

    # {capabilityId, admitted?}: both lanes' verdicts are asserted against
    # this column, so a divergence in either direction fails.
    @capability_corpus [
      {"recipe:mix-format", true},
      {"construct:xaas-mix-task", true},
      {"construct:ggen_igniter-lane", true},
      {"recipe:mix.format:v2", true},
      {"9x:y", true},
      {"a:b", true},
      {"mix format", false},
      {"recipe:Mix/Format", false},
      {"Recipe:mix-format", false},
      {"recipe:", false},
      {":mix-format", false},
      {"recipe:-mix-format", false},
      {"recipe:mix format", false},
      {"recipe:mix-format\n", false}
    ]

    test "sj:capabilityId admits exactly the ids the SA2A route grammar admits" do
      shapes = GgenIgniter.Ontology.load!(@shapes_path)
      capability = RDF.iri(@sj <> "cap-corpus")

      for {id, admitted?} <- @capability_corpus do
        assert Regex.match?(@sa2a_capability, id) == admitted?,
               "SA2A route grammar verdict for #{inspect(id)} is not #{admitted?}"

        report =
          RDF.Graph.new([
            {capability, RDF.type(), RDF.iri(@sj <> "Capability")},
            {capability, RDF.iri(@sj <> "capabilityId"), RDF.literal(id)}
          ])
          |> Shacl.validate(shapes)

        assert "capability_shape" in report.shapes_checked

        refused? =
          Enum.any?(
            report.violations,
            &(&1.shape == "capability_shape" and &1.path == @sj <> "capabilityId" and
                &1.constraint == :pattern)
          )

        assert refused? == not admitted?,
               "SHACL verdict for #{inspect(id)} diverges from the SA2A route: " <>
                 inspect(report.violations, pretty: true)
      end
    end
  end

  describe "Shacl.validate_file/2 (pre-Friday orders are unaffected)" do
    test "the canonical pack ontology (34 orders: 33 legacy + SJ-002, no sj:checkpointOf) still conforms" do
      report = Shacl.validate_file(@ontology_path, @shapes_path)

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"

      graph = GgenIgniter.Ontology.load!(@ontology_path)
      assert length(KernelDifferential.order_iris(graph)) == 34

      refute Enum.any?(RDF.Graph.triples(graph), fn {_s, p, _o} ->
               p == RDF.iri(@sj <> "checkpointOf")
             end)
    end

    test "dropping sj:checkpointOf and the whole tuple leaves an order that admits as legacy" do
      source =
        Enum.reduce(
          ~w(postcondition requiresCapability evidenceHorizon exclusion consequenceClass
             successorPolicy),
          replace_once!(goal_source(), "    sj:checkpointOf sj:gc-fixture-g4 ;\n", ""),
          fn field, acc -> replace_once!(acc, ~r/^    sj:#{field} [^\n]*;\n/m, "") end
        )

      refute source =~ ~r/^    sj:(postcondition|exclusion|successorPolicy) /m
      assert source =~ "    sj:checkpointOf sj:gc-fixture-root ;\n"
      report = validate_goal!(source)

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
    end

    @tag timeout: :timer.minutes(5)
    test "the KernelDifferential legacy work graph gains no violation from the Friday shapes" do
      orders = @kd_dir |> Path.join("orders.json") |> File.read!() |> Jason.decode!()
      repos = @kd_dir |> Path.join("repos.json") |> File.read!() |> Jason.decode!()
      pack = GgenIgniter.Ontology.load!(@ontology_path)

      data =
        KernelDifferential.work_graph(orders, repos["repos"], KernelDifferential.vocabulary(pack))

      legacy_orders = KernelDifferential.order_iris(data)
      assert length(legacy_orders) == 169

      friday_predicates =
        MapSet.new(
          ~w(checkpointOf boundaryClass courtCommand stopQuery successorOf postcondition
             requiresCapability evidenceHorizon exclusion consequenceClass successorPolicy),
          &RDF.iri(@sj <> &1)
        )

      refute Enum.any?(RDF.Graph.triples(data), fn {_s, p, _o} -> p in friday_predicates end)

      shapes = GgenIgniter.Ontology.load!(@shapes_path)

      pre_friday_shapes =
        Enum.reduce(@friday_shapes, shapes, fn name, acc ->
          RDF.Graph.delete_descriptions(acc, RDF.iri(@sj <> Macro.camelize(name)))
        end)

      full = Shacl.validate(data, shapes)
      pre_friday = Shacl.validate(data, pre_friday_shapes)

      refute Enum.any?(full.violations, &(&1.shape in @friday_shapes)),
             inspect(Enum.filter(full.violations, &(&1.shape in @friday_shapes)), pretty: true)

      assert Enum.sort_by(full.violations, &inspect/1) ==
               Enum.sort_by(pre_friday.violations, &inspect/1)

      assert length(full.shapes_checked) == length(pre_friday.shapes_checked) + 6
    end
  end

  describe "SemanticJira.machine_experience/1 -> sj:MachineExperienceShape" do
    # machine_experience/1 map key -> RDF property of the shape. Every key the
    # real function emits (except "kind", which is rdf:type) must be mapped,
    # so a new field in the function without a shape property fails here.
    @experience_fields %{
      "subject" => "subject",
      "work_order_digest" => "workOrderDigest",
      "execution_receipt_hash" => "executionReceiptHash",
      "observation_refs" => "observationRef",
      "verification_digest" => "verificationDigest",
      "resulting_state_digest" => "resultingStateDigest",
      "replay_identity" => "replayIdentity",
      "standing" => "standing",
      "authority" => "authorityClaim",
      "experience_digest" => "experienceDigest"
    }

    test "a manufactured MachineExperience conforms; ALIVE standing or an authority triple refuses" do
      experience = manufactured_experience!()

      assert experience |> Map.keys() |> Enum.sort() ==
               ["kind" | Map.keys(@experience_fields)] |> Enum.sort()

      shapes = GgenIgniter.Ontology.load!(@shapes_path)
      graph = experience_graph(experience)

      report = Shacl.validate(graph, shapes)
      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
      assert "machine_experience_shape" in report.shapes_checked

      promoted = Shacl.validate(experience_graph(%{experience | "standing" => "ALIVE"}), shapes)
      fetch_violation!(promoted, path: @sj <> "standing", constraint: :has_value)

      with_authority =
        graph
        |> RDF.Graph.add({experience_iri(), RDF.iri(@sj <> "authority"), RDF.iri(@sj <> "grant")})
        |> Shacl.validate(shapes)

      fetch_violation!(with_authority,
        path: @sj <> "authority",
        constraint: :closed,
        shape: "machine_experience_shape"
      )

      unobserved =
        graph
        |> RDF.Graph.delete(
          Enum.map(experience["observation_refs"], fn ref ->
            {experience_iri(), RDF.iri(@sj <> "observationRef"), RDF.literal(ref)}
          end)
        )
        |> Shacl.validate(shapes)

      fetch_violation!(unobserved, path: @sj <> "observationRef", constraint: :min_count)
    end
  end

  describe "ReconcileReactor.plan/1 (pack admission path)" do
    test "a Friday order missing its postcondition refuses before any receipt" do
      work_dir = scratch_dir!("plan_refusal")

      ontology =
        goal_source()
        |> replace_once!(~r/^    sj:postcondition [^\n]*;\n/m, "")
        |> write_merged!()

      assert {:error, {:refused_semantic_jira_shacl, violations}} =
               ReconcileReactor.plan(
                 pack: "semantic-jira-pack",
                 ontology: ontology,
                 manifest_dir: work_dir
               )

      assert Enum.any?(
               violations,
               &(&1.path == @sj <> "postcondition" and &1.focus_node == @order)
             )

      assert Receipt.read_all!(work_dir) == []
    end
  end

  describe "jira.md.eex (Render.render/2 over the real pack gates)" do
    test "a Friday order renders its tuple; a legacy order renders byte-for-byte without it" do
      graph = GgenIgniter.Ontology.load!(write_merged!(goal_source()))

      friday = render_ticket!(graph, "GC-FIXTURE-WO-1")
      legacy = render_ticket!(graph, "SJ-001")

      assert friday =~ "## Friday tuple\n\n"
      assert friday =~ "- **Checkpoint of:** **GC-FIXTURE G4 finite work graph** — Gate closed"

      assert friday =~
               "- **Postcondition:** mix format --check-formatted exits 0 on the exact subject SHA"

      assert friday =~
               "- **Required capability:** **Recipe: mix format** — Deterministic formatter"

      assert friday =~ "- **Evidence horizon:** EXECUTED_VERIFIED"
      assert friday =~ "- **Consequence class:** verification"

      assert friday =~
               "  - no LLM on the KNOWN path\n  - no network access during the episode\n\n## Dependencies"

      refute legacy =~ "Friday tuple"
      assert legacy =~ "graph_hash.\n\n## Dependencies"
    end

    test "a Friday order with zero exclusions renders \"none\" instead of refusing (0..n)" do
      graph =
        goal_source()
        |> replace_once!(~r/^    sj:exclusion [^\n]*;\n/m, "")
        |> write_merged!()
        |> GgenIgniter.Ontology.load!()

      friday = render_ticket!(graph, "GC-FIXTURE-WO-1")

      assert friday =~ "## Friday tuple\n\n"
      assert friday =~ "- **Exclusions:** none\n\n## Dependencies"
      refute friday =~ "  - no LLM on the KNOWN path"
    end

    test "the template refuses a Friday order missing a tuple field even when SHACL is bypassed" do
      graph =
        goal_source()
        |> replace_once!(~r/^    sj:successorPolicy [^\n]*;\n/m, "")
        |> write_merged!()
        |> GgenIgniter.Ontology.load!()

      error = assert_raise ArgumentError, fn -> render_ticket!(graph, "SJ-001") end

      assert error.message =~ "REFUSED:SEMANTIC_JIRA_INVALID_WORK_ORDER"
      assert error.message =~ "Friday tuple field sj:successorPolicy missing for GC-FIXTURE-WO-1"
    end
  end

  describe "mix ggen_igniter.sync (real subprocess over the merged goal graph)" do
    @tag timeout: :timer.minutes(5)
    test "manufactures the Friday ticket beside all 34 orders (33 legacy + SJ-002) with a graph-bound receipt" do
      work_dir = scratch_dir!("sync")
      ontology = write_merged!(goal_source())

      {output, exit_code} =
        System.cmd(
          "mix",
          [
            "ggen_igniter.sync",
            "--engine",
            "sparql",
            "--pack",
            "semantic-jira-pack:jira",
            "--ontology",
            ontology,
            "--out",
            Path.join(work_dir, "<%= id %>.md"),
            "--manifest-dir",
            work_dir,
            "--verify-cwd",
            File.cwd!()
          ],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      assert exit_code == 0, "sync failed:\n#{output}"
      assert length(Path.wildcard(Path.join(work_dir, "*.md"))) == 35

      friday = File.read!(Path.join(work_dir, "GC-FIXTURE-WO-1.md"))
      assert friday =~ "# GC-FIXTURE-WO-1 — Repair mix format drift"
      assert friday =~ "## Friday tuple"
      refute File.read!(Path.join(work_dir, "SJ-001.md")) =~ "Friday tuple"

      [receipt] = Receipt.read_all!(work_dir)
      assert receipt["standing"] == "alive"
      assert receipt["metadata"]["graph_hash"] == sha256_file(ontology)
    end
  end

  ## Helpers

  defp goal_source, do: File.read!(@goal_path)

  defp write_merged!(goal_source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_goal_checkpoint_#{System.unique_integer([:positive])}.ttl"
      )

    File.write!(path, File.read!(@ontology_path) <> "\n" <> goal_source)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp validate_goal!(goal_source),
    do: Shacl.validate_file(write_merged!(goal_source), @shapes_path)

  defp replace_once!(source, pattern, replacement) do
    replaced =
      case pattern do
        %Regex{} -> Regex.replace(pattern, source, replacement, global: false)
        binary -> String.replace(source, binary, replacement, global: false)
      end

    refute replaced == source, "mutation #{inspect(pattern)} did not apply"
    replaced
  end

  defp fetch_violation!(report, opts) do
    case Enum.find(report.violations, &violation_matches?(&1, opts)) do
      nil ->
        flunk(
          "no violation matching #{inspect(opts)} in:\n#{inspect(report.violations, pretty: true)}"
        )

      violation ->
        violation
    end
  end

  defp violation_matches?(violation, opts),
    do: Enum.all?(opts, fn {key, value} -> Map.get(violation, key) == value end)

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_goal_checkpoint_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir = RealDir.real_dir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp sha256_file(path),
    do: "sha256:" <> (:crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower))

  defp manufactured_experience! do
    {:ok, experience} =
      SemanticJira.machine_experience(%{
        "subject" => "ggen_igniter:mix-format-drift",
        "work_order_digest" => SemanticJira.digest(%{"id" => "GC-FIXTURE-WO-1"}),
        "execution_receipt" => %{
          "executed" => true,
          "receipt_hash" => SemanticJira.digest(%{"receipt" => "GC-FIXTURE-WO-1"})
        },
        "observation_refs" => ["receipts/v26.9.22/FRI-T1.json", "court/ggen_igniter/FRI-T1.json"],
        "verification" => %{"passed" => true, "exit_status" => 0},
        "resulting_state" => %{"formatted" => true},
        "replay_identity" => "semantic-jira:v26.9.22:GC-FIXTURE-WO-1"
      })

    experience
  end

  defp experience_iri, do: RDF.iri(@sj <> "experience-fixture")

  defp experience_graph(experience) do
    fields =
      Enum.flat_map(@experience_fields, fn {key, property} ->
        experience
        |> Map.fetch!(key)
        |> List.wrap()
        |> Enum.map(&{experience_iri(), RDF.iri(@sj <> property), RDF.literal(&1)})
      end)

    RDF.Graph.new([{experience_iri(), RDF.type(), RDF.iri(@sj <> "MachineExperience")} | fields])
  end

  # Renders jira.md.eex for one for_each row exactly as the sync pipeline
  # binds it: every pack gate's rows under its discovered name, plus the
  # driver row's columns as top-level atom-keyed bindings. The pack's SHACL
  # court is deliberately not in this path, so template-level refusals are
  # observed on their own.
  defp render_ticket!(graph, id) do
    named =
      @pack_dir
      |> Pack.discover_queries()
      |> Map.new(fn {name, path} ->
        {String.to_atom(name), Query.run(graph, File.read!(path))}
      end)

    row = Enum.find(named.work_orders, &(&1["id"] == id)) || flunk("no work_orders row for #{id}")

    {_frontmatter, _mode, template} =
      @pack_dir
      |> Path.join("templates/jira.md.eex")
      |> File.read!()
      |> GgenIgniter.Frontmatter.split_template()

    Render.render(
      template,
      Map.to_list(named) ++ Enum.map(row, fn {key, value} -> {String.to_atom(key), value} end)
    )
  end
end
