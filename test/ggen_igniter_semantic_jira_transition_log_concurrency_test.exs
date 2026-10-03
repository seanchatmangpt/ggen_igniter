defmodule GgenIgniter.SemanticJiraTransitionLogConcurrencyTest do
  @moduledoc """
  Chicago, no-mocks stress of `TransitionLog.append/2` under real parallel
  writers: BEAM tasks (real scheduler-parallel processes) and real OS
  processes (`mix run` subprocesses) appending to ONE real ledger on disk, for
  both the ndjson-file and the directory form. Assertions are on final disk
  state: no lost, torn or duplicated event, `seq` is exactly 1..N, every
  `event_digest` recomputes (`fetch/1` accepts the ledger). The
  `event_digest/1` + `legacy_event_digest/1` describe below pins the public
  digest pair against the cross-repo vector xaas's
  `semantic_jira_bridge_integrity_test.exs:289-307` relies on. Since the D1
  shrink (2026-10-02) the legacy rule is a deprecated, shrinking window
  (removal milestone v26.11.1): xaas's bridge probes the export's availability
  at run time instead of calling it unconditionally.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.TransitionLog

  @writers 8
  @per_writer 12

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_tlc_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp event(writer, n) do
    %{
      "kind" => "standing_transition_event",
      "identity" => "WO-#{writer}-#{n}",
      "from" => "UNKNOWN",
      "to" => "ALIVE",
      "payload" => String.duplicate("x", 2_000 + n),
      "authority" => "NONE"
    }
  end

  defp assert_intact(ledger, expected_identities) do
    assert {:ok, events} = TransitionLog.fetch(ledger)
    assert Enum.sort(Enum.map(events, & &1["identity"])) == Enum.sort(expected_identities)
    assert Enum.map(events, & &1["seq"]) == Enum.to_list(1..length(expected_identities)//1)
    digests = Enum.map(events, & &1["event_digest"])
    assert length(Enum.uniq(digests)) == length(digests)
  end

  defp identities(writers, per),
    do: for(w <- 1..writers, n <- 1..per, do: "WO-#{w}-#{n}")

  for {label, name} <- [file: "ledger.ndjson", dir: "ledger-dir"] do
    test "#{label} ledger: parallel tasks lose, tear and duplicate nothing", %{dir: dir} do
      ledger = Path.join(dir, unquote(name))

      results =
        1..@writers
        |> Enum.map(fn w ->
          Task.async(fn ->
            for n <- 1..@per_writer, do: TransitionLog.append(ledger, event(w, n))
          end)
        end)
        |> Task.await_many(60_000)
        |> List.flatten()

      assert Enum.all?(results, &match?({:ok, _, :appended}, &1)), inspect(results)
      assert_intact(ledger, identities(@writers, @per_writer))
    end

    test "#{label} ledger: racing writers of the SAME event record it exactly once",
         %{dir: dir} do
      ledger = Path.join(dir, unquote(name))

      results =
        1..@writers
        |> Enum.map(fn _ -> Task.async(fn -> TransitionLog.append(ledger, event(0, 0)) end) end)
        |> Task.await_many(60_000)

      assert Enum.count(results, &match?({:ok, _, :appended}, &1)) == 1
      assert Enum.count(results, &match?({:ok, _, :already_recorded}, &1)) == @writers - 1
      assert_intact(ledger, ["WO-0-0"])
    end
  end

  test "file ledger: real OS processes appending in parallel keep the ledger intact",
       %{dir: dir} do
    ledger = Path.join(dir, "os.ndjson")
    os_writers = 4
    per = 6

    script = """
    [w] = System.argv()
    ledger = #{inspect(ledger)}
    for n <- 1..#{per} do
      {:ok, _, :appended} =
        GgenIgniter.SemanticJira.TransitionLog.append(ledger, %{
          "kind" => "standing_transition_event",
          "identity" => "WO-\#{w}-\#{n}",
          "payload" => String.duplicate("y", 3_000),
          "authority" => "NONE"
        })
    end
    """

    script_path = Path.join(dir, "writer.exs")
    File.write!(script_path, script)

    results =
      1..os_writers
      |> Enum.map(fn w ->
        Task.async(fn ->
          System.cmd(
            "mix",
            ["run", "--no-compile", "--no-deps-check", script_path, Integer.to_string(w)],
            cd: File.cwd!(),
            stderr_to_stdout: true
          )
        end)
      end)
      |> Task.await_many(300_000)

    for {out, code} <- results, do: assert(code == 0, out)
    assert_intact(ledger, identities(os_writers, per))
    refute File.exists?(ledger <> ".lock")
  end

  # ── the public digest pair ─────────────────────────────────────────────────
  #
  # xaas's SemanticJiraBridge admits a stored ledger event when its
  # `event_digest` recomputes under EITHER rule
  # (test/xaas/ultracode/semantic_jira_bridge_integrity_test.exs:289-307), so
  # both rules must be public and behave exactly as pinned here.
  describe "event_digest/1 + legacy_event_digest/1 (public digest pair)" do
    # The xaas-pinned event shape: a standing transition carrying the derived
    # digests the bridge keys on.
    defp xaas_event do
      %{
        "kind" => "standing_transition_event",
        "identity" => "VERIFY-CLEAN",
        "from" => "UNKNOWN",
        "to" => "PARTIAL_ALIVE",
        "authority" => "NONE",
        "receipt_digest" => String.duplicate("a", 64),
        "definition_digest" => String.duplicate("b", 64),
        "snapshot_digest" => String.duplicate("c", 64),
        "transition_digest" => String.duplicate("d", 64)
      }
    end

    # 30 extra keys push the map past Elixir's 32-key small-map boundary, so
    # enumeration order is genuinely unordered and the digest's key sorting is
    # exercised rather than trivially satisfied.
    defp wide(event) do
      Map.merge(
        event,
        Map.new(0..29, &{"ext-#{Integer.to_string(&1) |> String.pad_leading(2, "0")}", &1})
      )
    end

    defp flip_first_char(digest) do
      rest = String.slice(digest, 1..-1//1)

      if String.starts_with?(digest, "0"), do: "1" <> rest, else: "0" <> rest
    end

    test "legacy_event_digest/1 diverges from event_digest/1 on derived digest fields" do
      event = xaas_event()

      legacy = TransitionLog.legacy_event_digest(event)
      current = TransitionLog.event_digest(event)

      refute legacy == current,
             "the two rules must diverge on derived-digest fields (exact vs elided)"

      # The divergence is exactly the elision: an event without any derived
      # digest field digests identically under both rules.
      bare = Map.drop(event, ~w(receipt_digest definition_digest transition_digest))
      assert TransitionLog.legacy_event_digest(bare) == TransitionLog.event_digest(bare)
    end

    test "legacy_event_digest/1 ignores seq and event_digest values (drop semantics)" do
      event = xaas_event()

      plain = TransitionLog.legacy_event_digest(event)

      one =
        Map.merge(event, %{
          "seq" => 1,
          "event_digest" => "sha256:" <> String.duplicate("0", 64)
        })

      ninety_nine =
        Map.merge(event, %{
          "seq" => 99,
          "event_digest" => "sha256:" <> String.duplicate("f", 64)
        })

      assert TransitionLog.legacy_event_digest(one) == plain
      assert TransitionLog.legacy_event_digest(ninety_nine) == plain

      # The current rule carries the same drop semantics.
      assert TransitionLog.event_digest(one) == TransitionLog.event_digest(ninety_nine)
    end

    test "both digests are independent of map insertion order" do
      event = wide(xaas_event())
      reversed = event |> Enum.reverse() |> Map.new()

      assert TransitionLog.event_digest(event) == TransitionLog.event_digest(reversed)

      assert TransitionLog.legacy_event_digest(event) ==
               TransitionLog.legacy_event_digest(reversed)
    end

    test "cross-repo vector: a legacy-stamped event recomputes only under the (deprecated, window-shrunk) legacy rule; a tampered event under neither",
         %{dir: dir} do
      ledger = Path.join(dir, "legacy.jsonl")

      # Rebuild xaas's pinned case exactly: strip seq/event_digest, stamp the
      # legacy rule, re-add seq=1, and write it to disk by hand (append/2
      # would restamp under the current rule).
      legacy =
        xaas_event()
        |> Map.drop(["seq", "event_digest"])
        |> then(&Map.put(&1, "event_digest", TransitionLog.legacy_event_digest(&1)))
        |> Map.put("seq", 1)

      File.write!(ledger, Jason.encode!(legacy) <> "\n")

      # Round-trip through the real file on disk — the bytes a consumer reads.
      [stored] =
        ledger |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

      assert stored["seq"] == 1
      refute stored["event_digest"] == TransitionLog.event_digest(stored)
      assert stored["event_digest"] == TransitionLog.legacy_event_digest(stored)

      # The acceptance rule xaas's bridge pins while the deprecated export
      # still ships (probed by derives?/1): recomputed over the FULL stored
      # event, the stamped digest must satisfy the either-rule membership.
      assert stored["event_digest"] in [
               TransitionLog.event_digest(stored),
               TransitionLog.legacy_event_digest(stored)
             ]

      # Tamper snapshot_digest (a derived field NOT in the elided set — both
      # rules see it): the stamped digest now recomputes under NEITHER rule —
      # this is what makes the bridge refuse log_untrusted.
      tampered = Map.update!(stored, "snapshot_digest", &flip_first_char/1)

      refute stored["event_digest"] in [
               TransitionLog.event_digest(tampered),
               TransitionLog.legacy_event_digest(tampered)
             ]

      # The elision law, pinned honestly: receipt_digest is elided by the
      # legacy rule, so a receipt-only swap is invisible at that layer. The
      # receipt is bound instead by the bridge's fabric-seal check
      # (export_not_sealed_by_fabric against the sealed Postgres row) — that
      # is the composite law, and this assertion documents its boundary.
      receipt_swapped = Map.update!(stored, "receipt_digest", &flip_first_char/1)
      assert receipt_swapped["event_digest"] == TransitionLog.legacy_event_digest(receipt_swapped)
      refute receipt_swapped["event_digest"] == TransitionLog.event_digest(receipt_swapped)
    end

    test "append/2 stamps a recomputing digest, overwriting any caller-supplied event_digest", %{
      dir: dir
    } do
      ledger = Path.join(dir, "stamp.ndjson")
      forged = "sha256:" <> String.duplicate("9", 64)

      event =
        xaas_event()
        |> Map.put("event_digest", forged)
        |> Map.put("seq", 7)

      assert {:ok, stamped, :appended} = TransitionLog.append(ledger, event)
      refute stamped["event_digest"] == forged
      assert stamped["event_digest"] == TransitionLog.event_digest(stamped)
      assert stamped["seq"] == 1

      assert {:ok, [stored]} = TransitionLog.fetch(ledger)
      assert stored["event_digest"] == stamped["event_digest"]
    end
  end

  # ── epoch: the ledger-generation counter (L3, loops-of-loops spec §1) ──────
  describe "append/3 epoch (ledger-generation counter)" do
    defp plain(w) do
      %{
        "kind" => "standing_transition_event",
        "identity" => "EP-#{w}",
        "from" => "UNKNOWN",
        "to" => "ALIVE",
        "authority" => "NONE"
      }
    end

    test "every write is stamped; the epoch stays within a receipt-window; seq orders within it",
         %{dir: dir} do
      for {name, marker} <- [{"e.ndjson", "e.ndjson.epoch"}, {"e-dir", "e-dir/epoch"}] do
        ledger = Path.join(dir, name)
        marker_path = Path.join(dir, marker)

        assert {:ok, e1, :appended} = TransitionLog.append(ledger, plain(1))
        assert {:ok, e2, :appended} = TransitionLog.append(ledger, plain(2))

        assert e1["epoch"] == 0 and e2["epoch"] == 0
        assert e1["seq"] == 1 and e2["seq"] == 2

        # A fresh ledger declares no generation above 0, so no marker file
        # exists yet in either form.
        assert {:ok, [^e1, ^e2]} = TransitionLog.fetch(ledger)
        refute File.exists?(marker_path)
      end
    end

    test "epoch_bump declares a new generation and persists it in the marker", %{dir: dir} do
      for {name, marker} <- [{"b.ndjson", "b.ndjson.epoch"}, {"b-dir", "b-dir/epoch"}] do
        ledger = Path.join(dir, name)
        marker_path = Path.join(dir, marker)

        assert {:ok, e0, :appended} = TransitionLog.append(ledger, plain(1))
        assert e0["epoch"] == 0

        assert {:ok, e1, :appended} = TransitionLog.append(ledger, plain(2), epoch_bump: 3)
        assert e1["epoch"] == 3
        assert File.read!(marker_path) == "3"

        # The generation stays for subsequent receipt-window events.
        assert {:ok, e2, :appended} = TransitionLog.append(ledger, plain(3))
        assert e2["epoch"] == 3

        assert {:ok, [_, stored1, stored2]} = TransitionLog.fetch(ledger)
        assert stored1["epoch"] == 3 and stored2["epoch"] == 3
      end
    end

    test "an explicit epoch below the ledger's last epoch is a typed refusal before any write",
         %{dir: dir} do
      ledger = Path.join(dir, "r.ndjson")

      assert {:ok, e0, :appended} = TransitionLog.append(ledger, plain(1), epoch_bump: 2)
      assert e0["epoch"] == 2
      before = File.read!(ledger)

      assert {:error, {:ledger_refused, :epoch_regression}} =
               TransitionLog.append(ledger, plain(2), epoch: 1)

      assert {:error, {:ledger_refused, :epoch_regression}} =
               TransitionLog.append(ledger, plain(2), epoch: 0)

      assert File.read!(ledger) == before

      # Equal to last is NOT a regression (same receipt-window); above last is
      # an explicit generation declaration that later plain appends inherit.
      assert {:ok, e1, :appended} = TransitionLog.append(ledger, plain(2), epoch: 2)
      assert e1["epoch"] == 2

      assert {:ok, e2, :appended} = TransitionLog.append(ledger, plain(3), epoch: 9)
      assert e2["epoch"] == 9

      assert {:ok, e3, :appended} = TransitionLog.append(ledger, plain(4))
      assert e3["epoch"] == 9
    end

    test "pre-L3 events (no epoch/vc) still append, verify, and continue at epoch 0", %{
      dir: dir
    } do
      ledger = Path.join(dir, "old.ndjson")

      old = %{
        "kind" => "standing_transition_event",
        "identity" => "EP-OLD",
        "from" => "UNKNOWN",
        "to" => "ALIVE",
        "authority" => "NONE"
      }

      # Written by hand: append/3 stamps the epoch, and the point is that an
      # event written BEFORE L3 — digest over exactly the fields it has —
      # still verifies.
      File.write!(
        ledger,
        Jason.encode!(Map.put(old, "event_digest", TransitionLog.event_digest(old))) <> "\n"
      )

      assert {:ok, [stored]} = TransitionLog.fetch(ledger)
      refute Map.has_key?(stored, "epoch")
      refute Map.has_key?(stored, "vc")

      # The next write continues the generation at 0 (pre-L3 events
      # contribute 0).
      assert {:ok, next, :appended} = TransitionLog.append(ledger, plain(1))
      assert next["epoch"] == 0
      assert {:ok, [^stored, ^next]} = TransitionLog.fetch(ledger)
    end

    test "the epoch is inside the digest: a tampered stamp refuses fetch", %{dir: dir} do
      ledger = Path.join(dir, "tamper.ndjson")

      assert {:ok, e, :appended} = TransitionLog.append(ledger, plain(1), epoch_bump: 4)
      assert e["epoch"] == 4

      # Flip the epoch in the raw bytes: the digest no longer recomputes.
      File.write!(ledger, String.replace(File.read!(ledger), "\"epoch\":4", "\"epoch\":5"))

      assert {:error, {:ledger_refused, {:event_digest_mismatch, 1}}} =
               TransitionLog.fetch(ledger)
    end

    test "forked-epoch court: two writers, one regresses -> refused, the ledger intact", %{
      dir: dir
    } do
      ledger = Path.join(dir, "fork-dir")

      parent = Task.async(fn -> TransitionLog.append(ledger, plain(1), epoch_bump: 5) end)
      assert {:ok, bumped, :appended} = Task.await(parent, 30_000)
      assert bumped["epoch"] == 5

      # The regressing replicas lose, typed, no matter how they arrive.
      regressions =
        1..4
        |> Enum.map(fn w ->
          Task.async(fn -> TransitionLog.append(ledger, plain(w), epoch: w) end)
        end)
        |> Task.await_many(30_000)

      assert Enum.all?(regressions, &match?({:error, {:ledger_refused, :epoch_regression}}, &1)),
             inspect(regressions)

      # A compliant writer (explicit epoch == last) appends alongside.
      assert {:ok, ok, :appended} = TransitionLog.append(ledger, plain(9), epoch: 5)
      assert ok["epoch"] == 5

      assert {:ok, events} = TransitionLog.fetch(ledger)
      assert Enum.map(events, & &1["epoch"]) == [5, 5]
      assert Enum.map(events, & &1["seq"]) == [1, 2]
    end
  end

  # ── vector clocks: the conflict law (L3, loops-of-loops spec §1) ───────────
  describe "append/3 vc + vc_dominates?/vc_concurrent? (the conflict law)" do
    defp clock(m), do: Map.new(m, fn {k, v} -> {Atom.to_string(k), v} end)

    setup %{dir: dir} do
      %{ledger: Path.join(dir, "vc.ndjson")}
    end

    test "vc is stamped only when the caller carries one, and lives inside the digest", %{
      ledger: ledger
    } do
      base = %{"kind" => "e", "identity" => "V", "from" => "UNKNOWN", "to" => "ALIVE"}

      assert {:ok, bare, :appended} = TransitionLog.append(ledger, base)
      refute Map.has_key?(bare, "vc")

      assert {:ok, stamped, :appended} = TransitionLog.append(ledger, base, vc: clock(r1: 3))
      assert stamped["vc"] == %{"r1" => 3}
      assert {:ok, [^bare, ^stamped]} = TransitionLog.fetch(ledger)

      # The vc field is part of the digested map: same content without it
      # digests differently.
      bare_digest =
        TransitionLog.event_digest(%{
          "kind" => "e",
          "identity" => "V",
          "from" => "UNKNOWN",
          "to" => "ALIVE",
          "epoch" => 0
        })

      vc_digest =
        TransitionLog.event_digest(%{
          "kind" => "e",
          "identity" => "V",
          "from" => "UNKNOWN",
          "to" => "ALIVE",
          "epoch" => 0,
          "vc" => %{"r1" => 3}
        })

      refute bare_digest == vc_digest
    end

    test "a malformed vc raises instead of stamping garbage", %{ledger: ledger} do
      assert_raise ArgumentError, ~r/opts\[:vc\]/, fn ->
        TransitionLog.append(ledger, %{"identity" => "V"}, vc: %{"r1" => -1})
      end
    end

    test "vc_dominates?/2 and vc_concurrent?/2 truth table (missing replica counts 0)" do
      assert TransitionLog.vc_dominates?(clock(r1: 2), clock(r1: 1))
      assert TransitionLog.vc_dominates?(clock(r1: 1, r2: 1), clock(r1: 1))
      assert TransitionLog.vc_dominates?(clock(r1: 1), %{})
      refute TransitionLog.vc_dominates?(%{}, %{})
      refute TransitionLog.vc_dominates?(clock(r1: 1), clock(r1: 1))
      refute TransitionLog.vc_dominates?(clock(r1: 1, r2: 0), clock(r1: 1))

      refute TransitionLog.vc_concurrent?(clock(r1: 2), clock(r1: 1))
      refute TransitionLog.vc_concurrent?(clock(r1: 1), clock(r1: 1))
      refute TransitionLog.vc_concurrent?(%{}, %{})
      assert TransitionLog.vc_concurrent?(clock(r1: 1), clock(r2: 1))
      assert TransitionLog.vc_concurrent?(clock(r1: 1, r2: 1), clock(r1: 1, r3: 1))
    end
  end
end
