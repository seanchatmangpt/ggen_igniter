defmodule GgenIgniter.SemanticJiraOriginGuardTest do
  @moduledoc """
  Chicago-style proof of the G1 trust-root pin law (v26.9.25 post-tag
  hardening, plan section "ggen_igniter G1").

  A recomputing `sj:admissionDigest` is an unkeyed content hash: a caller can
  type a fresh node `sj:StrategicObjective`, stamp it with
  `Authority.admit/2`, and the stamp recomputes. The pin law closes that
  channel: an authority is admitted only when its `(iri, digest)` pair is
  pinned by an `sj:AuthorityTrustRoot` of the CANONICAL semantic-jira-pack
  ontology. Every kernel entry point runs `Authority.require_origin/2`.

  Per entry point, four cases over real graphs, real stamping and the real
  canonical ontology (no doubles):

    1. missing origin            -> refused
    2. self-stamped caller graph -> refused `{:authority_not_pinned, iri}`
    3. pinned origin             -> admitted
    4. forged digest             -> refused `{:authority_not_pinned, iri}`

  The mutation court `scripts/sjira/origin_mutants.sh` (catalog
  `test/mutants/origin_guard.toml`) removes each guard in a fresh archive and
  requires this file to fail.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.{SemanticA2A, SemanticJira}
  alias GgenIgniter.SemanticJira.{Authority, Cli, Descriptor, Prose}

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @pinned @sj <> "objective-code-work-authority"
  @pinned_digest "sha256:310e14f1e30a9bb4d6ebd4388036e10ce3c973b13c0d45a7b550fa3dfd53c72c"
  @rogue @sj <> "objective-rogue-self-stamped"
  @forged "sha256:" <> String.duplicate("f", 64)

  # ── fixtures ────────────────────────────────────────────────────────────

  defp digest(seed),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, "origin-guard:" <> seed), case: :lower)

  defp work_order(overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => "SJ-G1-001",
        "title" => "Origin guard subject",
        "description" => "Exercise the trust-root pin law without granting authority.",
        "subject" => "urn:subject:g1",
        "repository" => "seanchatmangpt/ggen_igniter",
        "base_sha" => String.duplicate("a", 40),
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:g1:1",
        "dependencies" => [],
        "required_courts" => ["court:g1"],
        "required_evidence" => ["source", "verification"],
        "acceptance" => ["acceptance:g1"],
        "falsifiers" => ["falsifier:g1"],
        "projections" => SemanticJira.projection_types(),
        "required_receipt_classes" => ["verification"],
        "path_scope" => ["lib/ggen_igniter"],
        "authority_requirement" => "NONE",
        "origin_authority" => @pinned,
        "replay_required" => false
      },
      overrides
    )
  end

  defp without_origin, do: Map.delete(work_order(), "origin_authority")
  defp rogue_order, do: work_order(%{"origin_authority" => @rogue})

  # A caller graph that types a fresh objective and stamps its own digest:
  # the stamp RECOMPUTES (Authority.index/1 admits it unpinned).
  defp self_stamped_graph do
    graph =
      RDF.Graph.new([
        {RDF.iri(@rogue), RDF.type(), RDF.iri(@sj <> "StrategicObjective")},
        {RDF.iri(@rogue), RDF.iri("http://www.w3.org/2000/01/rdf-schema#label"),
         RDF.literal("Rogue objective")}
      ])

    {:ok, stamped, _report} = Authority.admit(graph)
    assert %{admitted: %{@rogue => _}} = Authority.index(stamped)
    stamped
  end

  # A ready-made index map restating the pinned IRI under a forged digest.
  defp forged_index, do: %{admitted: %{@pinned => @forged}, refused: %{}}

  defp not_pinned(iri), do: {:refused_origin, {:authority_not_pinned, iri}}

  defp lease_attrs do
    %{
      "run_id" => "run-g1",
      "epoch_id" => "epoch-g1",
      "worker_identity" => "worker:g1",
      "scope" => ["lib/ggen_igniter"],
      "allowed_operations" => ["edit"],
      "expiration" => "2026-09-26T00:00:00Z",
      "concurrency_key" => "g1"
    }
  end

  defp package_attrs do
    %{
      "graph_digest" => digest("graph"),
      "source_digest" => digest("source"),
      "worker_identity" => "worker:g1",
      "verifier_identity" => "verifier:g1"
    }
  end

  defp do_attrs(order) do
    {:ok, admitted} = SemanticJira.admit_work_order(order)

    %{
      "claim_store_status" => "available",
      "prepared_authority_receipt" => %{
        "status" => "prepared",
        "work_order_digest" => admitted["work_order_digest"],
        "subject" => admitted["subject"],
        "replay_identity" => admitted["replay_identity"],
        "authority_identity" => "authority:g1"
      },
      "lease_id" => "lease:g1",
      "capability_identity" => "capability:g1",
      "command_identity" => "command:g1"
    }
  end

  defp evidence(order) do
    {:ok, admitted} = SemanticJira.admit_work_order(order)

    %{
      "work_order_digest" => admitted["work_order_digest"],
      "subject" => admitted["subject"],
      "repository" => admitted["repository"],
      "base_sha" => admitted["base_sha"],
      "dependency_evidence" => %{},
      "court_results" => %{"court:g1" => %{"passed" => true}},
      "evidence_types" => admitted["required_evidence"],
      "acceptance_results" => Map.new(admitted["acceptance"], &{&1, true}),
      "falsifier_results" => Map.new(admitted["falsifiers"], &{&1, "survived"}),
      "receipt_classes" => admitted["required_receipt_classes"],
      "evidence_ceiling" => admitted["evidence_ceiling"],
      "observed_execution" => true,
      "inherited_standing" => false
    }
  end

  # A genuine promote/3 intent over the (pinned) order, then the transition
  # attrs; the order under test is swapped in afterwards.
  defp transition_attrs(order) do
    pinned = Map.put(order, "origin_authority", @pinned)
    {:ok, intent} = SemanticJira.promote(pinned, "PARTIAL_ALIVE", evidence(pinned))

    %{
      "intent" => intent,
      "evidence_identity" => "receipt:g1",
      "final_head" => String.duplicate("b", 40)
    }
  end

  defp repair_attrs do
    %{
      "failed_receipt_digest" => digest("failed"),
      "hypothesis" => "h",
      "smallest_repair" => "r",
      "permanent_guard" => "g",
      "changed_identities" => ["x"],
      "verifier" => "verifier:g1"
    }
  end

  defp descriptor_for(order) do
    {:ok, admitted} = SemanticJira.admit_work_order(Map.put(order, "origin_authority", @pinned))

    {:ok, definition} =
      SemanticJira.definition_digest(Map.put_new(order, "origin_authority", @pinned))

    %{
      "definition_digest" => definition,
      "snapshot_digest" => admitted["work_order_digest"],
      "base_sha" => admitted["base_sha"],
      "graph_digest" => digest("descriptor-graph")
    }
  end

  # The admitted snapshot of `order` when its origin is not the pinned one
  # (the kernel admits syntactically; only the guard judges the origin).
  defp snapshot(order) do
    {:ok, admitted} = SemanticJira.admit_work_order(Map.put(order, "origin_authority", @pinned))
    Map.put(admitted, "origin_authority", order["origin_authority"])
  end

  # ── the canonical trust root ─────────────────────────────────────────────

  describe "canonical trust roots" do
    test "pins exactly the three canonical strategic objectives, each recomputing" do
      assert {:ok, pins} = Authority.trust_roots()

      assert Map.keys(pins) |> Enum.sort() == [
               @sj <> "objective-code-work-authority",
               @sj <> "objective-project-manufacturer",
               @sj <> "objective-semantic-jira-mvp"
             ]

      assert {:ok, canonical} = Authority.canonical_index()
      assert canonical.admitted == pins
      assert {:ok, pinned} = Authority.index_from([])
      assert pinned.admitted == pins
    end

    test "every canonical trust root conforms to AuthorityTrustRootShape" do
      graph = RDF.Turtle.read_file!(Authority.canonical_path())
      shapes = Path.join(Path.dirname(Authority.canonical_path()), "shapes/work-order.shacl.ttl")
      report = SemanticJira.Shacl.validate_file(graph, shapes)

      trust_root_violations =
        Enum.filter(report.violations, fn violation ->
          inspect(violation) =~ "trust-root"
        end)

      assert trust_root_violations == []
    end

    test "AuthorityTrustRootShape refuses a scratch locator, a malformed digest and an untyped pin" do
      shapes = Path.join(Path.dirname(Authority.canonical_path()), "shapes/work-order.shacl.ttl")

      bad =
        RDF.Turtle.read_string!("""
        @prefix sj: <#{@sj}> .
        sj:trust-root-bad a sj:AuthorityTrustRoot ;
            sj:authorityIri sj:not-an-authority ;
            sj:admissionDigest "sha256:PENDING" ;
            sj:sourceLocator "/private/tmp/scratch/ontology.ttl" .
        """)

      report = SemanticJira.Shacl.validate_file(bad, shapes)
      refute report.conforms
      messages = inspect(report.violations)
      assert messages =~ "admissionDigest"
      assert messages =~ "sourceLocator"
      assert messages =~ "AUTHORITY_NOT_PINNED"
    end

    test "pins/1 pins nothing for a malformed digest, a missing locator or an ambiguous IRI" do
      graph =
        RDF.Turtle.read_string!("""
        @prefix sj: <#{@sj}> .
        sj:p1 a sj:AuthorityTrustRoot ; sj:authorityIri sj:a ;
            sj:admissionDigest "sha256:PENDING" ; sj:sourceLocator "https://x" .
        sj:p2 a sj:AuthorityTrustRoot ; sj:authorityIri sj:b ;
            sj:admissionDigest "#{@forged}" .
        sj:p3 a sj:AuthorityTrustRoot ; sj:authorityIri sj:c ;
            sj:admissionDigest "#{@forged}" ; sj:sourceLocator "https://x" .
        sj:p4 a sj:AuthorityTrustRoot ; sj:authorityIri sj:c ;
            sj:admissionDigest "#{@pinned_digest}" ; sj:sourceLocator "https://y" .
        sj:p5 a sj:AuthorityTrustRoot ; sj:authorityIri sj:d ;
            sj:admissionDigest "#{@pinned_digest}" ; sj:sourceLocator "https://z" .
        """)

      assert Authority.pins(graph) == %{(@sj <> "d") => @pinned_digest}
    end

    test "pin/2 keeps only exact (iri, digest) pairs" do
      index = %{admitted: %{@pinned => @forged, @rogue => @pinned_digest}, refused: %{}}
      pinned = Authority.pin(index, %{@pinned => @pinned_digest})

      assert pinned.admitted == %{}
      assert pinned.refused[@pinned] == {:authority_not_pinned, @pinned}
      assert pinned.refused[@rogue] == {:authority_not_pinned, @rogue}
    end

    test "a caller graph restating the pinned objective verbatim is admitted" do
      canonical = RDF.Turtle.read_file!(Authority.canonical_path())
      node = RDF.Graph.get(canonical, RDF.iri(@pinned))

      assert {:ok, @pinned_digest} =
               Authority.require_origin(work_order(), authority: RDF.Graph.new(node))
    end

    test "verify_origin/3 bounds a caller canonical graph by the pins" do
      canonical = self_stamped_graph()

      candidate =
        RDF.Graph.new([
          {RDF.iri(@sj <> "wo-g1"), RDF.type(), RDF.iri(@sj <> "WorkOrder")},
          {RDF.iri(@sj <> "wo-g1"), RDF.iri(@sj <> "originAuthority"), RDF.iri(@rogue)}
        ])

      assert {:error, not_pinned(@rogue)} ==
               Authority.verify_origin(candidate, canonical, @sj <> "wo-g1")
    end
  end

  # ── four cases per entry point ───────────────────────────────────────────

  describe "SemanticJira.lease_request/3" do
    test "missing origin refused" do
      assert {:error, {:refused_lease_request, _}} =
               SemanticJira.lease_request(without_origin(), lease_attrs())
    end

    test "self-stamped caller graph refused authority_not_pinned" do
      assert {:error, {:refused_lease_request, not_pinned(@rogue)}} ==
               SemanticJira.lease_request(rogue_order(), lease_attrs(),
                 authority: self_stamped_graph()
               )
    end

    test "pinned origin admitted" do
      assert {:ok, %{"kind" => "lease_request"}} =
               SemanticJira.lease_request(work_order(), lease_attrs())
    end

    test "forged digest refused" do
      assert {:error, {:refused_lease_request, not_pinned(@pinned)}} ==
               SemanticJira.lease_request(work_order(), lease_attrs(), authority: forged_index())
    end
  end

  describe "SemanticJira.execution_package/3" do
    test "missing origin refused" do
      assert {:error, _} = SemanticJira.execution_package(without_origin(), package_attrs())
    end

    test "self-stamped caller graph refused authority_not_pinned" do
      assert {:error, not_pinned(@rogue)} ==
               SemanticJira.execution_package(rogue_order(), package_attrs(),
                 authority: self_stamped_graph()
               )
    end

    test "pinned origin admitted" do
      assert {:ok, _shape} = SemanticJira.execution_package(work_order(), package_attrs())
    end

    test "forged digest refused" do
      assert {:error, not_pinned(@pinned)} ==
               SemanticJira.execution_package(work_order(), package_attrs(),
                 authority: forged_index()
               )
    end
  end

  describe "SemanticJira.do_intent/3" do
    test "missing origin refused" do
      assert {:error, {:refused_do, _}} =
               SemanticJira.do_intent(without_origin(), do_attrs(work_order()))
    end

    test "self-stamped caller graph refused authority_not_pinned" do
      order = rogue_order()

      assert {:error, {:refused_do, not_pinned(@rogue)}} ==
               SemanticJira.do_intent(order, do_attrs(order), authority: self_stamped_graph())
    end

    test "pinned origin admitted" do
      assert {:ok, %{"executed" => false}} =
               SemanticJira.do_intent(work_order(), do_attrs(work_order()))
    end

    test "forged digest refused" do
      assert {:error, {:refused_do, not_pinned(@pinned)}} ==
               SemanticJira.do_intent(work_order(), do_attrs(work_order()),
                 authority: forged_index()
               )
    end
  end

  describe "SemanticJira.promote/4" do
    test "missing origin refused" do
      assert {:error, _} =
               SemanticJira.promote(without_origin(), "PARTIAL_ALIVE", evidence(work_order()))
    end

    test "self-stamped caller graph refused authority_not_pinned (no NONE bypass)" do
      order = rogue_order()

      assert {:error, {:promotion_refused, not_pinned(@rogue)}} ==
               SemanticJira.promote(order, "PARTIAL_ALIVE", evidence(order),
                 authority: self_stamped_graph()
               )
    end

    test "pinned origin admitted" do
      assert {:ok, %{"kind" => "standing_transition_intent", "checks" => %{authority: true}}} =
               SemanticJira.promote(work_order(), "PARTIAL_ALIVE", evidence(work_order()))
    end

    test "forged digest refused" do
      assert {:error, {:promotion_refused, not_pinned(@pinned)}} ==
               SemanticJira.promote(work_order(), "PARTIAL_ALIVE", evidence(work_order()),
                 authority: forged_index()
               )
    end
  end

  describe "SemanticJira.apply_transition/3" do
    test "missing origin refused" do
      assert {:error, {:refused_transition, _}} =
               SemanticJira.apply_transition(without_origin(), transition_attrs(work_order()))
    end

    test "self-stamped caller graph refused authority_not_pinned" do
      order = rogue_order()

      assert {:error, {:refused_transition, not_pinned(@rogue)}} ==
               SemanticJira.apply_transition(order, transition_attrs(order),
                 authority: self_stamped_graph()
               )
    end

    test "pinned origin admitted" do
      assert {:ok, %{"kind" => "standing_transition_event"}} =
               SemanticJira.apply_transition(work_order(), transition_attrs(work_order()))
    end

    test "forged digest refused" do
      assert {:error, {:refused_transition, not_pinned(@pinned)}} ==
               SemanticJira.apply_transition(work_order(), transition_attrs(work_order()),
                 authority: forged_index()
               )
    end
  end

  describe "SemanticJira.repair_work_order/3" do
    test "missing origin refused" do
      assert {:error, _} = SemanticJira.repair_work_order(without_origin(), repair_attrs())
    end

    test "self-stamped caller graph refused authority_not_pinned" do
      assert {:error, not_pinned(@rogue)} ==
               SemanticJira.repair_work_order(rogue_order(), repair_attrs(),
                 authority: self_stamped_graph()
               )
    end

    test "pinned origin admitted" do
      assert {:ok, %{"kind" => "repair_work_order_candidate"}} =
               SemanticJira.repair_work_order(work_order(), repair_attrs())
    end

    test "forged digest refused" do
      assert {:error, not_pinned(@pinned)} ==
               SemanticJira.repair_work_order(work_order(), repair_attrs(),
                 authority: forged_index()
               )
    end
  end

  describe "Descriptor.to_a2a_task/3" do
    test "missing origin refused" do
      order = without_origin()

      assert {:error, {:refused_descriptor, _}} =
               Descriptor.to_a2a_task(descriptor_for(order), order)
    end

    test "self-stamped caller graph refused authority_not_pinned" do
      order = rogue_order()

      assert {:error, {:refused_descriptor, not_pinned(@rogue)}} ==
               Descriptor.to_a2a_task(descriptor_for(order), order,
                 authority: self_stamped_graph()
               )
    end

    test "pinned origin admitted" do
      order = work_order()

      assert {:ok, %{"taskId" => "urn:semantic-jira:g1:1"}} =
               Descriptor.to_a2a_task(descriptor_for(order), order)
    end

    test "forged digest refused" do
      order = work_order()

      assert {:error, {:refused_descriptor, not_pinned(@pinned)}} ==
               Descriptor.to_a2a_task(descriptor_for(order), order, authority: forged_index())
    end
  end

  describe "SemanticA2A.task_from_work_order/2" do
    test "missing origin refused" do
      assert {:error, {:refused_origin, :origin_authority_missing}} ==
               SemanticA2A.task_from_work_order(without_origin(), graph_digest: digest("g"))
    end

    test "self-stamped caller graph refused authority_not_pinned" do
      assert {:error, not_pinned(@rogue)} ==
               SemanticA2A.task_from_work_order(snapshot(rogue_order()),
                 graph_digest: digest("g"),
                 authority: self_stamped_graph()
               )
    end

    test "pinned origin admitted" do
      assert {:ok, %{"metadata" => %{"authority" => "NONE"}}} =
               SemanticA2A.task_from_work_order(work_order(), graph_digest: digest("g"))
    end

    test "forged digest refused" do
      assert {:error, not_pinned(@pinned)} ==
               SemanticA2A.task_from_work_order(work_order(),
                 graph_digest: digest("g"),
                 authority: forged_index()
               )
    end
  end

  describe "Cli.frontier/1 --authority-graph" do
    setup do
      dir = Path.join(System.tmp_dir!(), "g1-origin-guard-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "ledger"))
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    defp frontier(dir, order, graph) do
      orders = Path.join(dir, "orders.json")
      File.write!(orders, Jason.encode!([order]))

      opts = [work_orders: orders, ledger: Path.join(dir, "ledger")]

      opts =
        case graph do
          nil ->
            opts

          graph ->
            path = Path.join(dir, "authority.ttl")
            File.write!(path, RDF.Turtle.write_string!(graph))
            Keyword.put(opts, :authority_graph, path)
        end

      Cli.frontier(opts)
    end

    test "missing origin refused", %{dir: dir} do
      assert {0, %{"eligible" => [], "blocked" => [_]}} = frontier(dir, without_origin(), nil)
    end

    test "self-stamped caller graph refused authority_not_pinned", %{dir: dir} do
      assert {0, %{"eligible" => [], "blocked" => [blocked]}} =
               frontier(dir, rogue_order(), self_stamped_graph())

      assert blocked["refusal"] == ["authority_not_pinned", @rogue]
    end

    test "pinned origin admitted", %{dir: dir} do
      assert {0, %{"eligible" => [eligible]}} = frontier(dir, work_order(), nil)
      assert eligible["origin_admission_digest"] == @pinned_digest
    end

    test "forged digest refused", %{dir: dir} do
      canonical = RDF.Turtle.read_file!(Authority.canonical_path())

      edited =
        canonical
        |> RDF.Graph.get(RDF.iri(@pinned))
        |> RDF.Description.add({RDF.iri(@sj <> "note"), RDF.literal("edited under a restamp")})
        |> RDF.Graph.new()

      {:ok, restamped, _} = Authority.admit(edited)

      assert {0, %{"eligible" => [], "blocked" => [blocked]}} =
               frontier(dir, work_order(), restamped)

      assert blocked["refusal"] == ["authority_not_pinned", @pinned]
    end
  end

  describe "Prose.admit_goal/1 stamps but never admits" do
    test "a self-stamped goal authority is reported not pinned" do
      dir = Path.join(System.tmp_dir!(), "g1-prose-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      goal = Path.join(dir, "goal.ttl")

      File.write!(goal, """
      @prefix sj: <#{@sj}> .
      @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
      sj:objective-rogue-self-stamped a sj:StrategicObjective ;
          rdfs:label "Rogue objective" .
      """)

      assert {:ok, summary} = Prose.admit_goal(goal: goal)
      assert Map.has_key?(summary.stamped, @rogue)
      assert summary.authority_admitted == []
      assert summary.authority_not_pinned == [@rogue]
    end

    test "a verbatim restatement of a pinned objective is reported admitted" do
      dir = Path.join(System.tmp_dir!(), "g1-prose-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      goal = Path.join(dir, "goal.ttl")
      canonical = RDF.Turtle.read_file!(Authority.canonical_path())
      node = RDF.Graph.get(canonical, RDF.iri(@pinned))
      File.write!(goal, RDF.Turtle.write_string!(RDF.Graph.new(node)))

      assert {:ok, summary} = Prose.admit_goal(goal: goal)
      assert summary.authority_admitted == [@pinned]
      assert summary.authority_not_pinned == []
    end
  end
end
