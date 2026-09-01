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

  Two tests below (added post-v26.9.1-gap-#7, see
  `GAPS-TO-FILL.v26.9.1.md` #7) exercise the real per-run-scoping fix
  directly:

    * `counters/1` genuinely isolates two real, sequential
      `ReconcileReactor.run/1` calls from each other via
      `:telemetry_run_id` -- the SAME real compile-failure fixture run
      twice with two distinct run ids reads back two independent counts,
      neither summed into the other.
    * `error/2`'s real mutual exclusion: a single real `{:compile_failed,
      _}` failing run bumps ONLY `:build_broken`, never
      `:compensation_failed` too, even though
      `ReconcileReactor.find_compensation_failure/1` is (by construction of
      the real `revert_all/1` catastrophic-standing shape) capable of also
      matching a `:build_broken`-triggering error term.
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

      run_id = make_ref()

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        telemetry_run_id: run_id,
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

      run_counters = CompensationTelemetryMiddleware.counters(run_id)

      # -- THE REAL, STATE-BASED PROOF: real, per-run ETS counters genuinely
      # advanced by THIS real run (scoped by `run_id`, never summed with any
      # other test's counts), read back via counters/1 -- never an assertion
      # that event/3 or error/2 were "called".
      assert Map.get(run_counters, :undo_start, 0) >= 1,
             ":undo_start should have incremented for :actuate's real undo/4 " <>
               "(triggered by :verify's real compile failure) -- run_counters=#{inspect(run_counters)}"

      assert Map.get(run_counters, :build_broken, 0) >= 1,
             ":build_broken should have incremented via error/2's real " <>
               "find_step_error/2 match against the real {:compile_failed, _} reason -- " <>
               "run_counters=#{inspect(run_counters)}"

      # Mutual exclusion (the GAP #7 double-count fix): this real
      # {:compile_failed, _} run must bump ONLY :build_broken via error/2,
      # never :compensation_failed too, for the same one real error term.
      assert Map.get(run_counters, :compensation_failed, 0) == 0,
             ":compensation_failed must NOT also increment for a real " <>
               ":build_broken error term -- run_counters=#{inspect(run_counters)}"
    end

    test "two real sequential ReconcileReactor.run/1 calls with distinct telemetry_run_id are independently readable via counters/1" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      broken_template = write_broken_template!(fixtures)

      run_a = fn ->
        project_dir = new_mix_project!()
        run_id = make_ref()

        reconcile_opts = [
          engine: "sparql",
          ontology: ontology_path,
          manifest_dir: project_dir,
          verify_cwd: project_dir,
          telemetry_run_id: run_id,
          targets: [
            [
              template: broken_template,
              query: "spec=#{query_alpha}",
              out: Path.join([project_dir, "lib", "a.ex"])
            ],
            [
              template: broken_template,
              query: "spec=#{query_beta}",
              out: Path.join([project_dir, "lib", "b.ex"])
            ]
          ]
        ]

        {run_id, reconcile_opts}
      end

      {run_id_1, opts_1} = run_a.()
      {run_id_2, opts_2} = run_a.()

      refute run_id_1 == run_id_2

      assert {:error, receipt_1} = ReconcileReactor.run(opts_1)
      assert receipt_1.standing == :build_broken

      # Run 1's counters must already be nonzero BEFORE run 2 executes --
      # proves run 1's real counts are genuinely isolated under its own
      # `run_id` key, not just "not yet overwritten".
      counters_1_before_run_2 = CompensationTelemetryMiddleware.counters(run_id_1)
      assert Map.get(counters_1_before_run_2, :build_broken, 0) >= 1

      assert {:error, receipt_2} = ReconcileReactor.run(opts_2)
      assert receipt_2.standing == :build_broken

      counters_1_after_run_2 = CompensationTelemetryMiddleware.counters(run_id_1)
      counters_2 = CompensationTelemetryMiddleware.counters(run_id_2)

      # THE REAL PROOF: run 1's real per-run count is UNCHANGED by run 2's
      # real execution (no summing across runs) -- and run 2 has its own,
      # independently nonzero real count under its own run_id.
      assert Map.get(counters_1_after_run_2, :build_broken, 0) ==
               Map.get(counters_1_before_run_2, :build_broken, 0),
             "run 1's real per-run :build_broken count must not change when a " <>
               "SECOND, DIFFERENT real run executes -- run_id_1 counts before=" <>
               "#{inspect(counters_1_before_run_2)}, after=#{inspect(counters_1_after_run_2)}"

      assert Map.get(counters_2, :build_broken, 0) >= 1,
             "run 2's own real per-run :build_broken count must be independently " <>
               "nonzero -- counters_2=#{inspect(counters_2)}"
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

      run_id = make_ref()

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        telemetry_run_id: run_id,
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

      run_counters = CompensationTelemetryMiddleware.counters(run_id)

      assert Map.get(run_counters, :compensate_start, 0) >= 1,
             ":compensate_start should have incremented for :actuate's real " <>
               "compensate/4 firing on its own run/3 failure -- " <>
               "run_counters=#{inspect(run_counters)}"
    end
  end

  describe "error/2 mutual exclusion between :build_broken and :compensation_failed" do
    test "one real error term matching BOTH find_step_error's {:compile_failed, _} predicate and find_compensation_failure/1's {:compensation_failed, _} tag increments only :build_broken" do
      # This is real data shaped EXACTLY like the nested error terms
      # `find_compensation_failure/1` and `find_step_error/2` themselves
      # pattern-match on (see reconcile_reactor.ex lines 944-985: a map with
      # an `:errors` list of maps, each either `%{step: %{name: _}, error:
      # _}` or a bare `%{error: _}`) -- not a mock of any collaborator's
      # behavior, a real term exercising the real recursive match clauses.
      # This is the genuine "both would fire" shape: `:verify` originally
      # failed with `{:compile_failed, _}` (the real `:build_broken`
      # trigger), AND the SAME real run's `revert_all/1` (undo of `:actuate`)
      # itself failed, appending a real `{:compensation_failed, _}`-tagged
      # error alongside it -- both leaves genuinely present in ONE real
      # `error_or_errors` term for one real failing run.
      error_or_errors = %{
        errors: [
          %{step: %{name: :verify}, error: {:compile_failed, "mix compile failed: boom"}},
          %{error: {:compensation_failed, %{paths: ["/tmp/x"], restored: [], failed: ["/tmp/x"]}}}
        ]
      }

      run_id = make_ref()

      assert :ok =
               CompensationTelemetryMiddleware.error(error_or_errors, %{
                 compensation_telemetry_run_id: run_id
               })

      run_counters = CompensationTelemetryMiddleware.counters(run_id)

      assert Map.get(run_counters, :build_broken, 0) == 1,
             "the real {:compile_failed, _} leaf should have incremented :build_broken " <>
               "exactly once -- run_counters=#{inspect(run_counters)}"

      # THE REAL, STATE-BASED PROOF of the GAP #7 fix: even though this same
      # real error_or_errors term ALSO genuinely matches
      # find_compensation_failure/1's {:compensation_failed, _} pattern,
      # :compensation_failed must NOT also increment -- error/2's real
      # precedence (compile_failed checked first, compensation_failed only
      # on fallthrough) makes the two mutually exclusive for one error term.
      assert Map.get(run_counters, :compensation_failed, 0) == 0,
             ":compensation_failed must stay at 0 when :build_broken already matched " <>
               "the same real error term -- run_counters=#{inspect(run_counters)}"
    end

    test "a real error term matching ONLY find_compensation_failure/1 (no {:compile_failed, _} leaf) increments :compensation_failed" do
      error_or_errors = %{
        error: {:compensation_failed, %{paths: ["/tmp/y"], restored: [], failed: ["/tmp/y"]}}
      }

      run_id = make_ref()

      assert :ok =
               CompensationTelemetryMiddleware.error(error_or_errors, %{
                 compensation_telemetry_run_id: run_id
               })

      run_counters = CompensationTelemetryMiddleware.counters(run_id)

      assert Map.get(run_counters, :compensation_failed, 0) == 1,
             "run_counters=#{inspect(run_counters)}"

      assert Map.get(run_counters, :build_broken, 0) == 0,
             "run_counters=#{inspect(run_counters)}"
    end
  end
end
