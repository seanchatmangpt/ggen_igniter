defmodule GgenIgniter.SemanticJiraProvenanceFalsifierTest do
  @moduledoc """
  QUALIFIER falsifiers for `GgenIgniter.SemanticJira.Provenance` at c402a46.
  Every test here is EXPECTED TO FAIL against that head: each pins a defect the
  builder's own suite does not reach, and stays red until the defect is fixed.

  1. Chain triples are not covered by any digest or seal. Deleting a middle (or
     the first) event and editing ONE `prov:wasInformedBy` triple is accepted by
     `replay/1` with no digest recomputed, so a log entry is silently dropped
     (standing rolls back). The moduledoc lists only a coordinated seal rewrite
     and tail truncation as undetected.
  2. Unverified triples reach `standing_projection/1`. `replay/1` ignores an
     `sj:StandingTransitionEvent` that has no `dcterms:identifier`, but
     `standing_projection.rq`'s `FILTER NOT EXISTS ?later` counts it, so a
     phantom event with a high `sj:seq` makes a verified work order vanish from
     the SPARQL projection while `replay/1` still returns the full log.
  3. A string field that BEGINS with a Grapheme_Extend character (combining
     mark, ZWJ, ZWNJ, variation selector, emoji modifier) loses that character
     in RDF.ex's Turtle decoder (it treats quote+mark as one grapheme), so an
     honest, untampered export of a real `TransitionLog` event is refused with
     `:event_digest_mismatch`. Escaping such characters as `\\uXXXX` in
     `literal/1` avoids it (verified by hand-editing the Turtle).

  Chicago-style like the builder's suite: real WorkOrders, real `Reconciler`
  admission, a real file-backed `TransitionLog`, the real PROV-O template, real
  RDF.ex parsing and the real oxigraph NIF. State-based assertions only; no
  test doubles. Every tamper edits the real emitted Turtle text or its graph.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Provenance, Reconciler, TransitionLog}

  @sha String.duplicate("a", 40)
  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @xsd_integer "http://www.w3.org/2001/XMLSchema#integer"

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
    dir = Path.join(System.tmp_dir!(), "sj_prov_fals_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    root = wo("ROOT")
    b = wo("B", ["ROOT"])
    c = wo("C", ["ROOT"])
    graph = [root, b, c]

    for w <- graph do
      assert {:ok, _, :appended} = Reconciler.reconcile(w, receipt(w), dir)
    end

    events = TransitionLog.read(dir)
    assert length(events) == 3
    assert {:ok, ttl} = TransitionLog.export_turtle(dir)

    %{dir: dir, graph: graph, events: events, ttl: ttl}
  end

  defp event_iri(event), do: "urn:ggen:sj:event:" <> event["event_digest"]
  defp state_iri(event), do: "urn:ggen:sj:standing:" <> event["event_digest"]

  defp drop_event(ttl, event) do
    ttl
    |> RDF.Turtle.read_string!()
    |> RDF.Graph.delete_descriptions([RDF.iri(event_iri(event)), RDF.iri(state_iri(event))])
    |> RDF.Turtle.write_string!()
  end

  describe "chain integrity is not covered by any digest (falsifier)" do
    test "deleting a middle event and re-pointing the next chain triple is refused", ctx do
      [e1, e2, _e3] = ctx.events

      # ONE text edit (e3's prov:wasInformedBy: e2 -> e1) plus removal of e2's
      # event and state descriptions. No digest, seal or IRI is recomputed.
      repointed =
        String.replace(
          ctx.ttl,
          "prov:wasInformedBy <#{event_iri(e2)}>",
          "prov:wasInformedBy <#{event_iri(e1)}>",
          global: false
        )

      refute repointed == ctx.ttl
      result = repointed |> drop_event(e2) |> Provenance.replay()

      assert match?({:error, {:refused, _}}, result),
             "middle event #{e2["identity"]} (seq #{e2["seq"]}) was silently removed; " <>
               "replay returned kept seqs " <>
               inspect(with {:ok, evs} <- result, do: Enum.map(evs, & &1["seq"]))
    end

    test "deleting the first event and dropping the next chain triple is refused", ctx do
      [e1, e2 | _] = ctx.events

      rerooted =
        String.replace(ctx.ttl, " ;\n    prov:wasInformedBy <#{event_iri(e1)}>", "",
          global: false
        )

      refute rerooted == ctx.ttl
      result = rerooted |> drop_event(e1) |> Provenance.replay()

      assert match?({:error, {:refused, _}}, result),
             "first event #{e1["identity"]} was silently removed and #{e2["identity"]} " <>
               "re-rooted; replay returned " <> inspect(result, limit: 3)
    end
  end

  describe "unverified triples reach the SPARQL projection (falsifier)" do
    test "a phantom event (no identifier) cannot change standing_projection/1 while replay verifies",
         ctx do
      phantom =
        ctx.ttl <>
          """

          <urn:ggen:sj:event:phantom> a <#{@sj}StandingTransitionEvent> ;
              <#{@sj}workOrderId> "ROOT" ;
              <#{@sj}seq> "99"^^<#{@xsd_integer}> .
          """

      {_projected, logged} = SemanticJira.project(ctx.graph, ctx.events)
      replayed = Provenance.replay(phantom)
      projected = Provenance.standing_projection(phantom)

      # Either the phantom is refused outright, or replay and the SPARQL
      # projection must both still agree with the log.
      assert match?({:error, {:refused, _}}, replayed) or
               match?({:error, {:refused, _}}, projected) or
               (replayed == {:ok, ctx.events} and projected == {:ok, logged}),
             "replay returned the full verified log (#{inspect(replayed == {:ok, ctx.events})}) " <>
               "but standing_projection covers #{inspect(with {:ok, m} <- projected, do: Map.keys(m))} " <>
               "vs the log's #{inspect(Map.keys(logged))}"
    end
  end

  describe "string fields beginning with a Grapheme_Extend character (falsifier)" do
    # Codepoints are built with <<cp::utf8>> at compile time (not written as
    # literal characters) so `mix format` cannot rewrite the source.
    for {label, codepoint} <- [
          {"combining grave accent U+0300", 0x0300},
          {"zero width joiner U+200D", 0x200D},
          {"variation selector U+FE0F", 0xFE0F},
          {"emoji skin tone modifier U+1F3FB", 0x1F3FB},
          {"Telugu sign U+0C00", 0x0C00}
        ] do
      test "an honest export round-trips an identity starting with #{label}", ctx do
        dir = Path.join(ctx.dir, "extend")
        identity = <<unquote(codepoint)::utf8>> <> "work-order"

        assert {:ok, _, :appended} =
                 TransitionLog.append(dir, %{
                   "identity" => identity,
                   "to" => "ALIVE",
                   "authority" => "NONE"
                 })

        events = TransitionLog.read(dir)
        assert {:ok, ttl} = TransitionLog.export_turtle(dir)

        assert Provenance.replay(ttl) == {:ok, events}
      end
    end
  end
end
