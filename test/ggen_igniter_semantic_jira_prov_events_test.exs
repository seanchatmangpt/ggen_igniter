defmodule GgenIgniter.SemanticJiraProvEventsTest do
  @moduledoc """
  Chicago, no-mocks: real Reconciler-produced events in a real ledger, the
  real Turtle bytes on disk, re-read through the real `GgenIgniter.Ontology`
  loader and judged by the real `SemanticJira.Shacl` court. Assertions are on
  graph triples and bytes.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.Ontology
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{ProvEvents, Reconciler, Shacl, TransitionLog}

  @sha String.duplicate("a", 40)
  @origin "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @prov "http://www.w3.org/ns/prov#"
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_prov_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp wo(id, deps \\ []) do
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
      "origin_authority" => @origin,
      "dependencies" =>
        Enum.map(
          deps,
          &%{"upstream" => &1, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
        )
    }
  end

  defp receipt(w) do
    {:ok, dd} = SemanticJira.definition_digest(w)
    {:ok, a} = SemanticJira.admit_work_order(w)

    %{
      "definition_digest" => dd,
      "snapshot_digest" => a["work_order_digest"],
      "target" => "ALIVE",
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

  defp ledger_with_two(path) do
    root = wo("ROOT")
    b = wo("B", ["ROOT"])
    assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root), path)
    assert {:ok, _, :appended} = Reconciler.reconcile(b, receipt(b), path)
    TransitionLog.read(path)
  end

  defp iri(s), do: RDF.iri(s)

  defp objs(graph, s, p),
    do:
      graph
      |> RDF.Graph.description(iri(s))
      |> RDF.Description.get(iri(p), [])
      |> Enum.map(&to_string/1)

  defp ev_iri(e),
    do:
      "https://ggen-igniter.dev/ontology/semantic-jira/event/" <>
        String.replace_prefix(e["event_digest"], "sha256:", "")

  test "real reconciler events round-trip through the real Ontology loader", %{dir: dir} do
    events = ledger_with_two(Path.join(dir, "l.ndjson"))
    assert {:ok, ttl} = ProvEvents.to_turtle(events)
    path = Path.join(dir, "events.ttl")
    File.write!(path, ttl)
    graph = Ontology.load!(path)

    [e1, e2] = events
    assert objs(graph, ev_iri(e1), @sj <> "identity") == ["ROOT"]
    assert objs(graph, ev_iri(e1), @sj <> "to") == ["ALIVE"]
    assert objs(graph, ev_iri(e1), @sj <> "eventDigest") == [e1["event_digest"]]
    assert objs(graph, ev_iri(e1), @prov <> "wasInformedBy") == []
    assert objs(graph, ev_iri(e2), @prov <> "wasInformedBy") == [ev_iri(e1)]

    [post] = objs(graph, ev_iri(e1), @prov <> "generated")
    assert post == ev_iri(e1) <> "/post"
    assert objs(graph, post, @prov <> "wasGeneratedBy") == [ev_iri(e1)]
    derived = objs(graph, post, @prov <> "wasDerivedFrom")
    assert length(derived) == 2
    receipt_iri = Enum.find(derived, &String.contains?(&1, "/receipt/"))
    assert objs(graph, receipt_iri, @sj <> "receiptDigest") == [e1["receipt_digest"]]

    assert RDF.iri(@prov <> "Entity") in (graph
                                          |> RDF.Graph.description(iri(receipt_iri))
                                          |> RDF.Description.get(RDF.type()))

    assert RDF.iri(@prov <> "Activity") in (graph
                                            |> RDF.Graph.description(iri(ev_iri(e1)))
                                            |> RDF.Description.get(RDF.type()))

    assert {:ok, parsed} = ProvEvents.to_graph(events)
    assert RDF.Graph.triple_count(parsed) == RDF.Graph.triple_count(graph)
  end

  test "bytes are deterministic and independent of ledger form and input order", %{dir: dir} do
    events = ledger_with_two(Path.join(dir, "l.ndjson"))
    assert {:ok, a} = ProvEvents.to_turtle(events)
    assert {:ok, ^a} = ProvEvents.to_turtle(events)
    assert {:ok, ^a} = ProvEvents.to_turtle(Enum.reverse(events))
    assert {:ok, ^a} = ProvEvents.from_ledger(Path.join(dir, "l.ndjson"))

    dir_ledger = Path.join(dir, "ledger-dir")

    for e <- events,
        do:
          {:ok, _, :appended} =
            TransitionLog.append(dir_ledger, Map.drop(e, ["seq", "event_digest"]))

    assert {:ok, ^a} = ProvEvents.from_ledger(dir_ledger)
  end

  test "the SHACL court admits serialized events; a stripped triple is a violation", %{dir: dir} do
    events = ledger_with_two(Path.join(dir, "l.ndjson"))
    {:ok, ttl} = ProvEvents.to_turtle(events)
    report = ProvEvents.validate(ttl)
    assert %Shacl{conforms: true, focus_node_count: n, shapes_checked: checked} = report
    assert n >= 4

    # The court ran the PACK shape file, not module-local shapes: the report
    # names the ported shapes (Ra4 -- shapes_turtle/0 is gone).
    assert "standing_transition_event_prov_shape" in checked
    assert "standing_entity_prov_shape" in checked
    assert "generated_standing_prov_shape" in checked

    broken =
      ttl
      |> String.split("\n")
      |> Enum.reject(&String.contains?(&1, "prov:generated"))
      |> Enum.join("\n")
      |> String.replace("prov:used <", "prov:used <", global: false)

    # the removed line carried the statement terminator; restore a valid document
    broken = String.replace(broken, ~r/(prov:used [^\n]*) ;\n/, "\\1 .\n")
    bad = ProvEvents.validate(broken)
    refute bad.conforms
    assert Enum.any?(bad.violations, &(inspect(&1) =~ "generated"))
  end

  test "same identity chains: the second event derives from the first post entity", %{dir: dir} do
    ledger = Path.join(dir, "c.ndjson")
    base = %{"kind" => "standing_transition_event", "identity" => "X", "authority" => "NONE"}
    d1 = "sha256:" <> String.duplicate("1", 64)
    d2 = "sha256:" <> String.duplicate("2", 64)

    {:ok, e1, _} =
      TransitionLog.append(
        ledger,
        Map.merge(base, %{"from" => "UNKNOWN", "to" => "ALIVE", "receipt_digest" => d1})
      )

    {:ok, e2, _} =
      TransitionLog.append(
        ledger,
        Map.merge(base, %{"from" => "ALIVE", "to" => "STALE", "receipt_digest" => d2})
      )

    {:ok, graph} = ProvEvents.to_graph([e1, e2])
    used = objs(graph, ev_iri(e2), @prov <> "used")
    assert (ev_iri(e1) <> "/post") in used
    assert ProvEvents.validate(graph).conforms
  end

  test "an event missing a required field is a typed refusal, not partial Turtle" do
    assert {:error, {:invalid_event, 3, missing}} =
             ProvEvents.to_turtle([%{"seq" => 3, "identity" => "X", "from" => "A", "to" => "B"}])

    assert "event_digest" in missing and "receipt_digest" in missing
  end

  test "hostile string content is escaped and survives the round trip", %{dir: dir} do
    ledger = Path.join(dir, "h.ndjson")
    hostile = "X\"\\ \n <a> ; ."

    {:ok, e, _} =
      TransitionLog.append(ledger, %{
        "identity" => hostile,
        "from" => "UNKNOWN",
        "to" => "ALIVE",
        "receipt_digest" => "sha256:" <> String.duplicate("3", 64),
        "authority" => "NONE"
      })

    {:ok, graph} = ProvEvents.to_graph([e])
    assert objs(graph, ev_iri(e), @sj <> "identity") == [hostile]
  end
end
