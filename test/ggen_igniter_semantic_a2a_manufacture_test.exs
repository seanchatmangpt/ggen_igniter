defmodule GgenIgniter.SemanticA2AManufactureTest do
  @moduledoc """
  Chicago-style, no-mocks proof that the Semantic Jira pack MANUFACTURES its
  Ash/ash_a2a surface through the real upstream generators instead of writing
  Ash by hand.

  Real collaborators: a real `mix ggen_igniter.sync` subprocess renders the
  composed task from the real pack ontology; the real compiler loads it; the
  real `ash.gen.domain`, `ash.gen.resource --extend ets` and `ash_a2a.install`
  tasks run through `Igniter.Test` against an in-memory project. Assertions are
  on the resulting generated source, the real `igniter.issues`, and the state
  of a second real run.

  Falsifiers: F5 (`use Ash.Resource` in the rendered task), F9 (a second run
  changes files), plus ontology->argv drift in both directions.

  Real upstream finding pinned here: `ash_a2a.install` (26.9.17) appends its
  starter `a2a do end` block unconditionally, so the composed step is guarded
  (see the template) and the F9 test proves the guard, not upstream tolerance.
  """

  use ExUnit.Case, async: false

  import Igniter.Test

  alias GgenIgniter.Test.SemanticA2AManufactured, as: M

  @ontology "priv/ggen/semantic-jira-pack/ontology.ttl"

  setup_all do
    %{m: M.manufactured!()}
  end

  test "F5: the rendered task never declares an Ash surface itself", %{m: m} do
    refute m.source =~ ~r/^\s*use Ash\./m
    refute m.source =~ "use Ash.Resource"
    refute m.source =~ "use Ash.Domain"
    # It only composes real upstream tasks, in dependency order.
    assert Enum.map(m.module.plan(), & &1.task) ==
             ["ash.gen.domain", "ash.gen.resource", "ash_a2a.install"]

    assert m.source =~ "Igniter.compose_task(igniter, step.task, step.argv)"
  end

  test "the real composition produced no issues and queued nothing", %{m: m} do
    assert m.igniter.issues == []
    assert m.igniter.tasks == []
  end

  test "ash_a2a.install patched the generated resource with extensions: [AshA2A]", %{m: m} do
    assert m.resource_source =~ "defmodule SemanticJira.Work.Task do"
    assert m.resource_source =~ "use Ash.Resource"
    assert m.resource_source =~ "extensions: [AshA2A]"
    assert m.resource_source =~ "data_layer: Ash.DataLayer.Ets"
    assert m.resource_source =~ "domain: SemanticJira.Work"
    assert m.resource_source =~ "a2a do"
    assert m.domain_source =~ "resource(SemanticJira.Work.Task)"

    # exactly one AshA2A occurrence in the extensions list (no duplicate merge)
    assert length(Regex.scan(~r/AshA2A\b/, m.resource_source)) == 1
  end

  test "ash_a2a.install added the :a2a dependency to the target project", %{m: m} do
    mix = M.content!(m.igniter, "mix.exs")
    assert mix =~ ~s|{:a2a, "~> 0.2"}|
  end

  test "argv is DERIVED from ontology facts: every attribute fact appears, no flag is stored in the ontology",
       %{m: m} do
    graph = GgenIgniter.Ontology.load!(@ontology)

    facts =
      GgenIgniter.Query.run(
        graph,
        File.read!("priv/ggen/semantic-jira-pack/gates/064_a2a_attributes.rq")
      )

    assert length(facts) == 4

    [gen_resource] = Enum.filter(m.module.plan(), &(&1.task == "ash.gen.resource"))

    attr_args =
      gen_resource.argv
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn
        ["--attribute", value] -> [value]
        _ -> []
      end)
      |> Enum.sort()

    expected =
      facts
      |> Enum.map(fn f ->
        mods =
          [
            if(f["is_public"] in [true, "true"], do: "public"),
            if(f["is_required"] in [true, "true"], do: "required")
          ]
          |> Enum.reject(&is_nil/1)

        Enum.join([f["attribute_name"], f["attribute_type"]] ++ mods, ":")
      end)
      |> Enum.sort()

    assert attr_args == expected

    # each fact is a real attribute of the generated resource, with modifiers
    for f <- facts do
      assert m.resource_source =~ "attribute :#{f["attribute_name"]}, :#{f["attribute_type"]}"
    end

    ontology = File.read!(@ontology)
    refute ontology =~ "--attribute"
    refute ontology =~ "--extend"
  end

  test "F9: a second run over the already-manufactured project changes nothing", %{m: m} do
    applied = apply_igniter!(m.igniter)

    previous = Application.fetch_env(M.app(), :ash_domains)
    Application.put_env(M.app(), :ash_domains, [SemanticJira.Work])

    on_exit(fn ->
      case previous do
        {:ok, v} -> Application.put_env(M.app(), :ash_domains, v)
        :error -> Application.delete_env(M.app(), :ash_domains)
      end
    end)

    second = M.compose(applied, m.module, [])

    assert second.issues == []
    assert second.tasks == []
    assert_unchanged(second)
  end

  test "negative control: the raw upstream ash_a2a.install is NOT idempotent (why the step is guarded)",
       %{m: m} do
    applied = apply_igniter!(m.igniter)

    raw =
      M.compose(applied, "ash_a2a.install", [
        "--target",
        "SemanticJira.Work.Task",
        "--type",
        "resource"
      ])

    assert_raise ExUnit.AssertionError, fn -> assert_unchanged(raw) end
  end

  test "F8: renaming an attribute in the ontology changes the derived plan (drift is visible, not silent)",
       %{m: m} do
    renamed =
      String.replace(
        File.read!(@ontology),
        ~s|a2a:attributeName "receipt_digest"|,
        ~s|a2a:attributeName "receipt_hash"|
      )

    refute renamed == File.read!(@ontology)

    dir = Path.join(System.tmp_dir!(), "a2a_rename_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    onto = Path.join(dir, "renamed.ttl")
    File.write!(onto, renamed)

    {_output, 0} =
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

    rendered = File.read!(Path.join(dir, "semantic_jira.a2a.manufacture.ex"))
    assert rendered =~ "receipt_hash:string:public"
    refute rendered =~ "receipt_digest"
    assert m.source =~ "receipt_digest:string:public"
  end
end
