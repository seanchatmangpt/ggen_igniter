defmodule GgenIgniter.UltracodeTwoPortTest do
  @moduledoc """
  The two-port law for generated UltraCode agents, proven on a REAL consumer
  manufactured from `priv/ggen/ultracode-two-port-pack`:

      forall generated UltraCode agent A:  ExternalSemanticPorts(A) = {SA2A, sJira}

  Chicago-style, no doubles. Real `mix ggen_igniter.sync` subprocesses render
  the consumer; the real compiler builds it; the real SA2A surface is the
  manufactured `SemanticJira.Work.Task` ash_a2a resource over ETS with the real
  `AshA2A.Authority.Broker.InMemory`; the real sJira kernel admits, receipts and
  transitions the work; a real git repository is the local workspace.

  Falsifier of the whole claim: a regenerated consumer that carries an external
  semantic edge outside {SA2A, sJira} and is ACCEPTED -- by the gates (graph
  side) or by the generated firewall (compiled-code side). Both are attacked
  below with deliberately injected violations.
  """

  # async: false -- mutates global Application/System env; real `mix`/`ggen` subprocesses share this checkout's _build/dev; global telemetry/registered-process state.
  use ExUnit.Case, async: false
  @moduletag :integration

  alias AshA2A.Authority
  alias AshA2A.Identity
  alias GgenIgniter.Test.SemanticA2AManufactured, as: SA2A
  alias GgenIgniter.Test.UltracodeTwoPortManufactured, as: M

  @resource SemanticJira.Work.Task
  @agent UltracodeFixture.Agent
  @world UltracodeFixture.Agent.World
  @work UltracodeFixture.Agent.Work
  @capabilities UltracodeFixture.Agent.Capabilities
  @local UltracodeFixture.Agent.Local
  @constructor UltracodeFixture.Agent.Constructor
  @firewall UltracodeFixture.Agent.Firewall
  @origin "https://ggen-igniter.dev/ontology/semantic-jira#objective-code-work-authority"
  @clerk %{id: "ultracode-clerk"}

  setup_all do
    # The SA2A target: the manufactured (never hand-written) ash_a2a resource.
    sa2a = SA2A.manufactured!()
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)
    previous_validate = Application.fetch_env(:ash, :validate_domain_config_inclusion?)
    Application.put_env(:ash, :validate_domain_config_inclusion?, false)

    try do
      Code.compile_string(sa2a.domain_source <> "\n" <> sa2a.resource_source, sa2a.resource_path)
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)

      case previous_validate do
        {:ok, v} -> Application.put_env(:ash, :validate_domain_config_inclusion?, v)
        :error -> Application.delete_env(:ash, :validate_domain_config_inclusion?)
      end
    end

    start_supervised!(AshA2A.Authority.Broker.InMemory)

    {:ok, skill} = AshA2A.Info.skill(@resource, "create")
    {:ok, %Authority{}} = Authority.Grant.grant(Identity.principal(@clerk), skill.id)

    %{m: M.manufactured!(), create_id: skill.id}
  end

  setup do
    Ash.DataLayer.Ets.stop(@resource)
    :ok
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp git_workspace! do
    dir = M.fresh_dir!("ultracode_ws")

    git = fn args ->
      case System.cmd("git", ["-C", dir, "-c", "commit.gpgsign=false" | args],
             stderr_to_stdout: true
           ) do
        {_, 0} -> :ok
        {out, status} -> flunk("git #{inspect(args)} exited #{status}: #{out}")
      end
    end

    git.(["init", "-q"])
    git.(["config", "user.email", "fixture@example.invalid"])
    git.(["config", "user.name", "fixture"])
    File.write!(Path.join(dir, "README.md"), "fixture\n")
    git.(["add", "README.md"])
    git.(["commit", "-q", "-m", "base"])
    {head, 0} = System.cmd("git", ["-C", dir, "rev-parse", "HEAD"])
    {dir, String.trim(head)}
  end

  defp work_order(base_sha, overrides \\ %{}) do
    Map.merge(
      %{
        "identity" => "UC-TWOPORT-001",
        "title" => "Construct one artifact through the two-port world",
        "description" => "Receive work, resolve a capability, construct, evidence, transition.",
        "subject" => "urn:subject:ultracode-two-port",
        "repository" => "seanchatmangpt/ultracode-fixture",
        "base_sha" => base_sha,
        "standing" => "UNKNOWN",
        "evidence_ceiling" => "repository-local",
        "promotion_rule" => "exact subject and independent evidence",
        "replay_identity" => "semantic-jira:ultracode:1",
        "dependencies" => [],
        "required_courts" => ["court:two-port"],
        "required_evidence" => ["source", "verification"],
        "acceptance" => ["acceptance:artifact-written"],
        "falsifiers" => ["falsifier:stale-subject"],
        "projections" => GgenIgniter.SemanticJira.projection_types(),
        "required_receipt_classes" => ["verification"],
        "path_scope" => ["artifacts"],
        "authority_requirement" => "NONE",
        "origin_authority" => @origin,
        "replay_required" => false
      },
      overrides
    )
  end

  defp construct(%{subject: subject, cwd: cwd}) do
    with {:ok, artifact} <-
           mod(Local).write_artifact(
             cwd,
             "artifacts/#{subject["work_order_id"]}.txt",
             "constructed\n"
           ) do
      {:ok, [artifact]}
    end
  end

  defp verify(artifacts) do
    %{
      "court_results" => %{"court:two-port" => %{"passed" => artifacts != []}},
      "evidence_types" => ["source", "verification"],
      "acceptance_results" => %{"acceptance:artifact-written" => artifacts != []},
      "falsifier_results" => %{"falsifier:stale-subject" => "survived"},
      "dependency_evidence" => %{},
      "evidence_ceiling" => "repository-local",
      "observed_execution" => true
    }
  end

  defp bound_receipt(work, final_head),
    do: mod(Work).record_evidence(work, %{"final_head" => final_head})

  defp subject(base_sha),
    do: %{
      "work_order_id" => "UC-TWOPORT-001",
      "repository" => "seanchatmangpt/ultracode-fixture",
      "base_sha" => base_sha
    }

  # Resolved at runtime: the agent is generated AFTER this test file compiles.
  defp mod(name), do: Module.concat(@agent, name)

  defp agent_beams(m),
    do:
      Enum.filter(m.beams, fn {mod, _} ->
        mod |> inspect() |> String.starts_with?(inspect(@agent))
      end)

  # ── 1-2, 13: generation ────────────────────────────────────────────────

  describe "generation" do
    test "every pack template renders, is manifested, and the gates admit the compliant graph", %{
      m: m
    } do
      assert Enum.all?(m.results, &(&1.exit == 0)),
             inspect(Enum.reject(m.results, &(&1.exit == 0)))

      manifest =
        m.dir |> Path.join(".ggen_igniter/manifest.json") |> File.read!() |> Jason.decode!()

      recorded = manifest |> inspect()

      for {_stem, to} <- M.templates() do
        path = Path.join(m.dir, M.fixture_path(to))
        assert File.exists?(path), "missing #{path}"
        assert File.read!(path) =~ "GENERATED by ultracode-two-port-pack"
        assert recorded =~ Path.basename(path)
      end
    end

    test "the generated agent surface is exactly World/Work/Capabilities/Local/Constructor/Firewall",
         %{m: m} do
      assert m.beams |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
               Enum.sort([@capabilities, @constructor, @firewall, @local, @work, @world])

      assert mod(World).external_semantic_ports() == [:sa2a, :sjira]
      assert mod(World).work() == @work
      assert mod(World).capabilities() == @capabilities
      assert mod(World).construction() == @local
    end

    test "no generated source hand-writes Ash or names a concrete provider in agent logic", %{
      m: m
    } do
      for path <- m.sources do
        source = File.read!(path)
        refute source =~ "use Ash.Resource"
        refute source =~ "use Ash.Domain"

        unless String.ends_with?(path, "firewall.ex") do
          # gate 047's closed provider-token list, plus tracker/chat systems.
          refute source =~
                   ~r/\b(github|jira|slack|notion|anthropic|openai|claude|zcode|glm|gemini|codex)\b/i,
                 "provider token in #{path}"
        end
      end
    end
  end

  # ── 3-4: golden path with exact subject ─────────────────────────────────

  describe "golden path: sJira -> SA2A -> CONSTRUCT -> receipt -> sJira" do
    test "a work order is resolved, invoked, constructed, receipted and transitioned", %{
      create_id: create_id
    } do
      {cwd, head} = git_workspace!()
      ocel = Path.join(cwd, "events.ocel.ndjson")
      order = work_order(head)

      assert {:ok, run} =
               mod(Constructor).run(order, "create", &construct/1, &verify/1,
                 cwd: cwd,
                 authority: @clerk,
                 input: %{"task_id" => "UC-TWOPORT-001", "standing" => "UNKNOWN"},
                 ocel: ocel
               )

      # SA2A: the capability was resolved and really executed through AshA2A.
      assert run.resolution["capability"] == create_id
      assert run.resolution["authority"] == "NONE"
      assert [%{task_id: "UC-TWOPORT-001"}] = Ash.read!(@resource)

      # ...and through the BRCE route: a receipted SA2A command bound to the work subject.
      sa2a_receipt = run.invocation["sa2a_receipt"]
      assert sa2a_receipt["capability_id"] == create_id
      assert sa2a_receipt["graph_digest"] == run.work.subject["work_order_digest"]

      # Exact subject survives both ports and the receipt.
      assert run.resolution["subject"] == run.work.subject
      assert run.invocation["subject"] == run.work.subject
      assert run.receipt["subject"]["work_subject"] == run.work.subject
      assert run.work.subject["base_sha"] == head
      assert :ok == mod(Work).verify_evidence([run.receipt])

      # sJira: an append-only transition bound to the receipt and exact head.
      assert run.transition["kind"] == "standing_transition_event"
      assert run.transition["from_standing"] == "UNKNOWN"
      assert run.transition["to_standing"] == "PARTIAL_ALIVE"
      assert run.transition["evidence_identity"] == run.receipt["digest"]
      assert run.transition["final_head"] == head
      assert run.transition["authority"] == "NONE"

      # Local construction happened, and nothing outside cwd.
      [artifact] = run.artifacts
      assert File.read!(Path.join(cwd, artifact["path"])) == "constructed\n"

      # OCEL 2.0 evidence around the whole flow.
      types = Enum.map(run.events, & &1["type"])

      assert types == ~w(work_received capability_requested capability_resolved capability_invoked
                         construction_started construction_completed verification_completed
                         receipt_recorded work_updated)

      logged =
        ocel |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

      assert Enum.map(logged, & &1["type"]) == types

      for event <- logged do
        qualifiers = Enum.map(event["relationships"], & &1["qualifier"])
        assert "work" in qualifiers and "agent" in qualifiers and "subject" in qualifiers
      end
    end

    test "stale subject: work naming base X is never acted on at head Y" do
      {cwd, _head} = git_workspace!()
      stale = String.duplicate("a", 40)

      assert {:error, :stale_subject, [refused]} =
               mod(Constructor).run(work_order(stale), "create", &construct/1, &verify/1,
                 cwd: cwd,
                 authority: @clerk
               )

      assert refused["type"] == "refused"
      assert Ash.read!(@resource) == []
      refute File.exists?(Path.join(cwd, "artifacts"))
    end
  end

  describe "receipt and head binding (court findings 1-3)" do
    setup do
      {cwd, head} = git_workspace!()
      {:ok, work} = mod(Work).get(work_order(head))
      %{cwd: cwd, head: head, work: work}
    end

    test "a genuine receipt bound to this work and head transitions", %{work: work, head: head} do
      receipt = bound_receipt(work, head)

      assert {:ok, %{"final_head" => ^head}} =
               mod(Work).update(work, "PARTIAL_ALIVE", verify([:artifact]), receipt, head)
    end

    test "another work order's receipt is refused", %{work: work, head: head} do
      {:ok, other} = mod(Work).get(work_order(head, %{"identity" => "UC-TWOPORT-002"}))
      foreign = bound_receipt(other, head)

      assert {:error, {:work_update_refused, :receipt_not_bound}} =
               mod(Work).update(work, "PARTIAL_ALIVE", verify([:artifact]), foreign, head)
    end

    test "a fabricated or tampered receipt is refused", %{work: work, head: head} do
      fabricated = %{"digest" => "anything", "subject" => %{"work_subject" => work.subject}}

      tampered =
        put_in(bound_receipt(work, head), ["subject", "final_head"], String.duplicate("0", 40))

      for receipt <- [fabricated, tampered] do
        assert {:error, {:work_update_refused, :receipt_not_bound}} =
                 mod(Work).update(work, "PARTIAL_ALIVE", verify([:artifact]), receipt, head)
      end
    end

    test "a receipt for a different head is refused", %{work: work, head: head} do
      receipt = bound_receipt(work, head)
      other_head = String.duplicate("b", 40)

      assert {:error, {:work_update_refused, :receipt_not_bound}} =
               mod(Work).update(work, "PARTIAL_ALIVE", verify([:artifact]), receipt, other_head)
    end

    test "construction that commits locally transitions at the NEW head, descended from base",
         %{cwd: cwd, head: head} do
      commit_construct = fn %{cwd: cwd} = ctx ->
        {:ok, artifacts} = construct(ctx)
        {:ok, _} = mod(Local).git("add", ["artifacts"], cwd)
        {:ok, _} = mod(Local).git("commit", ["-q", "-m", "constructed"], cwd)
        {:ok, artifacts}
      end

      assert {:ok, run} =
               mod(Constructor).run(work_order(head), "read", commit_construct, &verify/1,
                 cwd: cwd
               )

      {:ok, new_head} = mod(Local).head(cwd)
      refute new_head == head
      assert run.receipt["subject"]["base_head"] == head
      assert run.receipt["subject"]["final_head"] == new_head
      assert run.transition["final_head"] == new_head
    end

    test "a tampered resolution (forged subject or target) is refused at invoke", %{head: head} do
      {:ok, resolution} =
        mod(Capabilities).resolve(%{capability: "read", subject: subject(head)})

      forged = put_in(resolution, ["subject", "repository"], "evil/elsewhere")
      assert {:error, :invalid_requirement} = mod(Capabilities).invoke(forged, %{})

      retargeted = Map.put(resolution, "target", "Other.Target")
      assert {:error, :invalid_requirement} = mod(Capabilities).invoke(retargeted, %{})
      assert {:ok, _} = mod(Capabilities).invoke(resolution, %{})
    end
  end

  # ── 5-7: typed failure, no implicit DO, local primitives ────────────────

  describe "capability plane" do
    test "an unknown capability is a typed :no_capability, never a bypass" do
      {cwd, head} = git_workspace!()

      assert {:error, :no_capability} =
               mod(Capabilities).resolve(%{
                 capability: "publish_candidate",
                 subject: subject(head)
               })

      assert {:error, :no_capability, _} =
               mod(Constructor).run(
                 work_order(head),
                 "publish_candidate",
                 &construct/1,
                 &verify/1,
                 cwd: cwd
               )

      refute File.exists?(Path.join(cwd, "artifacts"))
      assert :no_capability in mod(Capabilities).failures()
    end

    test "an incomplete subject is :invalid_requirement" do
      assert {:error, :invalid_requirement} =
               mod(Capabilities).resolve(%{
                 capability: "read",
                 subject: %{"work_order_id" => "X"}
               })

      assert {:error, :invalid_requirement} = mod(Capabilities).resolve(%{capability: "read"})
    end

    test "an uncompiled SA2A target is :provider_unavailable" do
      assert {:error, :provider_unavailable} =
               mod(Capabilities).resolve(
                 %{capability: "read", subject: subject(String.duplicate("c", 40))},
                 target: NoSuch.Sa2a.Target
               )
    end

    test "resolution never authorizes: a :change capability needs a granted identity" do
      s = subject(String.duplicate("d", 40))
      assert {:ok, resolution} = mod(Capabilities).resolve(%{capability: "create", subject: s})
      assert resolution["requires_authority"]
      assert resolution["authority"] == "NONE"

      input = %{"task_id" => "t-deny", "standing" => "UNKNOWN"}
      assert {:error, :unauthorized} = mod(Capabilities).invoke(resolution, input)

      assert {:error, :unauthorized} =
               mod(Capabilities).invoke(resolution, input, authority: %{id: "intruder"})

      assert Ash.read!(@resource) == []

      assert {:ok, %{"subject" => ^s}} =
               mod(Capabilities).invoke(resolution, input, authority: @clerk)

      assert [%{task_id: "t-deny"}] = Ash.read!(@resource)
    end

    test "an observe capability needs no grant" do
      s = subject(String.duplicate("e", 40))
      assert {:ok, resolution} = mod(Capabilities).resolve(%{capability: "read", subject: s})
      refute resolution["requires_authority"]
      assert {:ok, %{"subject" => ^s}} = mod(Capabilities).invoke(resolution, %{})
    end

    test "consequential actuation (git.push, pr.create) is :unauthorized without authority" do
      s = subject(String.duplicate("f", 40))

      for capability <- ~w(git.push pr.create merge.remote tracker.mutate) do
        assert capability in mod(Capabilities).actuations()

        assert {:error, :unauthorized} =
                 mod(Capabilities).resolve(%{capability: capability, subject: s})
      end

      # With authority it is still only reachable if SA2A actually offers it.
      assert {:error, :no_capability} =
               mod(Capabilities).resolve(%{capability: "git.push", subject: s}, authority: @clerk)
    end
  end

  describe "local construction runtime" do
    test "local git verbs run; network and workspace-escaping verbs are refused" do
      {cwd, head} = git_workspace!()
      assert {:ok, ^head} = mod(Local).head(cwd)
      assert {:ok, _} = mod(Local).git("status", ["--short"], cwd)

      for verb <- ~w(push fetch pull clone remote) do
        assert {:error, {:not_a_local_primitive, ^verb, route: :sa2a}} =
                 mod(Local).git(verb, [], cwd)
      end

      assert {:error, {:not_a_local_primitive, "log", reason: :workspace_override}} =
               mod(Local).git("log", ["-C", "/"], cwd)

      assert {:error, {:path_escape, "../outside.txt"}} =
               mod(Local).write_artifact(cwd, "../outside.txt", "x")
    end
  end

  # ── 8, 11: compiled-code firewall ──────────────────────────────────────

  describe "firewall over the compiled agent" do
    test "ExternalSemanticPorts(agent) = {SA2A, sJira}", %{m: m} do
      assert {:ok, census} = mod(Firewall).check(agent_beams(m))
      assert census.ports == [:sa2a, :sjira]

      assert census.modules ==
               Enum.sort([@capabilities, @constructor, @firewall, @local, @work, @world])

      assert :shell_boundary in census.runtime
    end

    test "check_app/1 (the generated consumer architecture test's entry) over a real app spec", %{
      m: m
    } do
      modules = Enum.map(agent_beams(m), &elem(&1, 0))

      # A real app directory layout (<lib>/ultracode_fixture/ebin) holding the
      # real compiled beams, on the code path, with a loaded app spec.
      ebin = Path.join(M.fresh_dir!("ultracode_app"), "ultracode_fixture/ebin")
      File.mkdir_p!(ebin)
      for {mod, bin} <- agent_beams(m), do: File.write!(Path.join(ebin, "#{mod}.beam"), bin)
      true = :code.add_patha(String.to_charlist(ebin))

      spec = [
        description: ~c"ultracode fixture",
        vsn: ~c"0.0.0",
        modules: modules,
        applications: []
      ]

      :ok = :application.load({:application, :ultracode_fixture, spec})

      on_exit(fn ->
        :application.unload(:ultracode_fixture)
        :code.del_path(String.to_charlist(ebin))
      end)

      assert {:ok, %{ports: [:sa2a, :sjira]}} = mod(Firewall).check_app(:ultracode_fixture)

      architecture_test =
        File.read!(
          Path.join(m.dir, "test/ultracode_fixture/ultracode_fixture_agent_architecture_test.exs")
        )

      assert architecture_test =~ "Firewall.check_app(:ultracode_fixture)"
    end

    test "FALSIFIER: an injected direct HTTP edge is named and refused; removing it restores :ok",
         %{m: m} do
      evil =
        M.compile_string!("""
        defmodule UltracodeFixture.Agent.Evil do
          def publish(url), do: Req.post(url, json: %{})
          def raw(url), do: :httpc.request(String.to_charlist(url))
        end
        """)

      assert {:error, violations} = mod(Firewall).check(agent_beams(m) ++ evil)

      assert Enum.any?(
               violations,
               &match?({:forbidden_direct_edge, UltracodeFixture.Agent.Evil, Req, _}, &1)
             )

      assert Enum.any?(violations, &match?({:forbidden_direct_edge, _, :httpc, _}, &1))

      assert {:ok, _} = mod(Firewall).check(agent_beams(m))
    end

    test "FALSIFIER: an unknown dependency is refused by default-deny", %{m: m} do
      evil =
        M.compile_string!("""
        defmodule UltracodeFixture.Agent.Sprawl do
          def card(r), do: Igniter.Test.test_project(app_name: r)
          def pack(s), do: GgenIgniter.Pack.fetch_pack!(s, [])
        end
        """)

      assert {:error, violations} = mod(Firewall).check(agent_beams(m) ++ evil)
      targets = for {:forbidden_direct_edge, _, to, _} <- violations, do: to
      assert Igniter.Test in targets
      assert GgenIgniter.Pack in targets
    end

    test "FALSIFIER: shell outside Local, and dynamic dispatch, are refused", %{m: m} do
      evil =
        M.compile_string!("""
        defmodule UltracodeFixture.Agent.Tunnel do
          def curl(url), do: System.cmd("curl", ["-X", "POST", url])
          def hidden(mod, url), do: mod.post(url)
          def applied(url), do: apply(Req, :post, [url])
        end
        """)

      assert {:error, violations} = mod(Firewall).check(agent_beams(m) ++ evil)

      assert Enum.any?(
               violations,
               &match?(
                 {:forbidden_shell_edge, UltracodeFixture.Agent.Tunnel, "System.cmd/" <> _},
                 &1
               )
             )

      assert {:dynamic_dispatch, UltracodeFixture.Agent.Tunnel} in violations
    end

    # Bypass corpus: each module reaches outside {SA2A, sJira} through a channel
    # a naive import scan misses. Every one must be REFUSED.
    for {name, body, expected} <- [
          {"Eval", ~S|def run(u), do: Code.eval_string("Req.post(u)", u: u)|,
           {:forbidden_direct_edge, Code}},
          {"ErlEval", ~S|def run(f), do: :erl_eval.exprs(f, [])|,
           {:forbidden_direct_edge, :erl_eval}},
          {"Loader", ~S|def run(b), do: :code.load_binary(Evil, ~c"evil", b)|,
           {:forbidden_direct_edge, :code}},
          {"Message", ~S|def run(pid, u), do: send(pid, {:post, u})|, :dynamic_dispatch},
          {"Call", ~S|def run(u), do: GenServer.call(:http_pool, {:post, u})|,
           {:forbidden_direct_edge, GenServer}},
          {"Supervised", ~S|def run(s, u), do: Task.Supervisor.async(s, Req, :post, [u])|,
           {:forbidden_direct_edge, Task.Supervisor}},
          {"Timer", ~S|def run(u), do: :timer.apply_after(0, Req, :post, [u])|,
           :dynamic_dispatch},
          {"Nif", ~S|def run(p), do: :erlang.load_nif(p, 0)|, :dynamic_dispatch},
          {"ProcLib", ~S|def run(u), do: :proc_lib.spawn(Req, :post, [u])|,
           {:forbidden_direct_edge, :proc_lib}},
          {"Capture", ~S|def run, do: &Req.post/1|, {:forbidden_direct_edge, Req}},
          {"LiteralAtom", ~S|def run(u), do: :"Elixir.Req".post(u)|,
           {:forbidden_direct_edge, Req}},
          {"Import", ~S|import Req, only: [post: 1]
                         def run(u), do: post(u)|, {:forbidden_direct_edge, Req}},
          {"Delegate", ~S|defdelegate run(u), to: Req, as: :post|, {:forbidden_direct_edge, Req}},
          {"Closure", ~S|def run(u), do: spawn(fn -> :gen_tcp.connect(~c"h", 80, []) && u end)|,
           {:forbidden_direct_edge, :gen_tcp}},
          {"Os", ~S|def run(c), do: :os.cmd(c)|, {:forbidden_direct_edge, :os}}
        ] do
      @bypass_name name
      @bypass_body body
      @bypass_expected expected
      test "FALSIFIER bypass corpus: #{name} is refused", %{m: m} do
        module = Module.concat(UltracodeFixture.Agent.Bypass, @bypass_name)

        evil =
          M.compile_string!("""
          defmodule #{inspect(module)} do
            #{@bypass_body}
          end
          """)

        assert {:error, violations} = mod(Firewall).check(agent_beams(m) ++ evil)

        case @bypass_expected do
          :dynamic_dispatch ->
            assert {:dynamic_dispatch, module} in violations

          {:forbidden_direct_edge, to} ->
            assert Enum.any?(violations, &match?({:forbidden_direct_edge, ^module, ^to, _}, &1)),
                   inspect(violations)
        end
      end
    end

    test "FALSIFIER: raw inet_tcp, remote-node spawn (incl. Node.spawn), and agent-named shims are refused",
         %{m: m} do
      evil =
        M.compile_string!("""
        defmodule UltracodeFixture.Agent.Raw do
          def tcp(h), do: :inet_tcp.connect(h, 443, [])
          def remote(n), do: :erlang.spawn(n, fn -> :ok end)
          def node(n), do: Node.spawn(n, fn -> :ok end)
          def shim(u), do: Shim.UltracodeFixture.Agent.post(u)
        end
        """)

      assert {:error, violations} = mod(Firewall).check(agent_beams(m) ++ evil)
      raw = UltracodeFixture.Agent.Raw
      assert Enum.any?(violations, &match?({:forbidden_direct_edge, ^raw, :inet_tcp, _}, &1))
      # Node.spawn/2 is inlined to :erlang.spawn/2 -- refused as a hidden edge.
      assert {:dynamic_dispatch, raw} in violations

      assert Enum.any?(
               violations,
               &match?({:forbidden_direct_edge, ^raw, Shim.UltracodeFixture.Agent, _}, &1)
             )
    end

    test "FALSIFIER: a protocol impl for an agent type (named after the protocol) is still guarded",
         %{m: m} do
      evil =
        M.compile_string!("""
        defmodule UltracodeFixture.Agent.Payload do
          defstruct [:url]
        end

        defimpl String.Chars, for: UltracodeFixture.Agent.Payload do
          def to_string(%{url: url}), do: inspect(Req.post(url))
        end
        """)

      assert {:error, violations} = mod(Firewall).check(agent_beams(m) ++ evil)

      assert Enum.any?(
               violations,
               &match?(
                 {:forbidden_direct_edge, String.Chars.UltracodeFixture.Agent.Payload, Req, _},
                 &1
               )
             )
    end

    test "FALSIFIER: an SA2A internal (receipt store) is not the SA2A port", %{m: m} do
      evil =
        M.compile_string!("""
        defmodule UltracodeFixture.Agent.Internals do
          def peek(id), do: AshA2A.ReceiptStore.Memory.fetch(id, [])
        end
        """)

      assert {:error,
              [
                {:forbidden_direct_edge, UltracodeFixture.Agent.Internals,
                 AshA2A.ReceiptStore.Memory, _}
              ]} =
               mod(Firewall).check(agent_beams(m) ++ evil)
    end

    test "FALSIFIER: a module without debug info cannot be proven and fails closed", %{m: m} do
      opaque =
        M.compile_string!(
          """
          defmodule UltracodeFixture.Agent.Opaque do
            def ok, do: :ok
          end
          """,
          false
        )

      assert {:error, [{:no_debug_info, UltracodeFixture.Agent.Opaque}]} =
               mod(Firewall).check(agent_beams(m) ++ opaque)
    end
  end

  # ── 9: graph-side falsifiers ────────────────────────────────────────────

  describe "gates refuse a violating agent graph before any byte is written" do
    for {fixture, code} <- [
          {"neg_direct_github.ttl", "FORBIDDEN_DIRECT_EDGE"},
          {"neg_missing_sa2a.ttl", "MISSING_CAPABILITY_PORT"},
          {"neg_foreign_work_port.ttl", "FOREIGN_WORK_PORT"},
          {"neg_unmediated_push.ttl", "UNMEDIATED_ACTUATION"},
          {"neg_network_verb.ttl", "NETWORK_VERB_IN_LOCAL_PRIMITIVE"},
          {"neg_extra_prefix.ttl", "EXTRA_PORT_PREFIX"},
          {"neg_stray_port.ttl", "FOREIGN_PORT"},
          {"neg_extra_runtime.ttl", "EXTRA_RUNTIME_APP"},
          {"neg_unknown_verb.ttl", "UNSANCTIONED_LOCAL_VERB"},
          {"neg_malformed_target.ttl", "MALFORMED_AGENT"},
          {"neg_missing_capability_name.ttl", "MISSING_CAPABILITY_NAME"},
          {"neg_two_agents.ttl", "MULTIPLE_AGENTS"}
        ] do
      @fixture fixture
      @code code
      test "#{fixture} -> #{code}" do
        %{dir: dir, results: results} = M.render!([@fixture])

        for r <- results do
          assert r.exit != 0, "#{r.stem} rendered despite #{@fixture}"
          assert r.output =~ "REFUSED_TWO_PORT_TOPOLOGY"
          assert r.output =~ @code
        end

        assert M.sources(dir) == []
        assert Path.wildcard(Path.join(dir, "{config,test}/**/*.exs")) == []
      end
    end

    test "only_invalid_agent.ttl (no compliant agent at all) -> typed MISSING_CAPABILITY_PORT" do
      %{dir: dir, results: results} = M.render!(["only_invalid_agent.ttl"], nil, agent: false)

      for r <- results do
        assert r.exit != 0
        assert r.output =~ "REFUSED_TWO_PORT_TOPOLOGY"
        assert r.output =~ "MISSING_CAPABILITY_PORT"
      end

      assert M.sources(dir) == []
    end

    test "the pack alone (no agent declared) renders nothing" do
      %{dir: dir, results: results} = M.render!([], nil, agent: false)
      assert Enum.all?(results, &(&1.exit != 0))
      assert M.sources(dir) == []
    end

    test "an injected sa2aTarget never reaches generated code" do
      marker = "/tmp/ultracode_injected"
      File.rm(marker)
      %{dir: dir} = M.render!(["neg_malformed_target.ttl"])
      assert M.sources(dir) == []
      refute File.exists?(marker)
    end
  end

  # ── 10: regeneration ────────────────────────────────────────────────────

  describe "regeneration" do
    test "deleting and regenerating reproduces byte-identical, still-compliant output", %{m: m} do
      originals = Map.new(M.sources(m.dir), &{Path.relative_to(&1, m.dir), File.read!(&1)})

      dir = M.fresh_dir!("ultracode_regen")
      %{results: results} = M.render!([], dir)
      assert Enum.all?(results, &(&1.exit == 0))

      regenerated = Map.new(M.sources(dir), &{Path.relative_to(&1, dir), File.read!(&1)})
      assert regenerated == originals

      for path <- M.sources(dir), do: File.rm!(path)
      assert M.sources(dir) == []

      %{results: again} = M.render!([], dir)
      assert Enum.all?(again, &(&1.exit == 0))
      assert Map.new(M.sources(dir), &{Path.relative_to(&1, dir), File.read!(&1)}) == originals

      beams = M.compile!(M.sources(dir))
      assert {:ok, %{ports: [:sa2a, :sjira]}} = mod(Firewall).check(beams)
    end
  end
end
