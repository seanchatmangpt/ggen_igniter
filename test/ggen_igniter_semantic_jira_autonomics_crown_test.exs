defmodule GgenIgniter.SemanticJiraAutonomicsCrownTest do
  @moduledoc """
  Chicago, no-mocks autonomics crown. Real collaborators throughout: a real
  temp git repo with a real failing check, `process_finding/1`, real FULL-shape
  SHACL admission (`SemanticJira.Admission` -> `Shacl.validate/2` over the pack's
  shipped `shapes/work-order.shacl.ttl`, loaded from disk), real frontier,
  `execution_package/2`, a real verifier command run at an exact commit SHA,
  `Reconciler` (run with `admission: :shacl`, i.e. the same code production
  would run), and the file backed `TransitionLog`. Producer state is discarded
  and state is replayed from a copy of the log alone. WorkOrder maps are never
  edited.

  Candidate WorkOrders are admitted through the whole shipped shape, not a
  subset. The `@inline_subset` constant below is retained ONLY as a witness for
  the falsifier: it is the old four-constraint shape, and the falsifier test
  proves a WorkOrder it accepts is now REFUSED for a missing required property.
  It admits nothing.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Admission, Reconciler, Shacl, TransitionLog}

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @dcterms "http://purl.org/dc/terms/"
  @sha String.duplicate("b", 40)

  # Witness only (see moduledoc): the previous inline subset of the WorkOrder shape.
  @inline_subset """
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

  # Seed WorkOrder. Carries every property the FULL shipped shape requires
  # (authority_ceiling, authority_requirement, path_scope, required_receipt_classes,
  # next_action, next_checkpoint in addition to the kernel-required fields).
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
      "authority_ceiling" => "CONSTRUCT",
      "authority_requirement" => "NONE",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid-#{id}",
      "path_scope" => ["lib/ggen_igniter/semantic_jira"],
      "required_courts" => ["ci"],
      "required_evidence" => ["exec"],
      "required_receipt_classes" => ["verification"],
      "acceptance" => ["a1"],
      "falsifiers" => ["f1"],
      "projections" => ["jira"],
      "next_action" => "run-court",
      "next_checkpoint" => "checkpoint-#{id}",
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
        "receipt_classes" => ["verification"],
        "evidence_ceiling" => "observed",
        "observed_execution" => true
      }
    }
  end

  # The same call production makes: full-shape SHACL admission inside reconcile/4.
  defp reconcile(w, r, dir, graph),
    do: Reconciler.reconcile(w, r, dir, admission: :shacl, work_orders: graph)

  # Old inline-subset witness graph (see moduledoc).
  defp inline_subset_graph(w) do
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

  defp inline_subset_conforms?(w),
    do: Shacl.validate(inline_subset_graph(w), RDF.Turtle.read_string!(@inline_subset)).conforms

  defp violations!({:error, {:refused_work_order, {:shacl_violations, v}}}), do: v
  defp violations!(other), do: flunk("expected SHACL refusal, got: #{inspect(other)}")

  defp has_violation?(violations, constraint, path) do
    Enum.any?(violations, &(&1.constraint == constraint and &1.path == path))
  end

  defp has_sparql_violation?(violations, message_fragment) do
    Enum.any?(violations, &(&1.constraint == :sparql and &1.message =~ message_fragment))
  end

  # Reconcile a kernel-valid candidate that violates the full shape; asserts the
  # typed SHACL refusal and that nothing reached the log. Returns the violations.
  defp refused_via_reconcile(dir, candidate, graph) do
    assert {:error, {:refused, {:refused_work_order, {:shacl_violations, v}}}} =
             reconcile(candidate, receipt(candidate, @sha), dir, graph)

    assert TransitionLog.read(dir) == []
    v
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

    # 4. FULL-shape SHACL admission (real validator, shipped shape file) + kernel
    #    admission; a bad SHA is refused by both
    for w <- graph do
      assert {:ok, %Shacl{conforms: true}} = Admission.admit(w, work_orders: graph)
      assert {:ok, _} = SemanticJira.admit_work_order(w)
    end

    bad = Map.put(root, "base_sha", "main")
    bad_violations = violations!(Admission.admit(bad, work_orders: graph))
    assert has_violation?(bad_violations, :pattern, @sj <> "baseSha")
    assert {:error, {:refused_work_order, _}} = SemanticJira.admit_work_order(bad)

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

    # 8. reconcile with full-shape SHACL admission: transition appended,
    #    dependent newly eligible
    assert {:ok, ev, :appended} = reconcile(root, receipt(root, cand), dir, graph)
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

  describe "FULL shipped shape is stricter than the retired inline subset (falsifier)" do
    # {dropped map key, ontology path the FULL shape must cite as sh:minCount}
    @missing [
      {"path_scope", @sj <> "pathScope"},
      {"authority_ceiling", @sj <> "authorityCeiling"},
      {"authority_requirement", @sj <> "authorityRequirement"},
      {"required_receipt_classes", @sj <> "requiresReceiptClass"},
      {"next_action", @sj <> "nextAction"},
      {"next_checkpoint", @sj <> "nextCheckpoint"}
    ]

    for {key, path} <- @missing do
      test "missing #{key}: inline subset accepted it, full shape REFUSES it, log stays empty",
           %{dir: dir} do
        key = unquote(key)
        path = unquote(path)
        good = wo("ROOT", @sha, [])
        candidate = Map.delete(good, key)

        # the retired subset and the kernel both accepted this WorkOrder ...
        assert inline_subset_conforms?(candidate)
        assert {:ok, _} = SemanticJira.admit_work_order(candidate)

        # ... the full shipped shape does not
        assert {:ok, _} = Admission.admit(good)
        violations = candidate |> Admission.admit() |> violations!()
        assert has_violation?(violations, :min_count, path)

        # and reconcile refuses it with the typed reason, appending nothing
        assert {:error, {:refused, {:refused_work_order, {:shacl_violations, v}}}} =
                 reconcile(candidate, receipt(candidate, @sha), dir, [candidate])

        assert has_violation?(v, :min_count, path)
        assert TransitionLog.read(dir) == []
      end
    end
  end

  describe "each major constraint violated -> REFUSED with the typed reason, never logged" do
    setup %{dir: dir} do
      %{dir: dir, root: wo("ROOT", @sha, [])}
    end

    test "sh:pattern: authority ceiling above CONSTRUCT", %{dir: dir, root: root} do
      c = Map.put(root, "authority_ceiling", "DO")
      v = refused_via_reconcile(dir, c, [c])
      assert has_violation?(v, :pattern, @sj <> "authorityCeiling")
    end

    test "sh:pattern: identifier outside ^[A-Z][A-Z0-9-]{1,63}$ (kernel accepts it)", %{
      dir: dir,
      root: root
    } do
      c = Map.put(root, "identity", "root-lowercase")
      assert {:ok, _} = SemanticJira.admit_work_order(c)
      v = refused_via_reconcile(dir, c, [c])
      assert has_violation?(v, :pattern, @dcterms <> "identifier")
    end

    test "sh:pattern: base SHA that is a branch name (kernel refuses first, SHACL refuses too)",
         %{dir: dir, root: root} do
      c = Map.put(root, "base_sha", "main")
      assert has_violation?(violations!(Admission.admit(c)), :pattern, @sj <> "baseSha")

      assert {:error, {:refused, {:refused_work_order, {:invalid_sha, :base_sha, "main"}}}} =
               reconcile(c, receipt(root, @sha), dir, [c])

      assert TransitionLog.read(dir) == []
    end

    test "sh:datatype: sj:requiresGitGroundTruth must be boolean", %{dir: dir, root: root} do
      c = Map.put(root, "requires_git_ground_truth", "yes")
      v = refused_via_reconcile(dir, c, [c])
      assert has_violation?(v, :datatype, @sj <> "requiresGitGroundTruth")

      ok = Map.put(root, "requires_git_ground_truth", true)
      assert {:ok, _} = Admission.admit(ok)
    end

    test "kernel-required scalar missing (title): SHACL refuses on its own, kernel refuses in reconcile",
         %{dir: dir, root: root} do
      c = Map.delete(root, "title")
      assert has_violation?(violations!(Admission.admit(c)), :min_count, @dcterms <> "title")

      assert {:error, {:refused, {:refused_work_order, {:missing_required_field, "title"}}}} =
               reconcile(c, receipt(root, @sha), dir, [c])

      assert TransitionLog.read(dir) == []
    end

    test "sh:minCount on typed nodes: no court / evidence / acceptance / falsifier / projection",
         %{root: root} do
      for {key, path} <- [
            {"required_courts", "requiresCourt"},
            {"required_evidence", "requiresEvidence"},
            {"acceptance", "acceptance"},
            {"falsifiers", "falsifier"},
            {"projections", "projection"}
          ] do
        v = root |> Map.delete(key) |> Admission.admit() |> violations!()
        assert has_violation?(v, :min_count, @sj <> path), "#{key} -> #{inspect(v)}"
      end
    end

    test "sparql: duplicate identifier across WorkOrders", %{dir: dir, root: root} do
      twin =
        root |> Map.put("subject", "other-subject") |> Map.put("replay_identity", "rid-other")

      v = refused_via_reconcile(dir, root, [root, twin])
      assert has_sparql_violation?(v, "identifiers must be unique")
    end

    test "sparql: duplicate replay identity across WorkOrders", %{dir: dir, root: root} do
      twin = root |> Map.put("identity", "TWIN")
      v = refused_via_reconcile(dir, root, [root, twin])
      assert has_sparql_violation?(v, "Replay identities must be unique")
    end

    test "sparql + sh:class: dependency on an upstream WorkOrder that is not in the graph",
         %{dir: dir} do
      orphan = wo("ORPHAN", @sha, ["GHOST"])
      v = refused_via_reconcile(dir, orphan, [orphan])
      assert has_sparql_violation?(v, "Dependency identities must resolve")
      assert has_violation?(v, :class, @sj <> "upstreamWorkOrder")

      # the same candidate is admitted once the upstream is in the graph
      ghost = wo("GHOST", @sha, [])
      assert {:ok, _} = Admission.admit(orphan, work_orders: [ghost, orphan])
    end

    test "sparql: ALIVE definition without candidate/subject SHA and durable receipt",
         %{dir: dir, root: root} do
      alive = Map.put(root, "standing", "ALIVE")
      v = refused_via_reconcile(dir, alive, [alive])
      assert has_sparql_violation?(v, "ALIVE requires exact candidate/subject SHA")
      assert has_sparql_violation?(v, "ALIVE requires an independent court and durable receipt")

      # exact SHAs + a typed durable receipt: the same definition is admitted
      sealed =
        alive
        |> Map.put("candidate_sha", @sha)
        |> Map.put("subject_sha", @sha)
        |> Map.put("receipt", %{
          "work_order_digest" => sha256("wo"),
          "receipt_class" => "verification"
        })

      assert {:ok, _} = Admission.admit(sealed)
    end

    test "sparql: authority-requiring work must bind authority, lease and worker",
         %{dir: dir, root: root} do
      needs = Map.put(root, "authority_requirement", "DO")
      v = refused_via_reconcile(dir, needs, [needs])
      assert has_sparql_violation?(v, "must bind authority, lease, and worker")

      bound = Map.merge(needs, %{"authority" => "a-1", "lease" => "l-1", "worker" => "w-1"})
      assert {:ok, _} = Admission.admit(bound)

      # authority: "NONE" binds nothing
      still = Map.merge(needs, %{"authority" => "NONE", "lease" => "l-1", "worker" => "w-1"})
      assert has_sparql_violation?(violations!(Admission.admit(still)), "must bind authority")
    end

    test "refused attempts consume no seq: the next lawful append is seq 1", %{
      dir: dir,
      root: root
    } do
      c = Map.delete(root, "path_scope")
      _ = refused_via_reconcile(dir, c, [c])
      assert {:ok, ev, :appended} = reconcile(root, receipt(root, @sha), dir, [root])
      assert ev["seq"] == 1
      assert [%{"seq" => 1}] = TransitionLog.read(dir)
    end

    test "default reconcile (no admission option) is unchanged: kernel-only", %{
      dir: dir,
      root: root
    } do
      c = Map.delete(root, "path_scope")
      assert {:ok, _, :appended} = Reconciler.reconcile(c, receipt(c, @sha), dir)
    end

    test "an unknown admission mode is a typed refusal, not a silent kernel-only pass", %{
      dir: dir,
      root: root
    } do
      assert {:error, {:refused, {:unknown_admission_mode, :bogus}}} =
               Reconciler.reconcile(root, receipt(root, @sha), dir, admission: :bogus)

      assert TransitionLog.read(dir) == []
    end
  end

  test "concurrent writers under full-shape admission: stale-snapshot sibling receipts land once, refused candidates never land, seq gapless",
       %{dir: dir} do
    base = String.duplicate("b", 40)
    root = wo("ROOT", base, [])
    siblings = for i <- 1..6, do: wo("S#{i}", base, ["ROOT"])
    graph = [root | siblings]
    sha = String.duplicate("c", 40)

    assert {:ok, _, :appended} = reconcile(root, receipt(root, sha), dir, graph)

    # candidates that violate the full shape (kernel-valid, so their receipts
    # are well-formed) raced against the lawful ones
    bad =
      for i <- 1..3 do
        "BAD#{i}" |> wo(base, ["ROOT"]) |> Map.delete("path_scope")
      end

    # all receipts minted before any sibling transitioned (stale snapshots),
    # each submitted twice concurrently: duplicates must dedupe
    jobs = Enum.map(siblings ++ bad, &{&1, receipt(&1, sha)})
    work = jobs ++ jobs

    results =
      work
      |> Task.async_stream(fn {w, r} -> reconcile(w, r, dir, graph ++ [w]) end,
        max_concurrency: length(work),
        ordered: false,
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    {lawful, refused} = Enum.split_with(results, &match?({:ok, _, _}, &1))

    assert Enum.all?(lawful, &match?({:ok, _, s} when s in [:appended, :already_recorded], &1))
    assert Enum.count(lawful, &match?({:ok, _, :appended}, &1)) == 6
    assert length(refused) == 6

    assert Enum.all?(
             refused,
             &match?({:error, {:refused, {:refused_work_order, {:shacl_violations, _}}}}, &1)
           )

    events = TransitionLog.read(dir)
    assert Enum.map(events, & &1["seq"]) == Enum.to_list(1..7)
    assert events |> Enum.map(& &1["event_digest"]) |> Enum.uniq() |> length() == 7
    refute Enum.any?(events, &String.starts_with?(&1["identity"], "BAD"))

    {projected, _} = SemanticJira.project(graph, events)
    assert Enum.all?(projected, &(&1["standing"] == "ALIVE"))
  end

  test "replay after kill: a fresh copy of the log alone reproduces standing under full-shape admission",
       %{dir: dir} do
    base = String.duplicate("b", 40)
    root = wo("ROOT", base, [])
    child = wo("CHILD", base, ["ROOT"])
    graph = [root, child]
    sha = String.duplicate("c", 40)

    assert {:ok, _, :appended} = reconcile(root, receipt(root, sha), dir, graph)
    assert {:ok, _, :appended} = reconcile(child, receipt(child, sha), dir, graph)
    live = state(graph, dir)

    # "kill": every producer-side value is dropped; only the log directory survives
    copy = dir <> "_killed"
    on_exit(fn -> File.rm_rf!(copy) end)
    File.cp_r!(dir, copy)
    File.rm_rf!(dir)

    fresh_graph = [wo("ROOT", base, []), wo("CHILD", base, ["ROOT"])]
    assert state(fresh_graph, copy) == live

    # a resumed writer re-submitting the same receipt is idempotent (a receipt
    # already in the log is replayed without re-admission)
    assert {:ok, _, :already_recorded} =
             reconcile(child, receipt(child, sha), copy, fresh_graph)

    assert Enum.map(TransitionLog.read(copy), & &1["seq"]) == [1, 2]
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
