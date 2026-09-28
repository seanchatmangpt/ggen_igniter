defmodule GgenIgniter.SemanticJiraReconcileCliTest do
  @moduledoc """
  Chicago, no-mocks: the reconcile -> frontier -> prov chain through the real
  `Cli` functions and real `mix semantic_jira.*` subprocesses over one real
  ndjson ledger and the real friday work-order fixture.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{Cli, TransitionLog}

  @fixture Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_rcli_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

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

  test "prov/1 on an empty ledger is a conforming, event-free export", %{dir: dir} do
    assert {0, %{"status" => "ok", "events" => 0, "conforms" => true, "turtle" => ttl}} =
             Cli.prov(ledger: Path.join(dir, "l.ndjson"))

    refute ttl =~ "prov:Activity, sj:StandingTransitionEvent"
    refute File.exists?(Path.join(dir, "l.ndjson"))
  end

  test "prov/1 requires --ledger (invalid invocation, exit 2)" do
    assert {2, %{"status" => "invalid_invocation"}} = Cli.prov([])
  end

  test "prov/1 refuses a tampered ledger and writes nothing", %{dir: dir} do
    ledger = Path.join(dir, "l.ndjson")

    {:ok, _, :appended} =
      TransitionLog.append(ledger, %{
        "identity" => "X",
        "from" => "UNKNOWN",
        "to" => "ALIVE",
        "receipt_digest" => "sha256:" <> String.duplicate("4", 64),
        "authority" => "NONE"
      })

    File.write!(ledger, String.replace(File.read!(ledger), "ALIVE", "STALE"))
    out = Path.join(dir, "out.ttl")
    assert {1, %{"status" => "refused"}} = Cli.prov(ledger: ledger, out: out)
    refute File.exists?(out)
  end

  test "a real ledger exports through the mix task: --out holds Turtle, stdout the status",
       %{dir: dir} do
    ledger = Path.join(dir, "l.ndjson")

    {:ok, _, :appended} =
      TransitionLog.append(ledger, %{
        "identity" => "FRI-FMT-A",
        "from" => "UNKNOWN",
        "to" => "ALIVE",
        "receipt_digest" => "sha256:" <> String.duplicate("5", 64),
        "authority" => "NONE"
      })

    out = Path.join(dir, "events.ttl")
    {code, json, output} = mix_json(["semantic_jira.prov", "--ledger", ledger, "--out", out])
    assert code == 0, output
    assert %{"status" => "ok", "events" => 1, "out" => ^out} = json
    graph = GgenIgniter.Ontology.load!(out)
    assert RDF.Graph.triple_count(graph) > 5
    assert GgenIgniter.SemanticJira.ProvEvents.validate(graph).conforms

    # the ledger is unchanged, and the frontier CLI still reads it
    assert {0, %{"events" => 1}} = Cli.frontier(work_orders: @fixture, ledger: ledger)
  end
end
