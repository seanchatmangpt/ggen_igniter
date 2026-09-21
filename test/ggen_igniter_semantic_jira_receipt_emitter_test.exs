defmodule GgenIgniter.SemanticJiraReceiptEmitterTest do
  @moduledoc """
  Chicago-style: real WorkOrders, real `SemanticJira.execution_package/2`
  RuntimeShape packages, REAL `sh` subprocesses (via `System.cmd` inside
  `ReceiptEmitter`) in real scratch dirs, real `GgenIgniter.Receipt` hashing,
  the real file-backed `TransitionLog` and the real `Reconciler`. No mocks,
  stubs or patched collaborators; every assertion is on returned/persisted
  state (receipt maps, log files, projected standing, marker files a refused
  plan must not have created).
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Digest, Receipt, SemanticJira}
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

  defp dep(upstream),
    do: %{"upstream" => upstream, "type" => "requiresReceipt", "required_standing" => "ALIVE"}

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

  defp emit_ok(work_order, argv, opts \\ []) do
    assert {:ok, receipt} =
             ReceiptEmitter.emit_command(work_order, package(work_order), argv, opts)

    receipt
  end

  defp reseal(receipt), do: Map.put(receipt, "receipt_digest", SemanticJira.digest(receipt))

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_emit_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, log: Path.join(dir, "log")}
  end

  describe "emit/4 + Reconciler.reconcile/4 (end to end)" do
    test "admit -> real command -> sealed receipt -> reconcile -> transition logged -> dependent eligible",
         %{log: log} do
      root = wo("ROOT")
      b = wo("B", %{"dependencies" => [dep("ROOT")]})
      graph = [root, b]

      assert %{eligible: [%{"identity" => "ROOT"}], blocked: [%{"identity" => "B"}]} =
               SemanticJira.frontier_from_events(graph, TransitionLog.read(log))

      receipt =
        emit_ok(root, ["sh", "-c", "printf 'hello\\n' > out.txt; printf built"],
          watch: ["out.txt"]
        )

      # identity
      {:ok, definition_digest} = SemanticJira.definition_digest(root)
      {:ok, admitted} = SemanticJira.admit_work_order(root)
      assert receipt["kind"] == "brce_receipt"
      assert receipt["definition_digest"] == definition_digest
      assert receipt["snapshot_digest"] == admitted["work_order_digest"]
      assert receipt["identity"]["work_order_digest"] == admitted["work_order_digest"]
      assert receipt["identity"]["package_digest"] == package(root).shape_digest

      # authority
      assert receipt["authority"]["level"] == "NONE"
      assert receipt["authority"]["prepared_receipt"] == nil

      # consequence: a real subprocess ran and wrote a real file
      c = receipt["consequence"]
      assert c["success"] == true
      assert c["exit_code"] == 0
      [step] = c["steps"]
      assert step["ran"] and step["passed"] and step["exit_code"] == 0
      assert step["stdout_digest"] == Digest.sha256("built")
      assert step["stderr_digest"] == Digest.sha256("")

      assert [%{"path" => "out.txt", "before" => "absent", "changed" => true} = file] = c["files"]
      assert file["after"] == Digest.sha256("hello\n")
      assert c["portable_files_digest"] == Receipt.hash_entries([{"out.txt", "hello\n"}])
      assert "sha256:" <> _ = c["files_after_digest"]

      # replay data and standing (proposal only)
      assert receipt["replay"]["plan"]["steps"] |> hd() |> Map.fetch!("argv") |> hd() == "sh"
      assert receipt["replay"]["toolchain_identity"] =~ "elixir:"

      assert receipt["standing"] == %{
               "from" => "UNKNOWN",
               "authority" => "NONE",
               "transition_applied" => false,
               "proposed" => "ALIVE"
             }

      assert receipt["stages"]["actuate"] == "executed"
      assert receipt["stages"]["route"] == "UNSUPPORTED(single-route)"

      # sealed: the emitted receipt verifies and is admitted with caller-supplied receipts eliminated
      assert :ok = ReceiptEmitter.verify(receipt, root)

      assert {:ok, event, :appended} =
               Reconciler.reconcile(root, receipt, log, require_sealed: true)

      assert event["to"] == "ALIVE"
      assert event["from"] == "UNKNOWN"
      assert event["receipt_digest"] == SemanticJira.digest(receipt)
      assert event["authority"] == "NONE"
      assert [logged] = TransitionLog.read(log)
      assert logged["event_digest"] == event["event_digest"]

      # dependent is now eligible (projection over the log)
      front = SemanticJira.frontier_from_events(graph, TransitionLog.read(log))
      assert Enum.map(front.eligible, & &1["identity"]) == ["B"]

      # dependent runs its own real command and transitions
      b_receipt = emit_ok(b, ["sh", "-c", "exit 0"])
      assert {:ok, _, :appended} = Reconciler.reconcile(b, b_receipt, log, require_sealed: true)

      {projected, _} = SemanticJira.project(graph, TransitionLog.read(log))
      assert Enum.map(projected, & &1["standing"]) == ["ALIVE", "ALIVE"]

      # idempotent replay of the same sealed receipt
      assert {:ok, _, :already_recorded} =
               Reconciler.reconcile(root, receipt, log, require_sealed: true)

      assert length(TransitionLog.read(log)) == 2
    end

    test "failing command yields a valid non-success receipt that is REFUSED; standing stays", %{
      log: log
    } do
      root = wo("ROOT")
      b = wo("B", %{"dependencies" => [dep("ROOT")]})

      receipt = emit_ok(root, ["sh", "-c", "echo boom >&2; exit 3"])

      assert :ok = ReceiptEmitter.verify(receipt, root)
      c = receipt["consequence"]
      assert c["success"] == false
      assert c["exit_code"] == 3
      [step] = c["steps"]
      assert step["ran"] and not step["passed"]
      assert step["stderr_excerpt"] =~ "boom"
      assert step["stderr_digest"] == Digest.sha256("boom\n")
      assert receipt["evidence"]["acceptance_results"] == %{"a1" => false}
      assert receipt["evidence"]["court_results"] == %{"ci" => %{"passed" => false}}
      assert receipt["evidence"]["falsifier_results"] == %{"f1" => "failed"}
      assert receipt["evidence"]["receipt_classes"] == []

      assert {:error, {:refused, {:non_success_receipt, 3}}} =
               Reconciler.reconcile(root, receipt, log, require_sealed: true)

      assert {:error, {:refused, {:non_success_receipt, 3}}} =
               Reconciler.reconcile(root, receipt, log)

      # nothing appended, standing unchanged, dependent still blocked
      assert TransitionLog.read(log) == []
      {[projected], _} = SemanticJira.project([root], TransitionLog.read(log))
      assert projected["standing"] == "UNKNOWN"

      assert %{eligible: [%{"identity" => "ROOT"}], blocked: [%{"identity" => "B"}]} =
               SemanticJira.frontier_from_events([root, b], TransitionLog.read(log))
    end

    test "steps fail fast: a later step is recorded ran: false and the receipt is non-success", %{
      log: log
    } do
      root = wo("ROOT")
      marker = Path.join(Path.dirname(log), "second-step-ran")

      plan = %{
        steps: [
          %{id: "one", argv: ["sh", "-c", "exit 7"], binds: %{acceptance: ["a1"]}},
          %{id: "two", argv: ["sh", "-c", "touch #{marker}"], binds: %{courts: ["ci"]}}
        ]
      }

      assert {:ok, receipt} = ReceiptEmitter.emit(root, package(root), plan)

      assert [%{"exit_code" => 7, "ran" => true}, %{"ran" => false, "passed" => false}] =
               receipt["consequence"]["steps"]

      assert receipt["consequence"]["exit_code"] == 7
      refute File.exists?(marker)

      assert {:error, {:refused, {:non_success_receipt, 7}}} =
               Reconciler.reconcile(root, receipt, log)
    end

    test "a plan that binds only part of the WorkOrder is sealed but not sufficient for promotion",
         %{
           log: log
         } do
      root = wo("ROOT", %{"acceptance" => ["a1", "a2"]})

      plan = %{
        steps: [
          %{
            id: "one",
            argv: ["sh", "-c", "exit 0"],
            binds: %{acceptance: ["a1"], courts: ["ci"], falsifiers: ["f1"], evidence: ["exec"]}
          }
        ]
      }

      assert {:ok, receipt} = ReceiptEmitter.emit(root, package(root), plan)

      assert receipt["consequence"]["success"] == true
      assert receipt["evidence"]["acceptance_results"] == %{"a1" => true, "a2" => false}

      assert {:error, {:refused, {:promotion_refused, failed}}} =
               Reconciler.reconcile(root, receipt, log)

      assert :acceptance in failed
      assert TransitionLog.read(log) == []
    end

    test "seed files reach the command; watched files report per-file before/after", %{log: log} do
      root = wo("ROOT")

      assert {:ok, plan} =
               ReceiptEmitter.command_plan(root, ["sh", "-c", "cat in.txt > out.txt"],
                 seed_files: %{"in.txt" => "seeded\n"},
                 watch: ["out.txt", "in.txt"]
               )

      assert {:ok, receipt} = ReceiptEmitter.emit(root, package(root), plan)
      by_path = Map.new(receipt["consequence"]["files"], &{&1["path"], &1})

      assert by_path["in.txt"]["changed"] == false
      assert by_path["in.txt"]["after"] == Digest.sha256("seeded\n")
      assert by_path["out.txt"]["changed"] == true
      assert by_path["out.txt"]["before"] == "absent"
      assert by_path["out.txt"]["after"] == Digest.sha256("seeded\n")
      assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt, log)
    end

    test "a step that exceeds its timeout is a non-success receipt with timed_out" do
      root = wo("ROOT")
      receipt = emit_ok(root, ["sh", "-c", "sleep 3"], timeout_ms: 200)

      [step] = receipt["consequence"]["steps"]
      assert step["timed_out"] == true
      assert step["exit_code"] == nil
      assert step["passed"] == false
      assert receipt["consequence"]["success"] == false
      assert receipt["consequence"]["exit_code"] == -1
      assert :ok = ReceiptEmitter.verify(receipt, root)
    end

    test "a missing executable is a real failing consequence (exit 127), not a crash" do
      root = wo("ROOT")
      receipt = emit_ok(root, ["definitely-not-a-real-binary-brce"])

      assert receipt["consequence"]["success"] == false
      assert receipt["consequence"]["exit_code"] == 127
      assert hd(receipt["consequence"]["steps"])["stderr_excerpt"] =~ "not found"
    end
  end

  describe "verify/2 and Reconciler.reconcile/4 (tampered receipts are REFUSED)" do
    setup %{log: log} do
      root = wo("ROOT")
      receipt = emit_ok(root, ["sh", "-c", "printf ok"])
      %{root: root, receipt: receipt, log: log}
    end

    test "edited exit code with the original seal", %{root: root, receipt: r, log: log} do
      tampered = put_in(r, ["consequence", "steps", Access.at(0), "exit_code"], 1)

      assert {:error, :seal_mismatch} = ReceiptEmitter.verify(tampered, root)

      assert {:error, {:refused, {:receipt_invalid, :seal_mismatch}}} =
               Reconciler.reconcile(root, tampered, log)

      assert TransitionLog.read(log) == []
    end

    test "edited seal digest", %{root: root, receipt: r, log: log} do
      tampered = Map.put(r, "receipt_digest", @digest)

      assert {:error, {:refused, {:receipt_invalid, :seal_mismatch}}} =
               Reconciler.reconcile(root, tampered, log)

      # even though this digest would otherwise match an event already in the log
      assert {:ok, _, :appended} = Reconciler.reconcile(root, r, log)

      assert {:error, {:refused, {:receipt_invalid, :seal_mismatch}}} =
               Reconciler.reconcile(root, tampered, log)

      assert length(TransitionLog.read(log)) == 1
    end

    test "edited exit code resealed but derived fields left stale", %{
      root: root,
      receipt: r,
      log: log
    } do
      tampered =
        r
        |> put_in(["consequence", "steps", Access.at(0), "exit_code"], 1)
        |> reseal()

      assert {:error, :step_result_mismatch} = ReceiptEmitter.verify(tampered)

      assert {:error, {:refused, {:receipt_invalid, :step_result_mismatch}}} =
               Reconciler.reconcile(root, tampered, log)

      assert TransitionLog.read(log) == []
    end

    test "edited evidence resealed", %{root: root, receipt: r, log: log} do
      failing = emit_ok(root, ["sh", "-c", "exit 1"])

      tampered =
        failing
        |> Map.put("evidence", r["evidence"])
        |> reseal()

      assert {:error, :evidence_not_derived_from_consequence} = ReceiptEmitter.verify(tampered)

      assert {:error, {:refused, {:receipt_invalid, :evidence_not_derived_from_consequence}}} =
               Reconciler.reconcile(root, tampered, log)
    end

    test "requirements edited to fit a weaker WorkOrder are refused against the real one", %{
      root: root,
      receipt: r,
      log: log
    } do
      # Requirements AND the evidence derived from them are edited consistently
      # (so the receipt is self-consistent); only the real WorkOrder catches it.
      tampered =
        r
        |> put_in(["requirements", "acceptance"], [])
        |> put_in(["evidence", "acceptance_results"], %{})
        |> reseal()

      assert :ok = ReceiptEmitter.verify(tampered)
      assert {:error, :requirements_mismatch} = ReceiptEmitter.verify(tampered, root)

      assert {:error, {:refused, {:receipt_invalid, _}}} =
               Reconciler.reconcile(root, tampered, log)
    end

    test "receipt for another definition is refused before anything else", %{
      root: root,
      receipt: r,
      log: log
    } do
      other = Map.put(root, "acceptance", ["a1", "sneaky"])

      assert {:error, {:refused, :definition_mismatch}} = Reconciler.reconcile(other, r, log)
    end

    test "structurally malformed but resealed receipt is refused, not a crash", %{
      root: root,
      receipt: r,
      log: log
    } do
      tampered = r |> Map.put("requirements", nil) |> reseal()

      assert {:error, :malformed_receipt} = ReceiptEmitter.verify(tampered)

      assert {:error, {:refused, {:receipt_invalid, :malformed_receipt}}} =
               Reconciler.reconcile(root, tampered, log)
    end

    test "hand-built receipts: admitted by default (unchanged), refused with require_sealed", %{
      log: log
    } do
      root = wo("ROOT")
      {:ok, definition_digest} = SemanticJira.definition_digest(root)
      {:ok, admitted} = SemanticJira.admit_work_order(root)

      hand_built = %{
        "definition_digest" => definition_digest,
        "snapshot_digest" => admitted["work_order_digest"],
        "target" => "ALIVE",
        "evidence" => %{
          "subject" => root["subject"],
          "repository" => root["repository"],
          "base_sha" => root["base_sha"],
          "evidence_types" => ["exec"],
          "court_results" => %{"ci" => %{"passed" => true}},
          "acceptance_results" => %{"a1" => true},
          "falsifier_results" => %{"f1" => "survived"},
          "receipt_classes" => [],
          "evidence_ceiling" => "observed",
          "observed_execution" => true
        }
      }

      assert {:error, {:refused, :unsealed_receipt}} =
               Reconciler.reconcile(root, hand_built, log, require_sealed: true)

      assert TransitionLog.read(log) == []
      assert {:ok, _, :appended} = Reconciler.reconcile(root, hand_built, log)

      # a hand-built map that merely CLAIMS a seal is verified as one
      claims = Map.put(hand_built, "receipt_digest", @digest)

      assert {:error, {:refused, {:receipt_invalid, :not_an_emitted_receipt}}} =
               Reconciler.reconcile(root, claims, log)
    end
  end

  describe "admission refuses BEFORE any command runs" do
    setup %{dir: dir} do
      %{marker: Path.join(dir, "ran"), root: wo("ROOT")}
    end

    test "package minted for a different WorkOrder", %{root: root, marker: marker} do
      other_package = package(wo("OTHER"))

      assert {:error, {:refused, :package_work_order_mismatch}} =
               ReceiptEmitter.emit_command(root, other_package, ["touch", marker])

      refute File.exists?(marker)
    end

    test "package whose content was edited after its digest was computed", %{
      root: root,
      marker: marker
    } do
      tampered = %{package(root) | subject_id: "urn:other"}

      assert {:error, {:refused, :package_digest_mismatch}} =
               ReceiptEmitter.emit_command(root, tampered, ["touch", marker])

      refute File.exists?(marker)
    end

    test "not a RuntimeShape package", %{root: root, marker: marker} do
      assert {:error, {:refused, :package_not_runtime_shape}} =
               ReceiptEmitter.emit_command(root, %{}, ["touch", marker])
    end

    test "invalid WorkOrder", %{marker: marker} do
      good = wo("ROOT")

      assert {:error, {:refused, {:work_order, _}}} =
               ReceiptEmitter.emit_command(Map.delete(good, "falsifiers"), package(good), [
                 "touch",
                 marker
               ])

      refute File.exists?(marker)
    end

    test "plan binding names an id the WorkOrder does not have", %{root: root, marker: marker} do
      plan = %{
        steps: [
          %{id: "s", argv: ["touch", marker], binds: %{acceptance: ["not-a-real-criterion"]}}
        ]
      }

      assert {:error, {:refused, {:unknown_binding, "acceptance", "not-a-real-criterion"}}} =
               ReceiptEmitter.emit(root, package(root), plan)

      refute File.exists?(marker)
    end

    test "watch/seed paths that escape the scratch dir", %{root: root, marker: marker} do
      for path <- ["/etc/passwd", "../escape"] do
        assert {:error, {:refused, :invalid_watch_path}} =
                 ReceiptEmitter.emit(root, package(root), %{
                   steps: [%{id: "s", argv: ["touch", marker]}],
                   watch: [path]
                 })

        assert {:error, {:refused, :invalid_seed_files}} =
                 ReceiptEmitter.emit(root, package(root), %{
                   steps: [%{id: "s", argv: ["touch", marker]}],
                   seed_files: %{path => "x"}
                 })
      end

      refute File.exists?(marker)
    end

    test "empty plan and duplicate step ids", %{root: root, marker: marker} do
      assert {:error, {:refused, :plan_requires_steps}} =
               ReceiptEmitter.emit(root, package(root), %{steps: []})

      dup = %{steps: [%{id: "s", argv: ["touch", marker]}, %{id: "s", argv: ["touch", marker]}]}

      assert {:error, {:refused, :duplicate_step_id}} =
               ReceiptEmitter.emit(root, package(root), dup)

      refute File.exists?(marker)
    end

    test "authority_requirement other than NONE needs a matching prepared authority receipt", %{
      marker: marker
    } do
      root = wo("ROOT", %{"authority_requirement" => "repo-write"})
      {:ok, admitted} = SemanticJira.admit_work_order(root)

      assert {:error, {:refused, :authority_not_prepared}} =
               ReceiptEmitter.emit_command(root, package(root), ["touch", marker])

      prepared = %{
        "status" => "prepared",
        "work_order_digest" => admitted["work_order_digest"],
        "subject" => admitted["subject"],
        "replay_identity" => admitted["replay_identity"],
        "authority_identity" => "authority:1"
      }

      assert {:error, {:refused, :authority_not_prepared}} =
               ReceiptEmitter.emit_command(root, package(root), ["touch", marker],
                 authority_receipt: %{prepared | "subject" => "other"}
               )

      refute File.exists?(marker)

      assert {:ok, receipt} =
               ReceiptEmitter.emit_command(root, package(root), ["sh", "-c", "exit 0"],
                 authority_receipt: prepared
               )

      # the emitter attests a prepared authority; it never grants any
      assert receipt["authority"]["level"] == "NONE"
      assert receipt["authority"]["requirement"] == "repo-write"
      assert receipt["authority"]["prepared_receipt"]["authority_identity"] == "authority:1"
      assert receipt["evidence"]["authority_receipt"]["status"] == "prepared"
    end
  end

  describe "evidence ceiling" do
    test "a local run cannot attest a hosted-ci ceiling: proposes PARTIAL_ALIVE; forcing ALIVE is refused",
         %{log: log} do
      root = wo("ROOT", %{"evidence_ceiling" => "hosted-ci"})
      receipt = emit_ok(root, ["sh", "-c", "exit 0"])

      assert receipt["target"] == "PARTIAL_ALIVE"
      assert receipt["evidence"]["evidence_ceiling"] == "observed"

      forced = emit_ok(root, ["sh", "-c", "exit 0"], target: "ALIVE")

      assert {:error, {:refused, {:promotion_refused, [:ceiling]}}} =
               Reconciler.reconcile(root, forced, log)

      assert TransitionLog.read(log) == []

      assert {:ok, event, :appended} = Reconciler.reconcile(root, receipt, log)
      assert event["to"] == "PARTIAL_ALIVE"
    end
  end

  describe "replay" do
    test "deterministic plan replays inline; the receipt records the replay verdict", %{log: log} do
      root = wo("ROOT", %{"replay_required" => true})

      receipt =
        emit_ok(root, ["sh", "-c", "printf stable > out.txt; printf stable"], watch: ["out.txt"])

      assert receipt["replay"]["requested"] == true
      assert receipt["replay"]["passed"] == true
      assert "sha256:" <> _ = receipt["replay"]["replay_receipt_digest"]
      assert receipt["evidence"]["replay_passed"] == true
      assert receipt["evidence"]["receipt_classes"] == ["verification", "replay"]
      assert receipt["stages"]["replay"] == "executed"

      # replay_required is satisfied by the receipt alone
      assert {:ok, %{"to" => "ALIVE"}, :appended} =
               Reconciler.reconcile(root, receipt, log, require_sealed: true)
    end

    test "nondeterministic plan fails replay honestly and cannot satisfy replay_required", %{
      log: log
    } do
      root = wo("ROOT", %{"replay_required" => true})
      receipt = emit_ok(root, ["sh", "-c", "echo $$"])

      assert receipt["consequence"]["success"] == true
      assert receipt["replay"]["passed"] == false
      assert receipt["replay"]["mismatched_fields"] == ["consequence_set"]
      assert receipt["evidence"]["replay_passed"] == false

      assert {:error, {:refused, {:promotion_refused, failed}}} =
               Reconciler.reconcile(root, receipt, log)

      assert :replay in failed
      assert TransitionLog.read(log) == []
    end

    test "replay/2 never executes the receipt's own argv unless explicitly trusted" do
      root = wo("ROOT")
      receipt = emit_ok(root, ["sh", "-c", "printf stable"])

      assert {:error, {:replay_refused, :untrusted_plan}} = ReceiptEmitter.replay(receipt)

      assert {:ok, %{"status" => "KNOWN_REPLAY"}} =
               ReceiptEmitter.replay(receipt, trust_receipt_plan: true)

      {:ok, plan} = ReceiptEmitter.command_plan(root, ["sh", "-c", "printf stable"])

      assert {:ok, %{"status" => "KNOWN_REPLAY"}} =
               ReceiptEmitter.replay(receipt, work_order: root, plan: plan)

      {:ok, other_plan} = ReceiptEmitter.command_plan(root, ["sh", "-c", "printf different"])

      assert {:error, {:replay_refused, :plan_digest_mismatch}} =
               ReceiptEmitter.replay(receipt, work_order: root, plan: other_plan)
    end

    test "QUALIFICATION: a self-consistent forgery passes verify/2 (seal is integrity, not signature) but not replay",
         %{log: log, dir: dir} do
      root = wo("ROOT")
      {:ok, plan} = ReceiptEmitter.command_plan(root, ["sh", "-c", "echo real-failure; exit 1"])
      {:ok, real} = ReceiptEmitter.emit(root, package(root), plan)
      assert real["consequence"]["success"] == false

      success = emit_ok(root, ["sh", "-c", "exit 0"])

      # Forger flips the outcome AND recomputes every derived field and the seal.
      forged_steps =
        Enum.map(real["consequence"]["steps"], fn step ->
          %{step | "exit_code" => 0, "passed" => true}
        end)

      comparable = %{
        "steps" =>
          Enum.map(
            forged_steps,
            &Map.take(&1, ~w(id ran exit_code timed_out passed stdout_digest))
          ),
        "files" => []
      }

      forged =
        real
        |> put_in(["consequence", "steps"], forged_steps)
        |> put_in(["consequence", "success"], true)
        |> put_in(["consequence", "exit_code"], 0)
        |> put_in(["consequence", "consequence_digest"], SemanticJira.digest(comparable))
        |> Map.put("evidence", success["evidence"])
        |> reseal()

      assert :ok = ReceiptEmitter.verify(forged, root)

      # (a) disclosed limit: with no replay_plan the forgery is admitted.
      forged_log = Path.join(dir, "forged-log")

      assert {:ok, _, :appended} =
               Reconciler.reconcile(root, forged, forged_log, require_sealed: true)

      # (b) mitigation: re-running the TRUSTED plan does not reproduce the claimed consequence.
      assert {:error, {:replay_refused, {:identity_mismatch, [%{"field" => "consequence_set"}]}}} =
               ReceiptEmitter.replay(forged, work_order: root, plan: plan)

      assert {:error, {:refused, {:replay_refused, {:identity_mismatch, _}}}} =
               Reconciler.reconcile(root, forged, log, replay_plan: plan)

      assert TransitionLog.read(log) == []

      # ... while the honest, successful receipt replays clean through the same option.
      {:ok, ok_plan} = ReceiptEmitter.command_plan(root, ["sh", "-c", "exit 0"])
      assert {:ok, _, :appended} = Reconciler.reconcile(root, success, log, replay_plan: ok_plan)
    end
  end

  describe "persist/2 and load/1" do
    test "content-addressed round trip; a corrupted file fails its seal", %{dir: dir} do
      root = wo("ROOT")
      receipt = emit_ok(root, ["sh", "-c", "printf persisted"])

      assert {:ok, path} = ReceiptEmitter.persist(receipt, Path.join(dir, "receipts"))

      assert Path.basename(path) ==
               String.replace_prefix(receipt["receipt_digest"], "sha256:", "") <> ".json"

      assert {:ok, ^path} = ReceiptEmitter.persist(receipt, Path.join(dir, "receipts"))
      assert {:ok, loaded} = ReceiptEmitter.load(path)
      assert loaded == receipt

      corrupted =
        path
        |> File.read!()
        |> String.replace("\"exit_code\":0", "\"exit_code\":9", global: false)

      refute corrupted == File.read!(path)
      File.write!(path, corrupted)
      assert {:error, :seal_mismatch} = ReceiptEmitter.load(path)
    end
  end
end
