defmodule GgenIgniter.SemanticJiraReceiptEmitterFalsifierTest do
  @moduledoc """
  Qualifier falsifiers for `GgenIgniter.SemanticJira.ReceiptEmitter` and the
  `Reconciler` options added with it (stream `brce-receipt-emitter`).

  Each test states the claim it attacks. A test in this file that FAILS is a
  reproduced counterexample to that claim at the tested commit, not a flaky
  test: the inputs are deterministic except the multi-process race, whose
  passing direction is deterministic (a fix cannot make it flake red).

  Chicago style: real WorkOrders, real `SemanticJira.execution_package/2`
  packages, real `sh` subprocesses, real files, the real file-backed
  `TransitionLog` and the real `Reconciler`. No mocks, stubs or patched
  collaborators. The multi-process test spawns real OS `elixir` VMs.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{ReceiptEmitter, Reconciler, TransitionLog}

  @sha String.duplicate("a", 40)
  @digest "sha256:" <> String.duplicate("c", 64)

  defp wo(id) do
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
      "dependencies" => []
    }
  end

  defp package(work_order) do
    {:ok, package} =
      SemanticJira.execution_package(work_order, %{
        "graph_digest" => @digest,
        "source_digest" => @digest,
        "worker_identity" => "worker:1",
        "verifier_identity" => "court:1"
      })

    package
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_falsify_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, log: Path.join(dir, "log")}
  end

  # -- claim: the plan is admitted BEFORE anything runs -------------------------
  #
  # A plan the emitter cannot digest (invalid UTF-8 has no JSON encoding) must
  # be refused at admission. At the tested commit the command RUNS and `emit/4`
  # then raises `Jason.EncodeError` while sealing the plan: an actuation with
  # neither a receipt nor a refusal.

  defp step(marker, extra_argv) do
    %{
      "id" => "s1",
      "argv" => ["sh", "-c", "touch #{marker}"] ++ extra_argv,
      "binds" => %{}
    }
  end

  defp assert_admitted_or_refused_before_run(work_order, plan, marker) do
    result =
      try do
        {:returned, ReceiptEmitter.emit(work_order, package(work_order), plan)}
      rescue
        error -> {:raised, error}
      end

    case result do
      {:raised, error} ->
        flunk(
          "emit/4 raised #{inspect(error.__struct__)} (#{Exception.message(error)}); " <>
            "the command already ran (marker present: #{File.exists?(marker)}), " <>
            "so this was an unreceipted actuation, not a pre-run refusal"
        )

      {:returned, {:ok, receipt}} ->
        assert :ok = ReceiptEmitter.verify(receipt, work_order)

      {:returned, {:error, {:refused, _reason}}} ->
        refute File.exists?(marker), "a refused plan must not run its command"
    end
  end

  describe "admission precedes actuation (plan with bytes that have no JSON encoding)" do
    test "invalid UTF-8 in an argv element", %{dir: dir} do
      marker = Path.join(dir, "ran_argv")
      w = wo("U-ARGV")
      plan = %{"steps" => [step(marker, [<<255>>])]}
      assert_admitted_or_refused_before_run(w, plan, marker)
    end

    test "invalid UTF-8 in a seed file's content", %{dir: dir} do
      marker = Path.join(dir, "ran_seed")
      w = wo("U-SEED")
      plan = %{"steps" => [step(marker, [])], "seed_files" => %{"bin.dat" => <<255, 254, 0>>}}
      assert_admitted_or_refused_before_run(w, plan, marker)
    end

    test "invalid UTF-8 in a step id", %{dir: dir} do
      marker = Path.join(dir, "ran_id")
      w = wo("U-ID")
      plan = %{"steps" => [%{step(marker, []) | "id" => <<255>>}]}
      assert_admitted_or_refused_before_run(w, plan, marker)
    end

    test "invalid UTF-8 in a watched path", %{dir: dir} do
      marker = Path.join(dir, "ran_watch")
      w = wo("U-WATCH")
      plan = %{"steps" => [step(marker, [])], "watch" => [<<255>>]}
      assert_admitted_or_refused_before_run(w, plan, marker)
    end
  end

  # -- claim: a tampered/edited receipt is refused ------------------------------
  #
  # Editing the exit code, digest, evidence or requirements of an emitted
  # receipt is refused. Deleting the seal and the kind marker turns the same
  # body into a "hand-built receipt", which `Reconciler.reconcile/3` admits by
  # default, so the refusal is bypassable by removing the two fields that
  # trigger it.

  test "a failing run's receipt with edited evidence and its seal + kind stripped is not admitted",
       %{log: log} do
    w = wo("DOWNGRADE")

    {:ok, receipt} =
      ReceiptEmitter.emit_command(w, package(w), ["sh", "-c", "exit 3"])

    assert receipt["consequence"]["success"] == false

    forged_evidence = %{
      receipt["evidence"]
      | "acceptance_results" => %{"a1" => true},
        "court_results" => %{"ci" => %{"passed" => true}},
        "falsifier_results" => %{"f1" => "survived"},
        "evidence_types" => ["exec"],
        "evidence_ceiling" => "observed",
        "observed_execution" => true
    }

    stripped =
      receipt
      |> Map.drop(["kind", "receipt_digest"])
      |> Map.put("evidence", forged_evidence)

    result = Reconciler.reconcile(w, stripped, log)

    assert match?({:error, {:refused, _}}, result),
           "an emitter-shaped receipt (identity/consequence/replay/stages) lost its seal and was " <>
             "admitted as hand-built: #{inspect(elem(result, 0))} -> standing " <>
             "#{inspect(with {:ok, event, _} <- result, do: event["to"])} for a run that exited 3"

    assert TransitionLog.read(log) == []
  end

  # -- claim: the receipt attests the stdout/stderr digests of THIS run ----------
  #
  # `ReceiptEmitter` redirects each step's stderr to
  # `System.tmp_dir!()/brce_err_<System.unique_integer/1>`. `unique_integer` is
  # unique per VM only (fresh VMs return small, overlapping values), and the
  # emitter deletes that file after reading it. Concurrent OS processes
  # (parallel CI shards, concurrent `mix` invocations) therefore share stderr
  # files, and a sealed receipt can carry ANOTHER run's stderr, or none.

  @vm_script ~S"""
  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.ReceiptEmitter
  tag = System.fetch_env!("BRCE_TAG")
  t0 = String.to_integer(System.fetch_env!("BRCE_T0"))
  sha = String.duplicate("a", 40)
  dg = "sha256:" <> String.duplicate("c", 64)

  w = %{
    "identity" => "VM-" <> tag, "title" => "t", "description" => "d", "subject" => "s-" <> tag,
    "repository" => "o/r", "base_sha" => sha, "standing" => "UNKNOWN",
    "evidence_ceiling" => "observed", "promotion_rule" => "all_courts",
    "replay_identity" => "rid-" <> tag, "required_courts" => ["ci"],
    "required_evidence" => ["exec"], "acceptance" => ["a1"], "falsifiers" => ["f1"],
    "projections" => ["jira"], "dependencies" => []
  }

  {:ok, pkg} =
    SemanticJira.execution_package(w, %{
      "graph_digest" => dg, "source_digest" => dg,
      "worker_identity" => "w", "verifier_identity" => "v"
    })

  Process.sleep(max(t0 - System.os_time(:millisecond), 0))

  {:ok, r} =
    ReceiptEmitter.emit_command(w, pkg, ["sh", "-c", "sleep 2; echo " <> tag <> " >&2; sleep 2"])

  [s] = r["consequence"]["steps"]
  IO.puts("RESULT:" <> Jason.encode!(%{tag: tag, stderr: s["stderr_excerpt"], verify: inspect(ReceiptEmitter.verify(r, w))}))
  """

  @tag timeout: 180_000
  test "concurrent OS processes each get their own stderr in their sealed receipt", %{dir: dir} do
    script = Path.join(dir, "emit_vm.exs")
    File.write!(script, @vm_script)

    elixir = System.find_executable("elixir") || flunk("no elixir executable on PATH")
    # `-pa` prepends each flag, so reverse to reproduce this VM's code path order.
    paths =
      :code.get_path() |> Enum.reverse() |> Enum.flat_map(&["-pa", to_string(&1)])

    count = 10
    t0 = System.os_time(:millisecond) + 10_000

    results =
      1..count
      |> Task.async_stream(
        fn i ->
          tag = "t#{i}"

          {out, _status} =
            System.cmd(elixir, paths ++ [script],
              env: [{"BRCE_TAG", tag}, {"BRCE_T0", Integer.to_string(t0)}],
              stderr_to_stdout: true
            )

          line = out |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "RESULT:"))
          {tag, line && Jason.decode!(String.replace_prefix(line, "RESULT:", "")), out}
        end,
        max_concurrency: count,
        timeout: 150_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    for {tag, decoded, out} <- results do
      assert decoded, "VM #{tag} produced no result: #{String.slice(out, 0, 400)}"
      assert decoded["verify"] == ":ok"
    end

    wrong =
      for {tag, decoded, _} <- results, decoded["stderr"] != tag <> "\n" do
        {tag, decoded["stderr"]}
      end

    assert wrong == [],
           "receipts attest stderr that is not their own run's (tag, recorded stderr): #{inspect(wrong)}"
  end
end
