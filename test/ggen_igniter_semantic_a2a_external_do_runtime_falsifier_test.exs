defmodule GgenIgniter.SemanticA2AExternalDoRuntimeFalsifierTest do
  @moduledoc """
  QUALIFIER runtime falsifiers for the manufactured `external_do` court skill
  (errc/external-do-capability). Real manufacture, real compile, real Ash ETS,
  real ash_a2a CommandBus, real `AshA2A.ReceiptStore.Memory` GenServer, real
  `EKV` (SQLite on disk), real broker. No test doubles.

    * R2m (characterization): with ash_a2a's DEFAULT receipt store the
      exactly-once guarantee of F10 is bounded by the store process's lifetime;
      after a restart of `AshA2A.ReceiptStore.Memory` the same message executes
      the court again.
    * R2d: with the durable `AshA2A.ReceiptStore.Ekv` that the manufacture step
      configures (`a2a:RuntimeConfig`), replaying an executed message after the
      EKV instance is stopped and restarted on the same data dir does NOT execute
      the court again: an out-of-band state change survives the replay and the
      receipt id is unchanged.
    * Q4 (was the C3 characterization): the manufactured resource refuses
      standing ALIVE without a `sha256:` receipt digest (ontology invariant
      `sj:a2a-inv-alive-needs-digest`, generated as Ash validations). A
      well-formed digest is still only FORMAT-checked: A2A does not verify it
      against a real receipt (C3b pins that bound).

  Characterizations (PASS; they pin observed behavior that bounds what F10 can
  be read to claim, and will flag a change in either direction):

    * C1: a retry that mints a fresh message id re-executes the court unless
      ash_a2a's `actuation_dedup` mode is set to `:strict`; the default is
      `:declared`, which the manufactured surface does not tighten.
    * C2: a granted court call whose Ash update fails still commits a receipt
      with `terminal_status: :executed`; the honest field is `status`.
    * C4: a judge identity forged in message metadata, sent over real HTTP
      under the intruder or clerk token or none, is refused with no state
      change and no receipt.
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

  defp receipt_for(message, store \\ AshA2A.ReceiptStore.Memory),
    do: store.fetch(Identity.command(message.message_id), [])

  defp court_message(data), do: data_message(data, "update")

  defp digest(seed), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, seed), case: :lower)

  defp alive(record, seed \\ nil),
    do: %{"id" => record.id, "standing" => "ALIVE", "receipt_digest" => digest(seed || record.id)}

  defp set_standing!(record, standing) do
    record
    |> Ash.Changeset.for_update(:update, %{standing: standing})
    |> Ash.update!()
  end

  defp standing_of(record), do: Enum.find(records(), &(&1.id == record.id)).standing

  defp judge(message), do: @agent.call(@agent, message, as_principal("court-judge"))

  # Real `AshA2A.ReceiptStore.Memory` (ash_a2a's default store, a GenServer under
  # the ash_a2a supervisor). Its claim/commit state lives and dies with the process.
  test "R2m: with the default Memory store, replay after a store restart executes the court again" do
    record = seed_task!("r2m")
    message = court_message(alive(record))

    assert {:ok, first} = judge(message)
    assert first.status.state == :completed
    assert {:ok, %AshA2A.Receipt{receipt_id: id}} = receipt_for(message)

    # Out-of-band state change, so a second execution is observable as state.
    set_standing!(record, "BLOCKED")
    assert standing_of(record) == "BLOCKED"

    pid = Process.whereis(AshA2A.ReceiptStore.Memory)
    assert is_pid(pid)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000
    wait_until(fn -> is_pid(Process.whereis(AshA2A.ReceiptStore.Memory)) end)

    assert {:ok, _again} = judge(message)

    # The bound: the identical message ran the court a second time.
    assert standing_of(record) == "ALIVE"
    assert {:ok, %AshA2A.Receipt{receipt_id: second_id}} = receipt_for(message)
    refute second_id == id
  end

  describe "R2d: the durable EKV receipt store the manufacture step configures" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "a2a_ekv_receipts_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      previous = Application.fetch_env(:ash_a2a, :receipt_store)
      Application.put_env(:ash_a2a, :receipt_store, AshA2A.ReceiptStore.Ekv)

      on_exit(fn ->
        case previous do
          {:ok, v} -> Application.put_env(:ash_a2a, :receipt_store, v)
          :error -> Application.delete_env(:ash_a2a, :receipt_store)
        end
      end)

      %{ekv_spec: {EKV, name: AshA2A.ReceiptStore.Ekv, data_dir: dir, cluster_size: 1}}
    end

    test "replay after the EKV instance is stopped and restarted does not execute the court again",
         %{ekv_spec: spec} do
      start_supervised!(spec, id: :ekv)

      record = seed_task!("r2d")
      message = court_message(alive(record))

      assert {:ok, first} = judge(message)
      assert first.status.state == :completed

      assert {:ok, %AshA2A.Receipt{receipt_id: id, standing: :durable}} =
               receipt_for(message, AshA2A.ReceiptStore.Ekv)

      set_standing!(record, "BLOCKED")

      # Stop the real EKV instance and start it again on the same data dir.
      stop_supervised!(:ekv)
      start_supervised!(spec, id: :ekv)

      assert {:ok, _again} = judge(message)

      # Not executed again: the out-of-band state survives and the receipt is the first one.
      assert standing_of(record) == "BLOCKED"

      assert {:ok, %AshA2A.Receipt{receipt_id: ^id}} =
               receipt_for(message, AshA2A.ReceiptStore.Ekv)
    end
  end

  describe "Q4: standing ALIVE needs a sha256 receipt digest (ontology invariant)" do
    test "ALIVE with no receipt_digest is refused and the state is unchanged" do
      record = seed_task!("q4-none")

      message = court_message(%{"id" => record.id, "standing" => "ALIVE"})
      assert {:ok, task} = judge(message)

      refute task.status.state == :completed
      assert standing_of(record) == "UNKNOWN"
    end

    test "ALIVE with a receipt_digest that is not a sha256 digest is refused" do
      record = seed_task!("q4-garbage")

      for garbage <- ["not-a-digest", "sha256:abc", "sha256:" <> String.duplicate("G", 64), ""] do
        message =
          court_message(%{"id" => record.id, "standing" => "ALIVE", "receipt_digest" => garbage})

        assert {:ok, task} = judge(message)
        refute task.status.state == :completed, "accepted #{inspect(garbage)}"
        assert standing_of(record) == "UNKNOWN"
      end
    end

    test "ALIVE with a well-formed sha256 digest is accepted and stored" do
      record = seed_task!("q4-ok")
      message = court_message(alive(record))

      assert {:ok, task} = judge(message)
      assert task.status.state == :completed

      stored = Enum.find(records(), &(&1.id == record.id))
      assert stored.standing == "ALIVE"
      assert stored.receipt_digest == digest(record.id)
    end

    test "a standing other than ALIVE needs no digest" do
      record = seed_task!("q4-partial")
      message = court_message(%{"id" => record.id, "standing" => "PARTIAL_ALIVE"})

      assert {:ok, task} = judge(message)
      assert task.status.state == :completed
      assert standing_of(record) == "PARTIAL_ALIVE"
    end

    test "the record_court_receipt (create) skill enforces it too" do
      message =
        data_message(%{"task_id" => "q4-create", "standing" => "ALIVE"}, "create")

      assert {:ok, task} = @agent.call(@agent, message, as_principal("court-clerk"))
      refute task.status.state == :completed
      assert records() == []
    end

    test "C3b (bound): the digest is FORMAT-checked, not verified against a receipt" do
      record = seed_task!("c3b")
      never_issued = "sha256:" <> String.duplicate("0", 64)

      message =
        court_message(%{
          "id" => record.id,
          "standing" => "ALIVE",
          "receipt_digest" => never_issued
        })

      assert {:ok, task} = judge(message)
      assert task.status.state == :completed
      assert standing_of(record) == "ALIVE"
    end
  end

  test "C1: a fresh message id re-executes the court unless actuation_dedup is :strict" do
    record = seed_task!("c1")
    data = alive(record)

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
    data2 = alive(record2)
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
    message =
      court_message(%{
        "id" => Ash.UUID.generate(),
        "standing" => "ALIVE",
        "receipt_digest" => digest("c2")
      })

    assert {:ok, task} = judge(message)
    assert task.status.state == :input_required
    assert records() == []

    assert {:ok, %AshA2A.Receipt{} = receipt} = receipt_for(message)
    assert receipt.status == :input_required
    assert receipt.terminal_status == :executed
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
        court_message(alive(record))
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

      assert standing_of(record) == "UNKNOWN"
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
