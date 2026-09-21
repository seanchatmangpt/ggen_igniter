defmodule GgenIgniter.SemanticJiraReceiptEmitterBindingTest do
  @moduledoc """
  Regression guards for what a sealed `ReceiptEmitter` receipt is allowed to
  attest (stream `brce-receipt-emitter`, repair round).

  Claims defended here, each with the counterexample that once broke it:

    * ALIVE means an observed run of the EXACT admitted subject under the
      WorkOrder's OWN commands and authority. Before: a trivial `true` in an empty
      scratch dir, bound by the plan author to every court/falsifier/acceptance
      id, reconciled to ALIVE under `require_sealed: true`.
    * The `RuntimeShape` package is checked for CONTENT (`worker_not_verifier`,
      `base_must_not_move`, repository/base binding), not only for self-digest.
    * A prepared authority receipt is a claim until the caller's verifier vouches
      for it. Before: a fabricated map was sealed into evidence and promoted.

  Chicago style: real WorkOrders, real `SemanticJira.execution_package/2`
  packages (rebuilt through the real `RuntimeShape.new/1` when a test needs a
  self-consistent but wrong one), a real git repository with real commits as the
  subject (`GgenIgniter.TestSupport.SubjectRepo`), real `sh`/`git`/`tar`
  subprocesses, real files, the real file-backed `TransitionLog` and `Reconciler`.
  No mocks. The authority verifier is a real hand-written function implementing
  the verifier contract, not an interaction-verifying double.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.{Digest, RuntimeShape, SemanticJira}
  alias GgenIgniter.SemanticJira.{ReceiptEmitter, Reconciler, TransitionLog}
  alias GgenIgniter.TestSupport.SubjectRepo

  @digest "sha256:" <> String.duplicate("c", 64)

  setup_all do
    dir = Path.join(System.tmp_dir!(), "sj_bind_subject_#{System.unique_integer([:positive])}")
    :persistent_term.put({__MODULE__, :subject}, SubjectRepo.create!(dir))
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  defp subject, do: :persistent_term.get({__MODULE__, :subject})

  defp wo(id, overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => id,
        "title" => id,
        "description" => "d",
        "subject" => "subj-#{id}",
        "repository" => "o/r",
        "base_sha" => subject().sha,
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "observed",
        "promotion_rule" => "all_courts",
        "replay_identity" => "rid-#{id}",
        "required_courts" => ["ci", "sec"],
        "required_evidence" => ["exec", "log"],
        "acceptance" => ["a1", "a2"],
        "falsifiers" => ["f1", "f2"],
        "projections" => ["jira"],
        "dependencies" => []
      },
      overrides
    )
  end

  defp pinned(work_order, argv, expect_exit \\ 0) do
    Map.put(work_order, "expected_consequence", %{
      "commands" => [%{"argv" => argv, "expect_exit" => expect_exit}]
    })
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

  # A self-consistent (freshly digested) package whose CONTENT was edited: the
  # forger's move. The digest alone cannot catch it.
  defp rebuilt(package, edit) do
    attrs = package |> RuntimeShape.to_map() |> Map.delete("shape_digest") |> edit.()
    {:ok, rebuilt} = RuntimeShape.new(attrs)
    rebuilt
  end

  defp prepared_for(work_order, identity \\ "authority:1") do
    {:ok, admitted} = SemanticJira.admit_work_order(work_order)

    %{
      "status" => "prepared",
      "work_order_digest" => admitted["work_order_digest"],
      "subject" => admitted["subject"],
      "replay_identity" => admitted["replay_identity"],
      "authority_identity" => identity
    }
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "sj_bind_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, log: Path.join(dir, "log"), marker: Path.join(dir, "ran")}
  end

  describe "ALIVE needs the exact subject, pinned commands and authority" do
    test "a trivial `true` in an empty scratch dir bound to every claim is only PARTIAL_ALIVE",
         %{dir: dir, log: log} do
      w = wo("TRIV")

      assert {:ok, r} = ReceiptEmitter.emit_command(w, package(w), ["true"])

      # It IS sealed and successful, and it names every claim...
      assert r["consequence"]["success"] == true
      assert r["evidence"]["acceptance_results"] == %{"a1" => true, "a2" => true}
      assert :ok = ReceiptEmitter.verify(r, w)

      # ...but nothing ties it to the subject or to a WorkOrder-declared command.
      assert r["evidence"]["binding"] == %{
               "subject" => false,
               "commands_pinned" => false,
               "authority" => true
             }

      assert r["evidence"]["observed_execution"] == false
      assert r["evidence"]["evidence_ceiling"] == "none"
      assert r["target"] == "PARTIAL_ALIVE"

      assert {:ok, %{"to" => "PARTIAL_ALIVE"}, :appended} =
               Reconciler.reconcile(w, r, log, require_sealed: true)

      # Forcing ALIVE is refused by the promotion calculus itself.
      assert {:ok, forced} = ReceiptEmitter.emit_command(w, package(w), ["true"], target: "ALIVE")

      assert {:error, {:refused, {:promotion_refused, [:ceiling]}}} =
               Reconciler.reconcile(w, forced, Path.join(dir, "forced-log"), require_sealed: true)

      assert TransitionLog.read(Path.join(dir, "forced-log")) == []
    end

    test "an unpinned WorkOrder stays PARTIAL_ALIVE even with the subject bound", %{dir: dir} do
      w = wo("UNPINNED")

      assert {:ok, r} =
               ReceiptEmitter.emit_command(w, package(w), ["true"],
                 subject_source: subject().path,
                 target: "ALIVE"
               )

      assert r["consequence"]["subject"]["bound"] == true
      assert r["evidence"]["binding"]["subject"] == true
      assert r["evidence"]["binding"]["commands_pinned"] == false
      assert r["evidence"]["observed_execution"] == false

      assert {:error, {:refused, {:promotion_refused, [:ceiling]}}} =
               Reconciler.reconcile(w, r, Path.join(dir, "log"), require_sealed: true)
    end

    test "a pinned WorkOrder without a subject stays PARTIAL_ALIVE", %{dir: dir} do
      w = "NOSUBJ" |> wo() |> pinned(["true"])

      assert {:ok, r} = ReceiptEmitter.emit_command(w, package(w), ["true"], target: "ALIVE")
      assert r["evidence"]["binding"]["commands_pinned"] == true
      assert r["evidence"]["binding"]["subject"] == false

      assert {:error, {:refused, {:promotion_refused, [:ceiling]}}} =
               Reconciler.reconcile(w, r, Path.join(dir, "log"), require_sealed: true)
    end

    test "pinned commands + the exact subject is ALIVE", %{log: log} do
      argv = ["sh", "-c", "grep -q subject-head marker.txt"]
      w = "PINNED" |> wo() |> pinned(argv)

      assert {:ok, r} =
               ReceiptEmitter.emit_command(w, package(w), argv, subject_source: subject().path)

      assert r["target"] == "ALIVE"
      assert r["evidence"]["observed_execution"] == true
      assert r["evidence"]["evidence_ceiling"] == "observed"
      assert r["requirements"]["pinned_commands"] == [%{"argv" => argv, "expect_exit" => 0}]

      assert {:ok, %{"to" => "ALIVE"}, :appended} =
               Reconciler.reconcile(w, r, log, require_sealed: true)
    end

    test "the pinned command really is evaluated against the subject: wrong content fails it" do
      # Same pin, but the subject at `first_sha` holds different content.
      argv = ["sh", "-c", "grep -q subject-head marker.txt"]
      w = "WRONGSUBJ" |> wo(%{"base_sha" => subject().first_sha}) |> pinned(argv)

      assert {:ok, r} =
               ReceiptEmitter.emit_command(w, package(w), argv, subject_source: subject().path)

      assert r["consequence"]["subject"]["sha"] == subject().first_sha
      assert r["consequence"]["success"] == false
      assert r["consequence"]["exit_code"] == 1
      assert {:error, {:refused, {:non_success_receipt, 1}}} = check_reconcile(w, r)
    end
  end

  defp check_reconcile(w, r) do
    dir = Path.join(System.tmp_dir!(), "sj_bind_chk_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    Reconciler.reconcile(w, r, dir, require_sealed: true)
  end

  describe "pinned commands: the plan cannot choose what runs or what it backs" do
    setup %{marker: marker} do
      argv = ["sh", "-c", "exit 0"]
      %{argv: argv, w: "PIN" |> wo() |> pinned(argv), marker: marker}
    end

    test "a plan with another command is refused before it runs", %{w: w, marker: marker} do
      assert {:error, {:refused, :plan_not_pinned}} =
               ReceiptEmitter.emit_command(w, package(w), ["touch", marker])

      refute File.exists?(marker)
    end

    test "extra, missing or edited steps are refused", %{w: w, argv: argv, marker: marker} do
      extra = %{
        steps: [
          %{id: "one", argv: argv},
          %{id: "two", argv: ["touch", marker]}
        ]
      }

      assert {:error, {:refused, :plan_not_pinned}} = ReceiptEmitter.emit(w, package(w), extra)

      wrong_exit = %{steps: [%{id: "one", argv: argv, expect_exit: 3}]}

      assert {:error, {:refused, :plan_not_pinned}} =
               ReceiptEmitter.emit(w, package(w), wrong_exit)

      refute File.exists?(marker)
    end

    test "the plan cannot narrow or widen which claims the command backs", %{w: w, argv: argv} do
      narrowed = %{steps: [%{id: "one", argv: argv, binds: %{acceptance: ["a1"]}}]}

      assert {:error, {:refused, :pinned_binds_mismatch}} =
               ReceiptEmitter.emit(w, package(w), narrowed)

      # Omitting binds is fine: a pinned command backs everything the WorkOrder names.
      omitted = %{steps: [%{id: "one", argv: argv}]}
      assert {:ok, r} = ReceiptEmitter.emit(w, package(w), omitted)
      assert r["evidence"]["acceptance_results"] == %{"a1" => true, "a2" => true}

      assert r["evidence"]["court_results"] == %{
               "ci" => %{"passed" => true},
               "sec" => %{"passed" => true}
             }
    end

    test "malformed pinned commands are a refusal; free-form expected_consequence is unpinned",
         %{marker: marker} do
      for bad <- [%{"commands" => [%{"argv" => []}]}, %{"commands" => "x"}, %{"commands" => [1]}] do
        w = Map.put(wo("BAD"), "expected_consequence", bad)

        assert {:error, {:refused, :invalid_expected_consequence}} =
                 ReceiptEmitter.emit_command(w, package(w), ["touch", marker])
      end

      refute File.exists?(marker)

      free = Map.put(wo("FREE"), "expected_consequence", "the build passes")
      assert {:ok, r} = ReceiptEmitter.emit_command(free, package(free), ["true"])
      assert r["requirements"]["pinned_commands"] == nil
    end

    test "a resealed receipt whose steps differ from the pin is refused against the WorkOrder",
         %{w: w, argv: argv, log: log} do
      assert {:ok, r} =
               ReceiptEmitter.emit_command(w, package(w), argv, subject_source: subject().path)

      tampered =
        r
        |> put_in(["consequence", "steps", Access.at(0), "argv"], ["true"])
        |> then(&Map.put(&1, "receipt_digest", SemanticJira.digest(&1)))

      assert :ok = ReceiptEmitter.verify(tampered)
      assert {:error, :steps_not_pinned} = ReceiptEmitter.verify(tampered, w)

      assert {:error, {:refused, {:receipt_invalid, :steps_not_pinned}}} =
               Reconciler.reconcile(w, tampered, log, require_sealed: true)

      assert TransitionLog.read(log) == []
    end
  end

  describe "subject materialization" do
    test "candidate_sha selects the commit; base_sha is the fallback" do
      argv = ["sh", "-c", "cat marker.txt > out.txt"]

      head = "HEAD" |> wo(%{"base_sha" => subject().first_sha, "candidate_sha" => subject().sha})
      head = pinned(head, argv)

      assert {:ok, r} =
               ReceiptEmitter.emit_command(head, package(head), argv,
                 subject_source: subject().path,
                 watch: ["out.txt"]
               )

      assert r["consequence"]["subject"]["sha"] == subject().sha
      assert [%{"after" => after_digest}] = r["consequence"]["files"]
      assert after_digest == Digest.sha256("subject-head\n")

      first = "FIRST" |> wo(%{"base_sha" => subject().first_sha}) |> pinned(argv)

      assert {:ok, r2} =
               ReceiptEmitter.emit_command(first, package(first), argv,
                 subject_source: subject().path,
                 watch: ["out.txt"]
               )

      assert r2["consequence"]["subject"]["sha"] == subject().first_sha
      assert [%{"after" => first_digest}] = r2["consequence"]["files"]
      assert first_digest == Digest.sha256("subject-first\n")
    end

    test "a commit that is not in the subject source is refused before anything runs",
         %{marker: marker, dir: dir} do
      missing = String.duplicate("b", 40)
      w = wo("MISSING", %{"base_sha" => missing})

      assert {:error, {:refused, {:subject_unavailable, ^missing}}} =
               ReceiptEmitter.emit_command(w, package(w), ["touch", marker],
                 subject_source: subject().path
               )

      # An existing directory that is not a git repository is the same refusal.
      plain = Path.join(dir, "not-a-repo")
      File.mkdir_p!(plain)
      w2 = wo("PLAIN")

      assert {:error, {:refused, {:subject_unavailable, _}}} =
               ReceiptEmitter.emit_command(w2, package(w2), ["touch", marker],
                 subject_source: plain
               )

      refute File.exists?(marker)
    end

    test "relative subject sources and seed files beside a subject are refused",
         %{marker: marker} do
      w = wo("REL")

      assert {:error, {:refused, :invalid_subject_source}} =
               ReceiptEmitter.emit_command(w, package(w), ["touch", marker],
                 subject_source: "relative/path"
               )

      assert {:error, {:refused, :seed_files_with_subject}} =
               ReceiptEmitter.emit_command(w, package(w), ["touch", marker],
                 subject_source: subject().path,
                 seed_files: %{"marker.txt" => "overwritten"}
               )

      refute File.exists?(marker)
    end

    test "a resealed receipt that claims another commit is refused" do
      argv = ["true"]
      w = "FORGEDSHA" |> wo() |> pinned(argv)

      assert {:ok, r} =
               ReceiptEmitter.emit_command(w, package(w), argv, subject_source: subject().path)

      forged =
        r
        |> put_in(["consequence", "subject", "sha"], subject().first_sha)
        |> then(&Map.put(&1, "receipt_digest", SemanticJira.digest(&1)))

      assert {:error, _reason} = ReceiptEmitter.verify(forged, w)
    end

    test "a bound receipt replays through the trusted plan and the Reconciler option", %{log: log} do
      argv = ["sh", "-c", "cat marker.txt"]
      w = "REPLAY" |> wo(%{"replay_required" => true}) |> pinned(argv)
      {:ok, plan} = ReceiptEmitter.command_plan(w, argv, subject_source: subject().path)

      assert {:ok, r} = ReceiptEmitter.emit(w, package(w), plan)
      assert r["replay"]["passed"] == true
      assert {:ok, _} = ReceiptEmitter.replay(r, work_order: w, plan: plan)

      assert {:ok, %{"to" => "ALIVE"}, :appended} =
               Reconciler.reconcile(w, r, log, require_sealed: true, replay_plan: plan)
    end
  end

  describe "package CONTENT is enforced, not only the package's self-digest" do
    setup %{marker: marker} do
      w = wo("PKG")
      %{w: w, pkg: package(w), marker: marker}
    end

    test "control: rebuilding an unedited package (fresh digest) is admitted", %{w: w, pkg: pkg} do
      same = rebuilt(pkg, & &1)
      assert same.shape_digest == pkg.shape_digest
      assert {:ok, r} = ReceiptEmitter.emit_command(w, same, ["true"])
      assert r["identity"]["package_digest"] == pkg.shape_digest
    end

    test "worker == verifier violates worker_not_verifier", %{w: w, pkg: pkg, marker: marker} do
      same_identity =
        rebuilt(pkg, fn attrs ->
          policies =
            Enum.map(attrs["policies"], fn
              %{"rule" => "worker_not_verifier"} = p -> %{p | "verifier" => p["worker"]}
              p -> p
            end)

          %{attrs | "policies" => policies}
        end)

      assert same_identity.shape_digest != pkg.shape_digest

      assert {:error, {:refused, :package_worker_not_verifier_violated}} =
               ReceiptEmitter.emit_command(w, same_identity, ["touch", marker])

      refute File.exists?(marker)
    end

    test "a package naming another repository or base is refused", %{
      w: w,
      pkg: pkg,
      marker: marker
    } do
      other_repo =
        rebuilt(pkg, fn attrs ->
          %{attrs | "bindings" => [%{"repository" => "evil/repo", "base_sha" => subject().sha}]}
        end)

      assert {:error, {:refused, :package_binding_mismatch}} =
               ReceiptEmitter.emit_command(w, other_repo, ["touch", marker])

      moved_base =
        rebuilt(pkg, fn attrs ->
          bad = String.duplicate("b", 40)

          policies =
            Enum.map(attrs["policies"], fn
              %{"rule" => "base_must_not_move"} = p -> %{p | "base_sha" => bad}
              p -> p
            end)

          %{attrs | "policies" => policies}
        end)

      assert {:error, {:refused, :package_base_policy_mismatch}} =
               ReceiptEmitter.emit_command(w, moved_base, ["touch", marker])

      refute File.exists?(marker)
    end

    test "a package without its policies, or for another work order's actions, is refused", %{
      w: w,
      pkg: pkg,
      marker: marker
    } do
      no_policies = rebuilt(pkg, &%{&1 | "policies" => []})

      assert {:error, {:refused, :package_base_policy_mismatch}} =
               ReceiptEmitter.emit_command(w, no_policies, ["touch", marker])

      other_action =
        rebuilt(pkg, fn attrs ->
          actions = Enum.map(attrs["actions"], &%{&1 | "work_order_id" => "SOMETHING-ELSE"})
          %{attrs | "actions" => actions}
        end)

      assert {:error, {:refused, :package_action_mismatch}} =
               ReceiptEmitter.emit_command(w, other_action, ["touch", marker])

      wrong_replay = rebuilt(pkg, &%{&1 | "provenance" => %{"replay_identity" => "rid-other"}})

      assert {:error, {:refused, :package_content_mismatch}} =
               ReceiptEmitter.emit_command(w, wrong_replay, ["touch", marker])

      refute File.exists?(marker)
    end

    test "a package with bytes that have no JSON encoding is refused", %{
      w: w,
      pkg: pkg,
      marker: marker
    } do
      broken = %{pkg | source_digest: <<255, 254>>}

      assert {:error, {:refused, :package_not_json_safe}} =
               ReceiptEmitter.emit_command(w, broken, ["touch", marker])

      refute File.exists?(marker)
    end
  end

  describe "prepared authority is a claim until the caller's verifier vouches for it" do
    setup do
      argv = ["sh", "-c", "grep -q subject-head marker.txt"]
      w = "AUTH" |> wo(%{"authority_requirement" => "human_approval"}) |> pinned(argv)
      %{w: w, argv: argv}
    end

    test "a fabricated authority receipt runs but is never evidence, so promotion is refused",
         %{w: w, argv: argv, log: log} do
      assert {:ok, r} =
               ReceiptEmitter.emit_command(w, package(w), argv,
                 subject_source: subject().path,
                 authority_receipt: prepared_for(w, "made-up-by-the-plan-author")
               )

      assert r["authority"]["verified"] == false
      assert r["authority"]["level"] == "NONE"
      refute Map.has_key?(r["evidence"], "authority_receipt")
      assert r["evidence"]["binding"]["authority"] == false
      assert r["target"] == "PARTIAL_ALIVE"

      assert {:error, {:refused, {:promotion_refused, failed}}} =
               Reconciler.reconcile(w, r, log, require_sealed: true)

      assert :authority in failed
      assert TransitionLog.read(log) == []
    end

    test "a verifier that rejects, raises or answers nonsense refuses before anything runs",
         %{w: w, marker: marker} do
      prepared = prepared_for(w)
      opts = fn verifier -> [authority_receipt: prepared, authority_verifier: verifier] end

      assert {:error, {:refused, {:authority_unverified, ":unknown_authority"}}} =
               ReceiptEmitter.emit_command(
                 w,
                 package(w),
                 ["touch", marker],
                 opts.(fn _prepared, _admitted -> {:error, :unknown_authority} end)
               )

      assert {:error, {:refused, {:authority_verifier_failed, "boom"}}} =
               ReceiptEmitter.emit_command(
                 w,
                 package(w),
                 ["touch", marker],
                 opts.(fn _prepared, _admitted -> raise "boom" end)
               )

      assert {:error, {:refused, {:authority_verifier_invalid, ":maybe"}}} =
               ReceiptEmitter.emit_command(
                 w,
                 package(w),
                 ["touch", marker],
                 opts.(fn _prepared, _admitted -> :maybe end)
               )

      assert {:error, {:refused, {:authority_verifier_invalid, _}}} =
               ReceiptEmitter.emit_command(
                 w,
                 package(w),
                 ["touch", marker],
                 opts.(:not_a_function)
               )

      refute File.exists?(marker)
    end

    test "a prepared receipt without an authority identity is not prepared", %{
      w: w,
      marker: marker
    } do
      prepared = w |> prepared_for() |> Map.delete("authority_identity")

      assert {:error, {:refused, :authority_not_prepared}} =
               ReceiptEmitter.emit_command(w, package(w), ["touch", marker],
                 authority_receipt: prepared
               )

      refute File.exists?(marker)
    end

    test "verified authority + pinned commands + the exact subject is ALIVE", %{
      w: w,
      argv: argv,
      log: log
    } do
      allowed = ["authority:1"]

      verifier = fn prepared, admitted ->
        if prepared["authority_identity"] in allowed and
             prepared["work_order_digest"] == admitted["work_order_digest"],
           do: :ok,
           else: {:error, :not_allowed}
      end

      assert {:ok, r} =
               ReceiptEmitter.emit_command(w, package(w), argv,
                 subject_source: subject().path,
                 authority_receipt: prepared_for(w),
                 authority_verifier: verifier
               )

      assert r["authority"]["verified"] == true
      assert r["evidence"]["authority_receipt"]["status"] == "prepared"
      assert r["target"] == "ALIVE"

      assert {:ok, %{"to" => "ALIVE"}, :appended} =
               Reconciler.reconcile(w, r, log, require_sealed: true)
    end
  end
end
