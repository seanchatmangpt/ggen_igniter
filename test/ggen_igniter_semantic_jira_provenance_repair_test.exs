defmodule GgenIgniter.SemanticJiraProvenanceRepairTest do
  @moduledoc """
  Permanent guards for the four defect classes the qualifier
  (`..._provenance_qualifier_test.exs`) and falsifier
  (`..._provenance_falsifier_test.exs`) files pinned at c402a46, each guarded at
  the layer where the root cause sat, not only through the honest-export symptom:

  1. `prov:startedAtTime` lexical form. Only canonical xsd:dateTime strings are
     emitted typed; every other string rides in `sj:extra`. Guarded with a
     combinatorial sweep of fraction / offset / year shapes, all in ONE log.
  2. `sj:seq` datatype and unverified nodes. `replay/1` refuses a retyped
     `sj:seq` and an event node lacking `dcterms:identifier` / `sj:seq`;
     `standing_projection.rq` is hardened on its own (identified `?later`,
     numeric seq compare) AND `standing_projection/1` only queries the
     canonical re-rendering of the verified events.
  3. Chain integrity. The predecessor digest is inside each `sj:contentSeal`,
     so a chain-triple edit is a seal mismatch, not just a `:broken_chain`.
  4. Turtle literals. `literal/1` writes pure ASCII; every codepoint that
     RDF.ex's grapheme-based decoder would fuse with the opening or closing
     quote (computed from `String.length/1`, not hard-coded) round-trips.

  Chicago-style like the rest of the suite: the real pack template, real RDF.ex
  parsing, the real oxigraph NIF through `GgenIgniter.Engine`; state-based
  assertions on returned events, standing maps and refusal reasons. Events in
  the sweeps are synthetic maps with a real `SemanticJira.digest/1` (the same
  digest `TransitionLog.append/2` computes) so thousands can be exercised
  without thousands of files; the honest-file path is covered in the qualifier
  and falsifier suites. No test doubles.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Engine, SemanticA2A, SemanticJira}
  alias GgenIgniter.SemanticJira.Provenance

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"

  defp event(seq, fields) do
    body = Map.merge(%{"to" => "ALIVE", "authority" => "NONE"}, fields)
    body |> Map.put("seq", seq) |> Map.put("event_digest", SemanticJira.digest(body))
  end

  defp chain_events do
    for n <- 1..4, do: event(n, %{"identity" => "W#{n}", "kind" => "standing_transition_event"})
  end

  defp event_iri(event), do: "urn:ggen:sj:event:" <> event["event_digest"]
  defp state_iri(event), do: "urn:ggen:sj:standing:" <> event["event_digest"]

  defp drop_events(ttl, events) do
    iris = Enum.flat_map(events, &[RDF.iri(event_iri(&1)), RDF.iri(state_iri(&1))])

    ttl
    |> RDF.Turtle.read_string!()
    |> RDF.Graph.delete_descriptions(iris)
    |> RDF.Turtle.write_string!()
  end

  defp export!(events) do
    assert {:ok, ttl} = Provenance.to_turtle(events)
    ttl
  end

  describe "started_at lexical forms" do
    @fractions ["", ".0", ".5", ".50", ".500", ".05", ".000001", ".0000010", ".123450"] ++
                 [".123456789", ".1000000000", ".9"]
    @offsets ["Z", "+00:00", "+05:30", "-08:00", "+14:00", "+00:30", "-00:00", "z", "+0000"]
    @years ["2026", "0001", "9999"]
    @junk [
      "not-a-date",
      "2026-09-21",
      "2026-02-30T00:00:00Z",
      "2026-09-21T10:11:12",
      "2026-09-21 10:11:12Z",
      "2026-09-21T24:00:00Z",
      "2026-09-21T10:11:60Z",
      ""
    ]

    setup do
      shapes =
        for year <- @years, fraction <- @fractions, offset <- @offsets do
          "#{year}-09-21T10:11:12#{fraction}#{offset}"
        end ++ @junk

      events =
        shapes
        |> Enum.with_index(1)
        |> Enum.map(fn {shape, n} ->
          event(n, %{"identity" => "dt-#{n}", "started_at" => shape})
        end)

      %{shapes: shapes, events: events}
    end

    test "every started_at shape replays equal to the log (one log, one replay)", ctx do
      assert length(ctx.events) > 300
      assert Provenance.replay(export!(ctx.events)) == {:ok, ctx.events}
    end

    test "canonical values are emitted as prov:startedAtTime, the rest ride in sj:extra", ctx do
      ttl = export!(ctx.events)

      for canonical <- [
            "2026-09-21T10:11:12Z",
            "2026-09-21T10:11:12.5Z",
            "2026-09-21T10:11:12.05Z",
            "2026-09-21T10:11:12.000001Z",
            "2026-09-21T10:11:12.123456789Z",
            "2026-09-21T10:11:12+05:30",
            "2026-09-21T10:11:12-08:00",
            "2026-09-21T10:11:12.9+14:00"
          ] do
        assert ttl =~ ~s(prov:startedAtTime "#{canonical}"^^xsd:dateTime),
               "#{canonical} should be emitted typed"
      end

      for lossy <- [
            "2026-09-21T10:11:12.000Z",
            "2026-09-21T10:11:12.500Z",
            "2026-09-21T10:11:12.123450Z",
            "2026-09-21T10:11:12.1000000000Z",
            "2026-09-21T10:11:12+00:00",
            "2026-09-21T10:11:12.0+05:30",
            "not-a-date"
          ] do
        refute ttl =~ ~s(prov:startedAtTime "#{lossy}"),
               "#{lossy} must not be emitted as a typed dateTime"
      end
    end

    test "a started_at carried in sj:extra cannot be shadowed by an added startedAtTime" do
      lossy = event(1, %{"identity" => "lossy", "started_at" => "2026-09-21T10:11:12.000Z"})
      ttl = export!([lossy])
      assert ttl =~ ~s(sj:extra)
      refute ttl =~ "prov:startedAtTime"

      # Add a typed startedAtTime to the ACTIVITY (the event carries the lossy
      # value in sj:extra): it must be refused, never silently preferred.
      forged =
        String.replace(
          ttl,
          ~s(sj:seq "1"^^xsd:integer),
          ~s(sj:seq "1"^^xsd:integer ;\n    prov:startedAtTime "2026-09-21T10:11:12Z"^^xsd:dateTime),
          global: false
        )

      refute forged == ttl

      assert {:error, {:refused, {:extra_shadows_field, "started_at", _}}} =
               Provenance.replay(forged)
    end
  end

  describe "sj:seq and unverified event nodes" do
    test "a retyped sj:seq is refused by replay and by standing_projection" do
      events = chain_events()
      ttl = export!(events)
      target = Enum.at(events, 1)

      expected = {:error, {:refused, {:invalid_seq, event_iri(target)}}}

      for retyped <- [~s(sj:seq "2"), ~s(sj:seq "2"^^xsd:decimal), ~s(sj:seq "2"^^xsd:double)] do
        forged = String.replace(ttl, ~s(sj:seq "2"^^xsd:integer), retyped, global: false)
        refute forged == ttl

        assert Provenance.replay(forged) == expected, "replay accepted #{retyped}"
        assert Provenance.standing_projection(forged) == expected
      end
    end

    test "a derived integer type (xsd:int) is either the same log or refused, never different" do
      events = chain_events()
      ttl = export!(events)
      refusal = {:error, {:refused, {:invalid_seq, event_iri(Enum.at(events, 1))}}}

      forged =
        String.replace(ttl, ~s(sj:seq "2"^^xsd:integer), ~s(sj:seq "2"^^xsd:int), global: false)

      refute forged == ttl

      # The RDF.ex -> oxigraph path widens derived integer types to xsd:integer, so
      # the value is the same integer; what must never happen is an accepted log
      # that differs from the honest one.
      assert Provenance.replay(forged) in [{:ok, events}, refusal]
    end

    test "an event node without dcterms:identifier is refused, not ignored" do
      events = chain_events()
      ttl = export!(events)

      phantom =
        ttl <>
          """

          <urn:ggen:sj:event:phantom> a <#{@sj}StandingTransitionEvent> ;
              <#{@sj}workOrderId> "W1" ;
              <#{@sj}seq> "99"^^<http://www.w3.org/2001/XMLSchema#integer> .
          """

      expected =
        {:error, {:refused, {:iri_literal_mismatch, :event, "urn:ggen:sj:event:phantom"}}}

      assert Provenance.replay(phantom) == expected
      assert Provenance.standing_projection(phantom) == expected
    end

    test "an event node with an identifier but no sj:seq is refused" do
      events = chain_events()
      ttl = export!(events)
      digest = "sha256:" <> String.duplicate("b", 64)

      phantom =
        ttl <>
          """

          <urn:ggen:sj:event:#{digest}> a <#{@sj}StandingTransitionEvent> ;
              <http://purl.org/dc/terms/identifier> "#{digest}" .
          """

      expected = {:error, {:refused, {:invalid_seq, "urn:ggen:sj:event:" <> digest}}}
      assert Provenance.replay(phantom) == expected
      assert Provenance.standing_projection(phantom) == expected
    end

    test "standing_projection/1 answers from verified events only: noise triples are inert" do
      events =
        for n <- 1..12,
            do: event(n, %{"identity" => "W", "from" => "S#{n - 1}", "to" => "S#{n}"})

      ttl =
        export!(events) <>
          """

          <urn:noise:1> a <http://www.w3.org/ns/prov#Activity> ;
              <#{@sj}workOrderId> "W" ;
              <#{@sj}seq> "999" .
          """

      {_projected, logged} = SemanticJira.project([%{"identity" => "W"}], events)
      assert %{"W" => %{"standing" => "S12"}} = logged
      assert Provenance.standing_projection(ttl) == {:ok, logged}
    end

    test "standing_projection.rq is hardened on its own, over a raw unverified graph" do
      # Bypasses Provenance.replay/1: the query file itself must not be fooled
      # by a phantom (no identifier) event or by string-compared seq numbers.
      raw = """
      @prefix sj: <#{@sj}> .
      @prefix dcterms: <http://purl.org/dc/terms/> .
      @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
      <urn:e:9> a sj:StandingTransitionEvent ; dcterms:identifier "e9" ;
        sj:workOrderId "W" ; sj:seq "9"^^xsd:integer ; sj:toStanding "S9" .
      <urn:e:10> a sj:StandingTransitionEvent ; dcterms:identifier "e10" ;
        sj:workOrderId "W" ; sj:seq "10"^^xsd:integer ; sj:toStanding "S10" .
      <urn:e:plain> a sj:StandingTransitionEvent ; dcterms:identifier "e11" ;
        sj:workOrderId "W" ; sj:seq "11" ; sj:toStanding "S11-plain" .
      <urn:e:phantom> a sj:StandingTransitionEvent ;
        sj:workOrderId "W" ; sj:seq "99"^^xsd:integer ; sj:toStanding "PHANTOM" .
      """

      engine = Engine.fetch!("oxigraph")
      context = engine.prepare!(RDF.Turtle.read_string!(raw), [])

      query =
        [SemanticA2A.pack_dir(), "runtime-queries", "standing_projection.rq"]
        |> Path.join()
        |> File.read!()

      standings = context |> engine.run(query) |> Enum.map(& &1["to"])

      # Numeric compare: 10 beats 9 (a string compare would pick S9), and the
      # unidentified phantom (seq 99) neither wins nor hides anything. The
      # plain-string seq "11" casts to 11 and legitimately wins.
      assert standings == ["S11-plain"]
    end
  end

  describe "chain integrity is sealed" do
    test "deleting a middle event and re-pointing the next chain triple is refused" do
      [e1, e2, _e3, _e4] = events = chain_events()
      ttl = export!(events)

      repointed =
        String.replace(
          ttl,
          "prov:wasInformedBy <#{event_iri(e2)}>",
          "prov:wasInformedBy <#{event_iri(e1)}>",
          global: false
        )

      refute repointed == ttl
      e3_iri = event_iri(Enum.at(events, 2))

      assert Provenance.replay(drop_events(repointed, [e2])) ==
               {:error, {:refused, {:content_seal_mismatch, e3_iri}}}
    end

    test "deleting the first event and dropping the next chain triple is refused" do
      [e1, e2 | _] = events = chain_events()
      ttl = export!(events)

      rerooted =
        String.replace(ttl, " ;\n    prov:wasInformedBy <#{event_iri(e1)}>", "", global: false)

      refute rerooted == ttl

      assert Provenance.replay(drop_events(rerooted, [e1])) ==
               {:error, {:refused, {:content_seal_mismatch, event_iri(e2)}}}
    end

    test "deleting a middle event WITHOUT touching the chain triple is still :broken_chain" do
      [_e1, e2, e3, _e4] = events = chain_events()
      ttl = export!(events)

      assert Provenance.replay(drop_events(ttl, [e2])) ==
               {:error, {:refused, {:broken_chain, e3["event_digest"]}}}
    end

    test "editing one chain triple with every event present is refused" do
      [_e1, e2, e3, e4] = events = chain_events()
      ttl = export!(events)

      # e4 claims to follow e2 instead of e3; nothing else is edited.
      forged =
        String.replace(
          ttl,
          "prov:wasInformedBy <#{event_iri(e3)}>",
          "prov:wasInformedBy <#{event_iri(e2)}>",
          global: false
        )

      refute forged == ttl

      assert Provenance.replay(forged) ==
               {:error, {:refused, {:content_seal_mismatch, event_iri(e4)}}}
    end

    test "an honest export still replays equal and is a fixed point" do
      events = chain_events()
      ttl = export!(events)
      assert Provenance.replay(ttl) == {:ok, events}
      assert export!(elem(Provenance.replay(ttl), 1)) == ttl
    end
  end

  describe "Turtle literals" do
    # Computed from the runtime's own grapheme segmentation (the same property
    # RDF.ex's decoder trips on), not hard-coded: codepoints that form ONE
    # grapheme with a directly preceding / following double quote.
    @fuse_leading for cp <- 0x80..0x10FFFF,
                      cp not in 0xD800..0xDFFF,
                      String.length("\"" <> <<cp::utf8>>) == 1,
                      do: cp
    @fuse_trailing for cp <- 0x80..0x10FFFF,
                       cp not in 0xD800..0xDFFF,
                       String.length(<<cp::utf8>> <> "\"") == 1,
                       do: cp

    test "the fusing classes are non-trivial (guards the guard)" do
      # Combining marks, ZWJ, variation selectors, emoji modifiers, Telugu sign.
      for cp <- [0x0300, 0x200D, 0xFE0F, 0x1F3FB, 0x0C00], do: assert(cp in @fuse_leading)
      # Arabic number sign (Prepend) fuses with the closing quote.
      assert 0x0600 in @fuse_trailing
      assert length(@fuse_leading) > 2000
    end

    test "literal/1 output is pure ASCII for any codepoint" do
      for s <- ["plain", "quote\"back\\slash", <<0x0300::utf8>>, <<0x1F3FB::utf8>> <> "x", "é"] do
        assert Provenance.literal(s) |> :binary.bin_to_list() |> Enum.all?(&(&1 < 128))
      end
    end

    test "every codepoint that fuses with a quote round-trips as the leading character" do
      events =
        @fuse_leading
        |> Enum.with_index(1)
        |> Enum.map(fn {cp, n} -> event(n, %{"identity" => <<cp::utf8>> <> "work-order"}) end)

      assert Provenance.replay(export!(events)) == {:ok, events}
    end

    test "every codepoint that fuses with a quote round-trips as the trailing character" do
      events =
        @fuse_trailing
        |> Enum.with_index(1)
        |> Enum.map(fn {cp, n} -> event(n, %{"identity" => "work-order" <> <<cp::utf8>>}) end)

      assert Provenance.replay(export!(events)) == {:ok, events}
    end

    test "supplementary-plane and mixed strings round-trip in typed fields and sj:extra" do
      events = [
        event(1, %{
          "identity" => "\u{1F3FB}\u{200D}\u{1F468}",
          "kind" => "̀́",
          "note" => "\u{1F3FB} in extra",
          "nested" => %{"‍" => ["ఀ", "a\u{1F600}"]}
        })
      ]

      assert Provenance.replay(export!(events)) == {:ok, events}
    end
  end
end
