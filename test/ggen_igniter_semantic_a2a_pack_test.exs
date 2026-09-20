defmodule GgenIgniter.SemanticA2APackTest do
  @moduledoc """
  Chicago-style, no-mocks proof of the Semantic Jira -> A2A ontology projection.

  Real collaborators throughout: the real pack ontology loaded by the real RDF
  loader, the real pack gates run by BOTH real query engines (pure-Elixir
  `sparql` and the oxigraph NIF), the real SHACL court against the real shapes,
  real files for the violating fixtures, and real sha256 digests. No test
  doubles of any kind; every assertion is on returned/persisted state.

  Falsifiers exercised here: F1 (ALIVE without receipt must not be
  `completed`, in the state function AND in the SHACL court), F3 (a Push/
  Publish-sourced skill must not be exposed), F4 (replay digest stability),
  F6 (state is derived from standing, never the reverse).
  """

  use ExUnit.Case, async: true

  alias GgenIgniter.{Ontology, Query, SemanticA2A}
  alias GgenIgniter.SemanticJira.Shacl

  @ontology "priv/ggen/semantic-jira-pack/ontology.ttl"
  @gates "priv/ggen/semantic-jira-pack/gates"
  @engines [GgenIgniter.Query, GgenIgniter.Query.Oxigraph]

  @standings ~w(UNKNOWN PARTIAL_ALIVE ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED REFUSED)

  setup_all do
    %{graph: Ontology.load!(@ontology)}
  end

  defp gate(graph, engine, name), do: engine.run(graph, File.read!(Path.join(@gates, name)))

  defp violating_report!(mutator) do
    mutated = mutator.(File.read!(@ontology))
    refute mutated == File.read!(@ontology), "fixture mutation did not change the ontology"

    path = Path.join(System.tmp_dir!(), "a2a_fixture_#{System.unique_integer([:positive])}.ttl")
    File.write!(path, mutated)
    on_exit(fn -> File.rm(path) end)
    Shacl.validate_file(path)
  end

  describe "gates on the real ontology" do
    test "skill set equals the exposed actions minus forbidden capabilities, on both engines", %{
      graph: graph
    } do
      for engine <- @engines do
        skills = gate(graph, engine, "060_a2a_skills.rq")

        assert skills |> Enum.map(& &1["skill_name"]) |> Enum.sort() ==
                 ["observe_work_order", "record_court_receipt"],
               "engine #{inspect(engine)}"

        by_name = Map.new(skills, &{&1["skill_name"], &1})
        assert by_name["observe_work_order"]["ash_action"] == "read"
        assert by_name["observe_work_order"]["consequence"] == "observe"
        assert by_name["record_court_receipt"]["ash_action"] == "create"
        assert by_name["record_court_receipt"]["consequence"] == "change"
      end
    end

    test "Push, Publish and the UNSUPPORTED external_do skill are refusals, not skills", %{
      graph: graph
    } do
      for engine <- @engines do
        refusals =
          gate(graph, engine, "062_a2a_refusals.rq") |> Map.new(&{&1["skill_name"], &1["reason"]})

        assert Map.keys(refusals) |> Enum.sort() ==
                 ["publish_candidate", "push_candidate", "run_exact_head_court"]

        assert refusals["push_candidate"] =~ "REFUSED(forbidden-capability)"
        assert refusals["publish_candidate"] =~ "REFUSED(forbidden-capability)"
        # UNSUPPORTED(generator-capability) is a different type from REFUSED.
        assert refusals["run_exact_head_court"] =~ "UNSUPPORTED(generator-capability)"
        refute refusals["run_exact_head_court"] =~ "REFUSED"

        skill_names = gate(graph, engine, "060_a2a_skills.rq") |> Enum.map(& &1["skill_name"])
        refute Enum.any?(Map.keys(refusals), &(&1 in skill_names))
      end
    end

    test "the two engines agree on the state map (order-insensitive)", %{graph: graph} do
      [a, b] = Enum.map(@engines, &(gate(graph, &1, "061_a2a_state_map.rq") |> MapSet.new()))
      assert a == b
      assert MapSet.size(a) == 8
    end

    test "gate 060 stays correct without SHACL: a forbidden-capability skill flipped to exposed is still excluded",
         %{} do
      mutated =
        File.read!(@ontology)
        |> String.replace(
          ~s|a2a:exposed false ;\n    a2a:requiresCapability "Push"|,
          ~s|a2a:exposed true ;\n    a2a:requiresCapability "Push"|
        )

      refute mutated == File.read!(@ontology)
      path = Path.join(System.tmp_dir!(), "a2a_gate_#{System.unique_integer([:positive])}.ttl")
      File.write!(path, mutated)
      on_exit(fn -> File.rm(path) end)

      for engine <- @engines do
        names =
          gate(Ontology.load!(path), engine, "060_a2a_skills.rq") |> Enum.map(& &1["skill_name"])

        refute "push_candidate" in names
      end
    end
  end

  describe "SHACL court on the real ontology and violating fixtures" do
    test "the real ontology conforms and the a2a shapes were actually checked" do
      report = Shacl.validate_file(@ontology)
      assert report.conforms, inspect(report.violations)
      checked = Enum.map(report.shapes_checked, &to_string/1)

      for shape <- ~w(skill_shape state_mapping_shape task_state_shape generator_capability_shape) do
        assert shape in checked
      end
    end

    test "F1: a completed mapping that is not receipt-bound ALIVE is a violation" do
      report =
        violating_report!(fn src ->
          String.replace(
            src,
            ~s|a2a:fromStanding "ALIVE" ; a2a:withReceipt false ; a2a:toState a2a:state-working|,
            ~s|a2a:fromStanding "ALIVE" ; a2a:withReceipt false ; a2a:toState a2a:state-completed|
          )
        end)

      refute report.conforms
      assert Enum.any?(report.violations, &(&1.message =~ "Falsifier F1"))
    end

    test "F3: an exposed skill sourced from a forbidden capability is a violation" do
      report =
        violating_report!(fn src ->
          String.replace(
            src,
            ~s|a2a:exposed false ;\n    a2a:requiresCapability "Publish"|,
            ~s|a2a:exposed true ;\n    a2a:requiresCapability "Publish"|
          )
        end)

      refute report.conforms
      assert Enum.any?(report.violations, &(&1.message =~ "forbidden capability"))
    end

    test "duplicate skill ids are a violation" do
      report =
        violating_report!(fn src ->
          String.replace(
            src,
            ~s|a2a:skillName "push_candidate"|,
            ~s|a2a:skillName "observe_work_order"|
          )
        end)

      refute report.conforms
      assert Enum.any?(report.violations, &(&1.message =~ "unique"))
    end

    test "a task state outside the TaskState enum is a violation" do
      report =
        violating_report!(fn src ->
          String.replace(src, ~s|a2a:stateValue "rejected"|, ~s|a2a:stateValue "exploded"|)
        end)

      refute report.conforms
    end

    test "a projection claiming authority other than NONE is a violation" do
      report =
        violating_report!(fn src ->
          String.replace(
            src,
            ~s|sj:authorityClaim "NONE" ;\n    a2a:forbidsCapability|,
            ~s|sj:authorityClaim "DO" ;\n    a2a:forbidsCapability|
          )
        end)

      refute report.conforms
    end

    test "UNSUPPORTED without an UNSUPPORTED(generator-capability) reason is a violation" do
      report =
        violating_report!(fn src ->
          String.replace(
            src,
            "UNSUPPORTED(generator-capability): ash_a2a.install cannot emit",
            "cannot emit"
          )
        end)

      refute report.conforms
    end

    test "REFUSED collapsing onto UNSUPPORTED's reason code is a violation" do
      report =
        violating_report!(fn src ->
          String.replace(src, ~s|a2a:reasonCode "REFUSED"|, ~s|a2a:reasonCode "SOMETHING_ELSE"|)
        end)

      refute report.conforms
    end
  end

  describe "standing -> task state, derived from the ontology through SPARQL" do
    test "table: all 7 standings map to the exact state and reason code" do
      map = SemanticA2A.state_map()
      valid = SemanticA2A.receipt(%{"court" => "exact-head"})

      table = [
        {"UNKNOWN", [], "submitted", "UNKNOWN"},
        {"PARTIAL_ALIVE", [], "working", "PARTIAL_ALIVE"},
        {"ALIVE", [valid], "completed", "ALIVE_RECEIPTED"},
        {"ALIVE", [], "working", "ALIVE_UNRECEIPTED"},
        {"BLOCKED", [], "failed", "BLOCKED"},
        {"BUILD_BROKEN", [], "failed", "BUILD_BROKEN"},
        {"REFUSED(policy)", [], "rejected", "REFUSED"},
        {"UNSUPPORTED", [], "rejected", "UNSUPPORTED"}
      ]

      for {standing, receipts, state, reason} <- table do
        assert {:ok, %{state: ^state, reason_code: ^reason}} =
                 SemanticA2A.state_for(standing, receipts, map),
               "standing #{standing} receipts=#{length(receipts)}"
      end

      # every canonical standing has at least one row
      for s <- @standings, do: assert(Enum.any?(map, &(&1.standing == s)), s)
    end

    test "UNSUPPORTED and REFUSED share a state but never a reason code" do
      {:ok, u} = SemanticA2A.state_for("UNSUPPORTED", [])
      {:ok, r} = SemanticA2A.state_for("REFUSED(x)", [])
      assert u.state == "rejected" and r.state == "rejected"
      refute u.reason_code == r.reason_code
    end

    test "F1: ALIVE with a forged (digest-mismatched) receipt is not completed" do
      forged = %{"digest" => "sha256:" <> String.duplicate("0", 64), "subject" => %{}}
      assert {:ok, %{state: "working"}} = SemanticA2A.state_for("ALIVE", [forged])
      assert {:error, {:refused, _}} = SemanticA2A.admit_completion("ALIVE", [forged])
      assert {:error, {:refused, _}} = SemanticA2A.admit_completion("ALIVE", [])

      assert {:error, {:refused, _}} =
               SemanticA2A.admit_completion("UNKNOWN", [SemanticA2A.receipt(%{})])

      assert :ok = SemanticA2A.admit_completion("ALIVE", [SemanticA2A.receipt(%{"a" => 1})])
    end

    test "an unmapped standing is a typed error, not a guess" do
      assert {:error, {:unmapped_standing, "MADE_UP"}} = SemanticA2A.state_for("MADE_UP", [])
    end

    test "the state map comes from the graph: mutating the ontology changes the derived state" do
      mutated =
        File.read!(@ontology)
        |> String.replace(
          ~s|a2a:fromStanding "BLOCKED" ; a2a:toState a2a:state-failed|,
          ~s|a2a:fromStanding "BLOCKED" ; a2a:toState a2a:state-input-required|
        )

      refute mutated == File.read!(@ontology)
      path = Path.join(System.tmp_dir!(), "a2a_map_#{System.unique_integer([:positive])}.ttl")
      File.write!(path, mutated)
      on_exit(fn -> File.rm(path) end)

      assert {:ok, %{state: "input-required"}} =
               SemanticA2A.state_for("BLOCKED", [], SemanticA2A.state_map(path))

      assert {:ok, %{state: "failed"}} = SemanticA2A.state_for("BLOCKED", [])
    end
  end

  describe "receipt chain and task projection" do
    test "F4: the receipt chain replays to an identical digest and tamper breaks it" do
      build = fn ->
        r1 =
          SemanticA2A.receipt(%{
            "work_order" => "GALL-001",
            "n" => 1,
            "nested" => %{"b" => 2, "a" => 1}
          })

        r2 = SemanticA2A.receipt(%{"work_order" => "GALL-001", "n" => 2}, r1["digest"])
        [r1, r2]
      end

      chain = build.()
      assert chain == build.()
      assert :ok = SemanticA2A.verify_chain(chain)
      assert Enum.all?(chain, &String.match?(&1["digest"], ~r/\Asha256:[0-9a-f]{64}\z/))

      # key order in the subject must not change the digest (canonical JSON)
      assert SemanticA2A.receipt(%{"a" => 1, "b" => 2})["digest"] ==
               SemanticA2A.receipt(%{"b" => 2, "a" => 1})["digest"]

      [r1, r2] = chain
      tampered = put_in(r2, ["subject", "n"], 3)
      assert {:error, {:broken_chain, 1}} = SemanticA2A.verify_chain([r1, tampered])
      assert {:error, {:broken_chain, 0}} = SemanticA2A.verify_chain([r2, r1])
    end

    test "task_from_work_order carries replay URN, graph digest and package identity; replay is stable" do
      dir = Path.join(System.tmp_dir!(), "a2a_task_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      File.write!(Path.join(dir, "work-order.ttl"), File.read!(@ontology))

      artifact = %{id: "a", digest: "sha256:" <> String.duplicate("a", 64), kind: "projection"}
      package = SemanticA2A.execution_package(dir, [artifact])
      graph_digest = "sha256:" <> String.duplicate("f", 64)

      work_order = %{
        "replay_identity" => "semantic-jira:v26.9.19:GALL-001",
        "standing" => "UNKNOWN",
        "base_sha" => String.duplicate("b", 40)
      }

      {:ok, task} =
        SemanticA2A.task_from_work_order(work_order, graph_digest: graph_digest, package: package)

      assert task["taskId"] == "urn:semantic-jira:v26.9.19:GALL-001"
      assert task["contextId"] == graph_digest
      assert task["status"] == %{"state" => "submitted", "reasonCode" => "UNKNOWN"}
      assert task["metadata"]["baseSha"] == work_order["base_sha"]
      assert task["metadata"]["graphDigest"] == graph_digest
      assert task["metadata"]["schema"] == package.schema
      assert task["metadata"]["authority"] == "NONE"
      assert [%{"kind" => "data", "data" => %{"package_digest" => pd}}] = task["input"]
      assert pd == package.package_digest

      assert {:ok, ^task} =
               SemanticA2A.task_from_work_order(work_order,
                 graph_digest: graph_digest,
                 package: package
               )
    end

    test "F6: standing is the only input; a task-state-shaped standing is unmapped, never inferred" do
      for state <- ~w(completed working submitted rejected failed) do
        assert {:error, {:unmapped_standing, ^state}} = SemanticA2A.state_for(state, [])
      end

      assert {:error, {:missing_field, "standing"}} =
               SemanticA2A.task_from_work_order(
                 %{"replay_identity" => "x:y", "base_sha" => "b", "status" => "completed"},
                 graph_digest: "sha256:0"
               )
    end
  end

  describe "the a2a_agent_card projection type" do
    test "is a registered Semantic Jira projection with authority NONE" do
      assert "a2a_agent_card" in GgenIgniter.SemanticJira.projection_types()

      rows =
        Query.run(
          Ontology.load!(@ontology),
          """
          PREFIX sj: <https://ggen-igniter.dev/ontology/semantic-jira#>
          SELECT ?a WHERE { ?s sj:projectionType "a2a_agent_card" ; sj:authorityClaim ?a }
          """
        )

      assert [%{"a" => "NONE"}] = rows
    end
  end
end
