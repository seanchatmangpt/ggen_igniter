defmodule Mix.Tasks.SemanticJira.AdmitCandidatesTest do
  @moduledoc """
  Chicago test of `mix semantic_jira.admit_candidates`: the real task module,
  the real `SemanticJira.admit_work_order/1`, the real canonical authority
  index of `priv/ggen/semantic-jira-pack/ontology.ttl`, a real JSONL file on
  disk. Assertions are on printed verdicts only; every expected digest is
  recomputed with the real kernel, never hard-coded. No doubles.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GgenIgniter.Ontology
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.Authority
  alias Mix.Tasks.SemanticJira.AdmitCandidates

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @objective @sj <> "objective-code-work-authority"
  @prose_observation @sj <> "review-26924-prose-authority"
  @fixture Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_admit_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp candidate(identity, origin) do
    @fixture
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("work_orders")
    |> Enum.find(&(&1["identity"] == "FRI-FMT-A"))
    |> Map.put("identity", identity)
    |> Map.put("replay_identity", "admit-candidates:" <> identity)
    |> Map.put("origin_authority", origin)
  end

  defp run_task(args) do
    Mix.Task.reenable("semantic_jira.admit_candidates")
    capture_io(fn -> AdmitCandidates.run(args) end)
  end

  test "admits the StrategicObjective-origin candidate and refuses prose origins, one verdict per line",
       %{dir: dir} do
    admitted = candidate("DOCTRINE-A", @objective)
    prose_iri = candidate("DOCTRINE-B", @prose_observation)
    prose_text = candidate("DOCTRINE-C", "the strategy memo says to do this")

    path = Path.join(dir, "candidates.jsonl")

    File.write!(
      path,
      Enum.map_join([admitted, prose_iri, prose_text], "\n", &Jason.encode!/1) <> "\n\n"
    )

    lines = path |> then(&run_task(["--candidates", &1])) |> String.split("\n", trim: true)

    {:ok, expected} = SemanticJira.admit_work_order(admitted)

    origin_digest =
      Authority.admission_digest(
        Ontology.load!("priv/ggen/semantic-jira-pack/ontology.ttl"),
        @objective
      )

    assert lines == [
             "admitted 1 DOCTRINE-A origin=#{@objective} origin_digest=#{origin_digest} " <>
               "work_order_digest=#{expected["work_order_digest"]}",
             "refused 2 DOCTRINE-B {:refused_origin, {:authority_not_admitted, \"#{@prose_observation}\"}}",
             "refused 3 DOCTRINE-C {:refused_work_order, {:invalid_origin_authority, \"the strategy memo says to do this\"}}",
             "summary admitted=1 refused=2"
           ]
  end

  test "a non-object or malformed line is refused with its line number", %{dir: dir} do
    path = Path.join(dir, "bad.jsonl")
    File.write!(path, "[1,2]\n{not json\n")

    assert run_task(["--candidates", path]) |> String.split("\n", trim: true) == [
             "refused 1 - {:refused_work_order, {:expected_json_object, :array}}",
             "refused 2 - {:refused_work_order, {:invalid_json, 1}}",
             "summary admitted=0 refused=2"
           ]
  end

  test "missing --candidates is an invalid invocation (exit 2)" do
    Mix.Task.reenable("semantic_jira.admit_candidates")

    {result, _err} =
      with_io(:stderr, fn ->
        catch_exit(AdmitCandidates.run([]))
      end)

    assert result == {:shutdown, 2}
  end
end
