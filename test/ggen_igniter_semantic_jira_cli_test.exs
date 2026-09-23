defmodule GgenIgniter.SemanticJiraCliTest do
  @moduledoc """
  Chicago-style: the real `GgenIgniter.SemanticJira.Cli` over the real
  work-order graph fixture `test/fixtures/semantic_jira/friday_work_orders.json`,
  a real on-disk standing ledger in a unique tmp dir (both the directory form
  and the ndjson-file form `Xaas.Ultracode.SemanticCrown` passes), and real
  `System.cmd("mix", ...)` subprocesses for the OS-level
  `mix semantic_jira.frontier` / `mix semantic_jira.descriptor` surface.
  No doubles: every assertion is on the returned/printed JSON or on disk.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Cli, TransitionLog}

  @fixture Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)
  @genesis "sha256:" <> String.duplicate("0", 64)
  @digest ~r/\Asha256:[0-9a-f]{64}\z/
  @alias "seanchatmangpt/ggen_igniter=ggen_igniter"
  @suite "ggen-igniter-format"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_cli_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp raw(identity) do
    @fixture
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("work_orders")
    |> Enum.find(&(&1["identity"] == identity))
  end

  defp ids(rows), do: Enum.map(rows, & &1["identity"])

  defp descriptor_opts(ledger, identity, extra) do
    [
      work_orders: @fixture,
      ledger: ledger,
      identity: identity,
      verifier_suite: @suite,
      alias: @alias
    ] ++ extra
  end

  # The mix subprocess may print Mix/compiler notices before the task's own
  # output; the task's result is the one line that decodes as a JSON object.
  defp mix_json(args) do
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

  describe "frontier/1 (TransitionLog.read/1 returns a list)" do
    test "an empty directory ledger yields the eligible order, not a WithClauseError",
         %{dir: dir} do
      ledger = Path.join(dir, "ledger")

      assert {0, result} = Cli.frontier(work_orders: @fixture, ledger: ledger)
      assert ids(result["eligible"]) == ["FRI-FMT-A"]

      assert [%{"identity" => "FRI-FMT-B", "reason" => "dependencies_unsatisfied"}] =
               result["blocked"]

      assert result["standings"] == %{"FRI-FMT-A" => "UNKNOWN", "FRI-FMT-B" => "UNKNOWN"}
      assert result["events"] == 0
      assert result["ledger_tail"] == @genesis
    end

    test "an ndjson ledger file path (the SemanticCrown shape) is read, never created",
         %{dir: dir} do
      ledger = Path.join(dir, "standing-ledger.ndjson")

      assert {0, result} = Cli.frontier(work_orders: @fixture, ledger: ledger)
      assert ids(result["eligible"]) == ["FRI-FMT-A"]
      refute File.exists?(ledger)
    end

    test "a tampered ledger event is a typed refusal, never silently projected",
         %{dir: dir} do
      ledger = Path.join(dir, "standing-ledger.ndjson")

      event = %{
        "kind" => "standing_transition_event",
        "identity" => "FRI-FMT-A",
        "from" => "UNKNOWN",
        "to" => "PARTIAL_ALIVE",
        "authority" => "NONE"
      }

      assert {:ok, _, :appended} = TransitionLog.append(ledger, event)

      assert {0, %{"standings" => %{"FRI-FMT-A" => "PARTIAL_ALIVE"}}} =
               Cli.frontier(work_orders: @fixture, ledger: ledger)

      File.write!(ledger, String.replace(File.read!(ledger), "PARTIAL_ALIVE", "ALIVE"))

      assert {1, %{"status" => "refused", "reason" => ["ledger_refused" | _]}} =
               Cli.frontier(work_orders: @fixture, ledger: ledger)
    end
  end

  describe "descriptor/1 (build_xaas_contract/4 through the CLI)" do
    test "--provider recipe binds the provider and admitted, non-nil digests", %{dir: dir} do
      ledger = Path.join(dir, "ledger")

      assert {0, descriptor} =
               Cli.descriptor(descriptor_opts(ledger, "FRI-FMT-A", provider: "recipe"))

      assert descriptor["provider"] == "recipe"

      {:ok, admitted} = SemanticJira.admit_work_order(raw("FRI-FMT-A"))
      {:ok, definition} = SemanticJira.definition_digest(raw("FRI-FMT-A"))
      bridge = descriptor["bridge"]

      assert bridge["definition_digest"] =~ @digest
      assert bridge["definition_digest"] == definition
      assert bridge["source_snapshot_digest"] =~ @digest
      assert bridge["source_snapshot_digest"] == admitted["work_order_digest"]
      assert bridge["ledger_tail"] == @genesis
      assert descriptor["graph_digest"] =~ @digest
      assert descriptor["dependencies"] == []
      assert descriptor["execution_repo_alias"] == "ggen_igniter"
      assert descriptor["verifier_suite"] == @suite
    end

    test "the provider defaults to zcode when --provider is absent", %{dir: dir} do
      assert {0, %{"provider" => "zcode"}} =
               Cli.descriptor(descriptor_opts(Path.join(dir, "ledger"), "FRI-FMT-A", []))
    end

    test "a malformed provider is a typed refusal", %{dir: dir} do
      assert {1, %{"status" => "refused", "reason" => reason}} =
               Cli.descriptor(
                 descriptor_opts(Path.join(dir, "ledger"), "FRI-FMT-A",
                   provider: "Recipe Worker!"
                 )
               )

      assert reason == ["descriptor_refused", ["invalid_option", "provider"]]
    end

    test "a dependent whose upstream is not ALIVE is refused, not described", %{dir: dir} do
      assert {1, %{"reason" => reason}} =
               Cli.descriptor(descriptor_opts(Path.join(dir, "ledger"), "FRI-FMT-B", []))

      assert reason == [
               "descriptor_refused",
               ["not_eligible", "FRI-FMT-B", "dependencies_unsatisfied"]
             ]
    end
  end

  describe "mix semantic_jira.frontier / semantic_jira.descriptor (real subprocess)" do
    test "frontier prints the eligible order from an empty ndjson ledger", %{dir: dir} do
      ledger = Path.join(dir, "standing-ledger.ndjson")

      {code, json, out} =
        mix_json(["semantic_jira.frontier", "--work-orders", @fixture, "--ledger", ledger])

      assert code == 0, out
      assert ids(json["eligible"]) == ["FRI-FMT-A"]
      assert json["events"] == 0
    end

    test "descriptor --provider recipe emits a contract with non-nil digests", %{dir: dir} do
      ledger = Path.join(dir, "standing-ledger.ndjson")
      out_path = Path.join(dir, "descriptor.json")

      {code, _json, out} =
        mix_json([
          "semantic_jira.descriptor",
          "--work-orders",
          @fixture,
          "--ledger",
          ledger,
          "--identity",
          "FRI-FMT-A",
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
      descriptor = out_path |> File.read!() |> Jason.decode!()

      assert descriptor["provider"] == "recipe"
      assert descriptor["bridge"]["definition_digest"] =~ @digest
      assert descriptor["bridge"]["source_snapshot_digest"] =~ @digest
      assert descriptor["work_order_iri"] == "urn:semantic-jira:work-order:FRI-FMT-A"
    end
  end
end
