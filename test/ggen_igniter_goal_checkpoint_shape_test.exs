defmodule GgenIgniter.GoalCheckpointShapeTest do
  @moduledoc """
  Chicago-style: proof of the GoalCheckpoint doc-graph SHACL shape
  (`shapes/goal-checkpoint.shacl.ttl`, SHACL round-2 finding).

  Real collaborators only: the real SHACL court
  (`GgenIgniter.SemanticJira.Shacl`) over the real shipped
  `shapes/goal-checkpoint.shacl.ttl` and the real vendored castle precedent
  goal graphs (`test/fixtures/semantic-jira-goal-checkpoint-shape/`, copied
  byte-for-byte from castle docs/sjira/v26.{9.28,10.8}/goal.ttl) read through
  the real Turtle loader. Corrupted subjects are the real fixture bytes under
  a regex mutation (bad baseSha, removed replayIdentity, injected
  sj:WorkOrder), asserted on the real violation report. No mocks, stubs or
  test doubles.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.Shacl

  @shapes_path "priv/ggen/semantic-jira-pack/shapes/goal-checkpoint.shacl.ttl"
  @fixture_dir "test/fixtures/semantic-jira-goal-checkpoint-shape"
  @castle_10_8 Path.join(@fixture_dir, "castle-v26.10.8-goal.ttl")
  @castle_9_28 Path.join(@fixture_dir, "castle-v26.9.28-goal.ttl")
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"

  describe "Shacl.validate_file/2 (castle precedent goal graphs)" do
    test "the castle v26.10.8 successor goal graph conforms" do
      report = Shacl.validate_file(@castle_10_8, @shapes_path)

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
      assert report.violations == []
      assert "goal_checkpoint_doc_graph_shape" in report.shapes_checked
    end

    test "the castle v26.9.28 governing goal graph conforms" do
      report = Shacl.validate_file(@castle_9_28, @shapes_path)

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
      assert report.violations == []
    end
  end

  describe "Shacl.validate_file/2 (corrupted goal graphs refuse)" do
    test "a root baseSha that is not a 40-hex SHA refuses on the pattern" do
      source = mutate!(@castle_10_8, ~r/sj:baseSha "[0-9a-f]{40}"/, "sj:baseSha \"fe78477deadbeef\"")

      report = validate_source(source)

      violation =
        fetch_violation!(report,
          path: @sj <> "baseSha",
          constraint: :pattern
        )

      assert violation.value == "fe78477deadbeef"
    end

    test "a root without sj:replayIdentity refuses" do
      source = mutate!(@castle_10_8, ~r/^\s*sj:replayIdentity "[^"]*" ;\n/m, "")

      report = validate_source(source)

      violation =
        fetch_violation!(report,
          path: nil,
          constraint: :sparql
        )

      assert violation.message =~ "requires sj:replayIdentity"
    end

    test "an authored sj:WorkOrder refuses under the STOP law" do
      source =
        mutate!(
          @castle_10_8,
          "c10:CASTLE-26.10.8-0\n    a sj:GoalCheckpoint ;",
          "c10:evil-order\n    a sj:WorkOrder ;\n    dcterms:identifier \"EVIL\" .\n\nc10:CASTLE-26.10.8-0\n    a sj:GoalCheckpoint ;"
        )

      report = validate_source(source)

      violation = fetch_violation!(report, constraint: :sparql)
      assert violation.message =~ "no authored sj:WorkOrder"
    end

    test "an authored sj:Receipt refuses under the STOP law" do
      source =
        mutate!(
          @castle_10_8,
          "c10:CASTLE-26.10.8-0\n    a sj:GoalCheckpoint ;",
          "c10:evil-receipt\n    a sj:Receipt ;\n    sj:standing \"ALIVE\" .\n\nc10:CASTLE-26.10.8-0\n    a sj:GoalCheckpoint ;"
        )

      report = validate_source(source)

      violation = fetch_violation!(report, constraint: :sparql)
      assert violation.message =~ "no authored sj:Receipt"
    end

    test "an authorityCeiling outside the CONSTRUCT fence refuses" do
      source =
        mutate!(
          @castle_10_8,
          "sj:authorityCeiling \"CONSTRUCT\"",
          "sj:authorityCeiling \"DO\""
        )

      report = validate_source(source)

      violation =
        fetch_violation!(report,
          path: @sj <> "authorityCeiling",
          constraint: :pattern
        )

      assert violation.value == "DO"
    end
  end

  ## Helpers

  defp validate_source(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_goal_checkpoint_shape_#{System.unique_integer([:positive])}.ttl"
      )

    File.write!(path, source)
    on_exit(fn -> File.rm_rf!(path) end)
    Shacl.validate_file(path, @shapes_path)
  end

  defp mutate!(file, pattern, replacement) do
    source = File.read!(file)

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
end
