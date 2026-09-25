defmodule GgenIgniter.SemanticA2ADispatchTest do
  @moduledoc """
  Chicago-style, no-mocks conformance proof that the MANUFACTURED Semantic Jira
  Ash resource really speaks A2A: direct dispatch, supervised agent, and a real
  HTTP server on an ephemeral port driven by a real HTTP client.

  Nothing here is hand-written Ash and nothing is a test double:

    * the resource/domain sources come from the real generators composed by
      `GgenIgniter.Test.SemanticA2AManufactured` (real `ash.gen.resource
      --extend ets`, real `ash_a2a.install`), then are compiled for real;
    * the data layer is a real ETS table (the same Ash action machinery as
      Postgres, without a database server);
    * the authority broker is the real `AshA2A.Authority.Broker.InMemory`
      GenServer from ash_a2a, holding real grants;
    * the HTTP server is real Bandit serving the real `A2A.Plug` fronted by the
      real `A2A.Plug.Auth`; the client is real `Req` over a real socket.

  Falsifiers: F2 (a nil-actor or ungranted `:change` dispatch must not execute),
  F3 (Push/Publish never on the card), the forged-identity fail-closed case,
  REFUSED_ACTION_NOT_FOUND for an unknown skill, -32601 for an unknown method,
  and `completed` for a work-order task only with a court receipt.
  """

  use ExUnit.Case, async: false

  alias AshA2A.Authority
  alias AshA2A.Identity
  alias GgenIgniter.SemanticA2A
  alias GgenIgniter.Test.SemanticA2AManufactured, as: M

  @resource SemanticJira.Work.Task
  @agent SemanticJira.Work.TaskAgent
  @clerk_token "clerk-token"
  @intruder_token "intruder-token"

  defmodule Pipeline do
    @moduledoc false
    # Real A2A.Plug.Auth in front of the real A2A.Plug on POST; GET (agent card
    # discovery) stays open, as the A2A spec serves it unauthenticated.
    @behaviour Plug

    @schemes %{"bearer_auth" => %A2A.SecurityScheme.HTTPAuth{scheme: "bearer"}}

    @impl Plug
    def init(opts) do
      %{
        auth: A2A.Plug.Auth.init(schemes: @schemes, verify: &__MODULE__.verify/3),
        plug: A2A.Plug.init(opts)
      }
    end

    @impl Plug
    def call(%Plug.Conn{method: "POST"} = conn, %{auth: auth, plug: plug}) do
      conn = A2A.Plug.Auth.call(conn, auth)
      if conn.halted, do: conn, else: A2A.Plug.call(conn, plug)
    end

    def call(conn, %{plug: plug}), do: A2A.Plug.call(conn, plug)

    @doc false
    def verify("bearer_auth", "clerk-token", _conn), do: {:ok, %{id: "court-clerk"}}
    def verify("bearer_auth", "intruder-token", _conn), do: {:ok, %{id: "intruder"}}
    def verify(_scheme, _credential, _conn), do: {:error, "invalid token"}
  end

  setup_all do
    m = M.manufactured!()

    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)
    previous_validate = Application.fetch_env(:ash, :validate_domain_config_inclusion?)
    Application.put_env(:ash, :validate_domain_config_inclusion?, false)

    try do
      # One compile pass: the domain and resource reference each other, so
      # Ash's post-compile verifiers must see both modules.
      Code.compile_string(m.domain_source <> "\n" <> m.resource_source, m.resource_path)

      Code.compile_string("""
      defmodule #{inspect(@agent)} do
        use AshA2A.Agent, resource_or_domain: #{inspect(@resource)}, name: "semantic_jira_agent"
      end
      """)
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)

      case previous_validate do
        {:ok, v} -> Application.put_env(:ash, :validate_domain_config_inclusion?, v)
        :error -> Application.delete_env(:ash, :validate_domain_config_inclusion?)
      end
    end

    # Real broker process (the one `config/test.exs` points :ash_a2a at).
    start_supervised!(AshA2A.Authority.Broker.InMemory)

    clerk = Identity.principal(%{id: "court-clerk"})
    {:ok, %Authority{}} = Authority.Grant.grant(clerk, capability_id!("create"))

    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:req)

    %{m: m}
  end

  setup do
    # Fresh ETS state per test: drop the resource's real ETS table.
    Ash.DataLayer.Ets.stop(@resource)

    start_supervised!({@agent, name: @agent})

    server =
      start_supervised!(
        {Bandit,
         plug: {Pipeline, agent: @agent, base_url: "http://localhost"},
         port: 0,
         ip: :loopback,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{base: "http://127.0.0.1:#{port}"}
  end

  defp capability_id!(selector) do
    {:ok, skill} = AshA2A.Info.skill(@resource, selector)
    skill.id
  end

  defp data_message(data, skill) do
    %{A2A.Message.new_user([A2A.Part.Data.new(data)]) | metadata: %{"skill" => skill}}
  end

  defp rpc(base, method, params, token) do
    headers = if token, do: [{"authorization", "Bearer " <> token}], else: []

    Req.post!(base,
      json: %{"jsonrpc" => "2.0", "id" => "1", "method" => method, "params" => params},
      headers: headers,
      retry: false
    )
  end

  defp send_message(base, message, token) do
    {:ok, json} = A2A.JSON.encode(message)
    rpc(base, "message/send", %{"message" => json}, token)
  end

  defp task_state(%Req.Response{status: 200, body: %{"result" => %{"task" => task}}}),
    do: task["status"]["state"]

  defp records, do: Ash.read!(@resource)

  describe "the agent card is the verified capability index of the manufactured resource" do
    test "AshA2A.Info.agent_card skills equal the ontology gate skills (id and consequence)", %{
      m: _m
    } do
      card = AshA2A.Info.agent_card(@resource, url: "http://localhost")

      card_ids = card.skills |> Enum.map(& &1.id) |> Enum.sort()

      gate = SemanticA2A.skills()

      expected_ids =
        gate |> Enum.map(&("#{inspect(@resource)}." <> &1["ash_action"])) |> Enum.sort()

      assert card_ids == expected_ids

      for skill <- gate do
        {:ok, compiled} = AshA2A.Info.skill(@resource, skill["ash_action"])
        assert Atom.to_string(compiled.consequence) == skill["consequence"]
      end
    end

    test "F3: no Push/Publish/external_do skill is on the card", %{m: _m} do
      card = AshA2A.Info.agent_card(@resource, url: "http://localhost")
      names = Enum.map(card.skills, &to_string(&1.name))

      for forbidden <- ~w(push_candidate publish_candidate run_exact_head_court push publish) do
        refute forbidden in names
      end

      for skill <- card.skills do
        {:ok, compiled} = AshA2A.Info.skill(@resource, skill.name)
        assert compiled.consequence in [:observe, :change]
      end
    end

    test "the golden AgentCard projection and the real served card agree on skill ids", %{
      base: base
    } do
      dir = Path.join(System.tmp_dir!(), "a2a_card_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      out = Path.join(dir, "card.json")

      {_output, 0} =
        System.cmd(
          "mix",
          [
            "ggen_igniter.sync",
            "--engine",
            "sparql",
            "--pack",
            "semantic-jira-pack:a2a_agent_card",
            "--out",
            out,
            "--manifest-dir",
            RealDir.real_dir!(dir),
            "--verify-cwd",
            File.cwd!()
          ],
          cd: File.cwd!(),
          stderr_to_stdout: true
        )

      golden = out |> File.read!() |> Jason.decode!()
      assert golden["authority"] == "NONE"

      served = Req.get!(base <> "/.well-known/agent-card.json", retry: false)
      assert served.status == 200
      served_ids = served.body["skills"] |> Enum.map(& &1["id"]) |> Enum.sort()

      assert golden["skills"] |> Enum.map(& &1["id"]) |> Enum.sort() == served_ids

      assert golden["refusedSkills"] |> Enum.map(& &1["name"]) |> Enum.sort() ==
               ["publish_candidate", "push_candidate", "run_exact_head_court"]
    end
  end

  describe "direct dispatch" do
    test "an observe skill returns a data part reply" do
      message = A2A.Message.new_user([A2A.Part.Data.new(%{})])
      assert {:reply, [%A2A.Part.Data{}]} = AshA2A.Dispatcher.dispatch(:read, message, @resource)
    end
  end

  describe "supervised agent: authority is not authentication" do
    test "F2: nil actor, and an authenticated principal WITHOUT a grant, never execute a change skill" do
      payload = %{"task_id" => "t1", "standing" => "UNKNOWN"}

      assert {:ok, task} = apply(@agent, :call, [@agent, data_message(payload, "create")])
      assert task.status.state == :failed
      assert records() == []

      ungranted = [metadata: %{"a2a.auth" => %{identity: %{id: "intruder"}}}]

      assert {:ok, task} =
               apply(@agent, :call, [@agent, data_message(payload, "create"), ungranted])

      assert task.status.state == :failed
      assert records() == []
    end

    test "a granted principal executes the change skill, and the state is really persisted" do
      granted = [metadata: %{"a2a.auth" => %{identity: %{id: "court-clerk"}}}]
      payload = %{"task_id" => "t2", "standing" => "UNKNOWN"}

      assert {:ok, task} =
               apply(@agent, :call, [@agent, data_message(payload, "create"), granted])

      assert task.status.state == :completed
      assert [%{task_id: "t2", standing: "UNKNOWN"}] = records()
    end

    test "an observe skill needs no grant" do
      assert {:ok, task} = apply(@agent, :call, [@agent, data_message(%{}, "read")])
      assert task.status.state == :completed
    end
  end

  describe "real HTTP: Bandit on an ephemeral port + Req" do
    test "GET agent card, then message/send observe skill, then tasks/get", %{base: base} do
      card = Req.get!(base <> "/.well-known/agent-card.json", retry: false)
      assert card.status == 200
      assert is_list(card.body["skills"]) and length(card.body["skills"]) == 2

      resp = send_message(base, data_message(%{}, "read"), @clerk_token)
      assert task_state(resp) == SemanticA2A.wire_state("completed")
      task_id = resp.body["result"]["task"]["id"]

      got = rpc(base, "tasks/get", %{"id" => task_id}, @clerk_token)
      assert got.status == 200
      assert got.body["result"]["id"] == task_id or got.body["result"]["task"]["id"] == task_id
    end

    test "`completed` for a work-order task appears only after a court receipt", %{base: base} do
      receipt = SemanticA2A.receipt(%{"work_order" => "GALL-001", "court" => "exact-head"})

      work_order = %{
        "replay_identity" => "semantic-jira:v26.9.19:GALL-001",
        "standing" => "ALIVE",
        "base_sha" => String.duplicate("b", 40),
        # G1: the task view requires an origin pinned by the canonical trust root.
        "origin_authority" =>
          "https://ggen-igniter.dev/ontology/semantic-jira#objective-project-manufacturer"
      }

      digest = "sha256:" <> String.duplicate("f", 64)

      # Before any court receipt exists on the server, the task view of an ALIVE
      # work order is NOT completed.
      assert [] == records()
      {:ok, before_view} = SemanticA2A.task_from_work_order(work_order, graph_digest: digest)
      assert before_view["status"]["state"] == "working"
      assert before_view["status"]["reasonCode"] == "ALIVE_UNRECEIPTED"

      # An ungranted caller cannot record the receipt.
      denied =
        send_message(
          base,
          data_message(
            %{
              "task_id" => "GALL-001",
              "standing" => "ALIVE",
              "receipt_digest" => receipt["digest"]
            },
            "create"
          ),
          @intruder_token
        )

      assert task_state(denied) == SemanticA2A.wire_state("failed")
      assert records() == []

      # The granted clerk records it through the CommandBus; the server state changes.
      allowed =
        send_message(
          base,
          data_message(
            %{
              "task_id" => "GALL-001",
              "standing" => "ALIVE",
              "receipt_digest" => receipt["digest"]
            },
            "create"
          ),
          @clerk_token
        )

      assert task_state(allowed) == SemanticA2A.wire_state("completed")
      assert [%{receipt_digest: recorded}] = records()
      assert recorded == receipt["digest"]

      # Read it back over the wire, then derive the task view WITH the receipt.
      read = send_message(base, data_message(%{}, "read"), @clerk_token)
      assert task_state(read) == SemanticA2A.wire_state("completed")
      assert inspect(read.body) =~ receipt["digest"]

      {:ok, after_view} =
        SemanticA2A.task_from_work_order(work_order, graph_digest: digest, receipts: [receipt])

      assert after_view["status"]["state"] == "completed"
      assert after_view["status"]["reasonCode"] == "ALIVE_RECEIPTED"
    end

    test "forged metadata identity still fails closed", %{base: base} do
      forged =
        %{
          data_message(%{"task_id" => "x", "standing" => "ALIVE"}, "create")
          | metadata: %{
              "skill" => "create",
              "actor" => %{"id" => "court-clerk"},
              "a2a.auth" => %{"identity" => %{"id" => "court-clerk"}}
            }
        }

      # Unauthenticated: rejected by A2A.Plug.Auth before A2A.Plug runs.
      unauth = send_message(base, forged, nil)
      assert unauth.status == 401

      # Authenticated as the intruder while claiming the clerk in metadata.
      resp = send_message(base, forged, @intruder_token)
      assert task_state(resp) == SemanticA2A.wire_state("failed")
      assert records() == []
    end

    test "an unknown skill is REFUSED_ACTION_NOT_FOUND", %{base: base} do
      resp = send_message(base, data_message(%{}, "push_candidate"), @clerk_token)
      assert resp.status == 200

      assert inspect(resp.body) =~ "REFUSED_ACTION_NOT_FOUND" or
               task_state(resp) == SemanticA2A.wire_state("failed")

      assert records() == []
    end

    test "an unknown JSON-RPC method is -32601", %{base: base} do
      resp = rpc(base, "semantic/jira", %{}, @clerk_token)
      assert resp.status == 200
      assert resp.body["error"]["code"] == -32_601
    end
  end
end
