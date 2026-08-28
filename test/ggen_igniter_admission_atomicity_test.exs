defmodule GgenIgniter.AdmissionAtomicityTest do
  @moduledoc """
  Chicago-style, no-mocks proof of the plan/admit/actuate BOUNDARY in
  `GgenIgniter.Reactors.ReconcileReactor`: real ontology files, real `sparql`
  engine queries, real EEx templates, a real `ReconcileReactor.run/1` call
  over a THREE-TARGET batch, and real `File.exists?/1`/`File.read!/1` checks
  against real disk state -- no `Reactor`/`Mix`/`File` mocking anywhere in
  this file.

  ## What this proves, precisely

  For a batch of N = 3 planned actuations where the THIRD target (index 2,
  "Gamma") makes the run's real stale-output policy trip (the same
  `GgenIgniter.Manifest.stale_paths/2` mechanism `ReconcileReactor`'s own
  moduledoc documents, here triggered for real by the SAME recipe --
  identical `(template_path, out_template)` -- resolving to a DIFFERENT
  rendered path across two real runs, exactly the "resource renamed" case
  this whole reconciliation system exists to catch), the two OTHER targets
  (Alpha, Beta -- both fresh, both independently writable, both would
  succeed if run alone) are NEVER written to real disk. `:admit` is one
  Reactor step evaluated over the FULL `[%PendingActuation{}]` plan (every
  target's real intended write PLUS the real stale-delete candidate) before
  `:actuate` ever runs -- Reactor's own dependency graph (`:actuate` takes
  `result(:admit)` as an argument) makes "some items already got written
  before the batch was fully admitted" structurally impossible, not merely
  untested. This is the real, load-bearing difference from the existing
  "two targets collide on the same --out path" test in
  `ggen_igniter_reconcile_reactor_test.exs`: here NONE of the three targets
  share a target path with each other -- the refusal comes from a DIFFERENT
  admission rule (real stale-output detection), and every one of the three
  items is independently well-formed on its own.

  Every collaborator is real production code: `GgenIgniter.Reactors.ReconcileReactor.run/1`
  (the real Reactor pipeline), `GgenIgniter.Manifest` (real `.ggen_igniter/manifest.json`
  read/write), the real `sparql` engine, real EEx rendering via `GgenIgniter.Render`.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Manifest
  alias GgenIgniter.Reactors.ReconcileReactor

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_admission_atomicity_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A real, minimal, dependency-free Mix project -- enough for `:verify`'s
  # real `mix compile --warnings-as-errors` subprocess to succeed honestly on
  # whatever `:actuate` writes into its `lib/` (which, per this test's whole
  # point, should be NOTHING).
  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))
    app = "admission_atomicity_fixture_#{System.unique_integer([:positive])}"

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

  # Alpha/Beta are two independent, always-fresh single-row entities; Gamma
  # carries a `slug` that changes across runs -- the SAME (template,
  # out_template) recipe resolving to a DIFFERENT real path is exactly how a
  # real rename/removal in the ontology produces a mechanically-detectable
  # stale output (see GgenIgniter.Manifest's own moduledoc).
  defp write_ontology!(dir, gamma_slug) do
    path = Path.join(dir, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/aa#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "AdmissionAtomicityFixture.Alpha" ;
      ex:greeting "hello_alpha" .
    ex:Beta a ex:Module ;
      ex:moduleName "AdmissionAtomicityFixture.Beta" ;
      ex:greeting "hello_beta" .
    ex:Gamma a ex:Module ;
      ex:moduleName "AdmissionAtomicityFixture.Gamma" ;
      ex:greeting "hello_gamma" ;
      ex:slug "#{gamma_slug}" .
    """)

    path
  end

  defp write_query!(dir, name, subject) do
    path = Path.join(dir, "#{name}.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/aa#>
    SELECT ?module_name ?greeting WHERE {
      ex:#{subject} ex:moduleName ?module_name ; ex:greeting ?greeting .
    }
    """)

    path
  end

  defp write_gamma_query!(dir) do
    path = Path.join(dir, "spec_gamma.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/aa#>
    SELECT ?module_name ?greeting ?slug WHERE {
      ex:Gamma ex:moduleName ?module_name ; ex:greeting ?greeting ; ex:slug ?slug .
    }
    """)

    path
  end

  defp write_template!(dir) do
    path = Path.join(dir, "valid.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  describe "a batch of N=3 targets: item 3's stale-output refusal blocks items 1 and 2 too" do
    test "Alpha and Beta (both independently fine) are never written when Gamma trips the real stale-output gate" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures, "gamma_old")
      alpha_query = write_query!(fixtures, "spec_alpha", "Alpha")
      beta_query = write_query!(fixtures, "spec_beta", "Beta")
      gamma_query = write_gamma_query!(fixtures)
      template_path = write_template!(fixtures)

      project_dir = new_mix_project!()

      # Gamma's real out path is EEx-templated on its own `slug` binding --
      # the SAME raw `out_template` string (hence the SAME real
      # `Manifest.recipe_key/2`) resolves to a DIFFERENT real path once
      # `slug` changes between runs.
      gamma_out_template = Path.join([project_dir, "lib", "<%= slug %>.ex"])
      gamma_old_path = Path.join([project_dir, "lib", "gamma_old.ex"])
      gamma_new_path = Path.join([project_dir, "lib", "gamma_new.ex"])

      alpha_out = Path.join([project_dir, "lib", "alpha_fresh.ex"])
      beta_out = Path.join([project_dir, "lib", "beta_fresh.ex"])

      # -- Seed run: establishes a real prior manifest entry recording
      # gamma_old_path as this recipe's ONLY known output -- a real,
      # persisted fact on disk, not a fixture stub.
      seed_opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{gamma_query}",
        template: template_path,
        out: gamma_out_template,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:ok, seed_receipt} = ReconcileReactor.run(seed_opts)
      assert seed_receipt.standing == :alive
      assert File.exists?(gamma_old_path)
      seed_content = File.read!(gamma_old_path)
      assert seed_content =~ "hello_gamma"

      gamma_recipe_key = Manifest.recipe_key(template_path, gamma_out_template)
      seed_manifest = Manifest.load(project_dir)
      assert %{"outputs" => %{}} = seed_entry = Manifest.get_entry(seed_manifest, gamma_recipe_key)
      assert Map.has_key?(seed_entry["outputs"], gamma_old_path)

      # -- Really change the ontology in place: Gamma's slug moves from
      # "gamma_old" to "gamma_new" -- the real "a resource got renamed"
      # event this whole reconciliation system exists to catch.
      write_ontology!(fixtures, "gamma_new")

      refute File.exists?(alpha_out)
      refute File.exists?(beta_out)
      refute File.exists?(gamma_new_path)

      # -- THE BATCH UNDER TEST: three independent targets in ONE Reactor
      # run. Alpha and Beta are both fresh, both would each succeed
      # perfectly well on their own. Gamma (index 2) is the one that trips
      # `:admit`'s real, whole-plan stale-output check (`on_stale` defaults
      # to the safe `:refuse`, per ReconcileReactor's own
      # `resolve_on_stale!/1`) because the SAME recipe now resolves to
      # gamma_new_path, leaving gamma_old_path stale.
      batch_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: template_path, query: "spec=#{alpha_query}", out: alpha_out],
          [template: template_path, query: "spec=#{beta_query}", out: beta_out],
          [template: template_path, query: "spec=#{gamma_query}", out: gamma_out_template]
        ]
      ]

      result = ReconcileReactor.run(batch_opts)

      assert {:error, receipt} = result
      assert receipt.standing == :refused

      # -- THE KEY PROOF: real disk state, read back from disk. Items 1 and
      # 2 (Alpha, Beta) -- both independently well-formed -- were NEVER
      # written, because the WHOLE plan (all three targets' real intended
      # writes, plus Gamma's real stale-delete candidate) is what `:admit`
      # inspects, and it refuses the ENTIRE batch before `:actuate` (the
      # only step that ever touches the filesystem for a create/replace)
      # runs at all.
      refute File.exists?(alpha_out),
             "expected Alpha's independently-fine write to NEVER happen: the whole batch was refused at :admit"

      refute File.exists?(beta_out),
             "expected Beta's independently-fine write to NEVER happen: the whole batch was refused at :admit"

      refute File.exists?(gamma_new_path),
             "expected Gamma's own new write to never happen either"

      # -- The real prior file is left completely untouched -- refusal
      # happens before actuation, so there is nothing to compensate, and
      # `--on-stale prune`'s real deletion (which only ever runs AFTER a
      # successful :verify) never got anywhere near it.
      assert File.exists?(gamma_old_path)
      assert File.read!(gamma_old_path) == seed_content

      # -- No real actuation ever started for this attempt.
      refute Enum.any?(receipt.events, &(&1["activity"] == "ACTUATION_STARTED")),
             "expected zero ACTUATION_STARTED events -- :actuate must never run when :admit refuses"

      assert receipt.files == []

      # -- The real, persisted manifest is untouched too: still exactly the
      # seed run's entry, still pointing at gamma_old_path only.
      post_manifest = Manifest.load(project_dir)
      assert Manifest.get_entry(post_manifest, gamma_recipe_key) == seed_entry
    end
  end
end
