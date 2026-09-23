defmodule GgenIgniter.SemanticJiraAttestationTest do
  @moduledoc """
  Chicago-style: a real git repository in a tmp dir (its real commits are the
  attested base and subject SHAs), real WorkOrders, real
  `Reconciler.reconcile/4` admission writing a real file-backed transition log,
  the real `semantic-jira-pack` template rendering each Statement, and a real
  JSON Schema validator (JSV, offline: it embeds the draft 2020-12 meta-schemas)
  over the vendored in-toto Statement v1 schema
  (`test/fixtures/in_toto/statement_v1.schema.json`). No mocks and no network:
  replay re-reads the Statement and the log from disk, from a copy, with the
  producer's state discarded.
  """
  use ExUnit.Case, async: true

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{Attestation, Reconciler, TransitionLog}

  @statement_schema Path.expand("fixtures/in_toto/statement_v1.schema.json", __DIR__)
  @predicate_schema Path.expand("../priv/schema/sj_admission.schema.json", __DIR__)
  @court "exact-head-court"
  @acceptance "mix test test/ggen_igniter_semantic_jira_attestation_test.exs"
  @falsifier "revert-makes-acceptance-fail"

  setup do
    root = Path.join(System.tmp_dir!(), "sj_attest_#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    repo = Path.join(root, "repo")
    File.mkdir_p!(repo)
    git!(repo, ~w(init -q))
    File.write!(Path.join(repo, "README.md"), "base\n")
    git!(repo, ~w(add README.md))
    git!(repo, ~w(commit -q -m base))
    base = git!(repo, ~w(rev-parse HEAD))
    File.write!(Path.join(repo, "candidate.ex"), "defmodule Candidate, do: nil\n")
    git!(repo, ~w(add candidate.ex))
    git!(repo, ~w(commit -q -m candidate))
    cand = git!(repo, ~w(rev-parse HEAD))

    %{root: root, log: Path.join(root, "log"), base: base, cand: cand}
  end

  describe "reconcile/4 (emission)" do
    test "every admitted transition writes an in-toto Statement next to its event",
         %{log: log, base: base, cand: cand} do
      root = wo("ROOT", base)
      dep = wo("DEP", base, ["ROOT"])

      assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root, cand), log)
      assert {:ok, _, :appended} = Reconciler.reconcile(dep, receipt(dep, cand), log)

      events = TransitionLog.read(log)
      assert Enum.map(events, & &1["identity"]) == ["ROOT", "DEP"]

      names = log |> File.ls!() |> Enum.reject(&String.ends_with?(&1, ".claim")) |> Enum.sort()

      assert names ==
               events
               |> Enum.flat_map(
                 &[TransitionLog.stem(&1) <> ".intoto.json", TransitionLog.stem(&1) <> ".json"]
               )
               |> Enum.sort()

      for event <- events do
        assert {:ok, statement} = Attestation.read(log, event)
        assert statement["_type"] == "https://in-toto.io/Statement/v1"
        assert statement["predicateType"] == "https://chatmangpt.com/sj/admission/v1"
        assert statement["predicate"]["transition"]["event_digest"] == event["event_digest"]

        assert statement["predicate"]["standing"] == %{
                 "from" => "UNKNOWN",
                 "to" => "ALIVE",
                 "derived_from" => event["receipt_digest"]
               }
      end
    end

    test "a refused transition emits no Statement and no event", %{
      log: log,
      base: base,
      cand: cand
    } do
      dep = wo("DEP", base, ["ROOT"])

      assert {:error, {:refused, {:promotion_refused, failed}}} =
               Reconciler.reconcile(dep, receipt(dep, cand), log)

      assert :dependencies in failed
      assert TransitionLog.read(log) == []
      assert Path.wildcard(Path.join(log, "*.intoto.json")) == []
    end

    test "a receipt naming a non-SHA subject is refused before anything is written",
         %{log: log, base: base, cand: cand} do
      root = wo("ROOT", base)
      bad = Map.put(receipt(root, cand), "candidate_sha", "HEAD")

      assert {:error, {:refused, :invalid_candidate_sha}} = Reconciler.reconcile(root, bad, log)
      assert TransitionLog.read(log) == []
    end

    test "an already-recorded receipt re-emits a Statement lost in the append/emit window",
         %{log: log, base: base, cand: cand} do
      root = wo("ROOT", base)
      r = receipt(root, cand)
      assert {:ok, event, :appended} = Reconciler.reconcile(root, r, log)
      path = Attestation.path(log, event)
      original = File.read!(path)

      File.rm!(path)
      assert {:ok, ^event, :already_recorded} = Reconciler.reconcile(root, r, log)
      assert File.read!(path) == original
    end
  end

  describe "statement/1 (in-toto Statement v1 schema)" do
    test "emitted Statements validate against the vendored in-toto v1 schema and the predicate schema",
         %{log: log, base: base, cand: cand} do
      root = wo("ROOT", base)
      dep = wo("DEP", base, ["ROOT"])
      assert {:ok, _, :appended} = Reconciler.reconcile(root, receipt(root, cand), log)
      assert {:ok, _, :appended} = Reconciler.reconcile(dep, receipt(dep, cand), log)

      statement_schema = schema(@statement_schema)
      predicate_schema = schema(@predicate_schema)

      for event <- TransitionLog.read(log) do
        {:ok, statement} = Attestation.read(log, event)
        assert {:ok, _} = JSV.validate(statement, statement_schema)
        assert {:ok, _} = JSV.validate(statement["predicate"], predicate_schema)

        predicate = statement["predicate"]
        assert predicate["courts"] == [%{"court" => @court, "passed" => true}]
        assert predicate["falsifiers"] == [%{"falsifier" => @falsifier, "result" => "survived"}]
        assert predicate["acceptance"] == [%{"criterion" => @acceptance, "passed" => true}]
        assert predicate["authority"]["granted"] == "NONE"
        assert Enum.all?(predicate["checks"], fn {_, passed} -> passed == true end)
      end
    end

    test "the vendored schema is not vacuous: malformed Statements are refused",
         %{log: log, base: base, cand: cand} do
      root = wo("ROOT", base)
      assert {:ok, event, :appended} = Reconciler.reconcile(root, receipt(root, cand), log)
      {:ok, good} = Attestation.read(log, event)
      statement_schema = schema(@statement_schema)
      [wo_subject, git_subject] = good["subject"]

      malformed = [
        Map.put(good, "_type", "https://in-toto.io/Statement/v0.1"),
        Map.put(good, "subject", []),
        Map.delete(good, "predicateType"),
        Map.put(good, "predicateType", "not a uri"),
        Map.put(good, "subject", [Map.delete(wo_subject, "digest"), git_subject]),
        Map.put(good, "subject", [put_in(wo_subject, ["digest", "sha256"], "ABC"), git_subject]),
        Map.put(good, "subject", [wo_subject, put_in(git_subject, ["digest", "gitCommit"], "abc")]),
        Map.put(good, "predicate", "not an object")
      ]

      assert {:ok, _} = JSV.validate(good, statement_schema)

      for bad <- malformed do
        assert {:error, _} = JSV.validate(bad, statement_schema)

        assert {:error, {:refused_attestation, _}} =
                 Attestation.verify(bad, root, TransitionLog.read(log))
      end
    end
  end

  describe "verify/3 (offline replay)" do
    test "replay from a copy of the log recomputes identical subject digests",
         %{root: tmp, log: log, base: base, cand: cand} do
      root = wo("ROOT", base)
      dep = wo("DEP", base, ["ROOT"])
      assert {:ok, root_event, :appended} = Reconciler.reconcile(root, receipt(root, cand), log)
      assert {:ok, dep_event, :appended} = Reconciler.reconcile(dep, receipt(dep, cand), log)

      copy = Path.join(tmp, "log_copy")
      File.cp_r!(log, copy)
      events = TransitionLog.read(copy)

      for {w, event} <- [{root, root_event}, {dep, dep_event}] do
        bytes = copy |> Attestation.path(event) |> File.read!()
        stored = Jason.decode!(bytes)

        assert {:ok, replayed} = Attestation.verify(bytes, w, events)
        assert replayed["subject"] == stored["subject"]
        assert replayed["event_digest"] == event["event_digest"]

        {:ok, admitted} = SemanticJira.admit_work_order(w)
        "sha256:" <> wo_hex = admitted["work_order_digest"]

        assert stored["subject"] == [
                 %{"name" => "sj:WorkOrder/" <> w["identity"], "digest" => %{"sha256" => wo_hex}},
                 %{"name" => w["repository"], "digest" => %{"gitCommit" => cand}}
               ]
      end
    end

    test "the same decision renders byte-identical Statements in independent logs",
         %{root: tmp, base: base, cand: cand} do
      root = wo("ROOT", base)
      r = receipt(root, cand)
      [a, b] = for n <- ~w(a b), do: Path.join(tmp, "log_" <> n)

      assert {:ok, ea, :appended} = Reconciler.reconcile(root, r, a)
      assert {:ok, eb, :appended} = Reconciler.reconcile(root, r, b)

      bytes = File.read!(Attestation.path(a, ea))
      assert bytes == File.read!(Attestation.path(b, eb))
      assert Attestation.render(Jason.decode!(bytes)) == bytes
    end

    test "a tampered predicate or subject is refused; the untampered Statement is admitted",
         %{log: log, base: base, cand: cand} do
      root = wo("ROOT", base)
      assert {:ok, event, :appended} = Reconciler.reconcile(root, receipt(root, cand), log)
      {:ok, good} = Attestation.read(log, event)
      events = TransitionLog.read(log)

      assert {:ok, %{"decision" => "ADMITTED"}} = Attestation.verify(good, root, events)

      tampered = [
        {put_in(good, ["predicate", "courts"], [%{"court" => @court, "passed" => false}]),
         {:predicate_mismatch, ["courts"]}},
        {put_in(good, ["predicate", "falsifiers"], [
           %{"falsifier" => @falsifier, "result" => "refuted"}
         ]), {:predicate_mismatch, ["falsifiers"]}},
        {put_in(good, ["predicate", "authority", "granted"], "DO"),
         {:predicate_mismatch, ["authority"]}},
        {put_in(good, ["predicate", "standing", "to"], "PARTIAL_ALIVE"),
         {:predicate_mismatch, ["standing"]}},
        {put_in(good, ["predicate", "lease"], "granted-by-tamper"),
         {:predicate_mismatch, ["lease"]}},
        {update_in(good, ["subject"], fn [w, g] ->
           [put_in(w, ["digest", "sha256"], String.duplicate("0", 64)), g]
         end), {:subject_mismatch, ["sj:WorkOrder/ROOT"]}},
        {update_in(good, ["subject"], fn [w, g] ->
           [w, put_in(g, ["digest", "gitCommit"], base)]
         end), {:subject_mismatch, [root["repository"]]}},
        {Map.put(good, "predicateType", "https://slsa.dev/provenance/v1"),
         {:unknown_predicate_type, "https://slsa.dev/provenance/v1"}}
      ]

      for {bad, reason} <- tampered do
        assert Attestation.verify(bad, root, events) == {:error, {:refused_attestation, reason}}
      end

      # tampering the embedded receipt detaches it from the logged transition
      forged =
        put_in(
          good,
          ["predicate", "receipt", "evidence", "falsifier_results", @falsifier],
          "refuted"
        )

      assert {:error, {:refused_attestation, {:receipt_not_logged, _}}} =
               Attestation.verify(forged, root, events)

      # tampering the bytes on disk is refused on a fresh read
      path = Attestation.path(log, event)

      File.write!(
        path,
        String.replace(File.read!(path), ~s("granted":"NONE"), ~s("granted":"DO"))
      )

      assert {:error, {:refused_attestation, {:predicate_mismatch, ["authority"]}}} =
               Attestation.verify(File.read!(path), root, TransitionLog.read(log))
    end

    test "replay against a different WorkOrder definition is refused",
         %{log: log, base: base, cand: cand} do
      root = wo("ROOT", base)
      assert {:ok, event, :appended} = Reconciler.reconcile(root, receipt(root, cand), log)
      {:ok, statement} = Attestation.read(log, event)
      redefined = Map.put(root, "acceptance", [@acceptance, "sneaky"])

      assert {:error, {:refused_attestation, {:replay_refused, :definition_mismatch}}} =
               Attestation.verify(statement, redefined, TransitionLog.read(log))

      assert {:error, {:refused_attestation, {:receipt_not_logged, _}}} =
               Attestation.verify(statement, root, [])
    end
  end

  defp wo(id, base, deps \\ []) do
    %{
      "identity" => id,
      "title" => id,
      "description" => "C11 attestation fixture #{id}",
      "subject" => "subj-#{id}",
      "repository" => "seanchatmangpt/ggen_igniter",
      "base_sha" => base,
      "standing" => "UNKNOWN",
      "evidence_ceiling" => "observed",
      "promotion_rule" => "all_courts",
      "replay_identity" => "rid-#{id}",
      "required_courts" => [@court],
      "required_evidence" => ["exec"],
      "acceptance" => [@acceptance],
      "falsifiers" => [@falsifier],
      "projections" => ["jira"],
      "dependencies" =>
        Enum.map(
          deps,
          &%{"upstream" => &1, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
        )
    }
  end

  defp receipt(w, cand) do
    {:ok, definition} = SemanticJira.definition_digest(w)
    {:ok, admitted} = SemanticJira.admit_work_order(w)

    %{
      "definition_digest" => definition,
      "snapshot_digest" => admitted["work_order_digest"],
      "target" => "ALIVE",
      "candidate_sha" => cand,
      "evidence" => %{
        "subject" => w["subject"],
        "repository" => w["repository"],
        "base_sha" => w["base_sha"],
        "evidence_types" => ["exec"],
        "court_results" => %{@court => %{"passed" => true}},
        "acceptance_results" => %{@acceptance => true},
        "falsifier_results" => %{@falsifier => "survived"},
        "receipt_classes" => [],
        "evidence_ceiling" => "observed",
        "observed_execution" => true
      }
    }
  end

  defp schema(path), do: path |> File.read!() |> Jason.decode!() |> JSV.build!()

  defp git!(dir, args) do
    {out, 0} =
      System.cmd(
        "git",
        [
          "-c",
          "commit.gpgsign=false",
          "-c",
          "user.name=sj",
          "-c",
          "user.email=sj@example.invalid"
        ] ++
          args,
        cd: dir,
        stderr_to_stdout: true
      )

    String.trim(out)
  end
end
