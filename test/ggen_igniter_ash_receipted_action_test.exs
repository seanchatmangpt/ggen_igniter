defmodule GgenIgniter.AshReceiptedActionTest do
  @moduledoc """
  Live chain for ggen-marketplace's `ash-extension-pack` receipted-action
  capability:

      marketplace pack (pinned copy, SOURCE.txt) -> real `mix ggen_igniter.sync`
      subprocess (oxigraph + WASM Tera) -> generated Receipt + ReceiptedAction
      -> real compile -> real actuation against an Ash resource manufactured
      by the upstream `ash.gen.*` generators (never hand-written here)

  Chicago-style, no doubles. Every assertion reads real state: the returned
  tuple, the receipt row in the generated ETS ledger, and the resource's own
  ETS rows.

  Contract under test (the Xaas.Actuation.run/4 shape):

    * no key                         -> `:idempotency_key_required`
    * first run                      -> sealed receipt, one row
    * same key, same request         -> `:replayed`, still one row
    * same key, different request    -> `{:idempotency_conflict, key}`, still one row
    * pending receipt (crash window) -> `{:in_flight, key}`; `reclaim: true` re-admits
    * failed action                  -> `:failed` receipt, key re-admittable

  Anti-vacuity: a mutant rendered from the same template, minus the conflict
  clause, must fail the conflict falsifier. That proves the conflict test
  observes the template's own clause rather than passing on some other path.
  """
  use ExUnit.Case, async: false

  alias GgenIgniter.Test.SemanticA2AManufactured, as: M

  @moduletag :integration

  @fixture "test/fixtures/ash_extension_receipted_consumer"
  @templates ~w(receipt receipted_action)
  @resource SemanticJira.Work.Task
  @receipt ReceiptedProbe.Receipt
  @action ReceiptedProbe.ReceiptedAction

  @valid %{task_id: "SJ-1", standing: "UNKNOWN"}

  setup_all do
    root = tmp_dir!("receipted_action")
    generated = sync!(Path.join(@fixture, "specs/receipted_spec.ttl"), root)

    m = M.manufactured!()

    with_compiler_env(fn ->
      Code.compile_string(m.domain_source <> "\n" <> m.resource_source, m.resource_path)

      for t <- @templates do
        path = Map.fetch!(generated, t)
        Code.compile_string(File.read!(path), path)
      end
    end)

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, generated: generated}
  end

  setup do
    Ash.DataLayer.Ets.stop(@resource)
    @receipt.reset!()
    :ok
  end

  describe "live generation" do
    test "writes exactly the receipt and receipted_action projections", ctx do
      for t <- @templates do
        source = File.read!(ctx.generated[t])
        assert {:defmodule, _, _} = Code.string_to_quoted!(source)
        refute source =~ "{{", "unrendered Tera placeholder in #{t}.ex"
        refute source =~ "{%", "unrendered Tera tag in #{t}.ex"
      end

      assert File.read!(ctx.generated["receipt"]) =~ "defmodule ReceiptedProbe.Receipt do"

      assert File.read!(ctx.generated["receipted_action"]) =~
               "defmodule ReceiptedProbe.ReceiptedAction do"

      assert File.read!(ctx.generated["receipted_action"]) =~ "(source: `caller_supplied`)"
    end

    test "regeneration is byte-identical", ctx do
      again = sync!(Path.join(@fixture, "specs/receipted_spec.ttl"), tmp_dir!("receipted_regen"))

      for t <- @templates do
        assert File.read!(again[t]) == File.read!(ctx.generated[t]), "#{t}.ex drifted"
      end
    end

    test "a spec with generatesReceiptedAction false is refused and projects nothing" do
      # A for_each driver resolving to zero rows is refused fail-closed (the same
      # doctrine test/ggen_igniter_semantic_jira_pack_health_test.exs pins), so an
      # opted-out spec can never silently "succeed" with an empty projection.
      root = tmp_dir!("receipted_opted_out")

      for t <- @templates do
        {output, code} = sync(Path.join(@fixture, "specs/receipted_spec_opted_out.ttl"), root, t)
        assert code != 0, "zero-row projection was admitted:\n#{output}"
        assert output =~ "[:targets] must not be an empty list"
      end

      assert Path.wildcard(Path.join(root, "lib/**/*.ex")) == []
    end

    test "pinned template copies equal the marketplace blobs named in SOURCE.txt" do
      marketplace = Path.expand("~/ggen-marketplace")

      [_, sha] =
        Regex.run(~r/source_sha:\s+([0-9a-f]{40})/, File.read!(Path.join(@fixture, "SOURCE.txt")))

      if File.dir?(Path.join(marketplace, ".git")) do
        for {copy, source} <- [
              {"templates/receipt.ex.tmpl", "templates/receipt.ex.tmpl"},
              {"templates/receipted_action.ex.tmpl", "templates/receipted_action.ex.tmpl"},
              {"specs/receipted_spec.ttl", "verify/fixtures/receipted_spec.ttl"},
              {"specs/receipted_spec_opted_out.ttl",
               "verify/fixtures/receipted_spec_opted_out.ttl"}
            ] do
          {blob, 0} =
            System.cmd("git", [
              "-C",
              marketplace,
              "show",
              "#{sha}:packs/ash-extension-pack/#{source}"
            ])

          assert File.read!(Path.join(@fixture, copy)) == blob, "#{copy} diverged from #{sha}"
        end
      else
        IO.puts(:stderr, "skip: #{marketplace} absent; pin not re-verified")
      end
    end
  end

  describe "receipted actuation" do
    test "a missing key is refused before anything is admitted" do
      assert {:error, :idempotency_key_required} = @action.run(@resource, :create, @valid, nil)
      assert {:error, :idempotency_key_required} = @action.run(@resource, :create, @valid, "")
      assert rows() == []
    end

    test "first run seals a receipt and writes one row" do
      assert {:ok, task, receipt} = @action.run(@resource, :create, @valid, "k-first")

      assert %{task_id: "SJ-1", standing: "UNKNOWN"} = task
      assert receipt.status == :sealed
      assert receipt.result.id == task.id
      assert {:ok, %{status: :sealed}} = @receipt.find_by_key("k-first")
      assert length(rows()) == 1
    end

    test "the same request under the same key replays without re-running" do
      {:ok, first, _} = @action.run(@resource, :create, @valid, "k-replay")

      assert {:ok, replayed, receipt} = @action.run(@resource, :create, @valid, "k-replay")
      assert receipt.status == :replayed
      assert replayed.id == first.id
      assert length(rows()) == 1
      # The stored receipt stays :sealed; :replayed is only the caller's view.
      assert {:ok, %{status: :sealed}} = @receipt.find_by_key("k-replay")
    end

    test "a different request under a sealed key is a conflict, not a replay" do
      {:ok, _, _} = @action.run(@resource, :create, @valid, "k-conflict")

      assert {:error, {:idempotency_conflict, "k-conflict"}} =
               @action.run(@resource, :create, %{@valid | task_id: "SJ-2"}, "k-conflict")

      assert [%{task_id: "SJ-1"}] = rows()
    end

    test "a pending receipt is refused as in flight unless reclaimed" do
      fp = @action.fingerprint(@resource, :create, nil, @valid)
      @receipt.admit!("k-pending", fp, @resource, :create)

      assert {:error, {:in_flight, "k-pending"}} =
               @action.run(@resource, :create, @valid, "k-pending")

      assert rows() == []

      assert {:ok, _, %{status: :sealed}} =
               @action.run(@resource, :create, @valid, "k-pending", reclaim: true)

      assert length(rows()) == 1
    end

    test "a failed action records a failed receipt and the key can be re-admitted" do
      invalid = Map.delete(@valid, :standing)

      assert {:error, %Ash.Error.Invalid{}} = @action.run(@resource, :create, invalid, "k-fail")

      assert {:ok, %{status: :failed, error: %Ash.Error.Invalid{}}} =
               @receipt.find_by_key("k-fail")

      assert rows() == []

      assert {:ok, _, %{status: :sealed}} = @action.run(@resource, :create, @valid, "k-fail")
      assert length(rows()) == 1
    end

    test "non-mutating and unknown actions are refused before admission" do
      # The manufactured resource only has create/read; :read is not a mutating
      # action and must be refused before admission.
      assert {:error, {:unsupported_action_type, :read}} =
               @action.run(@resource, :read, %{}, "k-read")

      assert {:ok, nil} = @receipt.find_by_key("k-read")

      assert {:error, {:unknown_action, @resource, :nope}} =
               @action.run(@resource, :nope, %{}, "k")
    end
  end

  describe "anti-vacuity" do
    test "a template without the conflict clause fails the conflict falsifier" do
      root = tmp_dir!("receipted_mutant")
      pack = Path.join(root, "pack")
      File.mkdir_p!(Path.join(pack, "templates"))

      for t <- @templates do
        source = File.read!(Path.join(@fixture, "templates/#{t}.ex.tmpl"))

        source =
          if t == "receipted_action" do
            clause = """
                    {:ok, %Receipt{status: :sealed}} ->
                      {:error, {:idempotency_conflict, idempotency_key}}

            """

            assert source =~ clause, "mutation target missing -- update this test"
            String.replace(source, clause, "")
          else
            source
          end

        File.write!(Path.join(pack, "templates/#{t}.ex.tmpl"), source)
      end

      spec = Path.join(root, "mutant_spec.ttl")

      File.write!(spec, """
      @prefix aex: <http://seanchatmangpt.github.io/packs/ash-extension-core#> .
      <urn:aex:fixture:mutant> a aex:AshExtensionSpec ;
          aex:packageName "receipted_mutant" ;
          aex:moduleName "ReceiptedMutant" ;
          aex:generatesReceiptedAction true .
      """)

      generated = sync!(spec, Path.join(root, "out"), pack)

      with_compiler_env(fn ->
        for t <- @templates, do: Code.compile_string(File.read!(generated[t]), generated[t])
      end)

      mutant = ReceiptedMutant.ReceiptedAction
      {:ok, _, _} = mutant.run(@resource, :create, @valid, "k-mutant")

      result =
        try do
          mutant.run(@resource, :create, %{@valid | task_id: "SJ-2"}, "k-mutant")
        rescue
          e in CaseClauseError -> {:raised, e}
        end

      refute match?({:error, {:idempotency_conflict, _}}, result),
             "conflict falsifier passed on a mutant lacking the conflict clause"
    end
  end

  defp rows, do: Ash.read!(@resource)

  defp sync!(spec, root, pack \\ @fixture) do
    Map.new(@templates, fn t ->
      {output, code} = sync(spec, root, t, pack)
      assert code == 0, "sync #{t} failed:\n#{output}"
      [path] = Path.wildcard(Path.join(root, "lib/*/#{t}.ex"))
      {t, path}
    end)
  end

  defp sync(spec, root, template, pack \\ @fixture) do
    System.cmd(
      "mix",
      [
        "ggen_igniter.sync",
        "--pack-dir",
        pack,
        "--template",
        Path.join(pack, "templates/#{template}.ex.tmpl"),
        "--ontology",
        spec,
        "--out",
        Path.join(root, "lib/<%= package_name %>/#{template}.ex"),
        "--manifest-dir",
        root,
        "--verify-cwd",
        File.cwd!()
      ],
      cd: File.cwd!(),
      stderr_to_stdout: true
    )
  end

  defp tmp_dir!(label) do
    dir =
      Path.join(System.tmp_dir!(), "ggen_igniter_#{label}_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  defp with_compiler_env(fun) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)
    previous_validate = Application.fetch_env(:ash, :validate_domain_config_inclusion?)
    Application.put_env(:ash, :validate_domain_config_inclusion?, false)

    try do
      fun.()
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)

      case previous_validate do
        {:ok, v} -> Application.put_env(:ash, :validate_domain_config_inclusion?, v)
        :error -> Application.delete_env(:ash, :validate_domain_config_inclusion?)
      end
    end
  end
end
