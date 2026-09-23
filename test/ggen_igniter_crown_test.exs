defmodule GgenIgniter.CrownTest do
  @moduledoc """
  Chicago-style proof for the W6-A8 crown glue: every stage of the closed
  loop executes REAL code against the REAL pack graph, the REAL SHACL court,
  and the REAL kernel — no fixture stubbing of the machinery under test.

  The synthetic sensing document mimics exactly the document
  `Xaas.Ultracode.Sensing.derive/2` emits for a failing pytest suite; the
  crown run itself consumes the real one.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Crown
  alias GgenIgniter.SemanticJira.Shacl

  @ontology_path "priv/ggen/semantic-jira-pack/ontology.ttl"
  @shapes_path "priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl"
  @seed_sha "b40964e70a8f87296fe7d69bad999aad02e06f19"

  @sensing_doc %{
    "schemaVersion" => "xaas-sensing/1",
    "head" => @seed_sha,
    "profile" => "failing_tests",
    "items" => [
      %{
        "id" => "fail-test-normalize-label-collapses-inner-whitespace-abc123",
        "goal" =>
          "The test suite reports this failure when sensed:\n\n" <>
            "    tests/test_w6_crown_seed.py::test_normalize_label_collapses_inner_whitespace\n\n" <>
            "Make the failing test pass WITHOUT weakening, skipping, or deleting it.",
        "allowed_paths" => ["src/eds/crown.py", "tests/test_w6_crown_seed.py"],
        "source" => %{"file" => "suite-output", "line" => nil, "text" => "FAILED"}
      }
    ]
  }

  @attrs %{
    "repository" => "local/eds",
    "base_sha" => @seed_sha,
    "replay_tag" => "crown-test:v1"
  }

  defp revised_graph_text do
    {:ok, manufactured} = Crown.manufacture(@sensing_doc, @attrs)

    # The canonical graph on this branch already carries the crown section
    # (the manufacture commit); strip it so the test exercises a fresh
    # append onto the pre-crown baseline.
    base =
      @ontology_path
      |> File.read!()
      |> String.split("# ── W6-A8 crown")
      |> List.first()

    Crown.append_to_graph(base, Crown.render_turtle(manufactured))
  end

  defp write_revised_graph do
    text = revised_graph_text()
    path = Path.join(System.tmp_dir!(), "crown-graph-#{System.unique_integer([:positive])}.ttl")
    File.write!(path, text)
    path
  end

  defp receipt_facts_for(crown_001) do
    %{
      "work_order_digest" => crown_001["work_order_digest"],
      "subject_sha" => String.duplicate("1", 40),
      "candidate_sha" => String.duplicate("2", 40),
      "receipt_iri" => "urn:xaas:ultracode:receipt:crown-test",
      "receipt_digest" => "sha256:" <> String.duplicate("c", 64),
      "receipt_class" => "verification"
    }
  end

  defp evidence_for(crown_001, observed) do
    %{
      "work_order_digest" => crown_001["work_order_digest"],
      "subject" => crown_001["subject"],
      "repository" => crown_001["repository"],
      "base_sha" => crown_001["base_sha"],
      "court_results" => Map.new(crown_001["required_courts"], &{&1, %{"passed" => true}}),
      "evidence_types" => crown_001["required_evidence"],
      "acceptance_results" => Map.new(crown_001["acceptance"], &{&1, true}),
      "falsifier_results" => Map.new(crown_001["falsifiers"], &{&1, "survived"}),
      "receipt_classes" => crown_001["required_receipt_classes"],
      "evidence_ceiling" => crown_001["evidence_ceiling"],
      "observed_execution" => observed,
      "inherited_standing" => false
    }
  end

  describe "observation -> candidate work orders" do
    test "manufacture admits primary + dependent through the kernel with digests" do
      {:ok, manufactured} = Crown.manufacture(@sensing_doc, @attrs)

      assert %{"work_order_digest" => "sha256:" <> digest} = manufactured["primary"]
      assert Regex.match?(~r/\A[0-9a-f]{64}\z/, digest)
      assert manufactured["primary"]["standing"] == "UNKNOWN"
      assert manufactured["primary"]["base_sha"] == @seed_sha

      assert manufactured["dependent"]["dependencies"] == [
               %{
                 "upstream" => "CROWN-001",
                 "type" => "requiresSemanticIdentity",
                 "required_standing" => "ALIVE"
               }
             ]

      assert Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, manufactured["sensing_digest"])
    end

    test "manufacture refuses a non-sensing document and an empty item list" do
      assert {:error, {:refused_manufacture, {:sensing_schema, "other/1"}}} =
               Crown.manufacture(%{"schemaVersion" => "other/1", "items" => []}, @attrs)

      assert {:error, {:refused_manufacture, :empty_sensing_items}} =
               Crown.manufacture(%{@sensing_doc | "items" => []}, @attrs)
    end
  end

  describe "canonical graph admission (SHACL)" do
    test "the graph revised with the manufactured work orders conforms" do
      text = revised_graph_text()
      path = Path.join(System.tmp_dir!(), "crown-shacl-#{System.unique_integer([:positive])}.ttl")
      File.write!(path, text)
      report = Shacl.validate_file(path, @shapes_path)
      File.rm(path)

      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"
      assert report.violations == []
    end
  end

  describe "graph -> kernel extraction -> frontier" do
    test "dependent is blocked before the upstream is ALIVE and eligible after" do
      path = write_revised_graph()
      {:ok, work_orders} = Crown.extract_work_orders(path)

      assert Map.has_key?(work_orders, "CROWN-001")
      assert Map.has_key?(work_orders, "CROWN-002")
      assert work_orders["CROWN-001"]["standing"] == "UNKNOWN"

      before = Crown.frontier(Map.values(work_orders), %{})

      assert Enum.any?(before.eligible, &(&1["identity"] == "CROWN-001"))
      refute Enum.any?(before.eligible, &(&1["identity"] == "CROWN-002"))

      blocked_002 = Enum.find(before.blocked, &(&1["identity"] == "CROWN-002"))
      assert blocked_002["reason"] == "dependencies_unsatisfied"

      after_evidence = %{
        "CROWN-001" => %{
          "standing" => "ALIVE",
          "receipt_digest" => "sha256:" <> String.duplicate("a", 64)
        }
      }

      work_orders_alive =
        Map.update!(work_orders, "CROWN-001", &Map.put(&1, "standing", "ALIVE"))

      after_frontier = Crown.frontier(Map.values(work_orders_alive), after_evidence)

      refute Enum.any?(after_frontier.eligible, &(&1["identity"] == "CROWN-001"))
      assert Enum.any?(after_frontier.eligible, &(&1["identity"] == "CROWN-002"))
    end
  end

  describe "xaas execution descriptor projection" do
    test "descriptor carries every SemanticWork.admit contract field" do
      path = write_revised_graph()
      {:ok, work_orders} = Crown.extract_work_orders(path)
      crown_001 = work_orders["CROWN-001"]

      {:ok, descriptor} =
        Crown.descriptor(crown_001, "sha256:" <> String.duplicate("b", 64), %{
          "goal" => "Repair observed failing condition",
          "provider" => "zcode",
          "verifier_suite" => "eds-dod",
          "execution_repo_alias" => "eds"
        })

      for key <-
            ~w(work_order_iri checkpoint_iri graph_digest repository_identity execution_repo_alias base_sha goal provider verifier_suite execution_policy dependencies) do
        assert Map.has_key?(descriptor, key), "missing #{key}"
      end

      assert descriptor["execution_policy"] == "autonomic_wave_attempt"
      assert descriptor["repository_identity"] == "local/eds"
      assert descriptor["execution_repo_alias"] == "eds"
      assert descriptor["base_sha"] == @seed_sha
    end
  end

  describe "reconciler: kernel-manufactured standing events" do
    test "transition turtle yields kernel events and a conformant graph" do
      path = write_revised_graph()
      {:ok, work_orders} = Crown.extract_work_orders(path)
      crown_001 = work_orders["CROWN-001"]
      evidence = evidence_for(crown_001, true)
      receipt_facts = receipt_facts_for(crown_001)

      {:ok, transition} = Crown.transition_turtle(crown_001, evidence, receipt_facts)
      assert transition =~ "a sj:StandingTransition"
      assert transition =~ "sj:transitionId \"sha256:"
      assert transition =~ "sj:toStanding \"ALIVE\""

      final_path =
        Path.join(
          System.tmp_dir!(),
          "crown-graph-events-#{System.unique_integer([:positive])}.ttl"
        )

      # The declared standing stays UNKNOWN; the events project the tip.
      File.write!(final_path, File.read!(path) <> transition)

      report = Shacl.validate_file(final_path, @shapes_path)
      assert report.conforms, "violations:\n#{inspect(report.violations, pretty: true)}"

      {:ok, events} = Crown.extract_transitions(final_path)
      assert length(events) == 2

      {:ok, projection} = GgenIgniter.SemanticJira.project_standing(events)
      assert projection == %{"CROWN-001" => "ALIVE"}

      # Frontier on PROJECTED standings: dependent becomes eligible.
      {:ok, after_work_orders} = Crown.extract_work_orders(final_path)

      projected =
        Map.new(after_work_orders, fn {id, wo} ->
          {id, Map.put(wo, "standing", projection[id] || wo["standing"])}
        end)

      after_evidence = %{
        "CROWN-001" => %{
          "standing" => "ALIVE",
          "receipt_digest" => receipt_facts["receipt_digest"]
        }
      }

      after_frontier = Crown.frontier(Map.values(projected), after_evidence)

      refute Enum.any?(after_frontier.eligible, &(&1["identity"] == "CROWN-001"))
      assert Enum.any?(after_frontier.eligible, &(&1["identity"] == "CROWN-002"))

      File.rm(final_path)
    end

    test "promote refuses ALIVE without observed execution (evidence ceiling)" do
      path = write_revised_graph()
      {:ok, work_orders} = Crown.extract_work_orders(path)
      crown_001 = work_orders["CROWN-001"]
      weak_evidence = evidence_for(crown_001, false)

      assert {:error, {:promotion_refused, failed}} =
               Crown.transition_turtle(crown_001, weak_evidence, receipt_facts_for(crown_001))

      assert :ceiling in failed
    end
  end
end
