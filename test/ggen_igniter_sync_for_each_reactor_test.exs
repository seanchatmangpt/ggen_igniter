defmodule GgenIgniter.SyncForEachReactorTest do
  @moduledoc """
  Chicago-style, real subprocess, no mocks: proves the two real, headline
  claims v26.9.2 (workstream B) exists to deliver, both through the ACTUAL
  `mix ggen_igniter.sync --for-each` CLI path (`Mix.Tasks.GgenIgniter.Sync.
  run_for_each_via_reactor!/7`), not just the pre-existing
  `GgenIgniter.Reactors.ReconcileReactor.run/1` `:targets` mechanism those
  two REAL claims are built on (already covered generically by
  `test/ggen_igniter_reconcile_reactor_test.exs`'s own multi-target
  compensation test):

    1. **The real correctness fix (workstream B(2)):** a `--for-each`
       recipe's stale-prune detection is computed ONCE against the UNION of
       every row's real output path, not independently per row -- so
       removing ONE row's underlying data (an ontology entity deleted)
       flags ONLY that row's own output path as stale, never a SIBLING
       row's still-produced path.
    2. **The real compensation-coverage payoff (workstream B(6)):** a real
       mid-run failure on ONE row (a genuinely malformed value that breaks
       `mix compile --warnings-as-errors` for the whole actuated project)
       reverts EVERY row's real writes in that run, not just the failing
       row's -- the deliberate all-or-nothing trade-off this whole task
       exists to deliver, in exchange for full Reactor compensation
       coverage `--for-each` never had before this task.

  Every collaborator is real: real ontology/query/template files on disk, a
  real `mix ggen_igniter.sync` subprocess, a real nested `mix compile
  --warnings-as-errors` subprocess for `:verify`, and real file-existence/
  content assertions after each run -- never an assertion on "was
  ReconcileReactor.run called".
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  defp scratch_dir!(tag) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_sync_for_each_reactor_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A real, minimal, dependency-free Mix project -- enough for a real
  # `mix compile --warnings-as-errors` subprocess (`:verify`) to succeed or
  # genuinely fail on whatever this run's `--for-each` fan-out writes into
  # its `lib/`.
  defp new_mix_project!(tag) do
    dir = scratch_dir!(tag)
    File.mkdir_p!(Path.join(dir, "lib"))
    app = "for_each_reactor_fixture_#{System.unique_integer([:positive])}"

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

  defp run(args) do
    System.cmd("mix", args, cd: File.cwd!(), stderr_to_stdout: true)
  end

  describe "workstream B(2): stale-prune detection is computed ONCE across the whole --for-each recipe" do
    test "removing one row's data flags ONLY that row's path as stale, never a sibling row's" do
      out_dir = scratch_dir!("stale")

      out_template = Path.join(out_dir, "<%= module_name %>.ex")

      base_args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--query",
        "modules=test/fixtures/modules.rq",
        "--for-each",
        "modules",
        "--template",
        "test/fixtures/for_each_module.ex.eex",
        "--out",
        out_template,
        "--manifest-dir",
        out_dir,
        "--verify-cwd",
        File.cwd!()
      ]

      # -- Run 1: the real, unmodified 3-row fixture ontology
      # (`test/fixtures/for_each_ontology.ttl` -- Alpha/Beta/Gamma).
      {output1, exit1} =
        run(base_args ++ ["--ontology", "test/fixtures/for_each_ontology.ttl"])

      assert exit1 == 0, "first --for-each sync (3 rows) failed:\n#{output1}"

      alpha_path = Path.join(out_dir, "Multi.Alpha.ex")
      beta_path = Path.join(out_dir, "Multi.Beta.ex")
      gamma_path = Path.join(out_dir, "Multi.Gamma.ex")

      assert File.exists?(alpha_path)
      assert File.exists?(beta_path)
      assert File.exists?(gamma_path)

      alpha_content = File.read!(alpha_path)
      beta_content = File.read!(beta_path)

      # -- Run 2: a REAL second ontology with Gamma's own entity genuinely
      # removed (mirrors `GgenIgniter.Manifest`'s own moduledoc convention of
      # simulating an ontology rename/removal via a distinct "before"/"after"
      # fixture pair, rather than mutating one file in place).
      ontology_2rows = Path.join(out_dir, "_fixture_2rows.ttl")

      File.write!(ontology_2rows, """
      @prefix mod: <http://seanchatmangpt.github.io/packs/multi-module#> .

      mod:M1 a mod:GeneratedModule ;
          mod:moduleName "Multi.Alpha" ;
          mod:fieldName "alpha_field" .

      mod:M2 a mod:GeneratedModule ;
          mod:moduleName "Multi.Beta" ;
          mod:fieldName "beta_field" .
      """)

      {output2, exit2} = run(base_args ++ ["--ontology", ontology_2rows])

      # `--on-stale refuse` is the default, and Gamma's own path genuinely
      # IS stale now (its underlying entity is gone) -- a real refusal is
      # the CORRECT outcome here, not a bug. The real, confirmed bug this
      # test guards against is refusing (or --on-stale prune deleting) the
      # WRONG paths: before the workstream B(2) fix, Alpha's and Beta's own
      # still-produced paths were ALSO independently flagged stale (each
      # row's own diff wrongly treated every OTHER row's legitimately
      # produced path as stale), so the refusal message named all three
      # paths -- Alpha and Beta included -- instead of Gamma alone.
      refute exit2 == 0, "expected run 2 to be refused (Gamma is genuinely stale):\n#{output2}"
      assert output2 =~ "refusing to sync"
      assert output2 =~ gamma_path

      refute output2 =~ alpha_path,
             "workstream B(2) regression: Alpha's still-produced path must never be flagged stale"

      refute output2 =~ beta_path,
             "workstream B(2) regression: Beta's still-produced path must never be flagged stale"

      # `refuse` means nothing at all was written or deleted this run --
      # real ground truth: all three original files, byte-identical.
      assert File.read!(alpha_path) == alpha_content
      assert File.read!(beta_path) == beta_content
      assert File.exists?(gamma_path)
    end
  end

  describe "workstream B(6): a real mid-run failure on one row reverts ALL rows' writes" do
    test "a genuinely malformed row poisons :verify's real mix compile, and Reactor's real undo/3 reverts every row" do
      project_dir = new_mix_project!("compensation")
      out_dir = Path.join(project_dir, "lib")
      out_template = Path.join(out_dir, "<%= module_name %>.ex")

      # A real 3-row ontology: two well-formed rows (Alpha, Beta), and one
      # row whose `module_name` value is genuinely NOT a valid Elixir alias
      # (contains a literal space) -- `test/fixtures/for_each_module.ex.eex`
      # interpolates it bare into `defmodule <%= module_name %> do`, so this
      # one row's real rendered file is genuinely invalid Elixir syntax,
      # exactly the "a real forced write failure on one row" class of
      # injected failure this task's own plan names.
      ontology_path = Path.join(project_dir, "poisoned.ttl")

      File.write!(ontology_path, """
      @prefix mod: <http://seanchatmangpt.github.io/packs/multi-module#> .

      mod:M1 a mod:GeneratedModule ;
          mod:moduleName "Multi.Alpha" ;
          mod:fieldName "alpha_field" .

      mod:M2 a mod:GeneratedModule ;
          mod:moduleName "Multi.Beta" ;
          mod:fieldName "beta_field" .

      mod:M3 a mod:GeneratedModule ;
          mod:moduleName "Multi Broken" ;
          mod:fieldName "broken_field" .
      """)

      alpha_path = Path.join(out_dir, "Multi.Alpha.ex")
      beta_path = Path.join(out_dir, "Multi.Beta.ex")
      broken_path = Path.join(out_dir, "Multi Broken.ex")

      refute File.exists?(alpha_path)
      refute File.exists?(beta_path)
      refute File.exists?(broken_path)

      args = [
        "ggen_igniter.sync",
        "--engine",
        "sparql",
        "--ontology",
        ontology_path,
        "--query",
        "modules=test/fixtures/modules.rq",
        "--for-each",
        "modules",
        "--template",
        "test/fixtures/for_each_module.ex.eex",
        "--out",
        out_template,
        "--manifest-dir",
        project_dir,
        "--verify-cwd",
        project_dir
      ]

      {output, exit_code} = run(args)

      # THE HEADLINE PROOF: the whole run genuinely fails (real
      # `mix compile --warnings-as-errors` failure on `Multi Broken.ex`,
      # inside the SAME actuated project as Alpha/Beta), and Reactor's real
      # `undo/3` reverts EVERY row this run wrote -- not just the broken
      # one. Before this task, `--for-each` ran via the inline
      # `run_pipeline!/3` pipeline, which had NO compensation at all: Alpha
      # and Beta would have been left genuinely written on disk even though
      # the run overall reported a failure on the broken row.
      refute exit_code == 0, "expected the whole run to fail (a row is genuinely uncompilable)"

      # `:build_broken` -- ReconcileReactor.standing_for_failure/2's real,
      # distinct standing for a `:verify` failure caused specifically by a
      # `{:compile_failed, _}` reason (as opposed to the more generic
      # `:compensated` a non-compile actuation failure would report) -- see
      # that function and this module's own moduledoc. The real revert
      # mechanism (Reactor's `undo/3`) is identical either way.
      assert output =~ "build_broken"

      refute File.exists?(alpha_path),
             "workstream B(6): Alpha's write must be reverted by real compensation"

      refute File.exists?(beta_path),
             "workstream B(6): Beta's write must be reverted by real compensation"

      refute File.exists?(broken_path),
             "the broken row's own write must be reverted too (it did genuinely get written before :verify ran)"

      # No partial manifest entry for this recipe either -- reconciliation
      # only ever advances on a real, successful :alive standing.
      refute File.exists?(Path.join(project_dir, ".ggen_igniter/manifest.json"))
    end
  end
end
