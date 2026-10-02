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

  The local-backend cases add the same fixtures the in-process twin
  (`ggen_igniter_semantic_jira_execute_test.exs`) builds — a real temporary
  git repository, a real minimal pack on disk, and a real work-orders file —
  so `sj:targetPack` enforcement is witnessed through the real CLI process
  boundary too.
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

  describe "mix semantic_jira.execute local backend (sj:targetPack at the OS boundary)" do
    @origin_authority "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
    @local_identity "EXEC-OS-1"
    @local_suite "ci"

    defp git!(repo, args) do
      {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
      String.trim(out)
    end

    defp git_repo!(dir) do
      File.mkdir_p!(dir)
      git!(dir, ["init", "-q"])
      git!(dir, ["config", "user.email", "execute-os-test@example.invalid"])
      git!(dir, ["config", "user.name", "Execute OS Test"])
      git!(dir, ["config", "commit.gpgsign", "false"])
      File.write!(Path.join(dir, "README"), "execute os test base\n")
      git!(dir, ["add", "README"])
      git!(dir, ["commit", "-q", "-m", "base"])
      %{dir: dir, head: git!(dir, ["rev-parse", "HEAD"])}
    end

    # Same minimal pack as the in-process twin: one gate (`gates/010_ci.rq`,
    # stem "ci" -- the work order's required court), one EEx template, one
    # ontology triple. No pack.toml, so the pack resolves by basename: "pack".
    defp pack!(pack_dir) do
      File.mkdir_p!(Path.join(pack_dir, "gates"))
      File.mkdir_p!(Path.join(pack_dir, "templates"))

      File.write!(
        Path.join(pack_dir, "ontology.ttl"),
        ~s(@prefix ex: <http://example.com/execute-pack#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:Report a rdfs:Class .
ex:exec-report a ex:Report ; ex:title "execute pack report" .
)
      )

      File.write!(
        Path.join([pack_dir, "gates", "010_ci.rq"]),
        ~s(PREFIX ex: <http://example.com/execute-pack#>
SELECT DISTINCT ?subject WHERE {
  ?s a ex:Report ; ex:title ?subject .
}
)
      )

      File.write!(
        Path.join([pack_dir, "templates", "report.md.eex"]),
        ~s(# ggen-manufactured report
<%= for row <- ci do %>gate row: <%= row["subject"] %>
<% end %>)
      )

      pack_dir
    end

    # Mirrors the in-process twin's `work_orders_file!/3` (which already
    # carries the `target_pack` parameter) — `defp` helpers cannot cross
    # files, so the OS-level suite holds its own copy here.
    defp work_orders_file!(dir, head, target_pack) do
      path = Path.join(dir, "work_orders.json")

      order = %{
        "identity" => @local_identity,
        "title" => "Execute one order through the local loop (OS boundary)",
        "description" => "Known-class pack manufacture at the target HEAD.",
        "subject" => "execute-test:subject",
        "repository" => "o/r",
        "base_sha" => head,
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "all_courts",
        "replay_identity" => "execute:v1:#{@local_identity}",
        "required_courts" => [@local_suite],
        "required_evidence" => ["verification"],
        "acceptance" => ["urn:semantic-jira:acceptance:#{@local_identity}:a1"],
        "falsifiers" => ["urn:semantic-jira:falsifier:#{@local_identity}:f1"],
        "projections" => ["jira"],
        "origin_authority" => @origin_authority,
        "dependencies" => []
      }

      order = Map.put(order, "target_pack", target_pack)

      File.write!(path, Jason.encode!(%{"work_orders" => [order]}))

      path
    end

    defp local_execute_args(ledger, work_orders, extra) do
      [
        "semantic_jira.execute",
        "--work-orders",
        work_orders,
        "--ledger",
        ledger,
        "--identity",
        @local_identity,
        "--verifier-suite",
        @local_suite,
        "--alias",
        "o/r=target"
      ] ++ extra
    end

    # The raw last-JSON stderr line (not just its decoded map), so the
    # refused.json byte contract can be asserted against real stderr bytes.
    defp last_json_line_raw(text) do
      text
      |> String.split("\n", trim: true)
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        case Jason.decode(line) do
          {:ok, %{} = map} -> {line, map}
          _ -> nil
        end
      end)
    end

    test "an order naming a different pack refuses target_pack_mismatch on stderr and writes nothing",
         %{dir: dir, ledger: ledger} do
      target = git_repo!(Path.join(dir, "target"))
      pack = pack!(Path.join(dir, "pack"))
      work_orders = work_orders_file!(dir, target.head, "some-other-pack")
      out_dir = Path.join(dir, "refusals")
      receipt_out = Path.join(dir, "receipt-export.json")

      {code, out, err} =
        mix(
          dir,
          local_execute_args(ledger, work_orders, [
            "--pack-dir",
            pack,
            "--target-dir",
            target.dir,
            "--receipt-out",
            receipt_out,
            "--out-dir",
            out_dir
          ])
        )

      assert code == 1, "#{out}\n#{err}"

      # The refusal is the LAST line of stderr — in fact the whole stderr
      # stream is exactly that one line.
      {raw_line, refusal} = last_json_line_raw(err)
      assert err == raw_line <> "\n"

      assert %{
               "standing" => "REFUSED(target_pack_mismatch)",
               "reason" => "target_pack_mismatch",
               "broken_term" => "mu_unlawful",
               "hop" => "execute",
               "detail" => %{"expected" => "some-other-pack", "resolved" => "pack"}
             } = refusal

      # refused.json byte-equals that refusal: pretty-printed, one trailing
      # newline, decoding to the SAME map the stderr line carries.
      refused_path = Path.join(out_dir, "refused.json")

      assert File.read!(refused_path) == Jason.encode!(refusal, pretty: true) <> "\n"
      assert Jason.decode!(File.read!(refused_path)) == refusal

      # NOTHING executed: the target work tree holds only what git_repo!
      # made, no receipt was synthesized, the ledger was never created.
      assert File.ls!(target.dir) |> Enum.sort() == [".git", "README"]
      refute File.exists?(Path.join(target.dir, "ggen-manufactured"))
      refute File.exists?(receipt_out)
      refute File.exists?(ledger)
    end

    test "an order naming the pack --pack-dir resolves to executes to PARTIAL_ALIVE",
         %{dir: dir, ledger: ledger} do
      target = git_repo!(Path.join(dir, "target"))
      pack = pack!(Path.join(dir, "pack"))
      work_orders = work_orders_file!(dir, target.head, "pack")
      receipt_out = Path.join(dir, "receipt-export.json")

      {code, out, err} =
        mix(
          dir,
          local_execute_args(ledger, work_orders, [
            "--pack-dir",
            pack,
            "--target-dir",
            target.dir,
            "--receipt-out",
            receipt_out
          ])
        )

      assert code == 0, "#{out}\n#{err}"

      # One JSON object on stdout; the pack's report landed in the target
      # tree; the sealed export is on disk; the transition is in the ledger.
      assert %{"status" => "executed", "target" => "PARTIAL_ALIVE"} = Jason.decode!(String.trim(out))

      report = Path.join(target.dir, "ggen-manufactured/report.md")
      assert File.exists?(report)
      assert File.read!(report) =~ "gate row: execute pack report"
      assert File.exists?(receipt_out)
      assert [%{"identity" => @local_identity, "to" => "PARTIAL_ALIVE", "seq" => 1}] =
               TransitionLog.read(ledger)
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
