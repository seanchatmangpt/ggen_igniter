defmodule GgenIgniter.PendingActuationTest do
  @moduledoc """
  Chicago-style, no-mocks proof of the `%GgenIgniter.PendingActuation{}` IR
  the `:render`/`:admit`/`:actuate` steps of
  `GgenIgniter.Reactors.ReconcileReactor` now really produce and consume
  (replacing the bare `{out_path, content}` shape this pipeline previously
  used internally).

  Every collaborator here is real and is the ACTUAL production code path,
  never a reimplementation or a stub:

    * `GgenIgniter.PendingActuation.for_file/6` -- the exact function
      `GgenIgniter.Reactors.ReconcileReactor`'s private `render_target/2`
      calls to build each item's real plan.
    * `GgenIgniter.Manifest.load/1`/`get_entry/2`/`hash_content/1` -- the
      exact real reconciliation-manifest reads the render step performs.
    * `GgenIgniter.Ontology.load!/1`, `GgenIgniter.Engine.fetch!/1`,
      `GgenIgniter.Reconcile.build_bindings/1`, `GgenIgniter.Render.render/2`
      -- the exact real query/render pipeline the render step runs, used
      here only to independently reproduce what the NEXT run's real content
      will be, so the plan-level assertions below are checked against real,
      freshly-computed content, not a hardcoded string.
    * `Reactor.run/2` against the real, real
      `GgenIgniter.Reactors.ReconcileReactor` -- the real end-to-end
      pipeline (`:render` -> `:admit` -> `:actuate` -> `:verify` ->
      `:commit_manifest` -> `:receipt`), including a real `mix compile
      --warnings-as-errors` subprocess for `:verify` against a real,
      minimal scratch Mix project.

  No `Mix`/`Reactor`/`File` mocking anywhere in this file -- every assertion
  is against real on-disk state or a real struct built by the real
  production function.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.{Engine, Manifest, Ontology, PendingActuation, Reconcile, Render}
  alias GgenIgniter.Reactors.ReconcileReactor

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_pending_actuation_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A real, minimal, dependency-free Mix project -- enough for `:verify`'s
  # real `mix compile --warnings-as-errors` subprocess to succeed honestly
  # on whatever `:actuate` writes into its `lib/`.
  defp new_mix_project! do
    dir = scratch_dir!("project")
    File.mkdir_p!(Path.join(dir, "lib"))
    app = "pending_actuation_fixture_#{System.unique_integer([:positive])}"

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule #{Macro.camelize(app)}.MixProject do
      use Mix.Project

      def project do
        [app: :#{app}, version: "0.1.0", elixir: "~> 1.14", deps: []]
      end
    end
    """)

    dir
  end

  defp write_ontology!(dir, greeting) do
    path = Path.join(dir, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/pa#> .
    ex:Widget a ex:Module ;
      ex:moduleName "PendingActuationFixture.Widget" ;
      ex:greeting "#{greeting}" .
    """)

    path
  end

  defp write_query!(dir) do
    path = Path.join(dir, "spec.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/pa#>
    SELECT ?module_name ?greeting WHERE {
      ex:Widget ex:moduleName ?module_name ; ex:greeting ?greeting .
    }
    """)

    path
  end

  defp write_template!(dir) do
    path = Path.join(dir, "widget.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  # Reproduces exactly what `ReconcileReactor`'s real render step would
  # render for `ontology_path` right now -- using the same real, public
  # production functions (`Ontology.load!/1`, the real `sparql` engine,
  # `Reconcile.build_bindings/1`, `Render.render/2`), so the "next run's
  # content" used in plan-level assertions below is genuinely computed, not
  # hardcoded.
  defp render_now!(ontology_path, query_path, template_path) do
    graph = Ontology.load!(ontology_path)
    engine = Engine.fetch!("sparql")
    context = engine.prepare!(graph, [])
    rows = engine.run(context, File.read!(query_path))
    bindings = Reconcile.build_bindings([{"spec", rows}])
    Render.render(File.read!(template_path), bindings)
  end

  test "unchanged re-run: every %PendingActuation{} in the plan has previous_hash == " <>
         "desired_hash and operation still :replace, while the real :actuate outcome is " <>
         ":unchanged -- both the plan-level prediction and the real actuation fact are asserted" do
    fixtures = scratch_dir!("fixtures")
    ontology_path = write_ontology!(fixtures, "hello_v1")
    query_path = write_query!(fixtures)
    template_path = write_template!(fixtures)

    project_dir = new_mix_project!()
    out_path = Path.join([project_dir, "lib", "widget.ex"])
    out_template = out_path

    opts = [
      engine: "sparql",
      ontology: ontology_path,
      query: "spec=#{query_path}",
      template: template_path,
      out: out_path,
      manifest_dir: project_dir,
      verify_cwd: project_dir
    ]

    # -- Run 1: fresh target, real :written outcome. (`GgenIgniter.Receipt`'s
    # own single-target compatibility field lives in `metadata["outcome"]`,
    # a string -- see `GgenIgniter.Reactors.ReconcileReactor.finalize_evidence/1`.)
    assert {:ok, receipt1} = Reactor.run(ReconcileReactor, %{reconcile_opts: opts})
    assert receipt1.metadata["outcome"] == "written"
    assert File.exists?(out_path)
    content1 = File.read!(out_path)

    # -- Plan-level proof, BEFORE run 2 ever executes: build the REAL
    # %PendingActuation{} the render step would build for this exact
    # unchanged re-run, via the real production constructor.
    manifest = Manifest.load(project_dir)
    recipe_key = Manifest.recipe_key(template_path, out_template)
    old_entry = Manifest.get_entry(manifest, recipe_key)

    # A genuinely unchanged re-run re-renders BYTE-IDENTICAL content (the
    # ontology has not changed) -- computed here via the real render
    # pipeline, not assumed equal to `content1`.
    next_content = render_now!(ontology_path, query_path, template_path)
    assert next_content == content1

    pa =
      PendingActuation.for_file(
        out_path,
        next_content,
        template_path,
        out_template,
        old_entry,
        %{}
      )

    assert %PendingActuation{} = pa
    assert pa.target == out_path
    assert pa.operation == :replace, "expected :replace (target already exists after run 1)"
    assert pa.previous_hash != nil
    assert pa.desired_hash != nil

    assert pa.previous_hash == pa.desired_hash,
           "expected previous_hash == desired_hash for a real unchanged re-run"

    assert PendingActuation.plan_unchanged?(pa)
    assert pa.ownership == true, "run 1's commit_manifest already recorded this path as owned"
    assert pa.compensation_data == {:previous_content, content1}

    # -- Run 2: identical opts. The REAL actuation outcome this plan
    # predicted: `:actuate` really calls `Actuate.write_file!/3`, which
    # really compares real bytes and comes back `:unchanged` -- a
    # different, real fact from `operation: :replace` above (operation is
    # existence-derived at plan time; outcome is a real content compare at
    # actuate time), asserted here together.
    assert {:ok, receipt2} = Reactor.run(ReconcileReactor, %{reconcile_opts: opts})
    assert receipt2.metadata["outcome"] == "unchanged"
    assert File.read!(out_path) == content1, "expected the real file content to be untouched"
  end

  test "changed run: previous_hash != desired_hash at plan time, and the real file content " <>
         "really changes after actuation" do
    fixtures = scratch_dir!("fixtures_changed")
    ontology_path = write_ontology!(fixtures, "hello_v1")
    query_path = write_query!(fixtures)
    template_path = write_template!(fixtures)

    project_dir = new_mix_project!()
    out_path = Path.join([project_dir, "lib", "widget.ex"])
    out_template = out_path

    opts = [
      engine: "sparql",
      ontology: ontology_path,
      query: "spec=#{query_path}",
      template: template_path,
      out: out_path,
      manifest_dir: project_dir,
      verify_cwd: project_dir
    ]

    # -- Run 1: establish the real baseline file.
    assert {:ok, receipt1} = Reactor.run(ReconcileReactor, %{reconcile_opts: opts})
    assert receipt1.metadata["outcome"] == "written"
    previous_content = File.read!(out_path)
    assert previous_content =~ "hello_v1"

    # -- Really change the ontology's content in place (same recipe_key --
    # same template/out_template pair -- exactly the "re-sync the same
    # ontology.ttl as its CONTENT evolves" scenario
    # `GgenIgniter.Manifest`'s own moduledoc describes).
    write_ontology!(fixtures, "hello_v2")
    new_content = render_now!(ontology_path, query_path, template_path)
    assert new_content != previous_content
    assert new_content =~ "hello_v2"

    # -- Plan-level proof, BEFORE run 2 ever executes.
    manifest = Manifest.load(project_dir)
    recipe_key = Manifest.recipe_key(template_path, out_template)
    old_entry = Manifest.get_entry(manifest, recipe_key)

    pa =
      PendingActuation.for_file(
        out_path,
        new_content,
        template_path,
        out_template,
        old_entry,
        %{}
      )

    assert pa.operation == :replace
    assert pa.previous_hash == Manifest.hash_content(previous_content)
    assert pa.desired_hash == Manifest.hash_content(new_content)

    assert pa.previous_hash != pa.desired_hash,
           "expected previous_hash != desired_hash for a real changed run"

    refute PendingActuation.plan_unchanged?(pa)
    assert pa.compensation_data == {:previous_content, previous_content}

    # -- Run 2: the real changed ontology. Real :written outcome, and the
    # real file content genuinely changed on disk.
    assert {:ok, receipt2} = Reactor.run(ReconcileReactor, %{reconcile_opts: opts})
    assert receipt2.metadata["outcome"] == "written"
    assert File.read!(out_path) == new_content
    assert File.read!(out_path) != previous_content
  end
end
