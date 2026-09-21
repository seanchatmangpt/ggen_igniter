defmodule GgenIgniter.SemanticA2AExternalDoTest do
  @moduledoc """
  Chicago-style, no-mocks proof for the `external_do` capability of the Semantic
  Jira -> ash_a2a manufacture: what the upstream installer CANNOT do (an exact
  falsifier, kept so the UNSUPPORTED(generator-capability) row stays accurate),
  and what the composed consequence-patch step of the rendered task DOES.

  Real collaborators: a real `mix ggen_igniter.sync` subprocess renders the
  task from the real (and from mutated copies of the real) pack ontology; the
  real compiler loads it; the real `ash.gen.domain`, `ash.gen.resource` and
  `ash_a2a.install` run through `Igniter.Test`; real Ash compiles the generated
  resource; states such as "declaration missing" or "consequence drifted" are
  built by editing the MANUFACTURED source, never by hand-writing Ash. No test
  doubles of any kind; every assertion is on generated source, real Igniter
  issues, real compiled capability data, or a real subprocess exit.

  Falsifiers:

    * F11 (upstream gap): the raw `ash_a2a.install` declares no consequence and
      silently ignores a consequence flag, so used alone the court skill would be
      compiled as a plain `:change` skill.
    * F12 (patch step): a second run is inert; a missing declaration is
      restored; a drifted consequence is corrected; a bare `skill` gains its
      consequence; a resource without an `a2a` block is a typed issue, not a
      silent no-op.
    * F13 (ontology direction): retiring or renaming the skill in the ontology
      changes the manufactured resource, and a skill naming an Ash action the
      generator cannot produce is refused at render time as
      UNSUPPORTED(generator-capability), never guessed.
  """

  use ExUnit.Case, async: false

  import Igniter.Test

  alias GgenIgniter.{Ontology, Query}
  alias GgenIgniter.Test.SemanticA2AManufactured, as: M

  @ontology "priv/ggen/semantic-jira-pack/ontology.ttl"
  @resource_path "lib/semantic_jira/work/task.ex"
  @court "skill(:update, :update, consequence: :external_do)"

  setup_all do
    %{m: M.manufactured!()}
  end

  setup do
    # Same `ash_domains` bookkeeping the F9 test needs for a re-composition.
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

  # -- helpers ---------------------------------------------------------------

  # The manufactured project with `mutator` applied to the resource source,
  # committed as the new baseline. Never hand-written Ash: the baseline is what
  # the real generators produced, edited by a string replacement.
  defp mutated_project(m, mutator) do
    applied = M.apply!(m.igniter)
    original = M.content!(applied, @resource_path)
    mutated = mutator.(original)
    refute mutated == original, "fixture mutation did not change the resource"

    applied
    |> Igniter.update_file(@resource_path, fn source ->
      Rewrite.Source.update(source, :content, mutated)
    end)
    |> M.apply!()
  end

  defp resource(igniter), do: M.content!(igniter, @resource_path)

  defp default_actions(module) do
    [gen_resource] = Enum.filter(module.plan(), &(&1.task == "ash.gen.resource"))
    index = Enum.find_index(gen_resource.argv, &(&1 == "--default-actions"))
    Enum.at(gen_resource.argv, index + 1)
  end

  defp skill_lines(source),
    do: ~r/^\s*skill\(.*\)$/m |> Regex.scan(source) |> Enum.map(&(&1 |> hd() |> String.trim()))

  # Only the upstream generators, in plan order, WITHOUT the consequence patch.
  defp raw_upstream(m) do
    Enum.reduce(m.module.plan(), Igniter.Test.test_project(app_name: M.app()), fn step, acc ->
      M.compose(acc, step.task, step.argv)
    end)
  end

  # Renders the manufacture task from a mutated copy of the real ontology, with
  # a distinct task name so the module never collides with the shared one.
  defp render_variant(mutator, task_name) do
    renamed =
      File.read!(@ontology)
      |> String.replace(
        ~s|a2a:taskName "semantic_jira.a2a.manufacture"|,
        ~s|a2a:taskName "#{task_name}"|
      )
      |> mutator.()

    refute renamed == File.read!(@ontology), "fixture mutation did not change the ontology"

    dir = Path.join(System.tmp_dir!(), "a2a_variant_#{System.unique_integer([:positive])}")
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

  defp compile_raw_variant!(source, from, to) do
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

  # -- F11: the upstream gap, as an exact falsifier -------------------------

  describe "F11: the raw upstream ash_a2a.install cannot declare a skill consequence" do
    test "the DSL supports consequence: :external_do -- the gap is the installer, not the DSL" do
      [section] = AshA2A.Dsl.sections()
      [skill] = section.entities
      consequence = Keyword.fetch!(skill.schema, :consequence)

      assert consequence[:type] == {:one_of, [:observe, :change, :external_do, :unknown]}
    end

    test "the installer's option schema has no way to carry one" do
      info = Mix.Tasks.AshA2a.Install.info([], nil)
      assert Keyword.keys(info.schema) |> Enum.sort() == [:target, :type]
    end

    test "raw output declares no consequence, and a consequence flag is silently ignored", %{m: m} do
      base =
        Enum.reduce(
          Enum.take(m.module.plan(), 2),
          Igniter.Test.test_project(app_name: M.app()),
          fn step, acc -> M.compose(acc, step.task, step.argv) end
        )

      target = ["--target", "SemanticJira.Work.Task", "--type", "resource"]
      plain = M.compose(base, "ash_a2a.install", target)
      flagged_a = M.compose(base, "ash_a2a.install", target ++ ["--consequence", "external_do"])

      flagged_b =
        M.compose(base, "ash_a2a.install", target ++ ["--skill", "update:update:external_do"])

      refute resource(plain) =~ "consequence"
      assert resource(plain) =~ "a2a do"

      for flagged <- [flagged_a, flagged_b] do
        # No error, no warning, no effect: the flag is dropped on the floor.
        assert flagged.issues == []
        assert flagged.warnings == []
        assert resource(flagged) == resource(plain)
      end
    end

    test "so used alone, the court skill compiles as a plain :change skill (the hazard the patch step closes)",
         %{m: m} do
      raw = raw_upstream(m)
      refute resource(raw) =~ "consequence"

      compile_raw_variant!(
        M.content!(raw, m.domain_path) <> "\n" <> resource(raw),
        "SemanticJira.Work",
        "SemanticJira.RawWork"
      )

      assert {:ok, update} = AshA2A.Info.skill(SemanticJira.RawWork.Task, "update")
      assert update.consequence == :change
      refute update.consequence == :external_do

      # ... whereas the manufactured resource (with the patch step) is external_do.
      assert m.resource_source =~ @court
    end
  end

  # -- F12: the composed consequence-patch step -----------------------------

  describe "F12: the composed consequence-patch step" do
    test "one explicit declaration per exposed skill, rendered from the ontology facts", %{m: m} do
      facts =
        Query.run(
          Ontology.load!(@ontology),
          File.read!("priv/ggen/semantic-jira-pack/gates/060_a2a_skills.rq")
        )

      assert length(facts) == 3

      expected =
        facts
        |> Enum.map(fn f ->
          %{
            name: String.to_atom(f["ash_action"]),
            action: String.to_atom(f["ash_action"]),
            consequence: String.to_atom(f["consequence"])
          }
        end)
        |> Enum.sort_by(& &1.name)

      assert Enum.sort_by(m.module.consequences(), & &1.name) == expected

      assert skill_lines(m.resource_source) == [
               "skill(:read, :read, consequence: :observe)",
               "skill(:create, :create, consequence: :change)",
               @court
             ]

      # exactly one court declaration, inside the a2a block
      assert length(Regex.scan(~r/consequence: :external_do/, m.resource_source)) == 1
      assert m.resource_source =~ ~r/a2a do\n\s+skill\(:read/
    end

    test "the Ash default actions are derived from the exposed skills, not hard-coded", %{m: m} do
      assert default_actions(m.module) == "read,create,update"
      assert m.resource_source =~ "update: ["
      assert m.igniter.issues == []
    end

    test "second run: the whole project is byte-identical, including the consequence block", %{
      m: m
    } do
      applied = M.apply!(m.igniter)
      second = M.compose(applied, m.module, [])

      assert second.issues == []
      assert second.tasks == []
      assert_unchanged(second)
      assert resource(second) == resource(applied)
      assert length(skill_lines(resource(second))) == 3
    end

    test "a missing declaration is restored", %{m: m} do
      project = mutated_project(m, &String.replace(&1, "    #{@court}\n", ""))
      refute resource(project) =~ "external_do"

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert skill_lines(resource(fixed)) |> Enum.member?(@court)
      assert length(skill_lines(resource(fixed))) == 3
      assert resource(fixed) =~ "consequence: :external_do"
    end

    test "a drifted consequence is corrected in place, without a second declaration", %{m: m} do
      project =
        mutated_project(
          m,
          &String.replace(&1, "consequence: :external_do", "consequence: :change")
        )

      refute resource(project) =~ "external_do"

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert resource(fixed) == m.resource_source
      assert length(skill_lines(resource(fixed))) == 3

      # and the correction is itself stable
      assert_unchanged(M.compose(M.apply!(fixed), m.module, []))
    end

    test "a bare skill declaration gains its consequence", %{m: m} do
      project = mutated_project(m, &String.replace(&1, @court, "skill(:update, :update)"))

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert resource(fixed) == m.resource_source
    end

    test "a resource without an a2a block is a typed issue, and the source is not corrupted", %{
      m: m
    } do
      project = mutated_project(m, &String.replace(&1, ~r/  a2a do\n.*?\n  end\n\n/s, ""))
      refute resource(project) =~ "a2a do"

      result = M.compose(project, m.module, [])

      assert Enum.any?(
               result.issues,
               &(&1 =~ "has no `a2a do ... end` block to declare skill consequences in")
             )

      refute resource(result) =~ "consequence: :external_do"
    end
  end

  # -- F13: the ontology is the source, in both directions ---------------------

  describe "F13: ontology -> resource, both directions" do
    test "changing the skill's consequence in the ontology changes the manufactured resource and re-converges",
         %{m: m} do
      {0, _output, path} =
        render_variant(
          fn onto ->
            String.replace(
              onto,
              ~s|a2a:consequence "external_do" ;\n    a2a:exposed true|,
              ~s|a2a:consequence "change" ;\n    a2a:exposed true|
            )
          end,
          "semantic_jira.a2a.manufacture_drift"
        )

      source = File.read!(path)
      module = M.load_task!(source, path)

      assert module != m.module
      assert Enum.any?(module.consequences(), &match?(%{name: :update, consequence: :change}, &1))
      refute source =~ "consequence: :external_do"

      # Run the changed ontology's task over the project the old ontology built.
      converged = M.compose(M.apply!(m.igniter), module, [])

      assert converged.issues == []

      assert skill_lines(resource(converged))
             |> Enum.member?("skill(:update, :update, consequence: :change)")

      refute resource(converged) =~ "external_do"
      assert length(skill_lines(resource(converged))) == 3

      assert_unchanged(M.compose(M.apply!(converged), module, []))
    end

    test "a FRESH manufacture from an ontology that retires the skill declares neither it nor its Ash action (retirement over an existing project is F14 and Q2)",
         %{m: m} do
      {0, _output, path} =
        render_variant(
          fn onto ->
            String.replace(
              onto,
              ~s|a2a:exposed true ;\n    a2a:generatedBy gi:ash-a2a-consequence-patch .|,
              ~s|a2a:exposed false ;\n    a2a:refusalReason "REFUSED(policy): retired in test" .|
            )
          end,
          "semantic_jira.a2a.manufacture_retired"
        )

      module = M.load_task!(File.read!(path), path)

      assert Enum.map(module.consequences(), & &1.name) |> Enum.sort() == [:create, :read]

      assert default_actions(module) == "read,create"

      igniter = raw_and_patch(module)
      refute resource(igniter) =~ "external_do"
      refute resource(igniter) =~ "update: ["
      assert m.resource_source =~ "update: ["
    end

    test "a skill naming an Ash action the generator cannot produce is refused at render, not guessed" do
      {status, output, _path} =
        render_variant(
          fn onto ->
            String.replace(
              onto,
              ~s|a2a:ashAction "update" ;\n    a2a:consequence "external_do"|,
              ~s|a2a:ashAction "run_court" ;\n    a2a:consequence "external_do"|
            )
          end,
          "semantic_jira.a2a.manufacture_custom_action"
        )

      refute status == 0
      assert output =~ "UNSUPPORTED(generator-capability)"
      assert output =~ "run_court"
    end
  end

  # -- F14: reconciling an EXISTING project with the ontology ---------------------
  #
  # ash.gen.resource never adds an action to a resource that exists, and ash_a2a
  # exposes every public Ash action. So the manufacture task also reconciles:
  # missing actions, retired exposure, unmodeled declarations, invariants and
  # runtime config (Q1, Q2, Q3, Q4, R2 of the qualification round).

  describe "F14: the composed reconciliation over an existing resource" do
    test "the Ash actions of the exposed skills are derived facts, with ash.gen.resource's accept list",
         %{m: m} do
      assert Enum.map(m.module.actions(), & &1.name) == [:read, :create, :update]

      assert %{accept: [:receipt_digest, :replay_identity, :standing, :task_id]} =
               Enum.find(m.module.actions(), &(&1.name == :update))

      assert %{accept: []} = Enum.find(m.module.actions(), &(&1.name == :read))
    end

    test "a keyword default action (update) missing from an existing resource is added, then stable",
         %{m: m} do
      project = mutated_project(m, &String.replace(&1, ~r/,\n\s+update: \[[^\]]*\]/, ""))
      refute resource(project) =~ "update: ["

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert resource(fixed) =~ "update: [:receipt_digest, :replay_identity, :standing, :task_id]"
      assert length(skill_lines(resource(fixed))) == 3

      applied = M.apply!(fixed)
      assert_unchanged(M.compose(applied, m.module, []))
      assert resource(applied) == resource(M.apply!(m.igniter))
    end

    test "an atom default action (read) missing from an existing resource is added in front of the keyword entries",
         %{m: m} do
      project = mutated_project(m, &String.replace(&1, ~r/\n\s+:read,/, ""))
      refute resource(project) =~ ~r/defaults\(\[\s*:read,/

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert resource(fixed) =~ ~r/defaults\(\[\s*:read,/
      assert_unchanged(M.compose(M.apply!(fixed), m.module, []))
    end

    test "an explicit action declaration counts as present, and the others are added as a new defaults call",
         %{m: m} do
      project =
        mutated_project(m, &String.replace(&1, ~r/defaults\(\[.*?\n    \]\)/s, "read(:read)"))

      refute resource(project) =~ "defaults("

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert resource(fixed) =~ "read(:read)"
      assert length(Regex.scan(~r/defaults\(/, resource(fixed))) == 1
      assert resource(fixed) =~ "create: [:receipt_digest, :replay_identity, :standing, :task_id]"
      assert resource(fixed) =~ "update: [:receipt_digest, :replay_identity, :standing, :task_id]"
      assert_unchanged(M.compose(M.apply!(fixed), m.module, []))
    end

    test "a `defaults` that is not a literal list makes the missing action a typed issue, and the skill is never declared",
         %{m: m} do
      project =
        mutated_project(m, fn source ->
          source
          |> String.replace(~r/defaults\(\[.*?\n    \]\)/s, "defaults(custom_actions())")
          |> String.replace("    #{@court}\n", "")
        end)

      result = M.compose(project, m.module, [])

      assert Enum.any?(result.issues, &(&1 =~ "REFUSED_ACTION_NOT_FOUND"))
      refute resource(result) =~ "external_do"
    end

    test "a skill declaration the ontology neither exposes nor retires is a typed issue, not kept silently",
         %{m: m} do
      project =
        mutated_project(
          m,
          &String.replace(
            &1,
            "    #{@court}\n",
            "    #{@court}\n    skill(:destroy, :destroy, consequence: :change)\n"
          )
        )

      result = M.compose(project, m.module, [])

      assert Enum.any?(result.issues, &(&1 =~ "declares skill(s) [:destroy]"))
    end

    test "the resource carries the ALIVE-needs-digest invariant as Ash validations", %{m: m} do
      assert [inv] = m.module.invariants()
      assert inv.requires_attribute == :receipt_digest
      assert m.resource_source =~ "validations do"
      assert m.resource_source =~ "present(:receipt_digest)"
      assert m.resource_source =~ ~S|~r/^sha256:[0-9a-f]{64}$/|
      assert m.resource_source =~ ~S|attribute_equals(:standing, "ALIVE")|
      assert length(Regex.scan(~r/REFUSED\(a2a-invariant\)/, m.resource_source)) == 2
    end

    test "a deleted validations block is restored", %{m: m} do
      project =
        mutated_project(m, &String.replace(&1, ~r/\n  validations do\n.*?\n  end\n/s, "\n"))

      refute resource(project) =~ "validations do"

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert resource(M.apply!(fixed)) == resource(M.apply!(m.igniter))
    end

    test "a drifted validation is replaced, not duplicated", %{m: m} do
      project =
        mutated_project(m, &String.replace(&1, "sha256:[0-9a-f]{64}", "sha256:.*"))

      refute resource(project) =~ "[0-9a-f]{64}"

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert resource(M.apply!(fixed)) == resource(M.apply!(m.igniter))
      assert length(Regex.scan(~r/validate\(/, resource(fixed))) == 2
    end

    test "an invariant the ontology drops is pruned from an existing resource", %{m: m} do
      {0, _output, path} =
        render_variant(
          fn onto ->
            String.replace(
              onto,
              "sj:a2a-inv-alive-needs-digest a a2a:ResourceInvariant ;",
              "sj:a2a-inv-alive-needs-digest a rdfs:Resource ;"
            )
          end,
          "semantic_jira.a2a.manufacture_no_invariant"
        )

      module = M.load_task!(File.read!(path), path)
      assert module.invariants() == []

      converged = M.compose(M.apply!(m.igniter), module, [])

      assert converged.issues == []
      refute resource(converged) =~ "REFUSED(a2a-invariant)"
      refute resource(converged) =~ "validate("
      assert_unchanged(M.compose(M.apply!(converged), module, []))
    end

    test "the receipt store is configured from the ontology, and a drifted value is corrected",
         %{m: m} do
      configured = "config :ash_a2a, receipt_store: AshA2A.ReceiptStore.Ekv"
      assert M.content!(m.igniter, "config/config.exs") =~ configured
      assert [%{app: :ash_a2a, key: :receipt_store}] = m.module.runtime_config()

      project =
        m.igniter
        |> M.apply!()
        |> Igniter.update_file("config/config.exs", fn source ->
          Rewrite.Source.update(
            source,
            :content,
            String.replace(
              Rewrite.Source.get(source, :content),
              "AshA2A.ReceiptStore.Ekv",
              "AshA2A.ReceiptStore.Memory"
            )
          )
        end)
        |> M.apply!()

      refute M.content!(project, "config/config.exs") =~ "Ekv"

      fixed = M.compose(project, m.module, [])

      assert fixed.issues == []
      assert M.content!(fixed, "config/config.exs") =~ configured
      assert_unchanged(M.compose(M.apply!(fixed), m.module, []))
    end

    test "composing the task does not leak its config into the running VM's :ash_a2a env", %{m: m} do
      before = Application.get_all_env(:ash_a2a)

      _ = M.compose(Igniter.Test.test_project(app_name: M.app()), m.module, [])

      assert Application.get_all_env(:ash_a2a) == before
      refute Application.get_env(:ash_a2a, :receipt_store) == AshA2A.ReceiptStore.Ekv
    end
  end

  # Runs every step of a rendered task (upstream generators + patch) on a fresh project.
  defp raw_and_patch(module),
    do: M.compose(Igniter.Test.test_project(app_name: M.app()), module, [])
end
