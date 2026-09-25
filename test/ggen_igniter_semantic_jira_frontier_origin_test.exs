defmodule GgenIgniter.SemanticJiraFrontierOriginTest do
  @moduledoc """
  AC-04 (SJ-002 origin-authority law at frontier selection): a work order
  whose `origin_authority` does not RESOLVE to an admitted authority -- a
  node typed `sj:StrategicObjective`/`sj:GoalCheckpoint`, not also typed as
  prose, carrying exactly one `sj:admissionDigest` that RECOMPUTES byte-equal
  over the authority graph -- never reaches the frontier.

  Chicago, no doubles: the real kernel (`SemanticJira.frontier/4`,
  `frontier_from_events/4`, `schedule/4`), the real `Descriptor`,
  `Reconciler` and `Bootstrap`, the real canonical ontology
  `priv/ggen/semantic-jira-pack/ontology.ttl`, real temp JSON/Turtle files,
  and one real `mix semantic_jira.frontier` subprocess. Every digest a test
  expects is recomputed here with `Authority.admission_digest/2`, never
  hard-coded. Assertions are on returned/printed state only.
  """

  # async: false -- the subprocess test runs `mix` in this checkout, and the
  # bootstrap test builds a real git repository.
  use ExUnit.Case, async: false

  alias GgenIgniter.Ontology
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Authority, Bootstrap, Cli, Descriptor, Reconciler}

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @dcterms "http://purl.org/dc/terms/"
  @rdfs_label "http://www.w3.org/2000/01/rdf-schema#label"
  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @fixture Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)
  @bootstrap_goal Path.expand("fixtures/semantic-jira-bootstrap/goal.ttl", __DIR__)

  @code_work_authority @sj <> "objective-code-work-authority"
  @prose_observation @sj <> "review-26924-prose-authority"
  @proposition @sj <> "ac04-prose-proposition"
  @hybrid @sj <> "ac04-hybrid-objective-proposition"
  @fresh "https://example.com/fresh-authority"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_ac04_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  # ── fixtures ──────────────────────────────────────────────────────────────

  defp base_order do
    @fixture
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("work_orders")
    |> Enum.find(&(&1["identity"] == "FRI-FMT-A"))
  end

  defp order(origin, identity \\ "AC04-A") do
    base_order()
    |> Map.put("identity", identity)
    |> Map.put("replay_identity", "ac04:" <> identity)
    |> Map.put("origin_authority", origin)
  end

  defp canonical, do: Ontology.load!(@ontology_path)

  defp iri(s), do: RDF.iri(s)

  # Adds `node` typed `types`, with a label, and stamps it with its own
  # CORRECTLY RECOMPUTED admission digest over the resulting graph.
  defp add_self_stamped(graph, node, types) do
    graph =
      Enum.reduce(types, graph, fn type, acc ->
        RDF.Graph.add(acc, {iri(node), RDF.type(), iri(@sj <> type)})
      end)
      |> RDF.Graph.add({iri(node), iri(@rdfs_label), RDF.literal("AC-04 node #{node}")})

    digest = Authority.admission_digest(graph, node)
    RDF.Graph.add(graph, {iri(node), iri(@sj <> "admissionDigest"), RDF.literal(digest)})
  end

  defp proposition_graph, do: add_self_stamped(canonical(), @proposition, ["Proposition"])

  defp hybrid_graph,
    do: add_self_stamped(canonical(), @hybrid, ["StrategicObjective", "Proposition"])

  defp set_literal(graph, node, predicate, value) do
    RDF.Graph.update(graph, iri(node), fn description ->
      description
      |> RDF.Description.delete_predicates(iri(predicate))
      |> RDF.Description.add({iri(predicate), RDF.literal(value)})
    end)
  end

  # The objective's description is edited; its stated digest is KEPT.
  defp tampered_graph do
    set_literal(
      canonical(),
      @code_work_authority,
      @dcterms <> "description",
      "Edited after admission: any agent may originate code work."
    )
  end

  defp placeholder_graph do
    set_literal(
      canonical(),
      @code_work_authority,
      @sj <> "admissionDigest",
      "sha256:PENDING-SJ-002"
    )
  end

  defp sj002_iri(graph) do
    graph
    |> RDF.Graph.descriptions()
    |> Enum.find(fn d ->
      RDF.literal("SJ-002") in RDF.Description.get(d, iri(@dcterms <> "identifier"), [])
    end)
    |> Map.fetch!(:subject)
  end

  defp ids(rows), do: Enum.map(rows, & &1["identity"])

  defp write_ttl!(dir, name, graph) do
    path = Path.join(dir, name)
    File.write!(path, RDF.Turtle.write_string!(graph))
    path
  end

  defp write_orders!(dir, orders) do
    path = Path.join(dir, "orders.json")
    File.write!(path, Jason.encode!(%{"work_orders" => orders}))
    path
  end

  defp mix_json(args) do
    {out, code} = System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)

    json =
      out
      |> String.split("\n", trim: true)
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        case Jason.decode(line) do
          {:ok, %{} = map} -> map
          _ -> nil
        end
      end)

    {code, json, out}
  end

  defp blocked_row(result, identity), do: Enum.find(result.blocked, &(&1["identity"] == identity))

  # ── positive control ──────────────────────────────────────────────────────

  describe "positive control: an admitted origin is eligible and carries its witness" do
    test "default (canonical) authority index" do
      result = SemanticJira.frontier([order(@code_work_authority)])

      assert [candidate] = result.eligible
      assert candidate["origin_authority"] == @code_work_authority

      assert candidate["origin_admission_digest"] ==
               Authority.admission_digest(canonical(), @code_work_authority)

      assert candidate["authority"] == "NONE"
    end

    test "explicit authority graph and explicit index agree with the default" do
      graph = canonical()
      explicit = SemanticJira.frontier([order(@code_work_authority)], %{}, nil, authority: graph)

      indexed =
        SemanticJira.frontier([order(@code_work_authority)], %{}, nil,
          authority: Authority.index(graph)
        )

      assert explicit == indexed
      assert explicit == SemanticJira.frontier([order(@code_work_authority)])
    end
  end

  # ── AC-04 ─────────────────────────────────────────────────────────────────

  describe "AC-04: a prose-typed origin with a correct self-computed digest is blocked" do
    test "the proposition's stated digest really does recompute (the forgery is internally valid)" do
      graph = proposition_graph()

      [stated] =
        graph
        |> RDF.Graph.get(iri(@proposition))
        |> RDF.Description.get(iri(@sj <> "admissionDigest"))
        |> Enum.map(&RDF.Literal.lexical/1)

      assert stated == Authority.admission_digest(graph, @proposition)
    end

    test "in-process frontier/4 blocks it with origin_not_admitted" do
      result =
        SemanticJira.frontier(
          [order(@code_work_authority, "AC04-POS"), order(@proposition, "AC04-PROSE")],
          %{},
          nil,
          authority: proposition_graph()
        )

      assert ids(result.eligible) == ["AC04-POS"]

      assert blocked_row(result, "AC04-PROSE") == %{
               "identity" => "AC04-PROSE",
               "reason" => "origin_not_admitted",
               "origin_authority" => @proposition,
               "refusal" => ["authority_not_admitted", @proposition]
             }
    end

    test "Cli.frontier/1 with real temp JSON and Turtle files blocks it", %{dir: dir} do
      orders =
        write_orders!(dir, [
          order(@code_work_authority, "AC04-POS"),
          order(@proposition, "AC04-PROSE")
        ])

      ttl = write_ttl!(dir, "authority.ttl", proposition_graph())

      assert {0, result} =
               Cli.frontier(
                 work_orders: orders,
                 ledger: Path.join(dir, "ledger"),
                 authority_graph: ttl
               )

      assert ids(result["eligible"]) == ["AC04-POS"]

      assert [%{"identity" => "AC04-PROSE", "reason" => "origin_not_admitted"} = row] =
               result["blocked"]

      assert row["refusal"] == ["authority_not_admitted", @proposition]
      assert Jason.encode!(result)
    end

    @tag timeout: 600_000
    test "a real `mix semantic_jira.frontier --authority-graph` subprocess blocks it", %{dir: dir} do
      orders =
        write_orders!(dir, [
          order(@code_work_authority, "AC04-POS"),
          order(@proposition, "AC04-PROSE")
        ])

      ttl = write_ttl!(dir, "authority.ttl", proposition_graph())

      {code, json, out} =
        mix_json([
          "semantic_jira.frontier",
          "--work-orders",
          orders,
          "--ledger",
          Path.join(dir, "ledger"),
          "--authority-graph",
          ttl
        ])

      assert code == 0, out
      assert ids(json["eligible"]) == ["AC04-POS"], out
      assert [%{"identity" => "AC04-PROSE", "reason" => "origin_not_admitted"}] = json["blocked"]
    end
  end

  describe "the default path is gated (no authority passed)" do
    test "a ProseObservation origin in the real ontology is blocked" do
      result = SemanticJira.frontier([order(@prose_observation)])

      assert result.eligible == []

      assert %{
               "reason" => "origin_not_admitted",
               "refusal" => ["authority_not_admitted", @prose_observation]
             } =
               blocked_row(result, "AC04-A")
    end

    test "a fresh, nonexistent IRI is blocked" do
      result = SemanticJira.frontier([order(@fresh)])

      assert result.eligible == []

      assert %{"reason" => "origin_not_admitted", "refusal" => ["authority_not_admitted", @fresh]} =
               blocked_row(result, "AC04-A")
    end
  end

  describe "the refusal vocabulary" do
    test "a node typed both StrategicObjective and Proposition is authority_type_mismatch" do
      result = SemanticJira.frontier([order(@hybrid)], %{}, nil, authority: hybrid_graph())

      assert result.eligible == []

      assert %{
               "reason" => "origin_not_admitted",
               "refusal" => ["authority_type_mismatch", @hybrid]
             } =
               blocked_row(result, "AC04-A")
    end

    test "an edited description under a kept digest is authority_digest_mismatch" do
      result =
        SemanticJira.frontier([order(@code_work_authority)], %{}, nil,
          authority: tampered_graph()
        )

      assert result.eligible == []

      assert %{
               "reason" => "origin_not_admitted",
               "refusal" => ["authority_digest_mismatch", @code_work_authority]
             } = blocked_row(result, "AC04-A")
    end

    test "a sha256:PENDING-SJ-002 placeholder is authority_digest_mismatch" do
      result =
        SemanticJira.frontier([order(@code_work_authority)], %{}, nil,
          authority: placeholder_graph()
        )

      assert result.eligible == []

      assert %{"refusal" => ["authority_digest_mismatch", @code_work_authority]} =
               blocked_row(result, "AC04-A")
    end

    test "Authority.resolve/2 over index/1 names each refusal" do
      assert {:ok, digest} = Authority.resolve(Authority.index(canonical()), @code_work_authority)
      assert digest == Authority.admission_digest(canonical(), @code_work_authority)

      assert {:error, {:refused_origin, {:authority_not_admitted, @proposition}}} =
               Authority.resolve(Authority.index(proposition_graph()), @proposition)

      assert {:error, {:refused_origin, {:authority_type_mismatch, @hybrid}}} =
               Authority.resolve(Authority.index(hybrid_graph()), @hybrid)

      assert {:error, {:refused_origin, {:authority_digest_mismatch, @code_work_authority}}} =
               Authority.resolve(Authority.index(tampered_graph()), @code_work_authority)
    end

    test "verify_origin/3 shares the law: a tampered canonical objective is refused" do
      graph = tampered_graph()
      sj002 = sj002_iri(graph)

      assert {:error, {:refused_origin, {:authority_digest_mismatch, @code_work_authority}}} =
               Authority.verify_origin(graph, graph, sj002)

      assert :ok = Authority.verify_origin(canonical(), canonical(), sj002)
    end
  end

  describe "every selection surface applies the gate" do
    setup do
      %{
        orders: [order(@code_work_authority, "AC04-POS"), order(@proposition, "AC04-PROSE")],
        graph: proposition_graph()
      }
    end

    test "frontier_from_events/4", %{orders: orders, graph: graph} do
      result = SemanticJira.frontier_from_events(orders, [], %{}, authority: graph)
      assert ids(result.eligible) == ["AC04-POS"]
      assert %{"reason" => "origin_not_admitted"} = blocked_row(result, "AC04-PROSE")
    end

    test "schedule/4", %{orders: orders, graph: graph} do
      result = SemanticJira.schedule(orders, [], %{}, authority: graph)
      assert ids(result.eligible) == ["AC04-POS"]
      assert %{"reason" => "origin_not_admitted"} = blocked_row(result, "AC04-PROSE")
    end

    test "Descriptor.build/4", %{orders: orders, graph: graph} do
      assert {:error, {:refused_descriptor, {:not_on_frontier, "origin_not_admitted"}}} =
               Descriptor.build(orders, "AC04-PROSE", %{}, authority: graph)
    end

    test "Descriptor.build_xaas_contract/4", %{orders: orders, graph: graph} do
      assert {:error, {:descriptor_refused, {:not_eligible, "AC04-PROSE", "origin_not_admitted"}}} =
               Descriptor.build_xaas_contract(orders, [], "AC04-PROSE",
                 verifier_suite: "ggen-igniter-format",
                 aliases: %{"seanchatmangpt/ggen_igniter" => "ggen_igniter"},
                 authority: graph
               )

      assert {:ok, %{"bridge" => _}} =
               Descriptor.build_xaas_contract(orders, [], "AC04-POS",
                 verifier_suite: "ggen-igniter-format",
                 aliases: %{"seanchatmangpt/ggen_igniter" => "ggen_igniter"},
                 authority: graph
               )
    end

    test "Reconciler.frontier/3", %{orders: orders, graph: graph} do
      assert {:ok, result} = Reconciler.frontier(orders, [], authority: graph)
      assert ids(result.eligible) == ["AC04-POS"]
      assert %{"reason" => "origin_not_admitted"} = blocked_row(result, "AC04-PROSE")
    end
  end

  # ── A.3: the promote path ────────────────────────────────────────────────

  describe "Reconciler.reconcile/4 (promote path) refuses an unadmitted origin" do
    defp receipt(work_order) do
      {:ok, definition} = SemanticJira.definition_digest(work_order)
      {:ok, admitted} = SemanticJira.admit_work_order(work_order)

      %{
        "definition_digest" => definition,
        "snapshot_digest" => admitted["work_order_digest"],
        "target" => "ALIVE",
        "evidence" => %{
          "subject" => work_order["subject"],
          "repository" => work_order["repository"],
          "base_sha" => work_order["base_sha"],
          "evidence_types" => work_order["required_evidence"],
          "court_results" => Map.new(work_order["required_courts"], &{&1, %{"passed" => true}}),
          "acceptance_results" => Map.new(work_order["acceptance"], &{&1, true}),
          "falsifier_results" => Map.new(work_order["falsifiers"], &{&1, "survived"}),
          "receipt_classes" => [],
          "evidence_ceiling" => work_order["evidence_ceiling"],
          "observed_execution" => true
        }
      }
    end

    test "the admitted origin's receipt appends; the prose origin's identical receipt is refused",
         %{dir: dir} do
      admitted = order(@code_work_authority, "AC04-POS")
      assert {:ok, event, :appended} = Reconciler.reconcile(admitted, receipt(admitted), dir)
      assert event["to"] == "ALIVE"

      prose = order(@prose_observation, "AC04-PROSE")

      assert {:error,
              {:refused, {:origin_not_admitted, {:authority_not_admitted, @prose_observation}}}} =
               Reconciler.reconcile(prose, receipt(prose), Path.join(dir, "second"))

      proposition = order(@proposition, "AC04-PROP")

      assert {:error, {:refused, {:origin_not_admitted, {:authority_not_admitted, @proposition}}}} =
               Reconciler.reconcile(proposition, receipt(proposition), Path.join(dir, "third"),
                 authority: proposition_graph()
               )
    end
  end

  # ── bootstrap: the goal-only index ───────────────────────────────────────

  describe "bootstrap selects only from an admitted goal root" do
    defp git!(repo, args) do
      {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
      String.trim(out)
    end

    defp bootstrap_ctx(dir) do
      repo = Path.join(dir, "subject")
      File.mkdir_p!(Path.join(repo, "receipts"))
      git!(repo, ["init", "-q"])

      for {k, v} <- [
            {"user.email", "ac04@example.invalid"},
            {"user.name", "AC04"},
            {"commit.gpgsign", "false"}
          ],
          do: git!(repo, ["config", k, v])

      File.mkdir_p!(Path.join(repo, "lib"))
      File.write!(Path.join(repo, "lib/a.ex"), "defmodule A do\nend\n")
      File.write!(Path.join(repo, "receipts/.keep"), "")
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-q", "-m", "fixture"])

      universe = Path.join(dir, "universe.json")

      File.write!(
        universe,
        Jason.encode!(%{
          "repositories" => [
            %{"name" => "subject", "github" => "fixture/subject", "path" => repo}
          ]
        })
      )

      [
        fleet: universe,
        ledger: Path.join(dir, "ledger/standing-ledger.ndjson"),
        receipts_dirs: [Path.join(repo, "receipts")],
        checkouts: ["fixture/subject=#{repo}"],
        env: %{}
      ]
    end

    defp eligible_ids(result) do
      result.state["orders"]
      |> Enum.filter(fn {_id, o} -> o["frontier"] == "eligible" end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()
    end

    test "the committed goal yields eligible work; a tampered GC-T description yields none",
         %{dir: dir} do
      opts = bootstrap_ctx(dir)

      assert {:ok, pristine} = Bootstrap.run(Keyword.put(opts, :goal, @bootstrap_goal))
      assert eligible_ids(pristine) != []

      tampered = Path.join(dir, "goal.ttl")

      File.write!(
        tampered,
        @bootstrap_goal
        |> File.read!()
        |> String.replace(~s(rdfs:label "GC-T fixture root"), ~s(rdfs:label "GC-T tampered root"))
      )

      refute File.read!(tampered) == File.read!(@bootstrap_goal)

      assert {:ok, result} = Bootstrap.run(Keyword.put(opts, :goal, tampered))
      assert eligible_ids(result) == []

      for id <- eligible_ids(pristine) do
        assert result.state["orders"][id]["frontier_reason"] == "origin_not_admitted"
      end
    end
  end

  # ── fail closed ──────────────────────────────────────────────────────────

  describe "fail closed" do
    test "an unreadable authority path blocks every order with authority_index_unavailable",
         %{dir: dir} do
      missing = Path.join(dir, "absent.ttl")

      result =
        SemanticJira.frontier(
          [order(@code_work_authority, "A"), order(@code_work_authority, "B")],
          %{},
          nil,
          authority: missing
        )

      assert result.eligible == []

      assert Enum.map(result.blocked, & &1["reason"]) ==
               List.duplicate("authority_index_unavailable", 2)

      assert ids(result.blocked) == ["A", "B"]
    end

    test "Cli.frontier/1 with an unreadable --authority-graph is invalid invocation (exit 2)",
         %{dir: dir} do
      orders = write_orders!(dir, [order(@code_work_authority)])

      assert {2, %{"status" => "invalid_invocation"}} =
               Cli.frontier(
                 work_orders: orders,
                 ledger: Path.join(dir, "ledger"),
                 authority_graph: Path.join(dir, "absent.ttl")
               )
    end

    test "Cli.frontier/1 with an unparseable --authority-graph is a typed refusal (exit 1)",
         %{dir: dir} do
      orders = write_orders!(dir, [order(@code_work_authority)])
      bad = Path.join(dir, "bad.ttl")
      File.write!(bad, "this is @@ not turtle <")

      assert {1, %{"status" => "refused"}} =
               Cli.frontier(
                 work_orders: orders,
                 ledger: Path.join(dir, "ledger"),
                 authority_graph: bad
               )
    end

    test "canonical_index/1 is keyed by content: an edited file is never served stale", %{
      dir: dir
    } do
      path = write_ttl!(dir, "authority.ttl", canonical())
      assert {:ok, index} = Authority.canonical_index(path: path)
      assert {:ok, _} = Authority.resolve(index, @code_work_authority)

      File.write!(path, RDF.Turtle.write_string!(tampered_graph()))
      assert {:ok, index2} = Authority.canonical_index(path: path)

      assert {:error, {:refused_origin, {:authority_digest_mismatch, @code_work_authority}}} =
               Authority.resolve(index2, @code_work_authority)

      assert {:error, {:authority_index_unavailable, _, _}} =
               Authority.canonical_index(path: Path.join(dir, "absent.ttl"))
    end
  end
end
