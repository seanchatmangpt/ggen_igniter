defmodule GgenIgniter.SemanticJiraShaclTest do
  @moduledoc """
  Chicago-style proof for the semantic-jira-pack SHACL admission court.

  Every test executes the real validator (`GgenIgniter.SemanticJira.Shacl`)
  against the real pack ontology and the real shape file
  (`shapes/work-order.shacl.ttl`) through the real RDF/Turtle loader and the
  real SPARQL engine -- no fixture stubbing, no acceptance mocks.

  The violation cases mirror the documented admission rejections: duplicate
  identifiers, wrong base SHA, invalid standing, authority above CONSTRUCT,
  projections claiming authority, and ALIVE without an exact-head receipt.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias GgenIgniter.SemanticJira.Shacl

  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @shapes_path "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
  @pack_dir "priv/ggen/semantic-jira-pack"
  @sj_base "https://ggen-igniter.dev/ontology/semantic-jira#"
  @dcterms_base "http://purl.org/dc/terms/"
  @sj_mvp @sj_base <> "semantic-jira-mvp"

  describe "canonical WorkOrder graph -> conformant" do
    test "the full dogfood ontology conforms to every node shape" do
      report = Shacl.validate_file(@ontology_path, @shapes_path)

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
      assert report.violations == []
      assert report.focus_node_count > 0

      assert MapSet.new(report.shapes_checked) ==
               MapSet.new(~w(work_order_shape global_integrity_shape dependency_edge_shape
                 projection_authority_shape prediction_shape standing_transition_shape
                 process_finding_shape lease_request_shape receipt_shape
                 skill_shape task_state_shape state_mapping_shape generator_capability_shape
                 checkpoint_shape goal_checkpoint_shape boundary_class_value_shape
                 capability_shape friday_work_order_shape machine_experience_shape))
    end

    test "gate-shaped run/2 reports one pass per node shape" do
      assert {:ok, results} = Shacl.run(@pack_dir, @ontology_path)

      assert {"work_order_shape", :pass} in results
      assert {"global_integrity_shape", :pass} in results
      assert {"lease_request_shape", :pass} in results
      assert {"skill_shape", :pass} in results
      assert {"state_mapping_shape", :pass} in results
      # 13 pre-Friday node shapes + 6 GC-FRI-0800 shapes (checkpoint,
      # goal_checkpoint, boundary_class_value, capability, friday_work_order,
      # machine_experience).
      assert {"friday_work_order_shape", :pass} in results
      assert length(results) == 19
    end
  end

  describe "documented admission rejections -> SHACL-backed rejections" do
    test "removing the required baseSha violates sh:minCount with the exact path" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(~r/^    sj:baseSha "[0-9a-f]+" ;\n/m, "")
        |> validate_override!()

      refute report.conforms

      violation = fetch_violation!(report, constraint: :min_count, path: @sj_base <> "baseSha")
      assert violation.shape == "work_order_shape"
      assert violation.focus_node == @sj_mvp
      assert violation.message =~ "minCount 1 violated"
    end

    test "a non-SHA baseSha (main) violates sh:pattern" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(~r/^    sj:baseSha "[0-9a-f]+" ;/m, "    sj:baseSha \"main\" ;")
        |> validate_override!()

      refute report.conforms

      violation = fetch_violation!(report, constraint: :pattern, path: @sj_base <> "baseSha")
      assert violation.focus_node == @sj_mvp
      assert violation.value == "main"
    end

    test "an invalid standing value violates sh:pattern" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once("sj:standing \"UNKNOWN\"", "sj:standing \"alive\"")
        |> validate_override!()

      refute report.conforms

      violation = fetch_violation!(report, constraint: :pattern, path: @sj_base <> "standing")
      assert violation.focus_node == @sj_mvp
      assert violation.value == "alive"
    end

    test "authority above CONSTRUCT violates sh:pattern" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          "sj:authorityCeiling \"CONSTRUCT\"",
          "sj:authorityCeiling \"DO\""
        )
        |> validate_override!()

      refute report.conforms

      violation =
        fetch_violation!(report, constraint: :pattern, path: @sj_base <> "authorityCeiling")

      assert violation.focus_node == @sj_mvp
    end

    test "duplicate work order identifiers violate the uniqueness SPARQL constraint" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          "dcterms:identifier \"GALL-001\"",
          "dcterms:identifier \"SJ-001\""
        )
        |> validate_override!()

      refute report.conforms

      dup_violations =
        Enum.filter(report.violations, fn v ->
          v.constraint == :sparql and v.message =~ "identifiers must be unique"
        end)

      focus_nodes = Enum.map(dup_violations, & &1.focus_node)
      assert @sj_mvp in focus_nodes
      assert (@sj_base <> "gall-001") in focus_nodes
    end

    test "duplicate replay identities violate the uniqueness SPARQL constraint" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          "sj:replayIdentity \"semantic-jira:v26.9.19:GALL-001\"",
          "sj:replayIdentity \"semantic-jira:v26.9.19:SJ-001\""
        )
        |> validate_override!()

      refute report.conforms

      dup_violations =
        Enum.filter(report.violations, fn v ->
          v.constraint == :sparql and v.message =~ "Replay identities must be unique"
        end)

      focus_nodes = Enum.map(dup_violations, & &1.focus_node)
      assert @sj_mvp in focus_nodes
      assert (@sj_base <> "gall-001") in focus_nodes
    end

    test "ALIVE without exact-head receipt violates the ALIVE integrity constraints" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once("sj:standing \"UNKNOWN\"", "sj:standing \"ALIVE\"")
        |> validate_override!()

      refute report.conforms

      alive_violations = Enum.filter(report.violations, &(&1.constraint == :sparql))
      assert length(alive_violations) == 2

      assert MapSet.new(alive_violations, & &1.shape) ==
               MapSet.new(~w(work_order_shape global_integrity_shape))
    end

    test "a projection claiming authority violates sh:hasValue" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once("sj:authorityClaim \"NONE\"", "sj:authorityClaim \"SELECT\"")
        |> validate_override!()

      refute report.conforms

      violation =
        fetch_violation!(report, constraint: :has_value, shape: "projection_authority_shape")

      assert violation.focus_node == @sj_base <> "projection-jira"
    end
  end

  describe "each shape class violated -> precise rejection" do
    test "sh:maxCount rejects a second scalar identifier (scalar-identity shape)" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          "dcterms:identifier \"SJ-001\" ;",
          "dcterms:identifier \"SJ-001\" ; dcterms:identifier \"SJ-001-DUP\" ;"
        )
        |> validate_override!()

      violation =
        fetch_violation!(report, constraint: :max_count, path: @dcterms_base <> "identifier")

      assert violation.focus_node == @sj_mvp
    end

    test "sh:datatype rejects a non-string identifier" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once("dcterms:identifier \"SJ-001\" ;", "dcterms:identifier 42 ;")
        |> validate_override!()

      violation =
        fetch_violation!(report, constraint: :datatype, path: @dcterms_base <> "identifier")

      assert violation.focus_node == @sj_mvp
    end

    test "sh:nodeKind rejects a literal court reference" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          "sj:requiresCourt sj:exact-head-projection-court",
          "sj:requiresCourt \"exact-head-projection-court\""
        )
        |> validate_override!()

      violation =
        fetch_violation!(report, constraint: :node_kind, path: @sj_base <> "requiresCourt")

      assert violation.focus_node == @sj_mvp
    end

    test "sh:class rejects an untyped acceptance criterion" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          "sj:acceptance sj:canonical-source,",
          "sj:acceptance sj:untyped-criterion,"
        )
        |> validate_override!()

      violation = fetch_violation!(report, constraint: :class, path: @sj_base <> "acceptance")
      assert violation.focus_node == @sj_mvp
    end

    test "sh:closed rejects a predicate outside the declared WorkOrder vocabulary" do
      report =
        @ontology_path
        |> File.read!()
        |> replace_once(
          "sj:nextCheckpoint sj:shacl-admission-checkpoint .",
          "sj:nextCheckpoint sj:shacl-admission-checkpoint ; sj:undeclaredPredicate \"x\" ."
        )
        |> validate_override!()

      violation = fetch_violation!(report, constraint: :closed, shape: "work_order_shape")
      assert violation.focus_node == @sj_mvp
      assert violation.path == @sj_base <> "undeclaredPredicate"
    end

    test "the opt-in sj:requiresGitGroundTruth triple is inside the declared WorkOrder vocabulary" do
      # Law-change witness (v26.9.19, residual_base_sha_wrong_commit closure):
      # WorkOrderShape gained `sj:requiresGitGroundTruth` (sh:maxCount 1,
      # xsd:boolean, deliberately NO sh:minCount -- absence stays the default
      # so the canonical fabric set manufactures unverified). Under sh:closed,
      # an undeclared predicate refuses; this proves the per-order git
      # ground-truth opt-in is lawfully declarable AND still type-checked.
      dogfood_base_sha = "sj:baseSha \"d84da1419a6945c6a8a64b8f6cdca9d0b2c9e0f3\" ;"

      conforms =
        @ontology_path
        |> File.read!()
        |> replace_once(
          dogfood_base_sha,
          dogfood_base_sha <> " sj:requiresGitGroundTruth true ;"
        )
        |> validate_override!()

      assert conforms.conforms, "violations:\n#{inspect(conforms.violations, pretty: true)}"

      non_boolean =
        @ontology_path
        |> File.read!()
        |> replace_once(
          dogfood_base_sha,
          dogfood_base_sha <> " sj:requiresGitGroundTruth \"yes\" ;"
        )
        |> validate_override!()

      refute non_boolean.conforms

      violation =
        fetch_violation!(non_boolean,
          constraint: :datatype,
          path: @sj_base <> "requiresGitGroundTruth"
        )

      assert violation.focus_node == @sj_mvp
    end

    test "an ambiguous standing transition violates the StandingTransition SPARQL constraint" do
      report =
        @ontology_path
        |> File.read!()
        |> Kernel.<>("""

        sj:transition-test a sj:StandingTransition ;
            sj:fromStanding "UNKNOWN" ;
            sj:toStanding "ALIVE" .
        """)
        |> validate_override!()

      violation =
        fetch_violation!(report, constraint: :sparql, shape: "standing_transition_shape")

      assert violation.focus_node == @sj_base <> "transition-test"
      assert violation.message =~ "ambiguous or skips explicit progression"
    end

    test "duplicate active exclusive lease requests violate the LeaseRequest SPARQL constraint" do
      lease = fn worker ->
        """
        sj:lease-test-#{worker} a sj:LeaseRequest ;
            sj:workOrderDigest "sha256:#{String.duplicate("a", 64)}" ;
            sj:worker "#{worker}" ;
            sj:pathScope "lib/ggen_igniter" ;
            sj:concurrencyKey "ggen_igniter:semantic-jira" ;
            sj:active true ;
            sj:exclusive true ;
            sj:authorityClaim "NONE" .
        """
      end

      report =
        @ontology_path
        |> File.read!()
        |> Kernel.<>("\n" <> lease.("worker-a") <> "\n" <> lease.("worker-b") <> "\n")
        |> validate_override!()

      dup_violations =
        Enum.filter(report.violations, fn v ->
          v.constraint == :sparql and v.shape == "lease_request_shape"
        end)

      assert length(dup_violations) == 2

      assert MapSet.new(dup_violations, & &1.focus_node) ==
               MapSet.new([
                 @sj_base <> "lease-test-worker-a",
                 @sj_base <> "lease-test-worker-b"
               ])
    end
  end

  describe "fail-closed on unsupported SHACL" do
    test "an unsupported constraint component (sh:in) is itself a violation, never a silent skip" do
      data = GgenIgniter.Ontology.load!(@ontology_path)

      shapes =
        RDF.Turtle.read_string!("""
        @prefix sh: <http://www.w3.org/ns/shacl#> .
        @prefix dcterms: <http://purl.org/dc/terms/> .
        @prefix sj: <https://ggen-igniter.dev/ontology/semantic-jira#> .

        sj:TestShape a sh:NodeShape ;
            sh:targetClass sj:WorkOrder ;
            sh:property [ sh:path dcterms:identifier ; sh:in ("SJ-001") ] .
        """)

      report = Shacl.validate(data, shapes)

      refute report.conforms

      assert Enum.any?(report.violations, fn v ->
               v.constraint == :unsupported_constraint and v.message =~ "shacl#in"
             end)
    end

    test "a non-simple property path is a violation, never a silent skip" do
      data = GgenIgniter.Ontology.load!(@ontology_path)

      shapes =
        RDF.Turtle.read_string!("""
        @prefix sh: <http://www.w3.org/ns/shacl#> .
        @prefix dcterms: <http://purl.org/dc/terms/> .
        @prefix sj: <https://ggen-igniter.dev/ontology/semantic-jira#> .

        sj:TestShape a sh:NodeShape ;
            sh:targetClass sj:WorkOrder ;
            sh:property [ sh:path ( dcterms:identifier sj:subject ) ; sh:minCount 1 ] .
        """)

      report = Shacl.validate(data, shapes)

      refute report.conforms

      assert Enum.any?(report.violations, fn v ->
               v.constraint == :unsupported_constraint and v.message =~ "non-simple sh:path"
             end)
    end

    test "gate-shaped run/2 fails with typed violations on a broken graph" do
      broken_ontology =
        Path.join(System.tmp_dir!(), "shacl_run_broken_#{System.unique_integer([:positive])}.ttl")

      File.write!(
        broken_ontology,
        replace_once(
          File.read!(@ontology_path),
          "sj:standing \"UNKNOWN\"",
          "sj:standing \"alive\""
        )
      )

      on_exit(fn -> File.rm_rf!(broken_ontology) end)

      assert {:error, {:shacl_violations, violations}} = Shacl.run(@pack_dir, broken_ontology)

      assert Enum.any?(
               violations,
               &(&1.constraint == :pattern and &1.path == @sj_base <> "standing")
             )
    end
  end

  ## Helpers

  defp replace_once(source, %Regex{} = pattern, replacement) do
    Regex.replace(pattern, source, replacement, global: false)
  end

  defp replace_once(source, pattern, replacement) when is_binary(pattern) do
    String.replace(source, pattern, replacement, global: false)
  end

  defp validate_override!(source) do
    path =
      Path.join(System.tmp_dir!(), "ggen_igniter_shacl_#{System.unique_integer([:positive])}.ttl")

    File.write!(path, source)
    on_exit(fn -> File.rm_rf!(path) end)
    Shacl.validate_file(path, @shapes_path)
  end

  defp violation(report, opts) do
    Enum.find(report.violations, fn v ->
      Enum.all?(opts, fn {key, value} -> Map.get(v, key) == value end)
    end)
  end

  defp fetch_violation!(report, opts) do
    case violation(report, opts) do
      nil ->
        flunk(
          "no violation matching #{inspect(opts)} in:\n#{inspect(report.violations, pretty: true)}"
        )

      violation ->
        violation
    end
  end
end
