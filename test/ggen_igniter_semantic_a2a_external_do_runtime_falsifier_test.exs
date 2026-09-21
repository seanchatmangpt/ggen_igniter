defmodule GgenIgniter.SemanticA2AExternalDoRuntimeFalsifierTest do
  @moduledoc """
  QUALIFIER runtime falsifiers for the manufactured `external_do` court skill
  (errc/external-do-capability). Real manufacture, real compile, real Ash ETS,
  real ash_a2a CommandBus, real `AshA2A.ReceiptStore.Memory` GenServer, real
  broker. No test doubles.

  Falsifier (expected to FAIL until fixed):

    * R2: replaying an already-executed court message after the receipt store
      process is killed and restarted must not execute the court again. The
      F10 replay test only proves dedup for the lifetime of one store process.

  Characterizations (PASS, C4 is a plain negative control; they pin observed behavior that bounds what F10
  can be read to claim, and will flag a change in either direction):

    * C1: a retry that mints a fresh message id re-executes the court unless
      ash_a2a's `actuation_dedup` mode is set to `:strict`; the default is
      `:declared`, which the manufactured surface does not tighten.
    * C2: a granted court call whose Ash update fails still commits a receipt
      with `terminal_status: :executed`; the honest field is `status`.
    * C4: a judge identity forged in message metadata, sent over real HTTP
      under the intruder or clerk token or none, is refused with no state
      change and no receipt.
    * C3: nothing in the manufactured resource validates that ALIVE standing
      carries a receipt: the court skill records `standing: "ALIVE"` from a
      bare claim and stores any string as `receipt_digest`.
  """

  use ExUnit.Case, async: false

  alias AshA2A.Authority
  alias AshA2A.Identity
  alias GgenIgniter.Test.SemanticA2AManufactured, as: M

  @resource SemanticJira.Work.Task
  @agent SemanticJira.Work.TaskAgent

  defmodule Pipeline do
    @moduledoc false
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

    start_supervised!(AshA2A.Authority.Broker.InMemory)

    clerk = Identity.principal(%{id: "court-clerk"})
    {:ok, %Authority{}} = Authority.Grant.grant(clerk, capability_id!("create"))
    judge = Identity.principal(%{id: "court-judge"})
    {:ok, %Authority{}} = Authority.Grant.grant(judge, capability_id!("update"))

    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:req)

    %{m: m}
  end

  setup do
    Ash.DataLayer.Ets.stop(@resource)
    start_supervised!({@agent, name: @agent})
    :ok
  end

  defp capability_id!(selector) do
    {:ok, skill} = AshA2A.Info.skill(@resource, selector)
    skill.id
  end

  defp data_message(data, skill) do
    %{A2A.Message.new_user([A2A.Part.Data.new(data)]) | metadata: %{"skill" => skill}}
  end

  defp as_principal(id), do: [metadata: %{"a2a.auth" => %{identity: %{id: id}}}]

  defp records, do: Ash.read!(@resource)

  defp seed_task!(task_id) do
    assert {:ok, task} =
             @agent.call(
               @agent,
               data_message(%{"task_id" => task_id, "standing" => "UNKNOWN"}, "create"),
               as_principal("court-clerk")
             )

    assert task.status.state == :completed
    [record] = Enum.filter(records(), &(&1.task_id == task_id))
    record
  end

  defp court_message(data), do: data_message(data, "update")

  defp receipt_for(message),
    do: AshA2A.ReceiptStore.Memory.fetch(Identity.command(message.message_id))

  defp judge(message), do: @agent.call(@agent, message, as_principal("court-judge"))

  test "R2: after the receipt store process restarts, replaying an executed message does not re-execute" do
    record = seed_task!("r2")
    message = court_message(%{"id" => record.id, "standing" => "ALIVE"})

    assert {:ok, first} = judge(message)
    assert first.status.state == :completed
    assert {:ok, %AshA2A.Receipt{receipt_id: id}} = receipt_for(message)

    # Kill the real store process; its supervisor restarts it empty.
    pid = Process.whereis(AshA2A.ReceiptStore.Memory)
    assert is_pid(pid)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000

    wait_until(fn -> is_pid(Process.whereis(AshA2A.ReceiptStore.Memory)) end)

    assert {:ok, _again} = judge(message)

    case receipt_for(message) do
      {:ok, %AshA2A.Receipt{receipt_id: ^id}} ->
        :ok

      other ->
        flunk("court re-executed after store restart; receipt now #{inspect(other, limit: 8)}")
    end
  end

  test "C1: a fresh message id re-executes the court unless actuation_dedup is :strict" do
    record = seed_task!("c1")
    data = %{"id" => record.id, "standing" => "ALIVE"}

    first = court_message(data)
    retry = court_message(data)
    refute first.message_id == retry.message_id

    assert {:ok, _} = judge(first)
    assert {:ok, %AshA2A.Receipt{terminal_status: :executed}} = receipt_for(first)

    assert {:ok, _} = judge(retry)
    assert {:ok, %AshA2A.Receipt{terminal_status: :executed} = second} = receipt_for(retry)
    refute second.metadata[:outcome] == :deduplicated

    # The same retry IS a dedup once ash_a2a is told to key on the effect alone.
    record2 = seed_task!("c1-strict")
    data2 = %{"id" => record2.id, "standing" => "ALIVE"}
    previous = Application.fetch_env(:ash_a2a, :actuation_dedup)
    Application.put_env(:ash_a2a, :actuation_dedup, :strict)

    on_exit(fn ->
      case previous do
        {:ok, v} -> Application.put_env(:ash_a2a, :actuation_dedup, v)
        :error -> Application.delete_env(:ash_a2a, :actuation_dedup)
      end
    end)

    strict_one = court_message(data2)
    strict_two = court_message(data2)
    assert {:ok, _} = judge(strict_one)
    assert {:ok, _} = judge(strict_two)
    assert {:ok, %AshA2A.Receipt{} = deduped} = receipt_for(strict_two)
    assert deduped.metadata[:outcome] == :deduplicated
  end

  test "C2: a granted court call whose Ash update fails still commits terminal_status :executed" do
    message = court_message(%{"id" => Ash.UUID.generate(), "standing" => "ALIVE"})

    assert {:ok, task} = judge(message)
    assert task.status.state == :input_required
    assert records() == []

    assert {:ok, %AshA2A.Receipt{} = receipt} = receipt_for(message)
    assert receipt.status == :input_required
    assert receipt.terminal_status == :executed
  end

  test "C3: the court skill records ALIVE with a receipt_digest that is not a digest" do
    record = seed_task!("c3")

    garbage =
      court_message(%{
        "id" => record.id,
        "standing" => "ALIVE",
        "receipt_digest" => "not-a-digest"
      })

    assert {:ok, task} = judge(garbage)
    assert task.status.state == :completed

    stored = Enum.find(records(), &(&1.id == record.id))
    assert stored.standing == "ALIVE"
    assert stored.receipt_digest == "not-a-digest"
    refute String.starts_with?(stored.receipt_digest, "sha256:")
  end

  test "C4: over real HTTP a forged judge identity in message metadata does not authorize the court" do
    record = seed_task!("c4")

    server =
      start_supervised!(
        {Bandit,
         plug: {Pipeline, agent: @agent, base_url: "http://localhost"},
         port: 0,
         ip: :loopback,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    base = "http://127.0.0.1:#{port}"

    forged =
      %{
        court_message(%{"id" => record.id, "standing" => "ALIVE"})
        | metadata: %{
            "skill" => "update",
            "actor" => %{"id" => "court-judge"},
            "principal" => %{"id" => "court-judge"},
            "a2a.auth" => %{"identity" => %{"id" => "court-judge"}}
          }
      }

    {:ok, json} = A2A.JSON.encode(forged)

    for token <- ["intruder-token", "clerk-token", nil] do
      headers = if token, do: [{"authorization", "Bearer " <> token}], else: []

      resp =
        Req.post!(base,
          json: %{
            "jsonrpc" => "2.0",
            "id" => "1",
            "method" => "message/send",
            "params" => %{"message" => json}
          },
          headers: headers,
          retry: false
        )

      if token do
        assert get_in(resp.body, ["result", "task", "status", "state"]) in [
                 "TASK_STATE_FAILED",
                 "failed"
               ],
               "token #{token}: #{inspect(resp.body, limit: 12)}"
      else
        assert resp.status == 401
      end

      assert Enum.find(records(), &(&1.id == record.id)).standing == "UNKNOWN"
      assert :error = receipt_for(forged)
    end
  end

  defp wait_until(fun, tries \\ 50) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("condition never held")

      true ->
        Process.sleep(50)
        wait_until(fun, tries - 1)
    end
  end
end
