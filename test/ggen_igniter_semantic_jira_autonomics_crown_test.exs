defmodule GgenIgniter.SemanticJiraAutonomicsCrownTest do
  @moduledoc """
  Chicago, no-mocks autonomics crown. Real collaborators throughout: a real
  temp git repo with a real failing check, `process_finding/1`, real SHACL
  admission (`Shacl.validate/2`), real frontier, `execution_package/2`, a real
  verifier command run at an exact commit SHA, `Reconciler`, and the file
  backed `TransitionLog`. Producer state is discarded and state is replayed
  from a copy of the log alone. WorkOrder maps are never edited.

  The SHACL shapes here are an inline subset of the pack's WorkOrder shape
  (identifier / repository / baseSha / standing constraints), because the full
  pack shape requires the whole ontology graph around an order.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Reconciler, Shacl, TransitionLog}

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"

  @shapes """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix dcterms: <http://purl.org/dc/terms/> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix sj: <#{@sj}> .

  sj:CandidateShape a sh:NodeShape ;
      sh:targetClass sj:WorkOrder ;
      sh:property [ sh:path dcterms:identifier ; sh:minCount 1 ; sh:maxCount 1 ; sh:datatype xsd:string ; sh:pattern "^[A-Z][A-Z0-9-]{1,63}$" ] ;
      sh:property [ sh:path sj:repository ; sh:minCount 1 ; sh:maxCount 1 ; sh:datatype xsd:string ; sh:pattern "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$" ] ;
      sh:property [ sh:path sj:baseSha ; sh:minCount 1 ; sh:maxCount 1 ; sh:datatype xsd:string ; sh:pattern "^[0-9a-f]{40}$" ] ;
      sh:property [ sh:path sj:standing ; sh:minCount 1 ; sh:maxCount 1 ; sh:datatype xsd:string ; sh:pattern "^UNKNOWN$" ] .
  """

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp seed_repo do
    repo = Path.join(System.tmp_dir!(), "sj_crown_repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    File.write!(Path.join(repo, "check.sh"), "test ! -e BROKEN\n")
    File.write!(Path.join(repo, "BROKEN"), "bounded failing condition\n")
    git!(repo, ["init", "-q"])
    git!(repo, ["config", "user.email", "crown@example.invalid"])
    git!(repo, ["config", "user.name", "crown"])
    git!(repo, ["add", "-A"])
    git!(repo, ["commit", "-q", "-m", "seed failing condition"])
    on_exit(fn -> File.rm_rf!(repo) end)
    repo
  end

  defp verify(repo), do: System.cmd("sh", ["check.sh"], cd: repo, stderr_to_stdout: true)

  defp sha256(bin), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bin), case: :lower)

  defp shapes, do: RDF.Turtle.read_string!(@shapes)

  defp wo(id, base_sha, deps) do
    %{
      "identity" => id,
      "title" => id,
      "description" => "d-#{id}",
      "subject" => "subj-#{id}",
      "repository" => "o/r",
      "base_sha" => base_sha,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "observed",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid-#{id}",
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"],
      "dependencies" =>
        Enum.map(
          deps,
          &%{"upstream" => &1, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
        )
    }
  end

  defp receipt(w, sha) do
    {:ok, dd} = SemanticJira.definition_digest(w)
    {:ok, a} = SemanticJira.admit_work_order(w)

    %{
      "definition_digest" => dd,
      "snapshot_digest" => a["work_order_digest"],
      "target" => "ALIVE",
      "candidate_sha" => sha,
      "evidence" => %{
        "subject" => w["subject"],
        "repository" => w["repository"],
        "base_sha" => w["base_sha"],
        "evidence_types" => ["exec"],
        "court_results" => %{"ci" => %{"passed" => true}},
        "acceptance_results" => %{"a1" => true},
        "falsifier_results" => %{"f1" => "survived"},
        "receipt_classes" => [],
        "evidence_ceiling" => "observed",
        "observed_execution" => true
      }
    }
  end

  defp candidate_graph(w) do
    RDF.Turtle.read_string!("""
    @prefix dcterms: <http://purl.org/dc/terms/> .
    @prefix sj: <#{@sj}> .
    <urn:wo:#{w["identity"]}> a sj:WorkOrder ;
        dcterms:identifier "#{w["identity"]}" ;
        sj:repository "#{w["repository"]}" ;
        sj:baseSha "#{w["base_sha"]}" ;
        sj:standing "#{w["standing"]}" .
    """)
  end

  defp state(graph, dir) do
    events = TransitionLog.read(dir)
    {projected, _} = SemanticJira.project(graph, events)
    front = SemanticJira.frontier_from_events(graph, events)

    %{
      standing: Map.new(projected, &{&1["identity"], &1["standing"]}),
      eligible: Enum.map(front.eligible, & &1["identity"]),
      events:
        Enum.map(events, &Map.take(&1, ~w(seq identity from to receipt_digest event_digest)))
    }
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_crown_log_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "crown: failing repo -> finding -> admission -> execution -> receipt -> transition -> replay",
       %{dir: dir} do
    repo = seed_repo()
    base = git!(repo, ["rev-parse", "HEAD"])

    # 1. bounded failing condition is real: verifier fails at the base SHA
    {out0, code0} = verify(repo)
    assert code0 != 0

    # 2. observed process finding (candidate only, no authority)
    assert {:ok, finding} =
             SemanticJira.process_finding(%{
               "normative_model_digest" => sha256("check.sh: test ! -e BROKEN"),
               "observed_model_digest" => sha256("BROKEN present at #{base}"),
               "delta" => "BROKEN exists",
               "observation_receipt_digest" => sha256("exit=#{code0} #{out0}")
             })

    assert finding["admission_state"] == "CANDIDATE"
    assert finding["authority"] == "NONE"

    # 3. candidate WorkOrders derived from the finding (never edited afterwards)
    root = wo("FIX-BROKEN", base, [])
    dependent = wo("VERIFY-CLEAN", base, ["FIX-BROKEN"])
    graph = [root, dependent]
    pristine = graph

    # 4. SHACL admission (real validator) + kernel admission; a bad SHA is refused
    for w <- graph do
      assert %Shacl{conforms: true} = Shacl.validate(candidate_graph(w), shapes())
      assert {:ok, _} = SemanticJira.admit_work_order(w)
    end

    bad = Map.put(root, "base_sha", "main")
    refute Shacl.validate(candidate_graph(bad), shapes()).conforms

    # 5. frontier: only the root is eligible
    assert %{eligible: [%{"identity" => "FIX-BROKEN"}], blocked: [_]} =
             SemanticJira.frontier_from_events(graph, [])

    # 6. execution descriptor
    assert {:ok, pkg} =
             SemanticJira.execution_package(root, %{
               "graph_digest" => sha256("graph"),
               "source_digest" => sha256("source"),
               "worker_identity" => "worker-1",
               "verifier_identity" => "verifier-1"
             })

    assert pkg.subject_id == root["subject"]

    # 7. execute: real fix commit, real verifier at the exact candidate SHA
    File.rm!(Path.join(repo, "BROKEN"))
    git!(repo, ["add", "-A"])
    git!(repo, ["commit", "-q", "-m", "remove BROKEN"])
    cand = git!(repo, ["rev-parse", "HEAD"])
    assert cand != base
    {out1, code1} = verify(repo)
    assert code1 == 0

    {:ok, a} = SemanticJira.admit_work_order(root)

    assert {:ok, evidence} =
             SemanticJira.exact_head_verification_evidence(%{
               "repository" => "o/r",
               "base_sha" => base,
               "candidate_sha" => cand,
               "work_order_digest" => a["work_order_digest"],
               "projection_digest" => sha256("projection"),
               "command" => "sh check.sh",
               "exit_code" => code1,
               "toolchain_identity" => "sh",
               "environment_identity" => "local",
               "validator_identity" => "verifier-1",
               "test_result_digest" => sha256(out1),
               "falsifier_results" => [%{"verdict" => "survived"}]
             })

    assert evidence["passed"]
    assert evidence["standing_authority"] == "NONE"

    # 8. reconcile: transition appended, dependent newly eligible
    assert {:ok, ev, :appended} = Reconciler.reconcile(root, receipt(root, cand), dir)
    assert ev["from"] == "UNKNOWN" and ev["to"] == "ALIVE" and ev["authority"] == "NONE"

    live = state(graph, dir)
    assert live.eligible == ["VERIFY-CLEAN"]
    assert live.standing == %{"FIX-BROKEN" => "ALIVE", "VERIFY-CLEAN" => "UNKNOWN"}

    # zero ticket editing: WorkOrder definitions are untouched
    assert graph == pristine
    assert {:ok, d1} = SemanticJira.definition_digest(root)
    assert {:ok, ^d1} = SemanticJira.definition_digest(Map.put(root, "standing", "ALIVE"))

    # 9. discard producer state; replay from a copy of the log alone
    copy = dir <> "_replay"
    on_exit(fn -> File.rm_rf!(copy) end)
    File.cp_r!(dir, copy)

    replayed_graph = [wo("FIX-BROKEN", base, []), wo("VERIFY-CLEAN", base, ["FIX-BROKEN"])]
    assert state(replayed_graph, copy) == live
  end

  test "concurrent writers: stale-snapshot sibling receipts land once, seq gapless", %{dir: dir} do
    base = String.duplicate("b", 40)
    root = wo("ROOT", base, [])
    siblings = for i <- 1..6, do: wo("S#{i}", base, ["ROOT"])
    graph = [root | siblings]
    sha = String.duplicate("c", 40)

    assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root, sha), dir)

    # all receipts minted before any sibling transitioned (stale snapshots),
    # each submitted twice concurrently: duplicates must dedupe
    jobs = Enum.map(siblings, &{&1, receipt(&1, sha)})
    work = jobs ++ jobs

    results =
      work
      |> Task.async_stream(fn {w, r} -> Reconciler.reconcile(w, r, dir) end,
        max_concurrency: length(work),
        ordered: false,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.all?(results, &match?({:ok, _, s} when s in [:appended, :already_recorded], &1))
    assert Enum.count(results, &match?({:ok, _, :appended}, &1)) == 6

    events = TransitionLog.read(dir)
    assert Enum.map(events, & &1["seq"]) == Enum.to_list(1..7)
    assert events |> Enum.map(& &1["event_digest"]) |> Enum.uniq() |> length() == 7

    {projected, _} = SemanticJira.project(graph, events)
    assert Enum.all?(projected, &(&1["standing"] == "ALIVE"))
  end

  test "concurrent raw appends never lose or duplicate an event", %{dir: dir} do
    events =
      for i <- 1..20, do: %{"identity" => "X#{i}", "to" => "ALIVE", "receipt_digest" => "r#{i}"}

    events
    |> Task.async_stream(&TransitionLog.append(dir, &1), max_concurrency: 20, timeout: 30_000)
    |> Enum.each(fn {:ok, r} -> assert {:ok, _, :appended} = r end)

    read = TransitionLog.read(dir)
    assert Enum.map(read, & &1["seq"]) == Enum.to_list(1..20)

    assert read |> Enum.map(& &1["identity"]) |> Enum.sort() ==
             events |> Enum.map(& &1["identity"]) |> Enum.sort()
  end
end
