defmodule GgenIgniter.SemanticJiraReceiptEmitterFalsifierTest do
  @moduledoc """
  Qualifier falsifiers for `GgenIgniter.SemanticJira.ReceiptEmitter` and the
  `Reconciler` options added with it (stream `brce-receipt-emitter`).

  Each test states the claim it attacks. The first six tests were RED at commit
  98ee9d9 (6 tests, 6 failures: reproduced counterexamples, not flakes) and are
  the permanent regression guards for the repair that followed; the rest extend
  the same claims to every input class the counterexamples generalize to. The
  inputs are deterministic except the multi-process race, whose passing
  direction is deterministic (a fix cannot make it flake red).

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

  defp wo(id, overrides \\ %{}) do
    Map.merge(
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
      },
      overrides
    )
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
  # be refused at admission. Before the repair the command RAN and `emit/4` then
  # raised `Jason.EncodeError` while sealing the plan: an actuation with neither
  # a receipt nor a refusal.

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
  # receipt is refused. Deleting the seal and the kind marker used to turn the
  # same body into a "hand-built receipt", which `Reconciler.reconcile/3` admits
  # by default, so the refusal was bypassable by removing the two fields that
  # trigger it. An emitter-shaped receipt without its seal is now refused.

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
  # `ReceiptEmitter` used to redirect each step's stderr to
  # `System.tmp_dir!()/brce_err_<System.unique_integer/1>`. `unique_integer` is
  # unique per VM only (fresh VMs return small, overlapping values), and the
  # emitter deleted that file after reading it. Concurrent OS processes
  # (parallel CI shards, concurrent `mix` invocations) therefore shared stderr
  # files, and a sealed receipt could carry ANOTHER run's stderr, or none. Each
  # run now has a private directory (exclusive mkdir, OS pid + random bytes).

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

  # -- the same claims, generalized ---------------------------------------------

  defp assert_refused_before_run(result, marker, expected_reason) do
    assert {:error, {:refused, ^expected_reason}} = result
    refute File.exists?(marker), "a refused emission must not run its command"
  end

  describe "admission precedes actuation (every other value that is sealed later)" do
    test "a WorkOrder, options or authority receipt with no JSON encoding is a refusal", %{
      dir: dir
    } do
      marker = Path.join(dir, "ran_generalized")
      touch = ["touch", marker]

      bad_title = Map.put(wo("U-TITLE"), "title", <<255>>)

      assert_refused_before_run(
        ReceiptEmitter.emit_command(bad_title, package(wo("U-TITLE")), touch),
        marker,
        {:work_order, :not_json_safe}
      )

      w = wo("U-OPTS")

      for {opt, reason} <- [
            {[target: {:not, :a, :standing}], {:invalid_target, {:not, :a, :standing}}},
            {[target: "NOT_A_STANDING"], {:invalid_target, "NOT_A_STANDING"}},
            {[emitter_identity: <<255>>], :invalid_emitter_identity},
            {[emitter_identity: 42], :invalid_emitter_identity},
            {[replay: "yes"], :invalid_replay_option}
          ] do
        assert_refused_before_run(
          ReceiptEmitter.emit_command(w, package(w), touch, opt),
          marker,
          reason
        )
      end

      auth = wo("U-AUTH", %{"authority_requirement" => "repo-write"})
      {:ok, admitted} = SemanticJira.admit_work_order(auth)

      prepared = %{
        "status" => "prepared",
        "work_order_digest" => admitted["work_order_digest"],
        "subject" => admitted["subject"],
        "replay_identity" => admitted["replay_identity"]
      }

      for identity <- [<<255>>, {:tuple, :identity}, self()] do
        assert_refused_before_run(
          ReceiptEmitter.emit_command(auth, package(auth), touch,
            authority_receipt: Map.put(prepared, "authority_identity", identity)
          ),
          marker,
          :authority_not_prepared
        )
      end
    end
  end

  describe "an emitter-shaped receipt never loses its verification by losing its seal" do
    defp hand_built(work_order) do
      {:ok, definition_digest} = SemanticJira.definition_digest(work_order)
      {:ok, admitted} = SemanticJira.admit_work_order(work_order)

      %{
        "definition_digest" => definition_digest,
        "snapshot_digest" => admitted["work_order_digest"],
        "target" => "ALIVE",
        "evidence" => %{
          "subject" => work_order["subject"],
          "repository" => work_order["repository"],
          "base_sha" => work_order["base_sha"],
          "evidence_types" => ["exec"],
          "court_results" => %{"ci" => %{"passed" => true}},
          "acceptance_results" => %{"a1" => true},
          "falsifier_results" => %{"f1" => "survived"},
          "receipt_classes" => [],
          "evidence_ceiling" => "observed",
          "observed_execution" => true
        }
      }
    end

    test "each emitter-only section, alone, marks a receipt as stripped", %{log: log} do
      w = wo("STRIP")

      for {key, value} <- [
            {"consequence", %{}},
            {"stages", %{}},
            {"replay", %{}},
            {"requirements", %{}},
            {"identity", %{}},
            {"emitted_by", "someone"},
            {"emitted_at", "2026-09-21T00:00:00Z"},
            {"receipt_class", "verification"}
          ] do
        receipt = w |> hand_built() |> Map.put(key, value)

        assert {:error, {:refused, {:receipt_invalid, :stripped_seal}}} =
                 Reconciler.reconcile(w, receipt, log)

        assert {:error, {:refused, {:receipt_invalid, :stripped_seal}}} =
                 Reconciler.reconcile(w, receipt, log, require_sealed: true)
      end

      assert TransitionLog.read(log) == []
    end

    test "control: a plain hand-built receipt is still admitted by default, refused when sealed is required",
         %{log: log} do
      w = wo("PLAIN")
      receipt = hand_built(w)

      assert {:error, {:refused, :unsealed_receipt}} =
               Reconciler.reconcile(w, receipt, log, require_sealed: true)

      assert {:ok, %{"to" => "ALIVE"}, :appended} = Reconciler.reconcile(w, receipt, log)
    end
  end

  describe "each run has a private directory" do
    test "the run directory is mode 0700, the cwd is its `work/`, and none survives the run" do
      w = wo("PRIVATE")
      prefix = "brce_run_#{System.pid()}_"

      leftovers = fn ->
        System.tmp_dir!() |> File.ls!() |> Enum.filter(&String.starts_with?(&1, prefix))
      end

      before = leftovers.()

      assert {:ok, r} =
               ReceiptEmitter.emit_command(
                 w,
                 package(w),
                 ["sh", "-c", "ls -ld .. | cut -c1-10; basename \"$(pwd)\""]
               )

      assert [%{"stdout_excerpt" => out}] = r["consequence"]["steps"]
      assert out == "drwx------\nwork\n"

      # failing, timed-out and refused-after-admission runs leave nothing behind either
      assert {:ok, _} = ReceiptEmitter.emit_command(w, package(w), ["sh", "-c", "exit 3"])

      assert {:ok, _} =
               ReceiptEmitter.emit_command(w, package(w), ["sleep", "3"], timeout_ms: 100)

      assert leftovers.() == before
    end

    test "concurrent emits inside ONE VM each attest their own stderr" do
      results =
        1..16
        |> Task.async_stream(
          fn i ->
            tag = "vm-local-#{i}"
            w = wo("LOCAL-#{i}")

            {:ok, r} =
              ReceiptEmitter.emit_command(w, package(w), [
                "sh",
                "-c",
                "sleep 0.3; echo #{tag} >&2; sleep 0.3"
              ])

            {tag, hd(r["consequence"]["steps"])["stderr_excerpt"]}
          end,
          max_concurrency: 16,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.all?(results, fn {tag, stderr} -> stderr == tag <> "\n" end), inspect(results)
    end
  end
end
