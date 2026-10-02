defmodule MixSemanticJiraExecuteTaskTest do
  @moduledoc """
  Chicago-style OS-level witness for `mix semantic_jira.execute`: real
  `System.cmd("mix", ["semantic_jira.execute", ...])` subprocesses (stderr
  captured through a real shell redirect, never swallowed) over the real
  work-order graph fixture `test/fixtures/semantic_jira/friday_work_orders.json`
  and a real ndjson standing-ledger file in a unique tmp dir.

  Exit contract under test: `0` prints exactly one JSON object on stdout;
  `1` prints the typed refusal JSON as the last line of STDERR (and writes
  `refused.json` under `--out-dir`); `2` is invalid invocation for missing or
  ambiguous execution input.

  The sealed XaaS export for the external backend is written as data per the
  documented contract of `Descriptor.receipt_from_xaas/2` (the fabric lives in
  the xaas repository); every step that consumes it is the real code.
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira.{Cli, Descriptor, TransitionLog}

  @fixture Path.expand("fixtures/semantic_jira/friday_work_orders.json", __DIR__)
  @alias "seanchatmangpt/ggen_igniter=ggen_igniter"
  @suite "ggen-igniter-format"
  @identity "FRI-FMT-A"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_execute_os_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    ledger = Path.join(dir, "standing-ledger.ndjson")

    %{
      dir: dir,
      ledger: ledger
    }
  end

  # One real mix subprocess with stderr redirected to a real file, so the
  # exit-1 contract ("refusal JSON last line of stderr") is witnessed on the
  # actual stderr stream.
  defp mix(dir, args) do
    err_log = Path.join(dir, "stderr-#{System.unique_integer([:positive])}.log")

    quoted =
      Enum.map_join(args, " ", fn arg ->
        "'" <> String.replace(arg, "'", "'\\''") <> "'"
      end)

    {out, code} = System.cmd("sh", ["-c", "mix #{quoted} 2> '#{err_log}'"], cd: File.cwd!())
    {code, out, File.read!(err_log)}
  end

  defp last_json_line(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, %{} = map} -> map
        _ -> nil
      end
    end)
  end

  defp descriptor!(dir, ledger) do
    descriptor_path = Path.join(dir, "descriptor-a.json")

    {code, out, _err} =
      mix(dir, [
        "semantic_jira.descriptor",
        "--work-orders",
        @fixture,
        "--ledger",
        ledger,
        "--identity",
        @identity,
        "--alias",
        @alias,
        "--verifier-suite",
        @suite,
        "--provider",
        "recipe",
        "--out",
        descriptor_path
      ])

    assert code == 0, out
    descriptor_path |> File.read!() |> Jason.decode!()
  end

  defp execute_args(ledger, extra) do
    [
      "semantic_jira.execute",
      "--work-orders",
      @fixture,
      "--ledger",
      ledger,
      "--identity",
      @identity,
      "--verifier-suite",
      @suite,
      "--alias",
      @alias
    ] ++ extra
  end

  describe "mix semantic_jira.execute (exit 0: one JSON on stdout, event in the ledger)" do
    test "the external backend executes one order to PARTIAL_ALIVE", %{dir: dir, ledger: ledger} do
      descriptor = descriptor!(dir, ledger)
      export_path = export_file!(dir, descriptor)
      out_path = Path.join(dir, "result.json")

      {code, out, err} =
        mix(dir, execute_args(ledger, ["--receipt", export_path, "--out", out_path]))

      assert code == 0, "#{out}\n#{err}"

      # One JSON object: the task's whole stdout IS the result document.
      assert %{"status" => "executed"} = Jason.decode!(String.trim(out))
      assert File.read!(out_path) |> Jason.decode!() |> Map.fetch!("status") == "executed"

      assert [%{"identity" => @identity, "to" => "PARTIAL_ALIVE", "seq" => 1}] =
               TransitionLog.read(ledger)
    end
  end

  # The sealed export for FRI-FMT-A from a real OS-level descriptor, written
  # where --receipt reads it: valid at the invocation boundary, so a test that
  # wants a LATER refusal actually reaches it.
  defp export_file!(dir, descriptor) do
    bridge = descriptor["bridge"]

    export = %{
      "epoch_id" => "epoch-os-execute",
      "run_id" => "run-os-execute",
      "receipt_id" => "receipt-os-execute",
      "bridge" => bridge,
      "final_head" => "0123456789abcdef0123456789abcdef01234567",
      "outcome" => "partial_alive",
      "head_verified" => false,
      "fabric_verifier" => %{
        "status" => "pass",
        "steps" => [%{"id" => @suite, "status" => "pass"}],
        "court_receipt" => %{
          "acceptance_results" => Map.new(bridge["requires"]["acceptance"], &{&1, true}),
          "falsifier_results" => Map.new(bridge["requires"]["falsifiers"], &{&1, "survived"})
        }
      }
    }

    export = Map.put(export, "receipt_digest", Descriptor.receipt_digest(export))
    path = Path.join(dir, "xaas-export.json")
    File.write!(path, Jason.encode!(export))
    path
  end

  describe "mix semantic_jira.execute (exit 1: typed refusal on stderr, refused.json on disk)" do
    test "a tampered ledger refuses at the frontier hop", %{dir: dir, ledger: ledger} do
      descriptor = descriptor!(dir, ledger)
      export_path = export_file!(dir, descriptor)

      TransitionLog.append(ledger, %{
        "kind" => "standing_transition_event",
        "identity" => @identity,
        "from" => "UNKNOWN",
        "to" => "PARTIAL_ALIVE",
        "authority" => "NONE"
      })

      forged = ledger |> File.read!() |> String.replace("\"to\":\"PARTIAL_ALIVE\"", "\"to\":\"ALIVE\"")
      File.write!(ledger, forged)

      out_dir = Path.join(dir, "refusals")

      {code, out, err} =
        mix(dir, execute_args(ledger, ["--receipt", export_path, "--out-dir", out_dir]))

      assert code == 1, "#{out}\n#{err}"

      refusal = last_json_line(err)
      assert %{"standing" => "REFUSED", "hop" => "frontier"} = refusal
      assert refusal["broken_term"] == "R_missing_replay"

      assert File.read!(Path.join(out_dir, "refused.json")) |> Jason.decode!() == refusal
      assert File.read!(ledger) == forged
    end
  end

  describe "mix semantic_jira.execute (exit 2: missing or ambiguous execution input)" do
    test "a lone --pack-dir without --target-dir is invalid invocation", %{dir: dir, ledger: ledger} do
      {code, out, err} = mix(dir, execute_args(ledger, ["--pack-dir", Path.join(dir, "pack")]))

      assert code == 2, "#{out}\n#{err}"
      assert %{"status" => "invalid_invocation"} = last_json_line(err)
      refute File.exists?(ledger)
    end

    test "no execution input at all is invalid invocation", %{dir: dir, ledger: ledger} do
      {code, out, err} = mix(dir, execute_args(ledger, []))

      assert code == 2, "#{out}\n#{err}"
      assert %{"status" => "invalid_invocation"} = last_json_line(err)
    end
  end

  # The in-process twin of the exit-1 contract: the same ledger refusal,
  # surfaced through the real Cli.emit/2 boundary the task uses.
  test "Cli.emit carries the refusal to stderr and exits 1", %{dir: dir} do
    import ExUnit.CaptureIO

    refusal = %{
      "standing" => "REFUSED",
      "reason" => ["ledger_refused", ["event_digest_mismatch", 1]],
      "broken_term" => "R_missing_replay",
      "hop" => "frontier",
      "detail" => "the standing ledger refused"
    }

    stderr =
      capture_io(:stderr, fn ->
        try do
          Cli.emit({1, refusal}, [])
        catch
          :exit, {:shutdown, 1} -> :ok
        end
      end)

    assert last_json_line(stderr) == refusal
    refute File.exists?(Path.join(dir, "nothing"))
  end
end
