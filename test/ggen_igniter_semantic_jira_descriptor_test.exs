defmodule GgenIgniter.SemanticJiraDescriptorTest do
  @moduledoc """
  Chicago, no doubles: real WorkOrders, real frontier/admission, real transition
  log on disk, real template render, real A2A task construction. Assertions are
  on returned state (descriptor, rendered JSON, task envelope).

  Also covers the fold of the former gall-semantic-work-pack into the single
  canonical semantic-jira-pack ontology (the gall pack no longer exists).
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, SemanticA2A, SemanticJira}
  alias GgenIgniter.SemanticJira.{Descriptor, Reconciler}

  @sha String.duplicate("a", 40)
  @graph "sha256:" <> String.duplicate("b", 64)
  @source "sha256:" <> String.duplicate("c", 64)
  @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @attrs %{
    "graph_digest" => @graph,
    "source_digest" => @source,
    "worker_identity" => "zcode-1",
    "verifier_identity" => "court-1"
  }

  defp wo(id, deps \\ [], extra \\ %{}) do
    Map.merge(
      %{
        "identity" => id,
        "title" => id,
        "description" => "d",
        "subject" => "subj-#{id}",
        "repository" => "o/r",
        "base_sha" => @sha,
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "observed",
        "promotion_rule" => "all_courts",
        "replay_identity" => "rid-#{id}",
        "required_courts" => ["ci"],
        "required_evidence" => ["exec"],
        "acceptance" => ["a1"],
        "falsifiers" => ["f1"],
        "projections" => ["jira"],
        "origin_authority" => @origin_authority,
        "dependencies" =>
          Enum.map(
            deps,
            &%{"upstream" => &1, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
          )
      },
      extra
    )
  end

  test "gall pack is folded: one canonical ontology carries the gall work orders" do
    refute File.exists?(Path.join(SemanticA2A.pack_dir(), "../gall-semantic-work-pack"))

    graph = Ontology.load!(SemanticA2A.ontology_path())

    rows =
      GgenIgniter.Query.run(
        graph,
        File.read!(Path.join([SemanticA2A.pack_dir(), "gates", "020_work_orders.rq"]))
      )

    assert Enum.any?(rows, &(&1["id"] == "GALL-001"))
  end

  test "descriptor for a frontier work order carries exact graph identity" do
    w = wo("A")
    assert {:ok, d} = Descriptor.build([w], "A", @attrs)
    {:ok, dd} = SemanticJira.definition_digest(w)
    {:ok, admitted} = SemanticJira.admit_work_order(w)

    assert d["definition_digest"] == dd
    assert d["snapshot_digest"] == admitted["work_order_digest"]
    assert d["base_sha"] == @sha
    assert d["graph_digest"] == @graph
    assert d["authority"] == "NONE"
    assert d["package"]["graph_digest"] == @graph
    assert d["package"]["admission"]["work_order_digest"] == admitted["work_order_digest"]
  end

  test "ggen-rendered descriptor JSON keeps the identity unchanged" do
    {:ok, d} = Descriptor.build([wo("A")], "A", @attrs)
    rendered = d |> Descriptor.render() |> Jason.decode!()

    assert Map.take(rendered, ~w(definition_digest snapshot_digest base_sha graph_digest)) ==
             Descriptor.identity(d)

    assert rendered["package"] == d["package"]
  end

  test "identity is unchanged through descriptor -> ash_a2a task envelope" do
    w = wo("A")
    {:ok, d} = Descriptor.build([w], "A", @attrs)
    assert {:ok, task} = Descriptor.to_a2a_task(d, w)

    assert task["metadata"]["definitionDigest"] == d["definition_digest"]
    assert task["metadata"]["snapshotDigest"] == d["snapshot_digest"]
    assert task["metadata"]["baseSha"] == d["base_sha"]
    assert task["metadata"]["graphDigest"] == d["graph_digest"]
    assert task["contextId"] == d["graph_digest"]
    assert [%{"data" => data}] = task["input"]
    assert data["definition_digest"] == d["definition_digest"]
    assert data["snapshot_digest"] == d["snapshot_digest"]
  end

  test "envelope refuses a descriptor whose identity drifted from the work order" do
    w = wo("A")
    {:ok, d} = Descriptor.build([w], "A", @attrs)

    moved = Map.put(w, "base_sha", String.duplicate("d", 40))

    assert {:error, {:refused_descriptor, {:identity_mismatch, _}}} =
             Descriptor.to_a2a_task(d, moved)

    forged = Map.put(d, "definition_digest", "sha256:" <> String.duplicate("0", 64))

    assert {:error, {:refused_descriptor, {:identity_mismatch, "definition_digest"}}} =
             Descriptor.to_a2a_task(forged, w)
  end

  describe "falsifier: no descriptor for a non-frontier work order" do
    test "dependency unmet" do
      wos = [wo("ROOT"), wo("B", ["ROOT"])]

      assert {:error, {:refused_descriptor, {:not_on_frontier, "dependencies_unsatisfied"}}} =
               Descriptor.build(wos, "B", @attrs)
    end

    test "non-UNKNOWN standing" do
      assert {:error, {:refused_descriptor, {:not_on_frontier, "standing=ALIVE"}}} =
               Descriptor.build([wo("A", [], %{"standing" => "ALIVE"})], "A", @attrs)
    end

    test "unadmitted work order (missing required field)" do
      bad = "A" |> wo() |> Map.delete("falsifiers")
      assert {:error, {:refused_descriptor, _}} = Descriptor.build([bad], "A", @attrs)
    end

    test "a work order stripped of origin_authority refuses on both descriptor surfaces" do
      stripped = Map.delete(wo("A"), "origin_authority")

      # The kernel's refusal, as the frontier reports it for an unadmittable row.
      kernel_reason =
        inspect({:refused_work_order, {:missing_required_field, "origin_authority"}})

      # The frontier blocks the row with the typed reason but WITHOUT its
      # identity (an unadmittable order has no admissible identity fields to
      # carry), so neither descriptor surface can bind a refusal to "A":
      # build/4 reports plain :not_found, and no descriptor exists.
      front = SemanticJira.frontier([stripped])
      assert front.eligible == []
      assert [%{"reason" => ^kernel_reason}] = front.blocked

      assert {:error, {:refused_descriptor, :not_found}} =
               Descriptor.build([stripped], "A", @attrs)

      # build_xaas_contract/4: the same law in the XaaS bridge vocabulary.
      assert {:error, {:descriptor_refused, {:not_eligible, "A", "unknown_identity"}}} =
               Descriptor.build_xaas_contract([stripped], [], "A", [
                 verifier_suite: "ci-suite",
                 aliases: %{"o/r" => "o_r"}
               ])
    end

    test "unknown identity" do
      assert {:error, {:refused_descriptor, :not_found}} =
               Descriptor.build([wo("A")], "Z", @attrs)
    end

    test "bad graph digest is refused, no descriptor" do
      assert {:error, {:refused_descriptor, _}} =
               Descriptor.build([wo("A")], "A", Map.put(@attrs, "graph_digest", "nope"))
    end
  end

  test "frontier follows the transition log: dependent becomes descriptor-eligible after ROOT is ALIVE" do
    dir = Path.join(System.tmp_dir!(), "sj_desc_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    root = wo("ROOT")
    b = wo("B", ["ROOT"])
    graph = [root, b]

    assert {:error, {:refused_descriptor, {:not_on_frontier, _}}} =
             Descriptor.build(graph, "B", @attrs, events: [])

    {:ok, dd} = SemanticJira.definition_digest(root)
    {:ok, a} = SemanticJira.admit_work_order(root)

    receipt = %{
      "definition_digest" => dd,
      "snapshot_digest" => a["work_order_digest"],
      "target" => "ALIVE",
      "evidence" => %{
        "subject" => root["subject"],
        "repository" => root["repository"],
        "base_sha" => root["base_sha"],
        "evidence_types" => ["exec"],
        "court_results" => %{"ci" => %{"passed" => true}},
        "acceptance_results" => %{"a1" => true},
        "falsifier_results" => %{"f1" => "survived"},
        "receipt_classes" => [],
        "evidence_ceiling" => "observed",
        "observed_execution" => true
      }
    }

    assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt, dir)
    events = GgenIgniter.SemanticJira.TransitionLog.read(dir)

    assert {:ok, d} = Descriptor.build(graph, "B", @attrs, events: events)
    assert d["work_order_id"] == "B"
  end

  describe "build/4 provider (V23-T6R: @default_provider, validated)" do
    test "defaults to the deterministic recipe provider, binds a named provider, refuses a malformed one" do
      graph = [wo("A")]

      # PRD PR-009 / ARD section 9: no LLM fallback when the provider is absent.
      assert {:ok, %{"provider" => "recipe"}} = Descriptor.build(graph, "A", @attrs)

      assert {:ok, %{"provider" => "zcode"}} =
               Descriptor.build(graph, "A", Map.put(@attrs, "provider", "zcode"))

      # Atom-keyed attrs bind identically to string-keyed ones.
      assert {:ok, %{"provider" => "zcode"}} =
               Descriptor.build(graph, "A", Map.put(@attrs, :provider, "zcode"))

      for bad <- ["not a provider", "Recipe", "", 42, nil] do
        assert {:error, {:refused_descriptor, {:invalid_option, :provider}}} =
                 Descriptor.build(graph, "A", Map.put(@attrs, "provider", bad)),
               "provider #{inspect(bad)} must refuse"
      end
    end
  end

  describe "build_xaas_contract/4 (admits the eligible row; provider is a parameter)" do
    @digest ~r/\Asha256:[0-9a-f]{64}\z/
    @contract_opts [verifier_suite: "ci-suite", aliases: %{"o/r" => "o_r"}]

    test "the bridge carries the ADMITTED definition and snapshot digests (never nil)" do
      root = wo("ROOT")

      assert {:ok, d} = Descriptor.build_xaas_contract([root], [], "ROOT", @contract_opts)

      {:ok, definition} = SemanticJira.definition_digest(root)
      {:ok, admitted} = SemanticJira.admit_work_order(root)

      assert d["bridge"]["definition_digest"] =~ @digest
      assert d["bridge"]["definition_digest"] == definition
      assert d["bridge"]["source_snapshot_digest"] =~ @digest
      assert d["bridge"]["source_snapshot_digest"] == admitted["work_order_digest"]
    end

    test "a row with no dependencies key is admitted (defaults), not crashed on" do
      root = Map.delete(wo("ROOT"), "dependencies")

      assert {:ok, d} = Descriptor.build_xaas_contract([root], [], "ROOT", @contract_opts)
      assert d["dependencies"] == []
    end

    test "provider defaults to the deterministic recipe provider and is bound from :provider" do
      graph = [wo("ROOT")]

      # PRD PR-009 / ARD section 9: no LLM fallback when :provider is absent.
      assert {:ok, %{"provider" => "recipe"}} =
               Descriptor.build_xaas_contract(graph, [], "ROOT", @contract_opts)

      assert {:ok, %{"provider" => "zcode"}} =
               Descriptor.build_xaas_contract(
                 graph,
                 [],
                 "ROOT",
                 [provider: "zcode"] ++ @contract_opts
               )

      assert {:error, {:descriptor_refused, {:invalid_option, :provider}}} =
               Descriptor.build_xaas_contract(
                 graph,
                 [],
                 "ROOT",
                 [provider: "not a provider"] ++ @contract_opts
               )
    end

    test "graph_digest is over admitted definitions: it moves when any definition moves" do
      graph = [wo("ROOT"), wo("B", ["ROOT"])]
      moved = [wo("ROOT"), wo("B", ["ROOT"], %{"title" => "B, retitled"})]

      assert {:ok, d1} = Descriptor.build_xaas_contract(graph, [], "ROOT", @contract_opts)
      assert {:ok, d2} = Descriptor.build_xaas_contract(moved, [], "ROOT", @contract_opts)

      assert d1["graph_digest"] =~ @digest
      refute d1["graph_digest"] == d2["graph_digest"]
    end
  end
end
