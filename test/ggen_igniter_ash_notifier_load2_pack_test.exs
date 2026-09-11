defmodule GgenIgniter.AshNotifierLoad2PackTest do
  @moduledoc """
  Chicago-style test over the real `ash-notifier-load2-pack`
  (`priv/ggen/ash-notifier-load2-pack/`): loads the pack's real
  `ontology.ttl` into a real `RDF.Graph`, runs its real gate query against
  it, and renders its real EEx template with the real single-row bindings
  -- the same `Ontology.load!/1 -> Query.run/2 -> Render.render/2` pipeline
  `mix ggen_igniter.sync` itself wires (see
  `lib/mix/tasks/ggen_igniter.sync.ex` moduledoc). No mocks: real RDF
  parsing, real SPARQL execution (`sparql` engine, in-process, no external
  service), real EEx evaluation.

  Beyond the `chicago-fault-injection-pack` test's pattern of asserting the
  rendered string, this file goes one step further per this ticket's DoD:
  it `Code.eval_string/1`s the rendered `load/2` function body inside a
  real wrapping module, alongside a real companion "Info" module providing
  the DSL-entity accessor the rendered code calls, and asserts on the real
  value the compiled function returns when invoked -- proving the rendered
  code compiles AND behaves correctly, not merely that the template string
  matches.

  Run twice, against two INDEPENDENT vocabularies, to prove the pack's
  ontology+query+template genuinely generalizes across subjects rather than
  being hardcoded to one DSL's predicate names:

  1. The pack's own real ontology individual -- `ash_ex4pm`'s hand-written
     `load/2` (commit `d4ffb71`), expressed as data.
  2. A second, hand-built binding set using a completely different
     vocabulary (`rules`/`trigger`/`watched_paths`/`path` instead of
     `activities`/`on`/`object_relationships`/`relationship`), rendered
     against a second, independent companion "Info" module
     (`GgenIgniter.Fixtures.AshNotifierLoad2.RulesInfo`,
     `test/support/ash_notifier_load2/rules_info.ex`) -- this repo's
     in-repo generality substitute for a second real EXTERNAL Spark-DSL
     extension example (see `docs/integrations/ash/notifier-load2.md`'s
     honest disclosure: a real second external example was not located
     this pass).
  """

  use ExUnit.Case, async: true

  @pack_dir Path.join([__DIR__, "..", "priv", "ggen", "ash-notifier-load2-pack"])
  @ontology_path Path.join(@pack_dir, "ontology.ttl")
  @gate_path Path.join([@pack_dir, "gates", "010_load2_spec.rq"])
  @template_path Path.join([@pack_dir, "templates", "notifier_load2.ex.eex"])

  defp strip_frontmatter(content) do
    case String.split(content, "---\n", parts: 3) do
      ["", _frontmatter, body] -> body
      [only] -> only
    end
  end

  defp template, do: File.read!(@template_path) |> strip_frontmatter()

  # Compiles the rendered `load/2` function inside a fresh module named
  # `mod_name`, declaring the real `Ash.Notifier` behaviour (available here
  # because `:ash` is a real dev/test dependency of this repo, per
  # `mix.exs:176`) so `@impl Ash.Notifier` is checked for real rather than
  # warning "no behaviour was declared".
  defp compile_notifier!(mod_name, rendered_fn) do
    source = """
    defmodule #{mod_name} do
      @behaviour Ash.Notifier

      #{rendered_fn}

      @impl Ash.Notifier
      def notify(_notification), do: :ok

      @impl Ash.Notifier
      def requires_original_data?(_resource, _action), do: false
    end
    """

    [{mod, _bytecode} | _] = Code.compile_string(source)
    mod
  end

  describe "the pack's own ontology individual (ash_ex4pm precedent)" do
    setup do
      graph = GgenIgniter.Ontology.load!(@ontology_path)
      query_string = File.read!(@gate_path)
      [row] = GgenIgniter.Query.run(graph, query_string)

      bindings = %{
        info_module: row["info_module"],
        entities_function: row["entities_function"],
        match_field: row["match_field"],
        list_field: row["list_field"],
        item_field: row["item_field"]
      }

      {:ok, bindings: bindings}
    end

    test "the real gate query returns ash_ex4pm's real spec row", %{bindings: bindings} do
      assert bindings.info_module == "AshEx4pm.Info"
      assert bindings.entities_function == "activities"
      assert bindings.match_field == "on"
      assert bindings.list_field == "object_relationships"
      assert bindings.item_field == "relationship"
    end

    test "rendering produces valid, parseable Elixir source", %{bindings: bindings} do
      rendered = GgenIgniter.Render.render(template(), bindings)

      assert {:ok, _quoted} = Code.string_to_quoted(rendered)
      assert rendered =~ "@impl Ash.Notifier"
      assert rendered =~ "AshEx4pm.Info.activities()"
      assert rendered =~ "&(&1.on == action.name)"
      assert rendered =~ "Enum.map(entity.object_relationships, & &1.relationship)"
    end

    test "the compiled load/2 returns the real declared relationship names, matched by action, for a real DSL entity",
         %{bindings: bindings} do
      rendered = GgenIgniter.Render.render(template(), bindings)

      mod =
        compile_notifier!(
          "GgenIgniter.Fixtures.AshNotifierLoad2.CompiledFromAshEx4pmSpec",
          rendered
        )

      # The rendered code ignores `resource` (it always calls
      # `AshEx4pm.Info.activities(resource)` since `AshEx4pm.Info` is the
      # literal `nlp:infoModule` binding, not derived from `resource`) --
      # any real atom works; `:widget` stands in for a real Ash.Resource.
      resource = :widget
      create_action = %{name: :create}
      archive_action = %{name: :archive}
      unmatched_action = %{name: :destroy}

      assert mod.load(resource, create_action) == [:owner, :team]
      assert mod.load(resource, archive_action) == [:owner]
      assert mod.load(resource, unmatched_action) == []
    end
  end

  describe "reused against a second, independent vocabulary (in-repo generality substitute)" do
    test "the same template renders and behaves correctly for a completely different DSL vocabulary" do
      bindings = %{
        info_module: "GgenIgniter.Fixtures.AshNotifierLoad2.RulesInfo",
        entities_function: "rules",
        match_field: "trigger",
        list_field: "watched_paths",
        item_field: "path"
      }

      rendered = GgenIgniter.Render.render(template(), bindings)

      assert {:ok, _quoted} = Code.string_to_quoted(rendered)
      assert rendered =~ "GgenIgniter.Fixtures.AshNotifierLoad2.RulesInfo.rules()"
      assert rendered =~ "&(&1.trigger == action.name)"
      assert rendered =~ "Enum.map(entity.watched_paths, & &1.path)"

      # Proves genericity, not leftover ash_ex4pm identifiers.
      refute rendered =~ "AshEx4pm"
      refute rendered =~ "activities"
      refute rendered =~ "object_relationships"

      mod =
        compile_notifier!(
          "GgenIgniter.Fixtures.AshNotifierLoad2.CompiledFromRulesSpec",
          rendered
        )

      resource = GgenIgniter.Fixtures.AshNotifierLoad2.RulesInfo
      update_action = %{name: :update}
      unmatched_action = %{name: :create}

      assert mod.load(resource, update_action) == [:assignee, :status]
      assert mod.load(resource, unmatched_action) == []
    end
  end
end
