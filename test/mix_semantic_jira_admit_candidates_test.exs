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

  test "a repeated identity, replay identity, or work order is admitted once, then refused",
       %{dir: dir} do
    first = candidate("DUP", @objective)
    same = candidate("DUP", @objective)

    replay_clash =
      candidate("DUP-2", @objective) |> Map.put("replay_identity", first["replay_identity"])

    other = candidate("UNIQUE", @objective)

    path = Path.join(dir, "dups.jsonl")
    File.write!(path, Enum.map_join([first, same, replay_clash, other], "\n", &Jason.encode!/1))

    lines = run_task(["--candidates", path]) |> String.split("\n", trim: true)

    assert "admitted 1 DUP " <> _ = Enum.at(lines, 0)

    assert Enum.at(lines, 1) ==
             "refused 2 DUP {:refused_candidate, {:duplicate, \"identity\", 1}}"

    assert Enum.at(lines, 2) ==
             "refused 3 DUP-2 {:refused_candidate, {:duplicate, \"replay_identity\", 1}}"

    assert "admitted 4 UNIQUE " <> _ = Enum.at(lines, 3)
    assert List.last(lines) == "summary admitted=2 refused=2"
  end

  test "a candidate claiming literal standing or an actuation ceiling is refused before admission",
       %{dir: dir} do
    alive = candidate("X-STANDING", @objective) |> Map.put("standing", "ALIVE")
    do_ceiling = candidate("X-DO", @objective) |> Map.put("evidence_ceiling", "DO")
    merge_ceiling = candidate("X-MERGE", @objective) |> Map.put("evidence_ceiling", " merge ")
    authority = candidate("X-AUTH", @objective) |> Map.put("authority_requirement", "DO")

    # Each of these passes the kernel on its own: the refusal is this task's.
    for c <- [alive, do_ceiling, merge_ceiling, authority],
        do: assert({:ok, _} = SemanticJira.admit_work_order(c))

    path = Path.join(dir, "bounds.jsonl")

    File.write!(
      path,
      Enum.map_join([alive, do_ceiling, merge_ceiling, authority], "\n", &Jason.encode!/1)
    )

    assert run_task(["--candidates", path]) |> String.split("\n", trim: true) == [
             "refused 1 X-STANDING {:refused_candidate, {:literal_standing, \"ALIVE\"}}",
             "refused 2 X-DO {:refused_candidate, {:ceiling_exceeds_construct, \"evidence_ceiling\", \"DO\"}}",
             "refused 3 X-MERGE {:refused_candidate, {:ceiling_exceeds_construct, \"evidence_ceiling\", \" merge \"}}",
             "refused 4 X-AUTH {:refused_candidate, {:ceiling_exceeds_construct, \"authority_requirement\", \"DO\"}}",
             "summary admitted=0 refused=4"
           ]
  end

  test "an evidence_ceiling naming an actuation in any token form is refused", %{dir: dir} do
    # The forms that an exact-token denylist admitted (court probe ADV-A1).
    forms = [
      {"C-ACTUATE", "ACTUATE"},
      {"C-EXECUTE", "execute"},
      {"C-DOMERGE", "DO/MERGE"},
      {"C-MERGE-MAIN", "merge-to-main"},
      {"C-DO-TAB", "\tdo\n"},
      {"C-PUSHED", "local then pushed"},
      {"C-NUMERIC", 7}
    ]

    candidates =
      for {id, ceiling} <- forms,
          do: candidate(id, @objective) |> Map.put("evidence_ceiling", ceiling)

    path = Path.join(dir, "ceilings.jsonl")
    File.write!(path, Enum.map_join(candidates, "\n", &Jason.encode!/1))

    expected =
      forms
      |> Enum.with_index(1)
      |> Enum.map(fn {{id, ceiling}, n} ->
        "refused #{n} #{id} " <>
          inspect({:refused_candidate, {:ceiling_exceeds_construct, "evidence_ceiling", ceiling}})
      end)

    assert run_task(["--candidates", path]) |> String.split("\n", trim: true) ==
             expected ++ ["summary admitted=0 refused=#{length(forms)}"]
  end

  test "evidence-ladder ceilings are not actuations and are admitted", %{dir: dir} do
    ladder =
      ~w(SPECIFIED IMPLEMENTED_UNVERIFIED EXECUTED_VERIFIED LOCAL_RUN repository-local CONSTRUCT)

    for c <- ladder,
        do: assert(AdmitCandidates.candidate_bounds(%{"evidence_ceiling" => c}) == :ok)

    candidates =
      for {c, n} <- Enum.with_index(ladder, 1),
          do: candidate("LADDER-#{n}", @objective) |> Map.put("evidence_ceiling", c)

    path = Path.join(dir, "ladder.jsonl")
    File.write!(path, Enum.map_join(candidates, "\n", &Jason.encode!/1))

    lines = run_task(["--candidates", path]) |> String.split("\n", trim: true)

    for n <- 1..length(ladder),
        do: assert(String.starts_with?(Enum.at(lines, n - 1), "admitted #{n} LADDER-#{n} "))

    assert List.last(lines) == "summary admitted=#{length(ladder)} refused=0"
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
