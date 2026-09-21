defmodule GgenIgniter.SemanticJiraDescriptorBridgeTest do
  @moduledoc """
  Chicago-style proofs for the frontier -> XaaS -> reconciler bridge.

  Every collaborator is real: the real reconciler and ndjson ledger, the real
  SHACL court over the real pack ontology, and real `mix` tasks run in fresh OS
  processes over real files. The XaaS key set is checked against the real
  `Xaas.Ultracode.SemanticWork` source when a checkout is present (a named skip
  otherwise). XaaS receipts are fabricated with a REAL computed digest, never a
  canned one. Assertions are on returned/persisted state.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.SemanticJira
  alias GgenIgniter.SemanticJira.{CourtMap, Descriptor, Ledger, Observation, Reconciler}

  @moduletag timeout: 600_000

  # Copied from Xaas.Ultracode.SemanticWork (@required, @dependency shape,
  # @execution_policies) at xaas PR #56 head 4812714. The next test re-derives
  # them from the real source when it is on disk.
  @xaas_required ~w(work_order_iri checkpoint_iri graph_digest repository_identity execution_repo_alias base_sha goal provider verifier_suite execution_policy dependencies)
  @xaas_dependency_keys ~w(work_order_iri required_standing observed_standing receipt_iri receipt_digest)
  @xaas_path System.get_env(
               "XAAS_SEMANTIC_WORK_PATH",
               "/Users/sac/wt/xaas-56/lib/xaas/ultracode/semantic_work.ex"
             )
  @xaas_present File.exists?(@xaas_path)

  @sj "https://ggen-igniter.dev/ontology/semantic-jira#"
  @repo "seanchatmangpt/ggen_igniter"

  setup do
    dir = Path.join(System.tmp_dir!(), "sj-bridge-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir, ledger: Path.join(dir, "ledger.ndjson")}
  end

  # --- fixtures -------------------------------------------------------------

  defp sha(seed), do: :crypto.hash(:sha, seed) |> Base.encode16(case: :lower)
  defp digest(seed), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, seed), case: :lower)

  defp work_order(id, overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => id,
        "title" => "Bridge test #{id}",
        "description" => "Exercise the descriptor bridge without granting authority.",
        "subject" => "urn:subject:#{id}",
        "repository" => @repo,
        "base_sha" => String.duplicate("a", 40),
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:bridge-test:#{id}",
        "dependencies" => [],
        "required_courts" => ["court:test"],
        "required_evidence" => ["verification"],
        "acceptance" => ["acceptance:test"],
        "falsifiers" => ["falsifier:test"],
        "projections" => SemanticJira.projection_types(),
        "required_receipt_classes" => ["verification"],
        "path_scope" => ["lib/ggen_igniter"],
        "authority_requirement" => "NONE",
        "replay_required" => false
      },
      overrides
    )
  end

  defp dependent(id, upstream, overrides \\ %{}) do
    work_order(
      id,
      Map.merge(
        %{
          "dependencies" => [
            %{"upstream" => upstream, "type" => "requiresReceipt", "required_standing" => "ALIVE"}
          ]
        },
        overrides
      )
    )
  end

  defp fleet, do: [work_order("SJ-A"), dependent("SJ-B", "SJ-A"), work_order("SJ-C")]

  defp opts(extra \\ []),
    do: Keyword.merge([verifier_suite: "aps-dod", aliases: %{@repo => "aps"}], extra)

  defp build!(wos, events, identity, extra \\ []) do
    assert {:ok, descriptor} = Descriptor.build(wos, events, identity, opts(extra))
    descriptor
  end

  defp uuid, do: Ecto.UUID.generate()

  # A sealed XaaS receipt with a REAL digest computed over its own contents.
  defp xaas_receipt(bridge, overrides \\ %{}) do
    base =
      Map.merge(
        %{
          "epoch_id" => uuid(),
          "run_id" => uuid(),
          "receipt_id" => uuid(),
          "outcome" => "alive",
          "final_head" => sha("head:" <> bridge["identity"]),
          "head_verified" => true,
          "fabric_verifier" => %{
            "status" => "pass",
            "steps" => [%{"id" => "court:test", "status" => "pass"}],
            "court_receipt" => %{
              "acceptance_results" => %{"acceptance:test" => true},
              "falsifier_results" => %{"falsifier:test" => "survived"}
            }
          },
          "bridge" => bridge
        },
        overrides
      )

    Map.put(base, "receipt_digest", Descriptor.receipt_digest(base))
  end

  defp settle!(wos, ledger, identity) do
    assert {:ok, events} = Ledger.read(ledger)
    descriptor = build!(wos, events, identity)
    xaas = xaas_receipt(descriptor["bridge"])
    assert {:ok, receipt} = Descriptor.receipt_from_xaas(xaas, descriptor["bridge"])
    assert {:ok, event} = Ledger.reconcile_and_append(wos, ledger, receipt)
    {descriptor, xaas, event}
  end

  defp refusal(result, tag) do
    assert {:error, {^tag, reason}} = result
    reason
  end

  defp write_json!(path, value), do: File.write!(path, Jason.encode!(value))

  # Real `mix` task in a fresh OS process; stdout and stderr captured separately.
  defp mix_task(dir, args) do
    err = Path.join(dir, "stderr-#{System.unique_integer([:positive])}.txt")
    quoted = Enum.map_join(args, " ", &("'" <> String.replace(&1, "'", "'\\''") <> "'"))

    {out, code} =
      System.cmd("sh", ["-c", "MIX_ENV=test mix #{quoted} 2>'#{err}'"],
        cd: File.cwd!(),
        env: [{"MIX_ENV", "test"}]
      )

    {code, last_json(out), last_json(File.read!(err))}
  end

  defp last_json(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "{"))
    |> List.last()
    |> case do
      nil -> nil
      line -> Jason.decode!(line)
    end
  end

  # --- descriptor ------------------------------------------------------------

  describe "descriptor: one admitted frontier candidate becomes the XaaS descriptor" do
    test "carries exactly the XaaS key set, plus only the opaque bridge, and survives JSON" do
      descriptor = build!(fleet(), [], "SJ-A")

      assert descriptor |> Map.keys() |> Enum.sort() == Enum.sort(@xaas_required ++ ["bridge"])
      assert descriptor["provider"] == "zcode"
      assert descriptor["execution_policy"] == "autonomic_wave_attempt"
      assert descriptor["verifier_suite"] == "aps-dod"
      assert descriptor["execution_repo_alias"] == "aps"
      assert descriptor["repository_identity"] == @repo
      assert descriptor["dependencies"] == []
      assert descriptor["work_order_iri"] == "urn:semantic-jira:work-order:SJ-A"

      assert descriptor["checkpoint_iri"] ==
               "urn:semantic-jira:checkpoint:" <> Reconciler.genesis_digest()

      # The shape rules Xaas.Ultracode.SemanticWork.admit/1 enforces.
      assert descriptor["base_sha"] =~ ~r/^[0-9a-f]{40}$/
      assert descriptor["graph_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
      assert descriptor["repository_identity"] =~ ~r/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/
      assert descriptor["execution_repo_alias"] =~ ~r/^[A-Za-z0-9_.-]{1,128}$/
      assert String.contains?(descriptor["work_order_iri"], ":")
      assert String.contains?(descriptor["checkpoint_iri"], ":")
      assert descriptor["goal"] =~ "SJ-A: Bridge test SJ-A"
      assert descriptor["goal"] =~ "acceptance:test"
      assert descriptor["goal"] =~ "falsifier:test"

      assert descriptor == descriptor |> Jason.encode!() |> Jason.decode!()

      bridge = descriptor["bridge"]
      [wo | _] = Enum.filter(fleet(), &(&1["identity"] == "SJ-A"))
      {:ok, admitted} = SemanticJira.admit_work_order(wo)
      assert bridge["identity"] == "SJ-A"
      assert bridge["definition_digest"] == admitted["definition_digest"]
      assert bridge["source_snapshot_digest"] == admitted["work_order_digest"]
      assert bridge["ledger_tail"] == Reconciler.genesis_digest()

      assert bridge["requires"] == %{
               "courts" => ["court:test"],
               "acceptance" => ["acceptance:test"],
               "falsifiers" => ["falsifier:test"],
               "evidence" => ["verification"]
             }
    end

    @tag skip: if(@xaas_present, do: false, else: "XaaS checkout not present at #{@xaas_path}")
    test "the expected key set is what the real Xaas.Ultracode.SemanticWork source declares" do
      source = File.read!(@xaas_path)

      assert [_, required] = Regex.run(~r/@required ~w\(\s*([^)]*?)\s*\)a/s, source)
      assert required |> String.split() |> Enum.sort() == Enum.sort(@xaas_required)

      assert [_, dependency] =
               Regex.run(~r/required = ~w\(([^)]*work_order_iri[^)]*)\)a/, source)

      assert dependency |> String.split() |> Enum.sort() == Enum.sort(@xaas_dependency_keys)
      assert source =~ "@execution_policies [:continuous_epoch_run, :autonomic_wave_attempt]"

      descriptor = build!(fleet(), [], "SJ-A")
      assert Enum.all?(@xaas_required, &Map.has_key?(descriptor, &1))
    end

    test "is deterministic; graph_digest tracks the definitions, checkpoint tracks the ledger",
         %{ledger: ledger} do
      wos = fleet()
      assert build!(wos, [], "SJ-A") == build!(wos, [], "SJ-A")

      changed =
        List.replace_at(wos, 2, work_order("SJ-C", %{"acceptance" => ["acceptance:other"]}))

      refute build!(wos, [], "SJ-A")["graph_digest"] ==
               build!(changed, [], "SJ-A")["graph_digest"]

      before_checkpoint = build!(wos, [], "SJ-C")["checkpoint_iri"]
      settle!(wos, ledger, "SJ-A")
      {:ok, events} = Ledger.read(ledger)
      refute build!(wos, events, "SJ-C")["checkpoint_iri"] == before_checkpoint
      assert build!(wos, events, "SJ-C")["checkpoint_iri"] =~ Reconciler.tail_digest(events)
    end

    test "refuses everything that is not a lawful frontier candidate", %{ledger: ledger} do
      wos = fleet()

      assert {:not_eligible, "SJ-B", "dependencies_unsatisfied"} =
               refusal(Descriptor.build(wos, [], "SJ-B", opts()), :descriptor_refused)

      assert {:not_eligible, "SJ-NOPE", "unknown_identity"} =
               refusal(Descriptor.build(wos, [], "SJ-NOPE", opts()), :descriptor_refused)

      settle!(wos, ledger, "SJ-A")
      {:ok, events} = Ledger.read(ledger)

      assert {:not_eligible, "SJ-A", "standing=ALIVE"} =
               refusal(Descriptor.build(wos, events, "SJ-A", opts()), :descriptor_refused)

      tampered = List.update_at(events, 0, &Map.put(&1, "to", "BLOCKED"))

      assert {:ledger_invalid, _} =
               refusal(Descriptor.build(wos, tampered, "SJ-B", opts()), :descriptor_refused)
    end

    test "nothing is invented: every required option is a distinct typed refusal" do
      wos = fleet()

      assert {:missing_option, :verifier_suite} =
               refusal(
                 Descriptor.build(wos, [], "SJ-A", aliases: %{@repo => "aps"}),
                 :descriptor_refused
               )

      assert {:missing_alias, @repo} =
               refusal(
                 Descriptor.build(wos, [], "SJ-A", verifier_suite: "aps-dod"),
                 :descriptor_refused
               )

      assert {:invalid_option, :verifier_suite} =
               refusal(
                 Descriptor.build(wos, [], "SJ-A", opts(verifier_suite: "Not A Suite")),
                 :descriptor_refused
               )

      assert {:invalid_option, :execution_repo_alias} =
               refusal(
                 Descriptor.build(wos, [], "SJ-A", opts(execution_repo_alias: "bad alias!")),
                 :descriptor_refused
               )

      assert {:ok, %{"execution_repo_alias" => "explicit"}} =
               Descriptor.build(wos, [], "SJ-A", opts(execution_repo_alias: "explicit"))
    end

    test "a dependent's descriptor carries the dependency's real ledger receipt digest", %{
      ledger: ledger
    } do
      wos = fleet()
      {_descriptor_a, xaas_a, event_a} = settle!(wos, ledger, "SJ-A")
      {:ok, events} = Ledger.read(ledger)

      descriptor_b = build!(wos, events, "SJ-B")

      assert [dependency] = descriptor_b["dependencies"]
      assert dependency["work_order_iri"] == "urn:semantic-jira:work-order:SJ-A"
      assert dependency["required_standing"] == "ALIVE"
      assert dependency["observed_standing"] == "ALIVE"
      assert dependency["receipt_digest"] == event_a["receipt_digest"]
      assert dependency["receipt_digest"] == xaas_a["receipt_digest"]
      assert dependency["receipt_iri"] == "urn:semantic-jira:receipt:" <> xaas_a["receipt_digest"]
      assert Enum.sort(Map.keys(dependency)) == Enum.sort(@xaas_dependency_keys)
    end

    test "a dependency requiring a standing XaaS cannot satisfy is refused, not downgraded" do
      wos = [
        work_order("SJ-A"),
        dependent("SJ-B", "SJ-A", %{
          "dependencies" => [
            %{
              "upstream" => "SJ-A",
              "type" => "requiresReceipt",
              "required_standing" => "PARTIAL_ALIVE"
            }
          ]
        })
      ]

      assert {:not_eligible, "SJ-B", "dependencies_unsatisfied"} =
               refusal(Descriptor.build(wos, [], "SJ-B", opts()), :descriptor_refused)
    end
  end

  # --- receipt ---------------------------------------------------------------

  describe "receipt_from_xaas: the sealed XaaS receipt becomes reconciler evidence" do
    test "a good receipt maps field by field and the reconciler applies it", %{ledger: ledger} do
      wos = fleet()
      descriptor = build!(wos, [], "SJ-A")
      xaas = xaas_receipt(descriptor["bridge"])

      assert {:ok, receipt} = Descriptor.receipt_from_xaas(xaas, descriptor["bridge"])

      assert receipt["identity"] == "SJ-A"
      assert receipt["definition_digest"] == descriptor["bridge"]["definition_digest"]
      assert receipt["source_snapshot_digest"] == descriptor["bridge"]["source_snapshot_digest"]
      assert receipt["candidate_sha"] == xaas["final_head"]
      assert receipt["receipt_digest"] == xaas["receipt_digest"]
      assert receipt["target"] == "ALIVE"
      assert receipt["observed_execution"] == true
      assert receipt["inherited_standing"] == false
      assert receipt["evidence_ceiling"] == "repository-local"
      assert receipt["court_results"] == %{"court:test" => %{"passed" => true}}
      assert receipt["acceptance_results"] == %{"acceptance:test" => true}
      assert receipt["falsifier_results"] == %{"falsifier:test" => "survived"}
      assert receipt["receipt_classes"] == ["verification"]
      assert receipt["evidence_types"] == ["exact_head_verification", "verification"]
      assert receipt["xaas"] == Map.take(xaas, ~w(epoch_id run_id receipt_id))

      assert {:ok, event} = Ledger.reconcile_and_append(wos, ledger, receipt)
      assert event["to"] == "ALIVE"
      assert event["receipt_digest"] == xaas["receipt_digest"]
      assert event["candidate_sha"] == xaas["final_head"]
    end

    test "each refusal is distinct and typed" do
      descriptor = build!(fleet(), [], "SJ-A")
      bridge = descriptor["bridge"]

      reason = fn overrides, post ->
        xaas = bridge |> xaas_receipt(overrides) |> post.()
        refusal(Descriptor.receipt_from_xaas(xaas, bridge), :receipt_refused)
      end

      same = & &1

      assert reason.(%{"bridge" => Map.put(bridge, "definition_digest", digest("other"))}, same) ==
               :bridge_mismatch

      assert reason.(%{"bridge" => Map.put(bridge, "identity", "SJ-C")}, same) == :bridge_mismatch
      assert reason.(%{"bridge" => Map.delete(bridge, "requires")}, same) == :bridge_mismatch

      assert reason.(%{"final_head" => "not-a-sha"}, same) == :invalid_final_head
      assert reason.(%{"final_head" => String.duplicate("A", 40)}, same) == :invalid_final_head

      assert reason.(%{}, &Map.put(&1, "final_head", sha("tampered"))) == :receipt_digest_mismatch

      assert reason.(%{}, &put_in(&1, ["fabric_verifier", "status"], "fail")) ==
               :receipt_digest_mismatch

      assert reason.(%{}, &Map.put(&1, "receipt_digest", "sha256:short")) ==
               :invalid_receipt_digest

      assert reason.(%{}, &Map.delete(&1, "receipt_digest")) == :invalid_receipt_digest

      assert reason.(%{"outcome" => "alive", "head_verified" => false}, same) ==
               :alive_without_head_verification

      assert reason.(%{"head_verified" => "yes"}, same) == :head_verified_not_boolean

      assert reason.(%{"fabric_verifier" => %{"status" => "fail", "steps" => []}}, same) ==
               :alive_without_verifier_pass

      assert reason.(%{"fabric_verifier" => %{"status" => "timeout", "steps" => []}}, same) ==
               :alive_without_verifier_pass

      assert reason.(%{"outcome" => "shipped"}, same) == {:unsupported_outcome, "shipped"}
      assert reason.(%{"outcome" => nil}, same) == {:unsupported_outcome, nil}

      assert :not_a_map = refusal(Descriptor.receipt_from_xaas("nope", bridge), :receipt_refused)

      assert {:bridge_invalid, ["ledger_tail"]} =
               refusal(
                 Descriptor.receipt_from_xaas(
                   xaas_receipt(bridge),
                   Map.delete(bridge, "ledger_tail")
                 ),
                 :receipt_refused
               )
    end

    test "acceptance is never inferred from the outcome: missing or false acceptance is refused by promotion",
         %{ledger: ledger} do
      wos = fleet()
      descriptor = build!(wos, [], "SJ-A")
      bridge = descriptor["bridge"]

      no_court_receipt =
        xaas_receipt(bridge, %{
          "fabric_verifier" => %{
            "status" => "pass",
            "steps" => [%{"id" => "court:test", "status" => "pass"}]
          }
        })

      assert {:ok, receipt} = Descriptor.receipt_from_xaas(no_court_receipt, bridge)
      assert receipt["observed_execution"] == true
      assert receipt["acceptance_results"] == %{"acceptance:test" => false}
      assert receipt["falsifier_results"] == %{"falsifier:test" => "unobserved"}

      assert {:promotion_refused, failed} =
               refusal(Ledger.reconcile_and_append(wos, ledger, receipt), :reconcile_refused)

      assert :acceptance in failed
      assert :falsifiers in failed

      false_acceptance =
        xaas_receipt(bridge, %{
          "fabric_verifier" => %{
            "status" => "pass",
            "steps" => [%{"id" => "court:test", "status" => "pass"}],
            "court_receipt" => %{
              "acceptance_results" => %{"acceptance:test" => false},
              "falsifier_results" => %{"falsifier:test" => "killed"}
            }
          }
        })

      assert {:ok, receipt} = Descriptor.receipt_from_xaas(false_acceptance, bridge)
      assert receipt["acceptance_results"] == %{"acceptance:test" => false}
      assert receipt["falsifier_results"] == %{"falsifier:test" => "killed"}

      assert {:promotion_refused, failed} =
               refusal(Ledger.reconcile_and_append(wos, ledger, receipt), :reconcile_refused)

      assert :acceptance in failed

      assert {:ok, []} = Ledger.read(ledger)
    end

    test "a required court passes only on a passing step with that exact id", %{ledger: ledger} do
      wos = fleet()
      bridge = build!(wos, [], "SJ-A")["bridge"]

      for steps <- [
            [],
            [%{"id" => "court:test", "status" => "fail"}],
            [%{"id" => "some-other-step", "status" => "pass"}]
          ] do
        xaas =
          xaas_receipt(bridge, %{
            "fabric_verifier" => %{
              "status" => "pass",
              "steps" => steps,
              "court_receipt" => %{
                "acceptance_results" => %{"acceptance:test" => true},
                "falsifier_results" => %{"falsifier:test" => "survived"}
              }
            }
          })

        assert {:ok, receipt} = Descriptor.receipt_from_xaas(xaas, bridge)
        assert receipt["court_results"] == %{"court:test" => %{"passed" => false}}

        assert {:promotion_refused, failed} =
                 refusal(Ledger.reconcile_and_append(wos, ledger, receipt), :reconcile_refused)

        assert :courts in failed
      end
    end

    test "a failed fabric verifier can never carry acceptance, whatever the court receipt says" do
      bridge = build!(fleet(), [], "SJ-A")["bridge"]

      xaas =
        xaas_receipt(bridge, %{
          "outcome" => "build_broken",
          "fabric_verifier" => %{
            "status" => "fail",
            "steps" => [%{"id" => "court:test", "status" => "pass"}],
            "court_receipt" => %{
              "acceptance_results" => %{"acceptance:test" => true},
              "falsifier_results" => %{"falsifier:test" => "survived"}
            }
          }
        })

      assert {:ok, receipt} = Descriptor.receipt_from_xaas(xaas, bridge)
      assert receipt["target"] == "BUILD_BROKEN"
      assert receipt["observed_execution"] == false
      assert receipt["court_results"] == %{"court:test" => %{"passed" => false}}
      assert receipt["acceptance_results"] == %{"acceptance:test" => false}
      assert receipt["falsifier_results"] == %{"falsifier:test" => "unobserved"}
      assert receipt["evidence_types"] == []
      assert receipt["receipt_classes"] == []
    end

    test "fabric-only evidence cannot reach a higher ceiling than repository-local", %{
      ledger: ledger
    } do
      wos = [work_order("SJ-A", %{"evidence_ceiling" => "hosted-ci"})]
      bridge = build!(wos, [], "SJ-A")["bridge"]

      assert {:ok, receipt} = Descriptor.receipt_from_xaas(xaas_receipt(bridge), bridge)
      assert receipt["evidence_ceiling"] == "repository-local"

      assert {:promotion_refused, failed} =
               refusal(Ledger.reconcile_and_append(wos, ledger, receipt), :reconcile_refused)

      assert :ceiling in failed
    end
  end

  # --- full loop in fresh OS processes -------------------------------------------

  describe "round trip through the real mix tasks" do
    test "descriptor -> XaaS receipt -> reconcile -> frontier advances, all in fresh processes",
         %{
           dir: dir,
           ledger: ledger
         } do
      wos_path = Path.join(dir, "work-orders.json")
      write_json!(wos_path, fleet())
      descriptor_path = Path.join(dir, "descriptor-a.json")

      {0, descriptor, nil} =
        mix_task(dir, [
          "semantic_jira.descriptor",
          "--work-orders",
          wos_path,
          "--ledger",
          ledger,
          "--identity",
          "SJ-A",
          "--alias",
          "#{@repo}=aps",
          "--verifier-suite",
          "aps-dod",
          "--out",
          descriptor_path
        ])

      assert descriptor == descriptor_path |> File.read!() |> Jason.decode!()
      assert descriptor |> Map.keys() |> Enum.sort() == Enum.sort(@xaas_required ++ ["bridge"])

      xaas = xaas_receipt(descriptor["bridge"])
      xaas_path = Path.join(dir, "xaas-receipt-a.json")
      write_json!(xaas_path, xaas)
      receipt_path = Path.join(dir, "receipt-a.json")

      # The whole descriptor is accepted where a bridge is expected.
      {0, receipt, nil} =
        mix_task(dir, [
          "semantic_jira.xaas_receipt",
          "--bridge",
          descriptor_path,
          "--xaas-receipt",
          xaas_path,
          "--out",
          receipt_path
        ])

      assert receipt == receipt_path |> File.read!() |> Jason.decode!()
      assert receipt["receipt_digest"] == xaas["receipt_digest"]

      assert {0, %{"status" => "applied", "event" => event}, nil} =
               mix_task(dir, [
                 "semantic_jira.reconcile",
                 "--work-orders",
                 wos_path,
                 "--ledger",
                 ledger,
                 "--receipt",
                 receipt_path
               ])

      assert event["to"] == "ALIVE"

      assert {0, %{"eligible" => eligible, "standings" => standings, "ledger_tail" => tail}, nil} =
               mix_task(dir, [
                 "semantic_jira.frontier",
                 "--work-orders",
                 wos_path,
                 "--ledger",
                 ledger
               ])

      assert eligible |> Enum.map(& &1["identity"]) |> Enum.sort() == ["SJ-B", "SJ-C"]
      assert standings["SJ-A"] == "ALIVE"
      assert tail == event["event_digest"]

      {0, descriptor_b, nil} =
        mix_task(dir, [
          "semantic_jira.descriptor",
          "--work-orders",
          wos_path,
          "--ledger",
          ledger,
          "--identity",
          "SJ-B",
          "--alias",
          "#{@repo}=aps",
          "--verifier-suite",
          "aps-dod"
        ])

      assert [%{"receipt_digest" => digest}] = descriptor_b["dependencies"]
      assert digest == xaas["receipt_digest"]
      assert descriptor_b["checkpoint_iri"] == "urn:semantic-jira:checkpoint:" <> tail

      # The settled work order is no longer a lawful descriptor subject.
      assert {1, nil, %{"status" => "refused", "reason" => reason}} =
               mix_task(dir, [
                 "semantic_jira.descriptor",
                 "--work-orders",
                 wos_path,
                 "--ledger",
                 ledger,
                 "--identity",
                 "SJ-A",
                 "--alias",
                 "#{@repo}=aps",
                 "--verifier-suite",
                 "aps-dod"
               ])

      assert reason == ["descriptor_refused", ["not_eligible", "SJ-A", "standing=ALIVE"]]
    end

    test "refusals and bad invocations exit non-zero with typed JSON on stderr only", %{
      dir: dir,
      ledger: ledger
    } do
      wos_path = Path.join(dir, "work-orders.json")
      write_json!(wos_path, fleet())
      bridge = build!(fleet(), [], "SJ-A")["bridge"]
      bad = xaas_receipt(bridge) |> Map.put("final_head", sha("tampered"))
      bad_path = Path.join(dir, "bad-xaas.json")
      write_json!(bad_path, bad)
      bridge_path = Path.join(dir, "bridge.json")
      write_json!(bridge_path, bridge)

      assert {1, nil,
              %{"status" => "refused", "reason" => ["receipt_refused", "receipt_digest_mismatch"]}} =
               mix_task(dir, [
                 "semantic_jira.xaas_receipt",
                 "--bridge",
                 bridge_path,
                 "--xaas-receipt",
                 bad_path
               ])

      assert {2, nil, %{"status" => "invalid_invocation", "reason" => "missing --verifier-suite"}} =
               mix_task(dir, [
                 "semantic_jira.descriptor",
                 "--work-orders",
                 wos_path,
                 "--ledger",
                 ledger,
                 "--identity",
                 "SJ-A",
                 "--alias",
                 "#{@repo}=aps"
               ])

      assert {2, nil,
              %{
                "status" => "invalid_invocation",
                "reason" => "--alias must be owner/repo=alias" <> _
              }} =
               mix_task(dir, [
                 "semantic_jira.descriptor",
                 "--work-orders",
                 wos_path,
                 "--ledger",
                 ledger,
                 "--identity",
                 "SJ-A",
                 "--alias",
                 "no-equals-sign",
                 "--verifier-suite",
                 "aps-dod"
               ])

      assert {1, nil,
              %{
                "status" => "refused",
                "reason" => ["descriptor_refused", ["missing_alias", @repo]]
              }} =
               mix_task(dir, [
                 "semantic_jira.descriptor",
                 "--work-orders",
                 wos_path,
                 "--ledger",
                 ledger,
                 "--identity",
                 "SJ-A",
                 "--verifier-suite",
                 "aps-dod"
               ])
    end
  end

  # --- observation ------------------------------------------------------------------

  describe "observation: a finding becomes an admitted candidate WorkOrder" do
    defp finding(seed \\ "delta-1") do
      %{
        "normative_model_digest" => digest("normative"),
        "observed_model_digest" => digest("observed:" <> seed),
        "delta" => "ci: exact-subject court fails on formatting (#{seed})",
        "observation_receipt_digest" => digest("obs-receipt:" <> seed)
      }
    end

    # Reuses the typed court/evidence nodes SJ-001 already has in the real graph.
    defp base_work_order do
      work_order("SJ-BASE", %{
        "required_courts" => [@sj <> "exact-head-projection-court"],
        "required_evidence" => [@sj <> "graph-receipt-evidence"],
        "acceptance" => [@sj <> "canonical-source"],
        "falsifiers" => [@sj <> "projection-gains-authority"],
        "path_scope" => ["lib/ggen_igniter", "test"]
      })
    end

    test "SHACL admits a candidate that reuses the graph's typed nodes, deterministically" do
      assert {:ok, result} = Observation.candidate(finding(), base_work_order())

      wo = result["work_order"]
      assert wo["standing"] == "UNKNOWN"
      assert wo["identity"] =~ ~r/^OBS-[0-9A-F]{12}$/
      assert wo["authority"] == "NONE"
      assert wo["dependencies"] == []
      assert wo["required_courts"] == [@sj <> "exact-head-projection-court"]
      assert [acceptance] = wo["acceptance"]
      assert String.starts_with?(acceptance, @sj <> "obs-")
      assert result["shacl"]["conforms"] == true
      assert "work_order_shape" in result["shacl"]["shapes_checked"]
      assert result["shacl"]["focus_node_count"] > 0
      assert result["turtle"] =~ "a sj:WorkOrder"
      assert result["finding"]["normative_model_mutated"] == false
      assert result["repair"] == nil
      assert {:ok, ^wo} = SemanticJira.admit_work_order(wo)

      assert {:ok, again} = Observation.candidate(finding(), base_work_order())
      assert again == result

      assert {:ok, other} = Observation.candidate(finding("delta-2"), base_work_order())
      refute other["work_order"]["identity"] == wo["identity"]
      refute other["work_order"]["replay_identity"] == wo["replay_identity"]
    end

    test "the kernel's repair lineage adds its guard acceptance criterion" do
      repair = %{
        "failed_receipt_digest" => digest("failed"),
        "hypothesis" => "formatter drift on the touched files",
        "smallest_repair" => "run mix format on the flagged files",
        "permanent_guard" => "format check in the exact-subject court",
        "changed_identities" => ["SJ-BASE"],
        "verifier" => "independent"
      }

      assert {:ok, result} = Observation.candidate(finding(), base_work_order(), repair: repair)
      assert result["repair"]["kind"] == "repair_work_order_candidate"
      assert result["repair"]["blind_rerun_allowed"] == false
      assert length(result["work_order"]["acceptance"]) == 2
      assert result["work_order"]["description"] =~ "Permanent guard: format check"
    end

    test "typed refusals: malformed finding, malformed base, untyped graph node, duplicate identity",
         %{dir: dir} do
      assert {:finding, {:missing_required_field, _}} =
               refusal(
                 Observation.candidate(%{"delta" => "x"}, base_work_order()),
                 :observation_refused
               )

      assert {:base_work_order, {:refused_work_order, _}} =
               refusal(
                 Observation.candidate(finding(), %{"identity" => "X"}),
                 :observation_refused
               )

      untyped = Map.put(base_work_order(), "required_courts", [@sj <> "no-such-court"])

      assert {:shacl_violations, violations} =
               refusal(Observation.candidate(finding(), untyped), :observation_refused)

      assert Enum.any?(violations, &(&1.path == @sj <> "requiresCourt"))

      # Identifier uniqueness is a GLOBAL constraint over the canonical graph: a
      # different finding claiming an identifier that already exists (SJ-001) is
      # refused by the real SPARQL constraint.
      assert {:shacl_violations, dup} =
               refusal(
                 Observation.candidate(finding("delta-3"), base_work_order(), identity: "SJ-001"),
                 :observation_refused
               )

      assert Enum.any?(dup, &(&1.message =~ "unique"))

      # The same finding appended to the graph is the same node: idempotent, not a duplicate.
      {:ok, first} = Observation.candidate(finding(), base_work_order())
      augmented = Path.join(dir, "ontology-with-candidate.ttl")

      File.write!(
        augmented,
        File.read!("priv/ggen/semantic-jira-pack/ontology.ttl") <> "\n" <> first["turtle"]
      )

      assert {:ok, again} =
               Observation.candidate(finding(), base_work_order(), ontology_path: augmented)

      assert again == first
    end

    test "an admitted candidate flows through the frontier into a descriptor with its acceptance in the bridge" do
      assert {:ok, %{"work_order" => candidate}} =
               Observation.candidate(finding(), base_work_order())

      descriptor = build!([candidate], [], candidate["identity"])

      assert descriptor["bridge"]["identity"] == candidate["identity"]
      assert descriptor["bridge"]["requires"]["acceptance"] == candidate["acceptance"]
      assert descriptor["bridge"]["requires"]["falsifiers"] == candidate["falsifiers"]
      assert descriptor["goal"] =~ candidate["identity"]

      assert descriptor["work_order_iri"] ==
               "urn:semantic-jira:work-order:" <> candidate["identity"]
    end

    test "the mix task admits a candidate and refuses bad input without touching the graph", %{
      dir: dir
    } do
      finding_path = Path.join(dir, "finding.json")
      base_path = Path.join(dir, "base.json")
      out_path = Path.join(dir, "candidate.json")
      write_json!(finding_path, finding())
      write_json!(base_path, base_work_order())
      before_ontology = File.read!("priv/ggen/semantic-jira-pack/ontology.ttl")

      assert {0, result, nil} =
               mix_task(dir, [
                 "semantic_jira.observe",
                 "--finding",
                 finding_path,
                 "--base-work-order",
                 base_path,
                 "--out",
                 out_path
               ])

      assert result == out_path |> File.read!() |> Jason.decode!()
      assert result["shacl"]["conforms"] == true
      assert {:ok, direct} = Observation.candidate(finding(), base_work_order())
      assert result["work_order"] == direct["work_order"]

      bad_path = Path.join(dir, "bad-finding.json")
      write_json!(bad_path, %{"delta" => "x"})

      assert {1, nil,
              %{"status" => "refused", "reason" => ["observation_refused", ["finding", _]]}} =
               mix_task(dir, [
                 "semantic_jira.observe",
                 "--finding",
                 bad_path,
                 "--base-work-order",
                 base_path
               ])

      assert {2, nil, %{"status" => "invalid_invocation"}} =
               mix_task(dir, ["semantic_jira.observe", "--finding", finding_path])

      assert File.read!("priv/ggen/semantic-jira-pack/ontology.ttl") == before_ontology
    end
  end

  # --- fabric court receipt (IRI-keyed verdicts witnessed by the fabric) -----

  describe "return edge: fabric court receipt binding" do
    @evidence ~w(https://sj.test#local-execution-evidence https://sj.test#receipt-evidence)

    defp witnessed_wo(id, overrides \\ %{}) do
      work_order(
        id,
        Map.merge(
          %{
            "required_courts" => [@sj <> "exact-head-projection-court"],
            "required_evidence" => @evidence,
            "acceptance" => [@sj <> "obs-acc-delta"],
            "falsifiers" => [@sj <> "obs-fal-delta"]
          },
          overrides
        )
      )
    end

    # A1 court-receipt producer shape: the suite step is named "test"; the
    # fabric court receipt binds each court IRI to that step at the sealed head.
    defp court_sealed_receipt(bridge, overrides \\ %{}) do
      head = sha("head:" <> bridge["identity"])

      court_receipt = %{
        "binding" => %{"suite" => "eds-dod", "step_id" => "test", "head" => head},
        "acceptance_results" => %{(@sj <> "obs-acc-delta") => true},
        "falsifier_results" => %{(@sj <> "obs-fal-delta") => "survived"},
        "court_results" => %{
          (@sj <> "exact-head-projection-court") => %{
            "passed" => true,
            "suite" => "eds-dod",
            "step_id" => "test",
            "head" => head
          }
        }
      }

      fabric =
        Map.merge(
          %{
            "status" => "pass",
            "steps" => [%{"id" => "test", "status" => "pass"}],
            "court_receipt" => court_receipt
          },
          overrides[:fabric] || %{}
        )

      base =
        Map.merge(
          %{
            "epoch_id" => uuid(),
            "run_id" => uuid(),
            "receipt_id" => uuid(),
            "outcome" => "alive",
            "final_head" => head,
            "head_verified" => true,
            "fabric_verifier" => fabric,
            "bridge" => bridge
          },
          Map.delete(overrides, :fabric)
        )

      Map.put(base, "receipt_digest", Descriptor.receipt_digest(base))
    end

    # Tampering helper: recompute the sealed digest over the tampered contents
    # (the digest must cover the map it seals -- same as the fabric does).
    defp resealed(receipt),
      do: Map.put(receipt, "receipt_digest", Descriptor.receipt_digest(receipt))

    test "a fabric court receipt with a passing binding witnesses the court and elevates the required evidence" do
      wo = witnessed_wo("SJ-W1")
      assert {:ok, descriptor} = Descriptor.build([wo], [], "SJ-W1", opts())
      bridge = descriptor["bridge"]
      assert {:ok, receipt} = Descriptor.receipt_from_xaas(court_sealed_receipt(bridge), bridge)

      court_iri = @sj <> "exact-head-projection-court"
      assert get_in(receipt, ["court_results", court_iri, "passed"]) == true
      assert receipt["acceptance_results"][@sj <> "obs-acc-delta"] == true
      assert receipt["falsifier_results"][@sj <> "obs-fal-delta"] == "survived"

      for evidence_iri <- @evidence do
        assert evidence_iri in receipt["evidence_types"]
      end
    end

    test "a court receipt bound to a DIFFERENT head does not witness the court nor elevate evidence" do
      wo = witnessed_wo("SJ-W2")
      assert {:ok, descriptor} = Descriptor.build([wo], [], "SJ-W2", opts())
      bridge = descriptor["bridge"]

      tampered =
        court_sealed_receipt(bridge)
        |> put_in(
          ["fabric_verifier", "court_receipt", "court_results"],
          %{
            (@sj <> "exact-head-projection-court") => %{
              "passed" => true,
              "suite" => "eds-dod",
              "step_id" => "test",
              "head" => sha("some-other-head")
            }
          }
        )
        |> resealed()

      assert {:ok, receipt} = Descriptor.receipt_from_xaas(tampered, bridge)
      court_iri = @sj <> "exact-head-projection-court"
      assert get_in(receipt, ["court_results", court_iri, "passed"]) == false

      for evidence_iri <- @evidence do
        refute evidence_iri in receipt["evidence_types"]
      end
    end

    test "a court receipt bound to a FAILING step does not witness the court" do
      wo = witnessed_wo("SJ-W3")
      assert {:ok, descriptor} = Descriptor.build([wo], [], "SJ-W3", opts())
      bridge = descriptor["bridge"]

      failing_step =
        court_sealed_receipt(bridge)
        |> put_in(["fabric_verifier", "steps"], [%{"id" => "test", "status" => "fail"}])
        |> put_in(["fabric_verifier", "status"], "fail")
        |> Map.put("outcome", "build_broken")
        |> resealed()

      assert {:ok, receipt} = Descriptor.receipt_from_xaas(failing_step, bridge)
      court_iri = @sj <> "exact-head-projection-court"
      assert get_in(receipt, ["court_results", court_iri, "passed"]) == false
    end

    test "the original step-id binding (step id IS the court IRI) still witnesses" do
      wo = witnessed_wo("SJ-W4")

      assert {:ok, descriptor} = Descriptor.build([wo], [], "SJ-W4", opts())
      bridge = descriptor["bridge"]

      legacy =
        xaas_receipt(bridge, %{
          "fabric_verifier" => %{
            "status" => "pass",
            "steps" => [%{"id" => @sj <> "exact-head-projection-court", "status" => "pass"}],
            "court_receipt" => %{
              "acceptance_results" => %{(@sj <> "obs-acc-delta") => true},
              "falsifier_results" => %{(@sj <> "obs-fal-delta") => "survived"}
            }
          }
        })

      assert {:ok, receipt} = Descriptor.receipt_from_xaas(legacy, bridge)
      court_iri = @sj <> "exact-head-projection-court"
      assert get_in(receipt, ["court_results", court_iri, "passed"]) == true

      for evidence_iri <- @evidence do
        assert evidence_iri in receipt["evidence_types"]
      end
    end
  end

  # --- descriptor court_map (upstream mint, fabric consumes) -----------------

  describe "descriptor court_map option" do
    @court_map %{
      "acceptance" => %{"acceptance:test" => %{"test" => "tests/p.py::t_one"}},
      "falsifiers" => %{"falsifier:test" => %{"test" => "tests/p.py::t_two"}},
      "courts" => ["court:test"]
    }

    test "a valid court map projects onto the descriptor and survives JSON round-trip" do
      descriptor = build!(fleet(), [], "SJ-A", court_map: @court_map)
      assert descriptor["court_map"] == @court_map
      assert descriptor == descriptor |> Jason.encode!() |> Jason.decode!()
    end

    test "no court map option means no court_map key (today's behavior)" do
      descriptor = build!(fleet(), [], "SJ-A")
      refute Map.has_key?(descriptor, "court_map")
    end

    test "a foreign acceptance IRI is refused, never trimmed" do
      foreign = Map.put(@court_map, "acceptance", %{"foreign:iri" => %{"test" => "t"}})

      assert {:error,
              {:descriptor_refused,
               {:court_map_refused, {:foreign_iri, "acceptance", "foreign:iri"}}}} =
               Descriptor.build(fleet(), [], "SJ-A", opts(court_map: foreign))
    end

    test "an unknown key is refused" do
      rogue = Map.put(@court_map, "punishment", %{})

      assert {:error,
              {:descriptor_refused, {:court_map_refused, {:unknown_keys, ["punishment"]}}}} =
               Descriptor.build(fleet(), [], "SJ-A", opts(court_map: rogue))
    end

    test "an all-empty court map is refused" do
      assert {:error, {:descriptor_refused, {:court_map_refused, :empty}}} =
               Descriptor.build(fleet(), [], "SJ-A", opts(court_map: %{"courts" => []}))
    end

    test "a malformed predicate is refused" do
      bad = %{"acceptance" => %{"acceptance:test" => %{"regex" => ".*"}}}

      assert {:error,
              {:descriptor_refused,
               {:court_map_refused,
                {:invalid_predicate, "acceptance", "acceptance:test", %{"regex" => ".*"}}}}} =
               Descriptor.build(fleet(), [], "SJ-A", opts(court_map: bad))
    end
  end

  # --- end-to-end: court-mapped descriptor -> fabric receipt -> transition ---

  describe "end-to-end: court map closes the loop the wave-7 crown refused" do
    test "court receipt with binding -> reconcile -> ONE ALIVE transition -> dependent eligible" do
      ledger =
        Path.join(System.tmp_dir!(), "sj-court-e2e-#{System.unique_integer([:positive])}.ndjson")

      upstream = witnessed_wo("SJ-E1")

      dependent =
        work_order("SJ-E2", %{
          "dependencies" => [
            %{
              "upstream" => "SJ-E1",
              "type" => "requiresSemanticIdentity",
              "required_standing" => "ALIVE"
            }
          ]
        })

      wos = [upstream, dependent]

      assert {:ok, descriptor} = Descriptor.build(wos, [], "SJ-E1", opts())
      xaas = court_sealed_receipt(descriptor["bridge"])
      assert {:ok, receipt} = Descriptor.receipt_from_xaas(xaas, descriptor["bridge"])
      assert {:ok, event} = Ledger.reconcile_and_append(wos, ledger, receipt)
      assert event["identity"] == "SJ-E1"
      assert event["from"] == "UNKNOWN"
      assert event["to"] == "ALIVE"

      # ONE transition only; replaying the same receipt is idempotent.
      assert {:ok, :already_applied, ^event} = Ledger.reconcile_and_append(wos, ledger, receipt)
      assert {:ok, events} = Ledger.read(ledger)
      assert length(events) == 1

      {:ok, %{eligible: eligible, blocked: blocked}} = Reconciler.frontier(wos, events)
      assert Enum.any?(eligible, &(&1["identity"] == "SJ-E2"))
      assert Enum.any?(blocked, &(&1["identity"] == "SJ-E1" and &1["reason"] == "standing=ALIVE"))
    end
  end

  # --- court map minting from the ontology -----------------------------------

  describe "mix semantic_jira.court_map: ontology witness facts become the court map" do
    @ttl """
    @prefix sj: <https://ggen-igniter.dev/ontology/semantic-jira#> .
    @prefix dcterms: <http://purl.org/dc/terms/> .

    sj:obs-abc123
        a sj:WorkOrder ;
        dcterms:identifier "CROWN-X-001" ;
        sj:requiresCourt <https://ggen-igniter.dev/ontology/semantic-jira#exact-head-projection-court> ;
        sj:acceptance <https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-acc-a>, <https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-acc-b> ;
        sj:falsifier <https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-fal-a> .

    <https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-acc-a> a sj:AcceptanceCriterion ;
        dcterms:description "acc a" ;
        sj:witnessedBy "tests/test_seed.py::test_a" .

    <https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-acc-b> a sj:AcceptanceCriterion ;
        dcterms:description "acc b" ;
        sj:witnessedBy "tests/test_seed.py::test_b" .

    <https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-fal-a> a sj:Falsifier ;
        dcterms:description "fal a" ;
        sj:witnessedBy "tests/test_seed.py::test_a" .
    """

    test "witnessed acceptance/falsifier nodes project to the fabric court-map shape" do
      assert {:ok, court_map} = CourtMap.from_ontology(@ttl, "CROWN-X-001")

      assert court_map == %{
               "acceptance" => %{
                 "https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-acc-a" => %{
                   "test" => "tests/test_seed.py::test_a"
                 },
                 "https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-acc-b" => %{
                   "test" => "tests/test_seed.py::test_b"
                 }
               },
               "falsifiers" => %{
                 "https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-fal-a" => %{
                   "test" => "tests/test_seed.py::test_a"
                 }
               },
               "courts" => [
                 "https://ggen-igniter.dev/ontology/semantic-jira#exact-head-projection-court"
               ]
             }
    end

    test "an unwitnessed acceptance IRI is a typed refusal, never a partial map" do
      unwitnessed =
        String.replace(@ttl, "sj:witnessedBy \"tests/test_seed.py::test_b\" .", ".")

      assert {:error, {:court_map_refused, {:unwitnessed, iri}}} =
               CourtMap.from_ontology(unwitnessed, "CROWN-X-001")

      assert iri == "https://ggen-igniter.dev/ontology/semantic-jira#obs-abc123-acc-b"
    end

    test "an unknown identity is refused" do
      assert {:error, {:court_map_refused, {:work_order_not_found, "NOPE"}}} =
               CourtMap.from_ontology(@ttl, "NOPE")
    end

    test "the mix task emits the map over a real ontology file" do
      dir = System.tmp_dir!()
      ttl_path = Path.join(dir, "ontology-#{System.unique_integer([:positive])}.ttl")
      File.write!(ttl_path, @ttl)

      {code, out, err} =
        mix_task(dir, [
          "semantic_jira.court_map",
          "--ontology",
          ttl_path,
          "--identity",
          "CROWN-X-001"
        ])

      assert code == 0, "stderr: #{inspect(err)}"

      assert out["courts"] == [
               "https://ggen-igniter.dev/ontology/semantic-jira#exact-head-projection-court"
             ]

      assert map_size(out["acceptance"]) == 2
    end
  end
end
