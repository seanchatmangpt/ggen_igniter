defmodule GgenIgniter.SemanticJiraEventSourcingKernelTest do
  @moduledoc """
  Chicago-style proof for the KERNEL half of the event-sourced standing law
  (v26.9.19, restored by WO-03, adopted by FRI-T6; tested by V23-T6R per
  PRD PR-006/PR-013, ARD §7).

  Restored verbatim from the kernel describes of
  `test/ggen_igniter_semantic_jira_event_sourcing_test.exs` at
  `preserve/v26.9.22/wo-03-wip` (2d1fadb). A WorkOrder's definition is
  immutable (`definition_digest/1` over the closed `@definition_fields`),
  `work_order_digest` remains the moving snapshot digest, standing changes are
  append-only `standing_transition_event`s manufactured by
  `apply_transition/2` from admitted `promote/3` intents, current standing is a
  pure projection (`project_standing/1`, chain tip wins, declared standing as
  fallback), the frontier consults the projection, and `replay_check/2`
  reconstructs standing from the transition log alone.

  The graph-side describes of that file (SHACL event shapes, the
  `055_standing_projection.rq` SPARQL-vs-kernel equivalence, the jira render of
  projected standing) are NOT restored: they need the deferred event-sourcing
  ontology/shape hunks (sj:transitionId, sj:transitionWorkOrder, ...), recorded
  as successor v23:GC-26.9.24 in receipts/v26.9.23/V23-T6R.json. Real kernel
  functions only; no doubles.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira

  # ── Kernel-side helpers ──────────────────────────────────────────────────

  # Always a form-valid sha256 digest (64 hex chars), distinct per seed —
  # fixture constants must never fail the pack's own digest patterns.
  defp semantic_digest(seed) do
    "sha256:" <>
      Base.encode16(:crypto.hash(:sha256, "semantic-jira-event-sourcing:" <> seed), case: :lower)
  end

  defp sample_work_order(overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => "SJ-TEST-001",
        "title" => "Bounded semantic test",
        "description" => "Exercise the kernel without granting authority.",
        "subject" => "urn:subject:test",
        "repository" => "seanchatmangpt/ggen_igniter",
        "base_sha" => String.duplicate("a", 40),
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:test:1",
        "dependencies" => [],
        "required_courts" => ["court:test"],
        "required_evidence" => ["source", "verification"],
        "acceptance" => ["acceptance:test"],
        "falsifiers" => ["falsifier:test"],
        "projections" => SemanticJira.projection_types(),
        "required_receipt_classes" => ["verification"],
        "path_scope" => ["lib/ggen_igniter"],
        "authority_requirement" => "NONE",
        "replay_required" => false
      },
      overrides
    )
  end

  # Full promotion evidence for `target`: every promote/3 check satisfied
  # except the ALIVE-only ceiling check, which needs observed execution.
  defp promote_intent!(work_order, target) do
    {:ok, admitted} = SemanticJira.admit_work_order(work_order)

    evidence = %{
      "work_order_digest" => admitted["work_order_digest"],
      "subject" => admitted["subject"],
      "repository" => admitted["repository"],
      "base_sha" => admitted["base_sha"],
      "dependency_evidence" => %{},
      "court_results" => %{"court:test" => %{"passed" => true}},
      "evidence_types" => admitted["required_evidence"],
      "acceptance_results" => Map.new(admitted["acceptance"], &{&1, true}),
      "falsifier_results" => Map.new(admitted["falsifiers"], &{&1, "survived"}),
      "receipt_classes" => admitted["required_receipt_classes"],
      "evidence_ceiling" => admitted["evidence_ceiling"],
      "observed_execution" => true,
      "inherited_standing" => false
    }

    assert {:ok, intent} = SemanticJira.promote(work_order, target, evidence)
    {admitted, intent}
  end

  defp apply_event!(work_order, target, attrs \\ %{}) do
    {admitted, intent} = promote_intent!(work_order, target)

    attrs =
      Map.merge(
        %{
          "intent" => intent,
          "evidence_identity" => "receipt:" <> String.downcase(target),
          "final_head" => String.duplicate("b", 40)
        },
        attrs
      )

    assert {:ok, event} = SemanticJira.apply_transition(admitted, attrs)
    {admitted, event}
  end

  describe "immutable definition digest vs moving snapshot digest" do
    test "definition digest is stable across standing change while the snapshot digest moves" do
      {:ok, unknown} = SemanticJira.admit_work_order(sample_work_order())

      {:ok, partial} =
        SemanticJira.admit_work_order(sample_work_order(%{"standing" => "PARTIAL_ALIVE"}))

      assert unknown["definition_digest"] == partial["definition_digest"]
      refute unknown["work_order_digest"] == partial["work_order_digest"]

      # The candidate moves with each attempt; the definition does not.
      {:ok, advanced} =
        SemanticJira.admit_work_order(
          sample_work_order(%{"candidate_sha" => String.duplicate("d", 40)})
        )

      assert unknown["definition_digest"] == advanced["definition_digest"]
      refute unknown["work_order_digest"] == advanced["work_order_digest"]

      assert Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, unknown["definition_digest"])
    end

    test "definition digest is insertion-order independent, blind to non-definition fields, and sensitive to definition fields" do
      work_order = sample_work_order()
      reversed = work_order |> Enum.reverse() |> Map.new()

      {:ok, first} = SemanticJira.admit_work_order(work_order)
      {:ok, second} = SemanticJira.admit_work_order(reversed)
      assert first["definition_digest"] == second["definition_digest"]

      # Prose and other non-definition keys never touch the definition digest.
      {:ok, annotated} = SemanticJira.admit_work_order(sample_work_order(%{"notes" => "prose"}))
      assert first["definition_digest"] == annotated["definition_digest"]

      # A definition field IS the definition.
      {:ok, renamed} = SemanticJira.admit_work_order(sample_work_order(%{"title" => "Renamed"}))
      refute first["definition_digest"] == renamed["definition_digest"]

      # The standalone function agrees with the admission stamp.
      assert {:ok, definition_digest} = SemanticJira.definition_digest(work_order)
      assert definition_digest == first["definition_digest"]
    end
  end

  # ── StandingTransition events (kernel) ───────────────────────────────────

  describe "StandingTransition events (kernel)" do
    test "apply_transition manufactures a deterministic event binding both digests" do
      work_order = sample_work_order()
      {admitted, event} = apply_event!(work_order, "PARTIAL_ALIVE")

      assert event["kind"] == "standing_transition_event"
      assert event["from_standing"] == "UNKNOWN"
      assert event["to_standing"] == "PARTIAL_ALIVE"
      assert event["work_order_id"] == "SJ-TEST-001"
      assert event["definition_digest"] == admitted["definition_digest"]
      assert event["snapshot_digest"] == admitted["work_order_digest"]
      assert event["evidence_identity"] == "receipt:partial_alive"
      assert event["final_head"] == String.duplicate("b", 40)
      assert event["authority"] == "NONE"
      assert Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, event["transition_id"])

      # Deterministic id over (work order id, toStanding, evidence, final head):
      # re-manufacturing the same transition re-derives the same id.
      {_admitted_again, event_again} = apply_event!(work_order, "PARTIAL_ALIVE")
      assert event_again["transition_id"] == event["transition_id"]

      # Any identity input change re-derives a different id.
      {_admitted_third, event_third} =
        apply_event!(work_order, "PARTIAL_ALIVE", %{"final_head" => String.duplicate("e", 40)})

      refute event_third["transition_id"] == event["transition_id"]
    end

    test "apply_transition refuses tampered, unbound, stale, and illegal intents" do
      work_order = sample_work_order()
      {admitted, intent} = promote_intent!(work_order, "PARTIAL_ALIVE")

      attrs = %{
        "intent" => intent,
        "evidence_identity" => "receipt:1",
        "final_head" => String.duplicate("b", 40)
      }

      # A forged intent whose content no longer re-derives its digest.
      tampered = Map.put(intent, "to", "ALIVE")

      assert {:error, {:refused_transition, :intent_digest_mismatch}} =
               SemanticJira.apply_transition(admitted, %{attrs | "intent" => tampered})

      # A genuine intent bound to a DIFFERENT work-order snapshot.
      {:ok, other} =
        SemanticJira.admit_work_order(sample_work_order(%{"identity" => "SJ-TEST-002"}))

      assert {:error, {:refused_transition, :intent_not_bound_to_work_order}} =
               SemanticJira.apply_transition(other, attrs)

      # A genuine intent overtaken by a standing change (stale `from`).
      moved = sample_work_order(%{"standing" => "PARTIAL_ALIVE"})
      {:ok, moved_admitted} = SemanticJira.admit_work_order(moved)

      assert {:error, {:refused_transition, :stale_intent}} =
               SemanticJira.apply_transition(moved_admitted, attrs)

      # The graph's progression law holds in the kernel: UNKNOWN -> ALIVE
      # refuses at the event court even though the pure promote/3 calculus
      # would admit the intent.
      {admitted_unknown, alive_intent} = promote_intent!(work_order, "ALIVE")

      assert {:error, {:refused_transition, {:illegal_progression, "UNKNOWN", "ALIVE"}}} =
               SemanticJira.apply_transition(admitted_unknown, %{
                 attrs
                 | "intent" => alive_intent,
                   "evidence_identity" => "receipt:alive"
               })

      # Attribute-level refusals.
      assert {:error, {:refused_transition, {:invalid_evidence_identity, ""}}} =
               SemanticJira.apply_transition(admitted, %{attrs | "evidence_identity" => ""})

      assert {:error, {:refused_transition, {:invalid_sha, :final_head, "main"}}} =
               SemanticJira.apply_transition(admitted, %{attrs | "final_head" => "main"})

      assert {:error, {:refused_transition, {:malformed_intent_or_attrs, nil}}} =
               SemanticJira.apply_transition(admitted, Map.delete(attrs, "intent"))
    end

    test "append_transition enforces the append-only law" do
      work_order = sample_work_order()
      {_admitted, event} = apply_event!(work_order, "PARTIAL_ALIVE")

      # First append lands.
      assert {:ok, [event]} = SemanticJira.append_transition([], event)

      # A second event for the chain lands in order.
      moved = sample_work_order(%{"standing" => "PARTIAL_ALIVE"})
      {_admitted, second_event} = apply_event!(moved, "ALIVE")

      assert {:ok, [^event, ^second_event] = log} =
               SemanticJira.append_transition([event], second_event)

      # Re-appending the byte-identical event is an idempotent no-op.
      assert {:ok, ^log} = SemanticJira.append_transition(log, event)

      # Re-deriving the SAME id with DIFFERENT content refuses: ids are
      # immutable once present.
      forged = Map.put(event, "to_standing", "ALIVE")

      assert {:error, {:refused_transition, :transition_id_immutable}} =
               SemanticJira.append_transition(log, forged)

      # Malformed events refuse. (A malformed body under an EXISTING id is
      # caught first by the immutability law, so the malformed fixture here
      # carries a fresh id to reach the completeness court.)
      assert {:error, {:refused_transition, :transition_id_immutable}} =
               SemanticJira.append_transition(log, Map.delete(event, "definition_digest"))

      fresh_id = Map.put(event, "transition_id", semantic_digest("fresh-id"))

      assert {:error, {:refused_transition, {:missing_required_field, "definition_digest"}}} =
               SemanticJira.append_transition(log, Map.delete(fresh_id, "definition_digest"))

      assert {:error, {:refused_transition, {:malformed_event, "forged_kind"}}} =
               SemanticJira.append_transition(log, Map.put(fresh_id, "kind", "forged_kind"))

      assert {:error, {:refused_transition, _}} = SemanticJira.append_transition(log, "not-a-map")
      assert {:error, {:refused_transition, _}} = SemanticJira.append_transition(event, event)
    end
  end

  # ── Standing projection ──────────────────────────────────────────────────

  describe "standing projection (kernel)" do
    test "no events default to the declared standing at the call site" do
      assert {:ok, %{}} = SemanticJira.project_standing([])
    end

    test "the chain tip wins: latest to_standing per work order" do
      work_order = sample_work_order()
      {_admitted, first} = apply_event!(work_order, "PARTIAL_ALIVE")
      moved = sample_work_order(%{"standing" => "PARTIAL_ALIVE"})
      {_admitted, second} = apply_event!(moved, "ALIVE")

      assert {:ok, projection} = SemanticJira.project_standing([first, second])
      assert projection == %{"SJ-TEST-001" => "ALIVE"}

      # Log order is time: the tail of the log is the latest standing.
      assert {:ok, reverted} = SemanticJira.project_standing([second, first])
      assert reverted == %{"SJ-TEST-001" => "PARTIAL_ALIVE"}

      # Independent work orders project independently.
      other = sample_work_order(%{"identity" => "SJ-TEST-002"})
      {_admitted, other_event} = apply_event!(other, "BLOCKED")

      assert {:ok, both} = SemanticJira.project_standing([first, other_event])
      assert both == %{"SJ-TEST-001" => "PARTIAL_ALIVE", "SJ-TEST-002" => "BLOCKED"}
    end

    test "a malformed log refuses instead of silently dropping events" do
      assert {:error, {:refused_standing_projection, {:malformed_transition, _}}} =
               SemanticJira.project_standing([%{"work_order_id" => "X"}])

      assert {:error, {:refused_standing_projection, :expected_transition_list}} =
               SemanticJira.project_standing("not-a-list")
    end

    test "the projection is pure: it round-trips through serialization alone" do
      work_order = sample_work_order()
      {_admitted, first} = apply_event!(work_order, "PARTIAL_ALIVE")
      moved = sample_work_order(%{"standing" => "PARTIAL_ALIVE"})
      {_admitted, second} = apply_event!(moved, "ALIVE")

      {:ok, direct} = SemanticJira.project_standing([first, second])

      # A fresh BEAM replays the log from its serialized form alone.
      reloaded = Jason.decode!(Jason.encode!([first, second]))
      assert {:ok, ^direct} = SemanticJira.project_standing(reloaded)
    end
  end

  # ── Frontier consults projected standing ────────────────────────────────

  describe "frontier consults projected standing" do
    test "a work order transitioned away from UNKNOWN is no longer frontier-eligible" do
      work_order = sample_work_order()
      {_admitted, event} = apply_event!(work_order, "PARTIAL_ALIVE")

      # No transitions: declared UNKNOWN stays eligible.
      assert [%{"identity" => "SJ-TEST-001"}] = SemanticJira.frontier([work_order]).eligible

      # Transitioned to PARTIAL_ALIVE: the projection blocks it.
      blocked = SemanticJira.frontier([work_order], %{}, [event])

      assert blocked.eligible == []

      assert [%{"identity" => "SJ-TEST-001", "reason" => "standing=PARTIAL_ALIVE"}] =
               blocked.blocked

      # A regression back to UNKNOWN re-opens the work for the same definition.
      moved = sample_work_order(%{"standing" => "PARTIAL_ALIVE"})
      {_admitted, regression} = apply_event!(moved, "UNKNOWN")

      assert [%{"identity" => "SJ-TEST-001"}] =
               SemanticJira.frontier([work_order], %{}, [event, regression]).eligible
    end

    test "the declared standing remains the fallback without transitions" do
      declared_partial = sample_work_order(%{"standing" => "PARTIAL_ALIVE"})

      blocked = SemanticJira.frontier([declared_partial])

      assert blocked.eligible == []
      assert [%{"reason" => "standing=PARTIAL_ALIVE"}] = blocked.blocked

      # The two-arity form keeps working (transition log defaults to []).
      assert [%{"identity" => "SJ-TEST-001"}] =
               SemanticJira.frontier([sample_work_order()], %{}).eligible
    end

    test "a malformed transition log fails the whole selection closed" do
      refused = SemanticJira.frontier([sample_work_order()], %{}, ["garbage"])

      assert refused.eligible == []
      assert [%{"reason" => "malformed_transition_log"}] = refused.blocked
    end

    test "eligible candidates carry the immutable definition digest" do
      assert [%{"identity" => "SJ-TEST-001", "definition_digest" => digest}] =
               SemanticJira.frontier([sample_work_order()]).eligible

      assert Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, digest)
    end
  end

  # ── Replay reconstruction from the transition log alone ─────────────────

  describe "replay_check reconstructs standing from transitions alone" do
    defp replay_manifests do
      work_order = sample_work_order()
      {_admitted, first} = apply_event!(work_order, "PARTIAL_ALIVE")
      moved = sample_work_order(%{"standing" => "PARTIAL_ALIVE"})
      {_admitted, second} = apply_event!(moved, "ALIVE")
      {:ok, definition} = SemanticJira.admit_work_order(work_order)

      base = %{
        "pack_subject" => "semantic-jira-pack@26.9.19",
        "dependency_set" => [semantic_digest("a")],
        "graph_digest" => semantic_digest("b"),
        "consequence_set" => [semantic_digest("c")],
        "toolchain_identity" => "elixir:1.18.4-otp-27",
        "environment_identity" => "darwin:local",
        "replay_identity" => "replay:1"
      }

      {base, definition, [first, second]}
    end

    test "a matching log replays and binds the reconstructed standing projection" do
      {base, definition, log} = replay_manifests()

      expected =
        Map.merge(base, %{
          "standing_transitions" => log,
          "definition_digest" => definition["definition_digest"]
        })

      observed =
        Map.merge(base, %{
          "standing_transitions" => log,
          "definition_digest" => definition["definition_digest"]
        })

      assert {:ok, receipt} = SemanticJira.replay_check(expected, observed)
      assert receipt["status"] == "KNOWN_REPLAY"
      assert receipt["standing_projection"] == %{"SJ-TEST-001" => "ALIVE"}
    end

    test "divergent projections refuse as identity mismatches" do
      {base, _definition, log} = replay_manifests()
      truncated = List.delete_at(log, 1)

      assert {:error, {:replay_refused, {:identity_mismatch, mismatches}}} =
               SemanticJira.replay_check(
                 Map.merge(base, %{"standing_transitions" => log}),
                 Map.merge(base, %{"standing_transitions" => truncated})
               )

      assert [%{"field" => "standing_projection", "expected" => e, "observed" => o}] = mismatches
      assert e == %{"SJ-TEST-001" => "ALIVE"}
      assert o == %{"SJ-TEST-001" => "PARTIAL_ALIVE"}
    end

    test "a half-supplied log refuses (replay evidence is all-or-nothing)" do
      {base, _definition, log} = replay_manifests()

      assert {:error, {:replay_refused, :transition_log_half_supplied}} =
               SemanticJira.replay_check(
                 Map.merge(base, %{"standing_transitions" => log}),
                 base
               )
    end

    test "transitions bound to a foreign definition digest refuse" do
      {base, _definition, log} = replay_manifests()
      foreign = Map.put(base, "definition_digest", semantic_digest("f"))

      assert {:error, {:replay_refused, {:transition_definition_mismatch, _}}} =
               SemanticJira.replay_check(
                 Map.merge(foreign, %{"standing_transitions" => log}),
                 Map.merge(foreign, %{"standing_transitions" => log})
               )
    end

    test "a fresh graph plus definition plus events reconstructs the same projection" do
      {base, definition, log} = replay_manifests()

      # The replaying side holds ONLY the definition identity and the event
      # log — no graph snapshot — and reconstructs the identical projection.
      original = Map.merge(base, %{"standing_transitions" => log})
      {:ok, original_receipt} = SemanticJira.replay_check(original, original)
      assert original_receipt["standing_projection"] == %{"SJ-TEST-001" => "ALIVE"}

      fresh_log = Jason.decode!(Jason.encode!(log))

      fresh =
        Map.merge(base, %{
          "standing_transitions" => fresh_log,
          "definition_digest" => definition["definition_digest"]
        })

      assert {:ok, fresh_receipt} = SemanticJira.replay_check(fresh, fresh)
      assert fresh_receipt["standing_projection"] == original_receipt["standing_projection"]
    end
  end
end
