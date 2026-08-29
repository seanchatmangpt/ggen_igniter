defmodule GgenIgniter.ReconcileReactorCompensationTelemetryTest do
  @moduledoc """
  Chicago-style: real ETS table (the module-under-test's own real, named,
  public `:ggen_igniter_compensation_counters` table -- never a mock/stub of
  `Reactor.Middleware`'s `event/3`/`error/2` callbacks), a real
  `GgenIgniter.Reactors.ReconcileReactor.run/1` execution against real
  ontology/query/template fixture files and a real scratch Mix project (the
  same real `mix compile --warnings-as-errors` subprocess `:verify` always
  runs), and state-based assertions read back from
  `GgenIgniter.Reactors.CompensationTelemetryMiddleware.counters/0` (a real
  `:ets.tab2list/1` snapshot) -- never an interaction assertion like "was
  `event/3` called".

  Both fixture builders below (`write_ontology!/1`, `write_query!/3`,
  `write_valid_template!/1`, `write_broken_template!/1`, `new_mix_project!/0`,
  `scratch_dir!/0`) and both real compensation-triggering scenarios (the
  `:verify`-fails-so-`:actuate`-gets-`undo/4`'d path, and the
  `:actuate`-self-heals-its-own-failure path) are copied verbatim from
  `test/ggen_igniter_reconcile_reactor_test.exs`'s own already-proven real
  setups, per this task's own instruction to reuse a real compensation
  fixture rather than inventing a new one.

  `async: false`: `CompensationTelemetryMiddleware` counts into ONE real,
  named ETS table shared process-globally across every test in this BEAM VM
  (not per-test/per-process state) -- running this file's tests concurrently
  with each other (or with any other test that exercises the same reactor)
  would make one test's real counter increments visible to another's
  assertions, which is exactly the shared-mutable-state hazard `async: true`
  is unsafe for.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Manifest
  alias GgenIgniter.Reactors.CompensationTelemetryMiddleware
  alias GgenIgniter.Reactors.ReconcileReactor

  # -- Fixture builders (copied verbatim from
  # test/ggen_igniter_reconcile_reactor_test.exs -- see that file for the
  # real, already-proven rationale behind each one) --------------------------

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_compensation_telemetry_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))

    app = "reactor_fixture_#{System.unique_integer([:positive])}"

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

  defp write_ontology!(dir) do
    path = Path.join(dir, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/rr#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "GgenIgniterCompTelemetryFixture.Alpha" ;
      ex:greeting "hello_from_alpha" .
    ex:Beta a ex:Module ;
      ex:moduleName "GgenIgniterCompTelemetryFixture.Beta" ;
      ex:greeting "hello_from_beta" .
    """)

    path
  end

  defp write_query!(dir, name, subject) do
    path = Path.join(dir, "#{name}.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/rr#>
    SELECT ?module_name ?greeting WHERE {
      ex:#{subject} ex:moduleName ?module_name ; ex:greeting ?greeting .
    }
    """)

    path
  end

  defp write_valid_template!(dir) do
    path = Path.join(dir, "valid.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  # Deliberately invalid Elixir: an unclosed `(` before `end` -- a real parse
  # failure `mix compile` cannot paper over.
  defp write_broken_template!(dir) do
    path = Path.join(dir, "broken.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def broken(
    end
    """)

    path
  end

  # -- The real test -----------------------------------------------------

  describe "CompensationTelemetryMiddleware.counters/0 after real ReconcileReactor runs" do
    test "a real :verify failure (undo/4 on :actuate) increments :undo_start and, via error/2, :build_broken" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      broken_template = write_broken_template!(fixtures)

      project_dir = new_mix_project!()

      existing_path = Path.join([project_dir, "lib", "existing.ex"])
      original_content = "defmodule Existing do\n  def value, do: :original\nend\n"
      File.write!(existing_path, original_content)

      new_path = Path.join([project_dir, "lib", "new_from_run.ex"])

      before_counters = CompensationTelemetryMiddleware.counters()

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: broken_template, query: "spec=#{query_alpha}", out: existing_path],
          [template: broken_template, query: "spec=#{query_beta}", out: new_path]
        ]
      ]

      assert {:error, receipt} = ReconcileReactor.run(reconcile_opts)

      # Sanity: this is the real, already-proven undo/build_broken path (see
      # test/ggen_igniter_reconcile_reactor_test.exs) -- confirming it here
      # too keeps this test's own counter assertions grounded in a real,
      # verified compensation event, not an assumed one.
      assert receipt.standing == :build_broken
      assert File.read!(existing_path) == original_content
      refute File.exists?(new_path)
      refute File.exists?(Manifest.path(project_dir))

      after_counters = CompensationTelemetryMiddleware.counters()

      # -- THE REAL, STATE-BASED PROOF: real ETS counters genuinely advanced
      # by this real run, read back via counters/0 -- never an assertion
      # that event/3 or error/2 were "called".
      assert Map.get(after_counters, :undo_start, 0) > Map.get(before_counters, :undo_start, 0),
             ":undo_start should have incremented for :actuate's real undo/4 " <>
               "(triggered by :verify's real compile failure) -- before=#{inspect(before_counters)}, " <>
               "after=#{inspect(after_counters)}"

      assert Map.get(after_counters, :build_broken, 0) >
               Map.get(before_counters, :build_broken, 0),
             ":build_broken should have incremented via error/2's real " <>
               "find_step_error/2 match against the real {:compile_failed, _} reason -- " <>
               "before=#{inspect(before_counters)}, after=#{inspect(after_counters)}"
    end

    test "a real :actuate self-heal (no :verify/compile step involved) increments :compensate_start" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      valid_template = write_valid_template!(fixtures)

      project_dir = new_mix_project!()

      out_a = Path.join([project_dir, "lib", "compensated_a.ex"])

      # Same real "parent segment is a plain file, not a directory" layout
      # test/ggen_igniter_reconcile_reactor_test.exs's own test 3b uses to
      # make `Actuate.write_file!/3`'s real `File.mkdir_p!/1` genuinely raise
      # `File.Error` mid-`:actuate`, without ever reaching `:verify`.
      blocker_file = Path.join([project_dir, "lib", "compensated_b_blocker.ex"])
      File.write!(blocker_file, "not a directory\n")
      out_b = Path.join(blocker_file, "nested.ex")

      before_counters = CompensationTelemetryMiddleware.counters()

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: valid_template, query: "spec=#{query_alpha}", out: out_a],
          [template: valid_template, query: "spec=#{query_beta}", out: out_b]
        ]
      ]

      assert {:error, receipt} = ReconcileReactor.run(reconcile_opts)

      # Sanity: the real, already-proven self-heal/:compensated path (see
      # test/ggen_igniter_reconcile_reactor_test.exs's test 3b) -- never
      # reaches :verify, so this is a genuinely different real trigger than
      # the test above (`:actuate`'s OWN `compensate/4` firing on ITS OWN
      # `run/3` failure, not a LATER step's `undo/4`).
      assert receipt.standing == :compensated
      refute File.exists?(out_a)
      refute File.exists?(Manifest.path(project_dir))

      after_counters = CompensationTelemetryMiddleware.counters()

      assert Map.get(after_counters, :compensate_start, 0) >
               Map.get(before_counters, :compensate_start, 0),
             ":compensate_start should have incremented for :actuate's real " <>
               "compensate/4 firing on its own run/3 failure -- " <>
               "before=#{inspect(before_counters)}, after=#{inspect(after_counters)}"
    end
  end
end
