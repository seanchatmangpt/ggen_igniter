defmodule GgenIgniter.SemanticA2AExternalDoFalsifierTest do
  @moduledoc """
  QUALIFIER falsifiers for the external_do consequence-patch stream
  (errc/external-do-capability). Chicago-style, no test doubles: the real
  `mix ggen_igniter.sync` render, the real upstream generators through
  `Igniter.Test`, and the real compiler.

    * Q1 (upgrade path): a project manufactured by the PREVIOUS plan
      (`--default-actions read,create`, no `update` Ash action) and then
      re-manufactured by the CURRENT task must still compile. The patch step
      declares `skill :update, :update, consequence: :external_do`; if the
      generator step does not add the `update` action to the existing resource,
      the composed result references an Ash action that does not exist.
    * Q2 (retirement): retiring the skill in the ontology (`a2a:exposed false`)
      over a project that already carries the declaration must revoke it.
      ash_a2a exposes EVERY public Ash action by default, so removing the
      `skill` line would leave the retired capability exposed as a plain
      `:change` skill; the reconciliation declares `expose?: false` instead,
      keeping the Ash action (which may back other code). Verified on the real
      compiled resource's capability index, with a stable second run and an exact
      round trip back to the exposed court.
  """

  use ExUnit.Case, async: false

  import Igniter.Test

  alias GgenIgniter.Test.SemanticA2AManufactured, as: M

  @ontology "priv/ggen/semantic-jira-pack/ontology.ttl"
  @resource_path "lib/semantic_jira/work/task.ex"

  setup_all do
    %{m: M.manufactured!()}
  end

  setup do
    previous = Application.fetch_env(M.app(), :ash_domains)
    Application.put_env(M.app(), :ash_domains, [SemanticJira.Work])

    on_exit(fn ->
      case previous do
        {:ok, v} -> Application.put_env(M.app(), :ash_domains, v)
        :error -> Application.delete_env(M.app(), :ash_domains)
      end
    end)

    :ok
  end

  defp resource(igniter), do: M.content!(igniter, @resource_path)

  defp skill_lines(source),
    do: ~r/^\s*skill\(.*\)$/m |> Regex.scan(source) |> Enum.map(&(&1 |> hd() |> String.trim()))

  # The manufactured project as the PREVIOUS plan built it: same steps, but the
  # resource generator was told only `read,create`.
  defp previous_plan_project(m) do
    Enum.reduce(m.module.plan(), Igniter.Test.test_project(app_name: M.app()), fn step, acc ->
      argv =
        if step.task == "ash.gen.resource" do
          idx = Enum.find_index(step.argv, &(&1 == "--default-actions"))
          List.replace_at(step.argv, idx + 1, "read,create")
        else
          step.argv
        end

      M.compose(acc, step.task, argv)
    end)
    |> M.apply!()
  end

  defp compile_variant!(source, from, to) do
    previous = Code.get_compiler_option(:ignore_module_conflict)
    previous_validate = Application.fetch_env(:ash, :validate_domain_config_inclusion?)
    Code.put_compiler_option(:ignore_module_conflict, true)
    Application.put_env(:ash, :validate_domain_config_inclusion?, false)

    try do
      Code.compile_string(String.replace(source, from, to))
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)

      case previous_validate do
        {:ok, v} -> Application.put_env(:ash, :validate_domain_config_inclusion?, v)
        :error -> Application.delete_env(:ash, :validate_domain_config_inclusion?)
      end
    end
  end

  defp render_variant(mutator, task_name) do
    renamed =
      File.read!(@ontology)
      |> String.replace(
        ~s|a2a:taskName "semantic_jira.a2a.manufacture"|,
        ~s|a2a:taskName "#{task_name}"|
      )
      |> mutator.()

    refute renamed == File.read!(@ontology), "fixture mutation did not change the ontology"

    dir = Path.join(System.tmp_dir!(), "a2a_falsifier_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir = RealDir.real_dir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    onto = Path.join(dir, "variant.ttl")
    File.write!(onto, renamed)

    {output, status} =
      System.cmd(
        "mix",
        [
          "ggen_igniter.sync",
          "--engine",
          "sparql",
          "--pack",
          "semantic-jira-pack:a2a_manufacture",
          "--ontology",
          onto,
          "--out",
          Path.join(dir, "<%= task_name %>.ex"),
          "--manifest-dir",
          dir,
          "--verify-cwd",
          File.cwd!()
        ],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    {status, output, Path.join(dir, task_name <> ".ex")}
  end

  describe "Q1: upgrade from a project manufactured by the previous plan" do
    test "re-running the current task over a read,create-only resource yields an update action for the court skill",
         %{m: m} do
      old = previous_plan_project(m)
      refute resource(old) =~ "update: [", "fixture: old plan must not carry an update action"

      upgraded = M.compose(old, m.module, [])
      source = resource(upgraded)

      assert upgraded.issues == []
      assert source =~ "update: [:receipt_digest, :replay_identity, :standing, :task_id]"

      # The upgrade converges: a second run over the upgraded project is inert.
      assert_unchanged(M.compose(M.apply!(upgraded), m.module, []))

      # The patch step declares the court skill ...
      assert skill_lines(source)
             |> Enum.member?("skill(:update, :update, consequence: :external_do)")

      # ... so the resource must also carry the Ash action that skill names.
      # Ash's verifier reports a skill over a missing action as a compile
      # diagnostic (a warning, fatal under `mix compile --warnings-as-errors`,
      # which is how this repo's e2e and Stop hook verify a manufactured tree).
      {_compiled, diagnostics} =
        Code.with_diagnostics(fn ->
          compile_variant!(
            M.content!(upgraded, m.domain_path) <> "\n" <> source,
            "SemanticJira.Work",
            "SemanticJira.Q1Work"
          )
        end)

      messages = Enum.map(diagnostics, &to_string(&1.message))

      refute Enum.any?(messages, &(&1 =~ "REFUSED_ACTION_NOT_FOUND")),
             "upgraded resource declares a skill over an Ash action it does not have: " <>
               inspect(messages)
    end
  end

  describe "Q2: retirement over an already-manufactured project" do
    test "an ontology that retires the court skill removes its declaration from the existing resource",
         %{m: m} do
      {0, _output, path} =
        render_variant(
          fn onto ->
            String.replace(
              onto,
              ~s|a2a:exposed true ;\n    a2a:generatedBy gi:ash-a2a-consequence-patch .|,
              ~s|a2a:exposed false ;\n    a2a:refusalReason "REFUSED(policy): retired by falsifier" .|
            )
          end,
          "semantic_jira.a2a.manufacture_q2_retired"
        )

      retired = M.load_task!(File.read!(path), path)
      refute Enum.any?(retired.consequences(), &(&1.name == :update))

      existing = M.apply!(m.igniter)
      assert resource(existing) =~ "consequence: :external_do"

      converged = M.compose(existing, retired, [])

      refute resource(converged) =~ "consequence: :external_do",
             "retired skill is still declared (exposed) on the existing resource:\n" <>
               resource(converged)

      assert converged.issues == []

      # Exposure is revoked with an explicit declaration, and the Ash action stays.
      assert skill_lines(resource(converged))
             |> Enum.member?("skill(:update, :update, expose?: false)")

      assert resource(converged) =~ "update: ["

      # The real compiled resource no longer offers the retired capability.
      compile_variant!(
        M.content!(converged, m.domain_path) <> "\n" <> resource(converged),
        "SemanticJira.Work",
        "SemanticJira.Q2Work"
      )

      names = SemanticJira.Q2Work.Task |> AshA2A.Info.capability_index() |> Enum.map(& &1.name)
      assert Enum.sort(names) == [:create, :read]

      # Stable, and re-exposing through the original ontology restores the court exactly.
      applied = M.apply!(converged)
      assert_unchanged(M.compose(applied, retired, []))

      restored = M.compose(applied, m.module, [])
      assert restored.issues == []
      assert resource(M.apply!(restored)) == resource(existing)
    end
  end
end
