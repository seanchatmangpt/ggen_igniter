defmodule GgenIgniter.SemanticJiraReconcilerTest do
  @moduledoc """
  Chicago-style proofs for the receipt reconciler: receipts become an
  append-only, hash-chained standing ledger and the projection feeds the next
  frontier.

  Every collaborator is real: real ndjson ledger files on disk, real OS-level
  lock contention (concurrent BEAM tasks and concurrent `mix` processes), and a
  replay that rebuilds state from the ledger file alone in a fresh OS process.
  Assertions are on returned/persisted state, never on interactions.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Ledger, Reconciler}

  @moduletag timeout: 300_000

  @pin_work_order "sha256:50a4b2c6a64dab060f9f004693c0db22d157072c899540b25f46700ae98c2667"
  @pin_work_order_blocked "sha256:9dcfa8b2d9e587ba85fed1e3ff036130c6043f8262bea0224fec3079d0332688"
  @pin_transition "sha256:4c7fd97fe78662a9e776f094b937d866f63840d0b21bb57a79f6cc421ef05e28"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj-reconciler-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir, ledger: Path.join(dir, "ledger.ndjson")}
  end

  # --- fixtures -------------------------------------------------------------

  defp sha(seed), do: :crypto.hash(:sha, seed) |> Base.encode16(case: :lower)
  defp digest(seed), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, seed), case: :lower)

  defp work_order(id, overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => id,
        "title" => "Bounded semantic test #{id}",
        "description" => "Exercise the reconciler without granting authority.",
        "subject" => "urn:subject:#{id}",
        "repository" => "seanchatmangpt/ggen_igniter",
        "base_sha" => String.duplicate("a", 40),
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:test:#{id}",
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

  defp admitted(id, overrides \\ %{}) do
    {:ok, wo} = SemanticJira.admit_work_order(work_order(id, overrides))
    wo
  end

  defp receipt(wo, seed, overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => wo["identity"],
        "definition_digest" => wo["definition_digest"],
        "source_snapshot_digest" => wo["work_order_digest"],
        "repository" => wo["repository"],
        "base_sha" => wo["base_sha"],
        "subject" => wo["subject"],
        "candidate_sha" => sha("candidate:" <> seed),
        "target" => "ALIVE",
        "receipt_digest" => digest("receipt:" <> seed),
        "court_results" => %{"court:test" => %{"passed" => true}},
        "evidence_types" => ["source", "verification"],
        "acceptance_results" => %{"acceptance:test" => true},
        "falsifier_results" => %{"falsifier:test" => "survived"},
        "receipt_classes" => ["verification"],
        "evidence_ceiling" => wo["evidence_ceiling"],
        "observed_execution" => true,
        "inherited_standing" => false
      },
      overrides
    )
  end

  defp rehash(event),
    do:
      Map.put(event, "event_digest", SemanticJira.digest_exact(Map.delete(event, "event_digest")))

  defp write_json!(path, value), do: File.write!(path, Jason.encode!(value))

  defp reconcile!(work_orders, ledger, receipt) do
    assert {:ok, event} = Ledger.reconcile_and_append(work_orders, ledger, receipt)
    event
  end

  # Runs a real `mix` task in a fresh OS process and returns {exit_code, decoded_last_json_line}.
  defp mix_task(args) do
    {output, code} =
      System.cmd(System.find_executable("mix"), args,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true,
        cd: File.cwd!()
      )

    json =
      output
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.starts_with?(&1, "{"))
      |> List.last()

    {code, json && Jason.decode!(json), output}
  end

  # --- definition digest ----------------------------------------------------

  describe "definition identity" do
    test "definition_digest survives a standing change while the snapshot digest moves" do
      unknown = admitted("SJ-D")
      blocked = admitted("SJ-D", %{"standing" => "BLOCKED"})
      with_candidate = admitted("SJ-D", %{"candidate_sha" => String.duplicate("c", 40)})

      assert unknown["definition_digest"] == blocked["definition_digest"]
      assert unknown["definition_digest"] == with_candidate["definition_digest"]
      refute unknown["work_order_digest"] == blocked["work_order_digest"]
      refute unknown["work_order_digest"] == with_candidate["work_order_digest"]

      changed = admitted("SJ-D", %{"acceptance" => ["acceptance:other"]})
      refute unknown["definition_digest"] == changed["definition_digest"]
    end

    test "re-admitting an admitted work order is idempotent for both digests" do
      first = admitted("SJ-D")
      assert {:ok, again} = SemanticJira.admit_work_order(first)
      assert again["work_order_digest"] == first["work_order_digest"]
      assert again["definition_digest"] == first["definition_digest"]
      assert SemanticJira.definition_digest(first) == first["definition_digest"]
    end

    test "legacy work_order_digest and promote transition_digest are byte-identical to the base" do
      fixture =
        work_order("SJ-TEST-001", %{
          "title" => "Bounded semantic test",
          "description" => "Exercise the kernel without granting authority.",
          "subject" => "urn:subject:test",
          "replay_identity" => "semantic-jira:test:1"
        })

      assert {:ok, wo} = SemanticJira.admit_work_order(fixture)
      assert wo["work_order_digest"] == @pin_work_order

      assert {:ok, blocked} = SemanticJira.admit_work_order(%{fixture | "standing" => "BLOCKED"})
      assert blocked["work_order_digest"] == @pin_work_order_blocked

      evidence = %{
        "work_order_digest" => wo["work_order_digest"],
        "subject" => wo["subject"],
        "repository" => wo["repository"],
        "base_sha" => wo["base_sha"],
        "dependency_evidence" => %{},
        "court_results" => %{"court:test" => %{"passed" => true}},
        "evidence_types" => ["source", "verification"],
        "acceptance_results" => %{"acceptance:test" => true},
        "falsifier_results" => %{"falsifier:test" => "survived"},
        "receipt_classes" => ["verification"],
        "evidence_ceiling" => wo["evidence_ceiling"],
        "observed_execution" => true,
        "inherited_standing" => false
      }

      assert {:ok, transition} = SemanticJira.promote(fixture, "ALIVE", evidence)
      assert transition["transition_digest"] == @pin_transition
    end
  end

  # --- reconcile / project --------------------------------------------------

  describe "receipt -> event -> projection" do
    test "a verified receipt yields a chained event and the projection reads ALIVE", %{
      ledger: ledger
    } do
      wos = [work_order("SJ-A")]
      wo = admitted("SJ-A")

      event = reconcile!(wos, ledger, receipt(wo, "a"))

      assert event["kind"] == "standing_transition"
      assert event["seq"] == 1
      assert event["from"] == "UNKNOWN"
      assert event["to"] == "ALIVE"
      assert event["authority"] == "NONE"
      assert event["prev_event_digest"] == Reconciler.genesis_digest()
      assert event["definition_digest"] == wo["definition_digest"]
      assert event["source_snapshot_digest"] == wo["work_order_digest"]
      assert event["projected_snapshot_digest"] == wo["work_order_digest"]

      assert {:ok, events} = Ledger.read(ledger)
      assert [%{"event_digest" => tail}] = events
      assert tail == Reconciler.tail_digest(events)

      assert {:ok, [projected], evidence} = Reconciler.project(wos, events)
      assert projected["standing"] == "ALIVE"
      assert projected["candidate_sha"] == event["candidate_sha"]
      assert projected["definition_digest"] == wo["definition_digest"]
      refute projected["work_order_digest"] == wo["work_order_digest"]

      assert evidence == %{
               "SJ-A" => %{"standing" => "ALIVE", "receipt_digest" => event["receipt_digest"]}
             }
    end

    test "a dependent work order is eligible only after its dependency's ALIVE transition", %{
      ledger: ledger
    } do
      up_receipt_digest = digest("receipt:up")

      down =
        work_order("SJ-DOWN", %{
          "dependencies" => [
            %{
              "upstream" => "SJ-UP",
              "type" => "requiresReceipt",
              "required_standing" => "ALIVE",
              "required_receipt_digest" => up_receipt_digest
            }
          ]
        })

      wos = [work_order("SJ-UP"), down]

      assert {:ok, before} = Reconciler.frontier(wos, [])
      assert Enum.map(before.eligible, & &1["identity"]) == ["SJ-UP"]

      assert [%{"identity" => "SJ-DOWN", "reason" => "dependencies_unsatisfied"}] =
               before.blocked

      reconcile!(wos, ledger, receipt(admitted("SJ-UP"), "up"))
      {:ok, events} = Ledger.read(ledger)

      assert {:ok, after_up} = Reconciler.frontier(wos, events)
      assert Enum.map(after_up.eligible, & &1["identity"]) == ["SJ-DOWN"]

      assert Enum.map(after_up.eligible, & &1["definition_digest"]) == [
               SemanticJira.definition_digest(admitted("SJ-DOWN", down))
             ]
    end

    test "falsifier: an ALIVE work order is never in the eligible frontier", %{ledger: ledger} do
      wos = [work_order("SJ-A"), work_order("SJ-B")]
      assert {:ok, %{eligible: both}} = Reconciler.frontier(wos, [])
      assert Enum.map(both, & &1["identity"]) == ["SJ-A", "SJ-B"]

      reconcile!(wos, ledger, receipt(admitted("SJ-A"), "a"))
      {:ok, events} = Ledger.read(ledger)

      assert {:ok, frontier} = Reconciler.frontier(wos, events)
      assert Enum.map(frontier.eligible, & &1["identity"]) == ["SJ-B"]

      assert Enum.any?(
               frontier.blocked,
               &(&1["identity"] == "SJ-A" and &1["reason"] == "standing=ALIVE")
             )
    end

    test "dependency truth comes from the ledger, never from the receipt", %{ledger: ledger} do
      down =
        work_order("SJ-DOWN", %{
          "dependencies" => [
            %{"upstream" => "SJ-UP", "type" => "requiresReceipt", "required_standing" => "ALIVE"}
          ]
        })

      wos = [work_order("SJ-UP"), down]

      forged =
        receipt(admitted("SJ-DOWN", down), "down", %{
          "dependency_evidence" => %{"SJ-UP" => %{"standing" => "ALIVE"}}
        })

      assert {:error, {:reconcile_refused, {:promotion_refused, failed}}} =
               Ledger.reconcile_and_append(wos, ledger, forged)

      assert :dependencies in failed
      assert {:ok, []} = Ledger.read(ledger)
    end
  end

  # --- idempotency, staleness, typed refusals -------------------------------

  describe "idempotency and refusals" do
    test "the same receipt twice is idempotent; a different receipt for an ALIVE work order is stale",
         %{ledger: ledger} do
      wos = [work_order("SJ-A")]
      wo = admitted("SJ-A")
      first = reconcile!(wos, ledger, receipt(wo, "a"))

      assert {:ok, :already_applied, again} =
               Ledger.reconcile_and_append(wos, ledger, receipt(wo, "a"))

      assert again == first
      assert {:ok, [_only]} = Ledger.read(ledger)

      assert {:error, {:reconcile_refused, :stale_transition}} =
               Ledger.reconcile_and_append(wos, ledger, receipt(wo, "b"))

      assert {:ok, [_still_only]} = Ledger.read(ledger)
    end

    test "each failure mode has its own typed refusal and writes nothing", %{ledger: ledger} do
      wos = [work_order("SJ-A")]
      wo = admitted("SJ-A")
      good = receipt(wo, "a")

      cases = [
        {:definition_mismatch, %{good | "definition_digest" => digest("other")}},
        {:base_sha_mismatch, %{good | "base_sha" => String.duplicate("b", 40)}},
        {:repository_mismatch, %{good | "repository" => "someone/else"}},
        {:subject_mismatch, %{good | "subject" => "urn:subject:other"}},
        {:invalid_receipt_digest, %{good | "receipt_digest" => "not-a-digest"}},
        {:invalid_source_snapshot, %{good | "source_snapshot_digest" => "nope"}},
        {:unknown_source_snapshot, %{good | "source_snapshot_digest" => digest("never-seen")}},
        {:invalid_candidate_sha, %{good | "candidate_sha" => "HEAD"}},
        {{:invalid_target, "UNKNOWN"}, Map.put(good, "target", "UNKNOWN")},
        {{:unknown_work_order, "SJ-NOPE"}, %{good | "identity" => "SJ-NOPE"}},
        {:receipt_identity_missing, Map.delete(good, "identity")},
        {{:promotion_refused, [:courts]}, %{good | "court_results" => %{}}},
        {{:promotion_refused, [:no_inherited_crown]}, %{good | "inherited_standing" => true}}
      ]

      reasons =
        for {expected, bad} <- cases do
          assert {:error, {:reconcile_refused, ^expected}} =
                   Ledger.reconcile_and_append(wos, ledger, bad)

          expected
        end

      assert length(Enum.uniq(reasons)) == length(cases)
      assert {:ok, []} = Ledger.read(ledger)
      assert File.exists?(ledger) == false
    end

    test "a non-ALIVE outcome is recorded and can still be superseded, ALIVE cannot", %{
      ledger: ledger
    } do
      wos = [work_order("SJ-A")]
      wo = admitted("SJ-A")

      broken = reconcile!(wos, ledger, receipt(wo, "broken", %{"target" => "BUILD_BROKEN"}))
      assert broken["to"] == "BUILD_BROKEN"

      {:ok, events} = Ledger.read(ledger)
      {:ok, [projected], _} = Reconciler.project(wos, events)
      assert projected["standing"] == "BUILD_BROKEN"

      # the receipt may bind any snapshot from this work order's own history
      alive = reconcile!(wos, ledger, receipt(wo, "fixed"))
      assert alive["from"] == "BUILD_BROKEN"
      assert alive["seq"] == 2
      assert alive["prev_event_digest"] == broken["event_digest"]
    end
  end

  # --- tamper evidence --------------------------------------------------------

  describe "tamper evidence" do
    setup %{ledger: ledger} do
      wos = for id <- ["SJ-A", "SJ-B", "SJ-C"], do: work_order(id)

      for {id, seed} <- [{"SJ-A", "a"}, {"SJ-B", "b"}, {"SJ-C", "c"}],
          do: reconcile!(wos, ledger, receipt(admitted(id), seed))

      {:ok, events} = Ledger.read(ledger)
      assert {:ok, _, _} = Reconciler.project(wos, events)
      {:ok, wos: wos, events: events}
    end

    test "every kind of edit to a persisted event is refused", %{wos: wos, events: events} do
      tampers = %{
        "flip receipt_digest" =>
          &List.update_at(&1, 1, fn e -> Map.put(e, "receipt_digest", digest("forged")) end),
        "flip evidence_digest" =>
          &List.update_at(&1, 0, fn e -> Map.put(e, "evidence_digest", digest("forged")) end),
        "flip authority" => &List.update_at(&1, 2, fn e -> Map.put(e, "authority", "ALL") end),
        "drop first event" => &List.delete_at(&1, 0),
        "drop middle event" => &List.delete_at(&1, 1),
        "swap events" => fn e -> [Enum.at(e, 0), Enum.at(e, 2), Enum.at(e, 1)] end,
        "duplicate an event" => fn e -> e ++ [Enum.at(e, 2)] end,
        "rehashed definition swap" =>
          &List.update_at(&1, 2, fn e -> rehash(Map.put(e, "definition_digest", digest("x"))) end),
        "rehashed wrong from" =>
          &List.update_at(&1, 2, fn e -> rehash(Map.put(e, "from", "BLOCKED")) end),
        "rehashed wrong snapshot" =>
          &List.update_at(&1, 2, fn e ->
            rehash(Map.put(e, "projected_snapshot_digest", digest("x")))
          end),
        "rehashed unknown identity" =>
          &List.update_at(&1, 2, fn e -> rehash(Map.put(e, "identity", "SJ-GHOST")) end)
      }

      for {name, tamper} <- tampers do
        assert {:error, {:ledger_invalid, _reason}} = Reconciler.project(wos, tamper.(events)),
               "tamper not detected: #{name}"
      end
    end

    test "a tampered ledger file cannot be appended to and is refused by the frontier task", %{
      dir: dir,
      ledger: ledger,
      wos: wos,
      events: events
    } do
      [first | rest] = events
      tampered = [Map.put(first, "receipt_digest", digest("forged")) | rest]
      File.write!(ledger, Enum.map_join(tampered, "", &(Jason.encode!(&1) <> "\n")))

      assert {:error, {:ledger_invalid, _}} =
               Ledger.reconcile_and_append(wos, ledger, receipt(admitted("SJ-A"), "z"))

      wo_path = Path.join(dir, "wos.json")
      write_json!(wo_path, wos)

      assert {1, %{"status" => "refused", "reason" => ["ledger_invalid" | _]}, _} =
               mix_task(["semantic_jira.frontier", "--work-orders", wo_path, "--ledger", ledger])
    end

    test "a torn ledger line is a typed refusal", %{ledger: ledger, wos: wos} do
      File.write!(ledger, ~s({"kind":"standing_transition","seq":1\n))
      assert {:error, {:ledger_invalid, {:unparseable_line, 1}}} = Ledger.read(ledger)

      assert {:error, {:ledger_invalid, {:unparseable_line, 1}}} =
               Ledger.reconcile_and_append(wos, ledger, receipt(admitted("SJ-A"), "z"))
    end

    test "append refuses an event that does not extend the tail", %{
      ledger: ledger,
      events: events
    } do
      stale = Map.put(hd(events), "prev_event_digest", digest("old"))
      assert {:error, {:ledger_conflict, tail}} = Ledger.append(ledger, stale)
      assert tail == Reconciler.tail_digest(events)
    end
  end

  # --- concurrency ------------------------------------------------------------

  describe "concurrency" do
    test "five concurrent workers from the same starting snapshot all land in one valid chain",
         %{ledger: ledger} do
      ids = for n <- 1..5, do: "SJ-W#{n}"
      wos = Enum.map(ids, &work_order/1)
      receipts = for id <- ids, do: receipt(admitted(id), id)

      results =
        receipts
        |> Enum.map(fn r ->
          Task.async(fn -> Ledger.reconcile_and_append(wos, ledger, r, 50) end)
        end)
        |> Task.await_many(60_000)

      assert Enum.all?(results, &match?({:ok, %{"kind" => "standing_transition"}}, &1)),
             inspect(results)

      {:ok, events} = Ledger.read(ledger)
      assert Enum.map(events, & &1["seq"]) == [1, 2, 3, 4, 5]
      assert events |> Enum.map(& &1["identity"]) |> Enum.sort() == ids

      assert {:ok, projected, _} = Reconciler.project(wos, events)
      assert Enum.all?(projected, &(&1["standing"] == "ALIVE"))
      refute File.exists?(ledger <> ".lock")
    end

    test "three concurrent OS processes serialize through the same ledger", %{
      dir: dir,
      ledger: ledger
    } do
      ids = for n <- 1..3, do: "SJ-P#{n}"
      wos = Enum.map(ids, &work_order/1)
      wo_path = Path.join(dir, "wos.json")
      write_json!(wo_path, wos)

      runs =
        ids
        |> Enum.map(fn id ->
          receipt_path = Path.join(dir, "#{id}.receipt.json")
          write_json!(receipt_path, receipt(admitted(id), id))

          Task.async(fn ->
            mix_task([
              "semantic_jira.reconcile",
              "--work-orders",
              wo_path,
              "--ledger",
              ledger,
              "--receipt",
              receipt_path
            ])
          end)
        end)
        |> Task.await_many(240_000)

      assert Enum.all?(runs, &match?({0, %{"status" => "applied"}, _}, &1)), inspect(runs)
      {:ok, events} = Ledger.read(ledger)
      assert Enum.map(events, & &1["seq"]) == [1, 2, 3]
      assert {:ok, _, _} = Reconciler.project(wos, events)
    end
  end

  # --- replay ----------------------------------------------------------------

  describe "replay" do
    test "a fresh OS process rebuilds the identical projection from the ledger file alone", %{
      dir: dir,
      ledger: ledger
    } do
      wos = [
        work_order("SJ-UP"),
        work_order("SJ-DOWN", %{
          "dependencies" => [
            %{"upstream" => "SJ-UP", "type" => "requiresReceipt", "required_standing" => "ALIVE"}
          ]
        }),
        work_order("SJ-SIDE")
      ]

      reconcile!(wos, ledger, receipt(admitted("SJ-UP"), "up"))
      reconcile!(wos, ledger, receipt(admitted("SJ-SIDE"), "side", %{"target" => "BLOCKED"}))

      {:ok, events} = Ledger.read(ledger)
      {:ok, projected, _} = Reconciler.project(wos, events)
      {:ok, live} = Reconciler.frontier(wos, events)

      wo_path = Path.join(dir, "wos.json")
      write_json!(wo_path, wos)

      assert {0, replayed, _} =
               mix_task(["semantic_jira.frontier", "--work-orders", wo_path, "--ledger", ledger])

      assert replayed["status"] == "ok"
      assert replayed["events"] == 2
      assert replayed["ledger_tail"] == Reconciler.tail_digest(events)
      assert replayed["standings"] == Map.new(projected, &{&1["identity"], &1["standing"]})

      assert replayed["standings"] == %{
               "SJ-UP" => "ALIVE",
               "SJ-DOWN" => "UNKNOWN",
               "SJ-SIDE" => "BLOCKED"
             }

      assert replayed["eligible"] == Jason.decode!(Jason.encode!(live.eligible))
      assert Enum.map(replayed["eligible"], & &1["identity"]) == ["SJ-DOWN"]
    end
  end

  # --- CLI contract -----------------------------------------------------------

  describe "mix tasks" do
    test "reconcile applies, replays as already_applied, refuses, and rejects bad invocations", %{
      dir: dir,
      ledger: ledger
    } do
      wos = [work_order("SJ-A")]
      wo = admitted("SJ-A")
      wo_path = Path.join(dir, "wos.json")
      write_json!(wo_path, %{"work_orders" => wos})
      good = Path.join(dir, "good.json")
      write_json!(good, receipt(wo, "a"))
      bad = Path.join(dir, "bad.json")
      write_json!(bad, receipt(wo, "b", %{"court_results" => %{}}))

      base = ["--work-orders", wo_path, "--ledger", ledger]

      assert {0, %{"status" => "applied", "event" => %{"seq" => 1}}, _} =
               mix_task(["semantic_jira.reconcile" | base] ++ ["--receipt", good])

      assert {0, %{"status" => "already_applied", "event" => %{"seq" => 1}}, _} =
               mix_task(["semantic_jira.reconcile" | base] ++ ["--receipt", good])

      assert {1, %{"status" => "refused", "reason" => ["reconcile_refused", _]}, _} =
               mix_task(["semantic_jira.reconcile" | base] ++ ["--receipt", bad])

      assert {2, %{"status" => "invalid_invocation"}, _} =
               mix_task(["semantic_jira.reconcile", "--work-orders", wo_path, "--ledger", ledger])

      assert {:ok, [_one]} = Ledger.read(ledger)
    end
  end
end
