defmodule GgenIgniter.SemanticJiraProvenanceTest do
  @moduledoc """
  Chicago-style: real WorkOrders, real `Reconciler`/`promote/3` admission, a
  real file-backed `TransitionLog` in a scratch dir, the real PROV-O template,
  the real RDF.ex Turtle parser, and the real oxigraph NIF (through
  `GgenIgniter.Ontology` and `GgenIgniter.Engine`). Assertions are on resulting
  state: event maps, SPARQL rows, frontier output, typed refusals. No test
  doubles of any kind; tamper cases edit the real emitted Turtle text/graph.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Engine, Ontology, SemanticJira}
  alias GgenIgniter.SemanticJira.{Provenance, Reconciler, TransitionLog}

  @sha String.duplicate("a", 40)
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @prefixes "PREFIX sj: <#{@sj}> PREFIX prov: <http://www.w3.org/ns/prov#> " <>
              "PREFIX dcterms: <http://purl.org/dc/terms/> "

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
      "dependencies" =>
        Enum.map(
          deps,
          &%{"upstream" => &1, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
        )
    }
  end

  defp receipt(w, target \\ "ALIVE") do
    {:ok, dd} = SemanticJira.definition_digest(w)
    {:ok, a} = SemanticJira.admit_work_order(w)

    %{
      "definition_digest" => dd,
      "snapshot_digest" => a["work_order_digest"],
      "target" => target,
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

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_prov_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    root = wo("ROOT")
    b = wo("B", ["ROOT"])
    c = wo("C", ["ROOT"])
    graph = [root, b, c]

    # A real three-event log: ROOT first, then B and C (both depend on ROOT).
    for w <- [root, b, c] do
      assert {:ok, _, :appended} = Reconciler.reconcile(w, receipt(w), dir)
    end

    events = TransitionLog.read(dir)
    assert length(events) == 3
    assert {:ok, ttl} = TransitionLog.export_turtle(dir)

    %{dir: dir, graph: graph, events: events, ttl: ttl}
  end

  defp flip(digest) do
    {head, last} = String.split_at(digest, -1)
    head <> if(last == "0", do: "1", else: "0")
  end

  defp tamper_literal(ttl, digest) do
    # Exactly ONE literal is altered (the first occurrence). Most digests occur
    # once; `transition_digest` is identical across sibling transitions (it
    # excludes the work order digest), so it may occur several times.
    quoted = ~s("#{digest}")
    assert String.contains?(ttl, quoted), "expected a #{quoted} literal"
    String.replace(ttl, quoted, ~s("#{flip(digest)}"), global: false)
  end

  defp write_ttl!(dir, ttl) do
    File.mkdir_p!(dir)
    path = Path.join(dir, "log-#{System.unique_integer([:positive])}.ttl")
    File.write!(path, ttl)
    path
  end

  defp oxigraph(graph, query) do
    engine = Engine.fetch!("oxigraph")
    engine.run(engine.prepare!(graph, []), @prefixes <> query)
  end

  describe "to_turtle/1 and replay/1 (round trip)" do
    test "replaying the exported Turtle returns exactly the log's event maps", ctx do
      assert Provenance.replay(ctx.ttl) == {:ok, ctx.events}
      assert Enum.map(ctx.events, & &1["seq"]) == [1, 2, 3]
    end

    test "export is deterministic and a fixed point of replay", ctx do
      assert Provenance.to_turtle(Enum.reverse(ctx.events)) == {:ok, ctx.ttl}
      assert {:ok, replayed} = Provenance.replay(ctx.ttl)
      assert Provenance.to_turtle(replayed) == {:ok, ctx.ttl}
    end

    test "TransitionLog.export_turtle/1 accepts a dir or an event list", ctx do
      assert TransitionLog.export_turtle(ctx.events) == {:ok, ctx.ttl}
      assert Provenance.to_turtle(ctx.events) == {:ok, ctx.ttl}
    end

    test "an empty or missing log exports valid Turtle that replays to no events", ctx do
      missing = Path.join(ctx.dir, "never-created")
      assert {:ok, ttl} = TransitionLog.export_turtle(missing)
      assert Provenance.replay(ttl) == {:ok, []}
      assert Provenance.standing_projection(ttl) == {:ok, %{}}
    end

    test "statement order is irrelevant: a reversed N-Triples permutation replays equal", ctx do
      nt = ctx.ttl |> RDF.Turtle.read_string!() |> RDF.NTriples.write_string!()
      reversed = nt |> String.split("\n", trim: true) |> Enum.reverse() |> Enum.join("\n")

      refute reversed == nt
      assert Provenance.replay(reversed) == {:ok, ctx.events}
    end

    test "literals with quotes, backslashes, control chars, unicode and non-digest fields survive",
         ctx do
      dir = Path.join(ctx.dir, "odd")

      odd = %{
        "kind" => "standing_transition_event",
        "identity" => "wo \"quoted\" \\ back\nline\ttab é 日本 \u0001 end",
        "from" => "UNKNOWN",
        "to" => "REFUSED(x)",
        "authority" => "NONE",
        "started_at" => "2026-09-21T10:11:12.345Z",
        "receipt_digest" => "not-a-digest",
        "definition_digest" => nil,
        "note" => %{"nested" => [1, 2.5, nil, true, "s"]}
      }

      no_authority = %{"kind" => 5, "identity" => "X", "to" => "ALIVE", "authority" => "we ird"}

      assert {:ok, _, :appended} = TransitionLog.append(dir, odd)
      assert {:ok, _, :appended} = TransitionLog.append(dir, no_authority)
      events = TransitionLog.read(dir)

      assert {:ok, ttl} = TransitionLog.export_turtle(dir)
      assert ttl =~ "prov:startedAtTime \"2026-09-21T10:11:12.345Z\"^^xsd:dateTime"
      assert Provenance.replay(ttl) == {:ok, events}
    end

    test "prov:startedAtTime is only emitted for events that carry started_at", ctx do
      refute ctx.ttl =~ "startedAtTime"
    end
  end

  describe "real oxigraph over the emitted Turtle" do
    test "the file loads through Ontology.load!/1 and SPARQL sees the PROV-O structure", ctx do
      path = write_ttl!(ctx.dir, ctx.ttl)
      graph = Ontology.load!(path)

      activities =
        oxigraph(graph, """
        SELECT ?e (COUNT(?used) AS ?n) WHERE {
          ?e a prov:Activity ; prov:used ?used .
        } GROUP BY ?e
        """)

      assert length(activities) == 3
      assert Enum.all?(activities, &(&1["n"] == "3"))

      generated =
        oxigraph(graph, """
        SELECT ?state ?e ?agent ?receipt WHERE {
          ?state a prov:Entity ; prov:wasGeneratedBy ?e ;
                 prov:wasAttributedTo ?agent ; prov:wasDerivedFrom ?receipt .
          ?e a prov:Activity .
        }
        """)

      assert length(generated) == 3
      assert Enum.all?(generated, &(&1["agent"] == "urn:ggen:sj:authority:NONE"))

      assert Provenance.replay_file(path) == {:ok, ctx.events}
    end

    test "SPARQL recovers the log ordering: seq 1,2,3 and ROOT before its dependents", ctx do
      graph = ctx.ttl |> then(&write_ttl!(ctx.dir, &1)) |> Ontology.load!()

      rows =
        oxigraph(graph, """
        SELECT ?seq ?id WHERE {
          ?e a sj:StandingTransitionEvent ; sj:seq ?seq ; sj:workOrderId ?id .
        } ORDER BY ?seq
        """)

      assert Enum.map(rows, &{&1["seq"], &1["id"]}) == [{"1", "ROOT"}, {"2", "B"}, {"3", "C"}]
    end

    test "the frontier computed from RDF-replayed events equals the one from the JSON log",
         ctx do
      # Only the ROOT transition exported: the frontier must then list B, C.
      assert {:ok, root_ttl} = Provenance.to_turtle(Enum.take(ctx.events, 1))
      assert {:ok, from_rdf} = Provenance.replay(root_ttl)

      via_rdf = SemanticJira.frontier_from_events(ctx.graph, from_rdf)
      via_log = SemanticJira.frontier_from_events(ctx.graph, Enum.take(ctx.events, 1))

      assert via_rdf == via_log
      assert Enum.map(via_rdf.eligible, & &1["identity"]) == ["B", "C"]

      # Full log: everything is ALIVE, nothing is eligible, and both agree.
      assert {:ok, all} = Provenance.replay(ctx.ttl)

      assert SemanticJira.frontier_from_events(ctx.graph, all) ==
               SemanticJira.frontier_from_events(ctx.graph, ctx.events)
    end

    test "standing_projection/1 (SPARQL) equals SemanticJira.project/2's evidence", ctx do
      {_projected, logged} = SemanticJira.project(ctx.graph, ctx.events)
      assert Provenance.standing_projection(ctx.ttl) == {:ok, logged}
    end

    test "standing_projection/1 picks the latest event per work order", ctx do
      dir = Path.join(ctx.dir, "two-step")
      root = wo("ROOT")

      assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root, "PARTIAL_ALIVE"), dir)
      assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root, "ALIVE"), dir)
      events = TransitionLog.read(dir)
      assert Enum.map(events, & &1["to"]) == ["PARTIAL_ALIVE", "ALIVE"]

      assert {:ok, ttl} = TransitionLog.export_turtle(dir)
      {_projected, logged} = SemanticJira.project([root], events)

      assert {:ok, %{"ROOT" => %{"standing" => "ALIVE"}} = sparql} =
               Provenance.standing_projection(ttl)

      assert sparql == logged
    end
  end

  describe "falsifiers: replay refuses tampered or malformed Turtle" do
    test "a single altered receipt digest literal is refused (IRI/literal disagree)", ctx do
      digest = Enum.at(ctx.events, 1)["receipt_digest"]

      assert {:error, {:refused, {:iri_literal_mismatch, "receipt_digest", _}}} =
               ctx.ttl |> tamper_literal(digest) |> Provenance.replay()
    end

    test "a single altered event digest literal is refused", ctx do
      digest = Enum.at(ctx.events, 0)["event_digest"]

      assert {:error, {:refused, {:iri_literal_mismatch, :event, _}}} =
               ctx.ttl |> tamper_literal(digest) |> Provenance.replay()
    end

    test "a single altered definition digest literal is refused", ctx do
      digest = Enum.at(ctx.events, 2)["definition_digest"]

      assert {:error, {:refused, {:iri_literal_mismatch, "definition_digest", _}}} =
               ctx.ttl |> tamper_literal(digest) |> Provenance.replay()
    end

    test "a single altered snapshot digest literal is refused", ctx do
      digest = Enum.at(ctx.events, 1)["snapshot_digest"]

      assert {:error, {:refused, {:iri_literal_mismatch, "snapshot_digest", _}}} =
               ctx.ttl |> tamper_literal(digest) |> Provenance.replay()
    end

    test "an altered transition digest literal is caught by the content seal", ctx do
      digest = Enum.at(ctx.events, 0)["transition_digest"]

      assert {:error, {:refused, {:content_seal_mismatch, _}}} =
               ctx.ttl |> tamper_literal(digest) |> Provenance.replay()
    end

    test "an altered standing literal is caught by the event digest", ctx do
      tampered =
        String.replace(ctx.ttl, ~s(sj:toStanding "ALIVE"), ~s(sj:toStanding "BLOCKED"),
          global: false
        )

      refute tampered == ctx.ttl

      assert {:error, {:refused, {:event_digest_mismatch, _}}} = Provenance.replay(tampered)
    end

    test "rewriting a receipt digest consistently (IRI and literal) is caught by the seal",
         ctx do
      digest = Enum.at(ctx.events, 0)["receipt_digest"]
      hex = String.replace_prefix(digest, "sha256:", "")
      forged = String.replace(ctx.ttl, hex, flip(hex))

      assert {:error, {:refused, {:content_seal_mismatch, _}}} = Provenance.replay(forged)
    end

    test "a deleted middle event breaks the prov:wasInformedBy chain", ctx do
      middle = Enum.at(ctx.events, 1)["event_digest"]

      graph =
        ctx.ttl
        |> RDF.Turtle.read_string!()
        |> RDF.Graph.delete_descriptions([
          RDF.iri("urn:ggen:sj:event:" <> middle),
          RDF.iri("urn:ggen:sj:standing:" <> middle)
        ])

      cut = RDF.Turtle.write_string!(graph)
      last = Enum.at(ctx.events, 2)["event_digest"]

      assert {:error, {:refused, {:broken_chain, ^last}}} = Provenance.replay(cut)
    end

    test "an altered standing-state literal disagrees with its event", ctx do
      tampered =
        String.replace(ctx.ttl, ~s(sj:standing "ALIVE"), ~s(sj:standing "BLOCKED"), global: false)

      refute tampered == ctx.ttl
      assert {:error, {:refused, {:state_mismatch, _}}} = Provenance.replay(tampered)
    end

    test "a standing state derived from a different receipt is refused", ctx do
      hex = Enum.at(ctx.events, 0)["receipt_digest"] |> String.replace_prefix("sha256:", "")
      derived = "prov:wasDerivedFrom <urn:ggen:sj:receipt:sha256:"

      tampered =
        String.replace(ctx.ttl, derived <> hex, derived <> flip(hex), global: false)

      refute tampered == ctx.ttl
      assert {:error, {:refused, {:state_mismatch, _}}} = Provenance.replay(tampered)
    end

    test "deleting a standing-state entity is refused (authority is carried by it)", ctx do
      first = Enum.at(ctx.events, 0)["event_digest"]

      cut =
        ctx.ttl
        |> RDF.Turtle.read_string!()
        |> RDF.Graph.delete_descriptions(RDF.iri("urn:ggen:sj:standing:" <> first))
        |> RDF.Turtle.write_string!()

      # The event's `authority` is only expressed on its state entity, so its
      # body no longer matches its event digest.
      assert {:error, {:refused, {:event_digest_mismatch, _}}} = Provenance.replay(cut)
    end

    test "a missing standing-state entity is refused even for an authority-less event", ctx do
      dir = Path.join(ctx.dir, "no-authority")

      assert {:ok, %{"event_digest" => digest}, :appended} =
               TransitionLog.append(dir, %{"identity" => "X", "to" => "ALIVE"})

      assert {:ok, ttl} = TransitionLog.export_turtle(dir)
      assert Provenance.replay(ttl) == {:ok, TransitionLog.read(dir)}

      cut =
        ttl
        |> RDF.Turtle.read_string!()
        |> RDF.Graph.delete_descriptions(RDF.iri("urn:ggen:sj:standing:" <> digest))
        |> RDF.Turtle.write_string!()

      assert {:error, {:refused, {:missing_state, _}}} = Provenance.replay(cut)
    end

    test "an sj:extra literal cannot shadow a first-class field", ctx do
      event = "urn:ggen:sj:event:" <> Enum.at(ctx.events, 0)["event_digest"]

      injected =
        ctx.ttl <>
          "\n<#{event}> <#{@sj}extra> \"{\\\"to\\\":\\\"ALIVE\\\"}\" .\n"

      assert {:error, {:refused, {:extra_shadows_field, "to", _}}} = Provenance.replay(injected)
    end

    test "a second sj:seq on one event makes it ambiguous", ctx do
      event = "urn:ggen:sj:event:" <> Enum.at(ctx.events, 0)["event_digest"]

      injected =
        ctx.ttl <>
          "\n<#{event}> <#{@sj}seq> \"9\"^^<http://www.w3.org/2001/XMLSchema#integer> .\n"

      assert {:error, {:refused, {:ambiguous_event, _}}} = Provenance.replay(injected)
    end

    test "invalid Turtle is refused, not raised" do
      assert {:error, {:refused, {:invalid_turtle, _}}} = Provenance.replay("<a> <b> .")
    end

    test "standing_projection/1 refuses a tampered graph" do
      assert {:error, {:refused, {:invalid_turtle, _}}} =
               Provenance.standing_projection("<a> <b> .")
    end

    test "standing_projection/1 refuses instead of reporting standing from tampered events",
         ctx do
      tampered =
        String.replace(ctx.ttl, ~s(sj:toStanding "ALIVE"), ~s(sj:toStanding "BLOCKED"),
          global: false
        )

      assert {:error, {:refused, _}} = Provenance.standing_projection(tampered)
    end

    test "replay_file/1 refuses a missing file", ctx do
      assert {:error, {:refused, {:invalid_turtle, _}}} =
               Provenance.replay_file(Path.join(ctx.dir, "nope.ttl"))
    end
  end

  describe "to_turtle/1 refusals" do
    test "malformed events are refused with a typed export refusal" do
      assert {:error, {:refused_export, {:invalid_event_digest, "bad"}}} =
               Provenance.to_turtle([%{"seq" => 1, "event_digest" => "bad"}])

      digest = "sha256:" <> String.duplicate("b", 64)

      assert {:error, {:refused_export, {:invalid_seq, "1"}}} =
               Provenance.to_turtle([%{"seq" => "1", "event_digest" => digest}])

      assert {:error, {:refused_export, {:not_a_map, :x}}} = Provenance.to_turtle([:x])
      assert {:error, {:refused_export, :expected_event_list}} = Provenance.to_turtle(:nope)
    end

    test "duplicate seq or event digest is refused" do
      d1 = "sha256:" <> String.duplicate("b", 64)
      d2 = "sha256:" <> String.duplicate("c", 64)

      assert {:error, {:refused_export, {:duplicate_seq, 1}}} =
               Provenance.to_turtle([
                 %{"seq" => 1, "event_digest" => d1},
                 %{"seq" => 1, "event_digest" => d2}
               ])

      assert {:error, {:refused_export, {:duplicate_event_digest, ^d1}}} =
               Provenance.to_turtle([
                 %{"seq" => 1, "event_digest" => d1},
                 %{"seq" => 2, "event_digest" => d1}
               ])
    end
  end
end
