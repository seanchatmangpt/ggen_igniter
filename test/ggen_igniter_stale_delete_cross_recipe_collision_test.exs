defmodule GgenIgniter.StaleDeleteCrossRecipeCollisionTest do
  @moduledoc """
  Chicago-style, no-mocks proof for the confirmed adversarial finding:
  "Stale-prune can delete a file another recipe just wrote and verified this
  same run."

  ## The real scenario this reproduces

  Recipe A previously produced real output path P (recorded in A's real
  manifest entry). In a later run, A no longer produces P (P is legitimately
  stale FOR A), while an unrelated recipe B (a DIFFERENT template/out_template
  pair) independently renders to that SAME real canonical path P for the
  first time, in the SAME run, under `--on-stale prune`.

  Before the fix: `compute_stale_deletes/2` diffed A's old outputs against
  only A's OWN new outputs (never B's), so P was flagged stale for A
  regardless of B's fresh write. `admit_pending/2` only cross-checked
  duplicates WITHIN `write_pending`, never `delete_pending` against
  `write_pending`. `finalize_evidence/1` then called `Manifest.prune!/1` on
  the stale set unconditionally, `File.rm`-ing the file B had just written
  and `:verify`'d as part of this same run.

  After the fix: `compute_stale_deletes/2` unions canonical output paths
  across ALL recipes in the run before computing staleness, so P is excluded
  from A's stale set (real primary fix), and `admit_pending/2` additionally
  refuses outright if any delete/write collision somehow still reaches it
  (defense in depth).

  Every collaborator here is real production code: a real
  `GgenIgniter.Reactors.ReconcileReactor.run/1` batch, the real `sparql`
  engine, real EEx rendering, a real `.ggen_igniter/manifest.json`, and real
  `File.exists?/1`/`File.read!/1` checks against real disk state -- no
  `Mock`/`mox`/`patch`/`monkeypatch` anywhere in this file.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Manifest
  alias GgenIgniter.Reactors.ReconcileReactor

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_stale_cross_collision_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))
    app = "stale_collision_fixture_#{System.unique_integer([:positive])}"

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

  defp write_ontology!(fixtures, a_slug) do
    path = Path.join(fixtures, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/xc#> .
    ex:RecipeA a ex:Module ;
      ex:moduleName "StaleCollisionFixture.RecipeA" ;
      ex:slug "#{a_slug}" .
    ex:RecipeB a ex:Module ;
      ex:moduleName "StaleCollisionFixture.RecipeB" ;
      ex:greeting "hello_from_b" .
    """)

    path
  end

  defp write_query!(fixtures, name, subject, extra_var) do
    path = Path.join(fixtures, "#{name}.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/xc#>
    SELECT ?module_name #{extra_var} WHERE {
      ex:#{subject} ex:moduleName ?module_name#{if extra_var != "", do: " ; ex:#{String.trim_leading(extra_var, "?")} #{extra_var}", else: ""} .
    }
    """)

    path
  end

  defp write_template_a!(fixtures) do
    path = Path.join(fixtures, "recipe_a.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def owner, do: :recipe_a
    end
    """)

    path
  end

  defp write_template_b!(fixtures) do
    path = Path.join(fixtures, "recipe_b.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def owner, do: :recipe_b
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  describe "a stale path for one recipe that is also a fresh write for a different recipe, same run, --on-stale prune" do
    test "the freshly-written, just-verified file is NEVER deleted by prune" do
      fixtures = scratch_dir!()
      project_dir = new_mix_project!()

      template_a = write_template_a!(fixtures)
      template_b = write_template_b!(fixtures)

      query_a = write_query!(fixtures, "spec_a", "RecipeA", "?slug")
      query_b = write_query!(fixtures, "spec_b", "RecipeB", "?greeting")

      # Recipe A's real out path is EEx-templated on its own `slug` binding,
      # so the SAME recipe (same template_path/out_template pair, same
      # `Manifest.recipe_key/2`) resolves to a DIFFERENT real path once
      # `slug` changes between runs.
      a_out_template = Path.join([project_dir, "lib", "<%= slug %>.ex"])
      a_old_path = Path.join([project_dir, "lib", "collide.ex"])
      a_new_path = Path.join([project_dir, "lib", "a_moved.ex"])

      # Recipe B's real out path is FIXED and, by construction, identical to
      # recipe A's OLD (about-to-be-stale) path -- the real collision this
      # finding is about.
      b_out = a_old_path

      # -- Seed run: only recipe A. Establishes a real prior manifest entry
      # recording a_old_path as A's only known output.
      seed_opts = [
        engine: "sparql",
        ontology: write_ontology!(fixtures, "collide"),
        query: "spec=#{query_a}",
        template: template_a,
        out: a_out_template,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:ok, seed_receipt} = ReconcileReactor.run(seed_opts)
      assert seed_receipt.standing == :alive
      assert File.exists?(a_old_path)
      refute File.exists?(a_new_path)

      a_recipe_key = Manifest.recipe_key(template_a, a_out_template)
      seed_manifest = Manifest.load(project_dir)
      seed_entry = Manifest.get_entry(seed_manifest, a_recipe_key)
      assert Map.has_key?(seed_entry["outputs"], a_old_path)

      # -- Real ontology mutation: A's slug moves, so A now resolves to
      # a_new_path, leaving a_old_path stale FOR A. Recipe B is introduced
      # in this SAME batch, independently writing to that exact same real
      # path for the first time.
      ontology_path = write_ontology!(fixtures, "a_moved")

      batch_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        on_stale: "prune",
        targets: [
          [template: template_a, query: "spec=#{query_a}", out: a_out_template],
          [template: template_b, query: "spec=#{query_b}", out: b_out]
        ]
      ]

      result = ReconcileReactor.run(batch_opts)

      assert {:ok, receipt} = result
      assert receipt.standing == :alive

      # -- THE REAL PROOF: recipe B's fresh, verified write at a_old_path
      # (== b_out) survives prune -- it is NOT collateral damage from A's
      # stale-delete, because compute_stale_deletes/2 now unions canonical
      # output paths across the WHOLE plan before computing staleness.
      assert File.exists?(a_old_path),
             "expected recipe B's fresh write at the collision path to survive --on-stale prune"

      content = File.read!(a_old_path)
      assert content =~ "hello_from_b",
             "expected the surviving file to be recipe B's real content, not A's stale leftovers"

      # -- Recipe A's own new output was written too.
      assert File.exists?(a_new_path)

      # -- The real, persisted manifest reflects both recipes' real outputs.
      post_manifest = Manifest.load(project_dir)
      a_post_entry = Manifest.get_entry(post_manifest, a_recipe_key)
      assert Map.has_key?(a_post_entry["outputs"], a_new_path)
      refute Map.has_key?(a_post_entry["outputs"], a_old_path)

      b_recipe_key = Manifest.recipe_key(template_b, b_out)
      b_post_entry = Manifest.get_entry(post_manifest, b_recipe_key)
      assert Map.has_key?(b_post_entry["outputs"], b_out)
    end
  end
end
