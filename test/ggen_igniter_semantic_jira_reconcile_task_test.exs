defmodule GgenIgniter.SemanticJiraReconcileTaskTest do
  @moduledoc """
  Chicago-style G8 graph-side witness. Real `System.cmd("mix", ...)`
  subprocesses drive the same OS-level chain `Xaas.Ultracode.SemanticCrown`
  drives -- `semantic_jira.frontier` -> `semantic_jira.descriptor --provider
  recipe` -> `semantic_jira.xaas_receipt` -> `semantic_jira.reconcile` ->
  `semantic_jira.frontier` -- over the real work-order graph fixture
  `test/fixtures/semantic_jira/friday_work_orders.json` and a real ndjson
  standing-ledger file in a unique tmp dir. The `TransitionLog` ledger-kind
  tests use real directories and real files on disk.

  The one input not produced by ggen_igniter is the sealed XaaS receipt
  export: the XaaS fabric (guarded verifier run + `Lease.close`) lives in the
  separate xaas repository and runtime and cannot run in-process here, so the
  test writes its export as data per the documented contract of
  `GgenIgniter.SemanticJira.Descriptor.receipt_from_xaas/2` (bridge echo,
  fabric verifier steps, court receipt, `receipt_digest` recomputed by the
  real `Descriptor.receipt_digest/1`). It is external input data, not a double
  of any collaborator: every step that consumes it is the real code.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{Cli, Descriptor, TransitionLog}

  @fixture Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)
  @alias "seanchatmangpt/ggen_igniter=ggen_igniter"
  @suite "ggen-igniter-format"
  @final_head "0123456789abcdef0123456789abcdef01234567"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_reconcile_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp ids(rows), do: Enum.map(rows, & &1["identity"])

  defp mix(args) do
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

  defp frontier!(ledger) do
    {code, json, out} =
      mix(["semantic_jira.frontier", "--work-orders", @fixture, "--ledger", ledger])

    assert code == 0, out
    json
  end

  defp descriptor!(ledger, identity, out_path) do
    {code, _json, out} =
      mix([
        "semantic_jira.descriptor",
        "--work-orders",
        @fixture,
        "--ledger",
        ledger,
        "--identity",
        identity,
        "--alias",
        @alias,
        "--verifier-suite",
        @suite,
        "--provider",
        "recipe",
        "--out",
        out_path
      ])

    assert code == 0, out
    out_path |> File.read!() |> Jason.decode!()
  end

  # The sealed XaaS export for an `alive` outcome: the verifier suite step
  # that judged the required court passed at the exact final head, and the
  # fabric's court receipt carries the IRI-keyed acceptance/falsifier verdicts.
  defp sealed_xaas_receipt(bridge) do
    receipt = %{
      "epoch_id" => "epoch-fri-t6",
      "run_id" => "run-fri-t6",
      "receipt_id" => "receipt-fri-t6",
      "bridge" => bridge,
      "final_head" => @final_head,
      "outcome" => "alive",
      "head_verified" => true,
      "fabric_verifier" => %{
        "status" => "pass",
        "steps" => [%{"id" => @suite, "status" => "pass"}],
        "court_receipt" => %{
          "acceptance_results" => Map.new(bridge["requires"]["acceptance"], &{&1, true}),
          "falsifier_results" => Map.new(bridge["requires"]["falsifiers"], &{&1, "survived"})
        }
      }
    }

    Map.put(receipt, "receipt_digest", Descriptor.receipt_digest(receipt))
  end

  defp ledger_lines(ledger), do: ledger |> File.read!() |> String.split("\n", trim: true)

  defp event(to) do
    %{
      "kind" => "standing_transition_event",
      "identity" => "FRI-FMT-A",
      "from" => "UNKNOWN",
      "to" => to,
      "authority" => "NONE"
    }
  end

  describe "mix semantic_jira.reconcile (G8 closed frontier over an ndjson ledger)" do
    test "an ALIVE receipt moves the order out of the frontier and its dependent in",
         %{dir: dir} do
      ledger = Path.join(dir, "standing-ledger.ndjson")

      before = frontier!(ledger)
      assert ids(before["eligible"]) == ["FRI-FMT-A"]
      assert "FRI-FMT-B" in ids(before["blocked"])
      assert before["events"] == 0

      descriptor_path = Path.join(dir, "descriptor-a.json")
      descriptor = descriptor!(ledger, "FRI-FMT-A", descriptor_path)
      assert descriptor["provider"] == "recipe"

      xaas_path = Path.join(dir, "xaas-receipt.json")
      File.write!(xaas_path, Jason.encode!(sealed_xaas_receipt(descriptor["bridge"])))
      reconciler_path = Path.join(dir, "reconciler-receipt.json")

      {code, _json, out} =
        mix([
          "semantic_jira.xaas_receipt",
          "--bridge",
          descriptor_path,
          "--xaas-receipt",
          xaas_path,
          "--out",
          reconciler_path
        ])

      assert code == 0, out

      reconcile_args = [
        "semantic_jira.reconcile",
        "--work-orders",
        @fixture,
        "--ledger",
        ledger,
        "--receipt",
        reconciler_path
      ]

      {code, applied, out} = mix(reconcile_args)
      assert code == 0, out
      assert applied["status"] == "applied"
      assert applied["event"]["identity"] == "FRI-FMT-A"
      assert applied["event"]["from"] == "UNKNOWN"
      assert applied["event"]["to"] == "ALIVE"

      # The ledger XaaS passes is a FILE: it stays one, one event per line.
      assert File.regular?(ledger)
      assert length(ledger_lines(ledger)) == 1

      after_frontier = frontier!(ledger)
      assert ids(after_frontier["eligible"]) == ["FRI-FMT-B"]
      settled = %{"identity" => "FRI-FMT-A", "reason" => "standing=ALIVE"}
      assert settled in after_frontier["blocked"]
      assert after_frontier["standings"] == %{"FRI-FMT-A" => "ALIVE", "FRI-FMT-B" => "UNKNOWN"}
      assert after_frontier["events"] == 1
      assert after_frontier["ledger_tail"] == applied["event"]["event_digest"]

      # Replaying the same receipt is idempotent: no second line.
      {code, again, out} = mix(reconcile_args)
      assert code == 0, out
      assert again["status"] == "already_applied"
      assert length(ledger_lines(ledger)) == 1

      # The dependent is now describable and binds the upstream receipt.
      b = descriptor!(ledger, "FRI-FMT-B", Path.join(dir, "descriptor-b.json"))

      assert [
               %{
                 "work_order_iri" => "urn:semantic-jira:work-order:FRI-FMT-A",
                 "observed_standing" => "ALIVE",
                 "receipt_digest" => receipt_digest
               }
             ] = b["dependencies"]

      assert receipt_digest == applied["event"]["receipt_digest"]
      assert b["bridge"]["ledger_tail"] == applied["event"]["event_digest"]
    end
  end

  describe "reconcile/1 (refusals leave the ledger untouched)" do
    test "a receipt for a foreign definition refuses and appends nothing", %{dir: dir} do
      ledger = Path.join(dir, "standing-ledger.ndjson")
      receipt_path = Path.join(dir, "foreign.json")

      File.write!(
        receipt_path,
        Jason.encode!(%{
          "definition_digest" => "sha256:" <> String.duplicate("e", 64),
          "snapshot_digest" => "sha256:" <> String.duplicate("f", 64),
          "target" => "ALIVE",
          "evidence" => %{}
        })
      )

      assert {1, %{"status" => "refused", "reason" => ["refused", "no_matching_work_order"]}} =
               Cli.reconcile(work_orders: @fixture, ledger: ledger, receipt: receipt_path)

      refute File.exists?(ledger)
    end
  end

  describe "TransitionLog.append/2 (ledger kind: directory or file, explicitly)" do
    test "kind/1 resolves the ledger form by what exists, then by extension", %{dir: dir} do
      existing_file = Path.join(dir, "ledger")
      File.write!(existing_file, "")
      existing_dir = Path.join(dir, "events.ndjson")
      File.mkdir_p!(existing_dir)

      assert TransitionLog.kind(existing_file) == :file
      assert TransitionLog.kind(existing_dir) == :dir
      assert TransitionLog.kind(Path.join(dir, "missing.ndjson")) == :file
      assert TransitionLog.kind(Path.join(dir, "missing.jsonl")) == :file
      assert TransitionLog.kind(Path.join(dir, "missing")) == :dir
    end

    test "an existing ledger FILE is appended to, never mkdir_p'd", %{dir: dir} do
      ledger = Path.join(dir, "standing-ledger.ndjson")
      File.write!(ledger, "")

      assert {:ok, first, :appended} = TransitionLog.append(ledger, event("PARTIAL_ALIVE"))
      assert first["seq"] == 1

      assert {:ok, ^first, :already_recorded} =
               TransitionLog.append(ledger, event("PARTIAL_ALIVE"))

      assert {:ok, second, :appended} = TransitionLog.append(ledger, event("ALIVE"))
      assert second["seq"] == 2

      assert File.regular?(ledger)
      assert length(ledger_lines(ledger)) == 2
      assert TransitionLog.read(ledger) == [first, second]
      assert {:ok, [^first, ^second]} = TransitionLog.fetch(ledger)
    end

    test "a missing .ndjson ledger is created as a file, not a directory", %{dir: dir} do
      ledger = Path.join([dir, "work", "standing-ledger.ndjson"])

      assert {:ok, _, :appended} = TransitionLog.append(ledger, event("ALIVE"))
      assert File.regular?(ledger)
      refute File.dir?(ledger)
    end

    test "a directory ledger keeps one immutable JSON file per event", %{dir: dir} do
      ledger = Path.join(dir, "ledger")

      assert {:ok, first, :appended} = TransitionLog.append(ledger, event("PARTIAL_ALIVE"))
      assert {:ok, second, :appended} = TransitionLog.append(ledger, event("ALIVE"))

      assert File.dir?(ledger)
      assert ledger |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json")) |> length() == 2
      assert TransitionLog.read(ledger) == [first, second]
    end
  end
end
