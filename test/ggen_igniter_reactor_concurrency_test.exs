defmodule GgenIgniter.ReactorConcurrencyTest do
  @moduledoc """
  Chicago-style, no-mocks proof of two concurrency properties of
  `GgenIgniter.Reactors.ReconcileReactor`, real ontology/query/template
  fixtures and real `ReconcileReactor.run/1` calls throughout -- no
  `Mock`/`patch`/`monkeypatch` anywhere in this file.

  ## Property 1: concurrent multi-target run == serial single-target runs

  `:actuate` runs every admitted target's real write via
  `Task.async_stream/3` (`max_concurrency: System.schedulers_online()`) --
  there is no config flag to force it serial, so "the real serial
  equivalent" this task asks for is constructed the only real way available:
  running the SAME two independent targets (different real ontology
  entities, different real output files, no shared state) as TWO SEPARATE,
  SEQUENTIAL `ReconcileReactor.run/1` invocations (one full Reactor run per
  target, run one after the other) against a fresh scratch project, versus
  ONE `ReconcileReactor.run/1` invocation with both targets under `:targets`
  (which actuates them concurrently inside a single Reactor run) against a
  second, independently-fresh scratch project. Both paths start from
  identical empty state; the real, load-bearing assertion is a real
  byte-for-byte `File.read!/1` comparison of each target's own output file
  across the two projects.

  ## Property 2: same real output path -- refusal, checked for real determinism

  Per this module's own moduledoc ("Same-output-path collision"), two
  targets resolving to the SAME real `out_path` are refused OUTRIGHT by
  `:admit` (`{:error, {:refused_duplicate_output_path, ...}}`) -- this
  implementation does not attempt an implicit ordering. This is reported
  honestly below (not forced into an "ordering" shape the code does not
  have): the real, repeated-run assertion is that the refusal itself is
  deterministic -- running the exact same colliding plan twice, independently,
  produces the same real standing (`:refused`) and the same real on-disk
  outcome (NEITHER target's content ever lands at the colliding path) both
  times, not merely once by luck.
  """

  use ExUnit.Case, async: false

  alias GgenIgniter.Manifest
  alias GgenIgniter.Reactors.ReconcileReactor
  alias GgenIgniter.Receipt

  # -- Fixture builders (same style as ggen_igniter_reconcile_reactor_test.exs) -

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_reactor_concurrency_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  # A real, minimal, dependency-free Mix project: enough for a real `mix
  # compile --warnings-as-errors` subprocess to succeed honestly on whatever
  # `:actuate` writes into its `lib/`.
  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))

    app = "reactor_concurrency_fixture_#{System.unique_integer([:positive])}"

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

  # ex:Alpha / ex:Beta -- two independent, single-row entities, so two
  # targets never collide on rendered module name and neither target's
  # content depends on the other's.
  defp write_ontology!(dir) do
    path = Path.join(dir, "ontology.ttl")

    File.write!(path, """
    @prefix ex: <http://example.org/rr#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "GgenIgniterReactorConcurrencyFixture.Alpha" ;
      ex:greeting "hello_from_alpha" .
    ex:Beta a ex:Module ;
      ex:moduleName "GgenIgniterReactorConcurrencyFixture.Beta" ;
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

  # A deterministic template: no timestamps, no PIDs, no randomness -- purely
  # a function of the real query bindings, so a real byte-for-byte cross-run
  # comparison is meaningful (a template that embedded e.g. `DateTime.utc_now/0`
  # would make ANY two independent runs differ regardless of concurrency, and
  # would falsify this test's own premise).
  defp write_valid_template!(dir) do
    path = Path.join(dir, "valid.ex.eex")

    File.write!(path, """
    defmodule <%= module_name %> do
      def greeting, do: "<%= greeting %>"
    end
    """)

    path
  end

  # -- Property 1: concurrent (one Reactor run, N targets) == serial (N Reactor runs) --

  describe "concurrent multi-target run produces identical bytes to serial single-target runs" do
    test "each target's real output file is byte-for-byte identical whether actuated concurrently (one Reactor run) or serially (N Reactor runs)" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      template_path = write_valid_template!(fixtures)

      # -- CONCURRENT path: one ReconcileReactor.run/1 call, both targets
      # under :targets -- :actuate's own Task.async_stream/3 runs their real
      # writes concurrently inside this single Reactor invocation.
      concurrent_project = new_mix_project!()
      concurrent_out_a = Path.join([concurrent_project, "lib", "alpha.ex"])
      concurrent_out_b = Path.join([concurrent_project, "lib", "beta.ex"])

      concurrent_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: concurrent_project,
        verify_cwd: concurrent_project,
        targets: [
          [template: template_path, query: "spec=#{query_alpha}", out: concurrent_out_a],
          [template: template_path, query: "spec=#{query_beta}", out: concurrent_out_b]
        ]
      ]

      assert {:ok, concurrent_receipt} = ReconcileReactor.run(concurrent_opts)
      assert concurrent_receipt.standing == :alive
      assert concurrent_receipt.metadata["target_count"] == 2
      assert File.exists?(concurrent_out_a)
      assert File.exists?(concurrent_out_b)

      # -- SERIAL path: TWO separate, sequential ReconcileReactor.run/1
      # invocations -- target A's entire Reactor run completes (observe ->
      # ... -> finalize_evidence, including its own real `mix compile`)
      # before target B's Reactor run is even started. This is the real
      # "serial equivalent": no Task.async_stream overlap is possible when
      # each target is its own top-level Reactor.run call, invoked one after
      # the other from this same test process.
      serial_project = new_mix_project!()
      serial_out_a = Path.join([serial_project, "lib", "alpha.ex"])
      serial_out_b = Path.join([serial_project, "lib", "beta.ex"])

      serial_opts_a = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: serial_project,
        verify_cwd: serial_project,
        template: template_path,
        query: "spec=#{query_alpha}",
        out: serial_out_a
      ]

      serial_opts_b = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: serial_project,
        verify_cwd: serial_project,
        template: template_path,
        query: "spec=#{query_beta}",
        out: serial_out_b
      ]

      assert {:ok, serial_receipt_a} = ReconcileReactor.run(serial_opts_a)
      assert serial_receipt_a.standing == :alive

      assert {:ok, serial_receipt_b} = ReconcileReactor.run(serial_opts_b)
      assert serial_receipt_b.standing == :alive

      assert File.exists?(serial_out_a)
      assert File.exists?(serial_out_b)

      # -- THE REAL, LOAD-BEARING PROOF: byte-for-byte identical real file
      # content, per target, regardless of whether that target's write was
      # actuated concurrently (alongside another target, in one Reactor run)
      # or serially (alone, in its own Reactor run, one after the other).
      assert File.read!(concurrent_out_a) == File.read!(serial_out_a),
             "expected target A's real output bytes to be identical whether written " <>
               "concurrently or serially"

      assert File.read!(concurrent_out_b) == File.read!(serial_out_b),
             "expected target B's real output bytes to be identical whether written " <>
               "concurrently or serially"

      # Both are also each individually correct against the real query
      # results (not merely equal to each other by coincidence, e.g. both
      # empty).
      assert File.read!(concurrent_out_a) =~ "hello_from_alpha"
      assert File.read!(concurrent_out_b) =~ "hello_from_beta"

      # -- Real receipts exist for every run on both paths (correction A):
      # 1 receipt for the concurrent project (one Reactor invocation), 2 for
      # the serial project (two Reactor invocations).
      assert length(Receipt.read_all!(concurrent_project)) == 1
      assert length(Receipt.read_all!(serial_project)) == 2
    end
  end

  # -- Property 2: same real output path -- deterministic refusal, checked twice --

  describe "same real output path: deterministic refusal, verified across repeated runs" do
    test "two targets resolving to the SAME real out_path are refused, and re-running the identical colliding plan produces the SAME refusal again" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_alpha = write_query!(fixtures, "spec_alpha", "Alpha")
      query_beta = write_query!(fixtures, "spec_beta", "Beta")
      template_path = write_valid_template!(fixtures)

      project_dir = new_mix_project!()
      collision_out = Path.join([project_dir, "lib", "collision.ex"])
      refute File.exists?(collision_out)

      reconcile_opts = [
        engine: "sparql",
        ontology: ontology_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir,
        targets: [
          [template: template_path, query: "spec=#{query_alpha}", out: collision_out],
          [template: template_path, query: "spec=#{query_beta}", out: collision_out]
        ]
      ]

      # -- First run of the colliding plan.
      result_1 = ReconcileReactor.run(reconcile_opts)

      assert {:error, receipt_1} = result_1

      refute File.exists?(collision_out),
             "expected NEITHER target's content to have landed at the colliding path " <>
               "on the first run -- a real refusal, not a race or last-writer-wins"

      assert receipt_1.standing == :refused
      assert receipt_1.files == []
      refute Enum.any?(receipt_1.events, &(&1["activity"] == "ACTUATION_STARTED")),
             "a fail-closed refusal at :admit must happen BEFORE :actuate ever runs -- no " <>
               "ACTUATION_STARTED event should exist for this attempt"

      # -- REAL DETERMINISM CHECK: re-run the IDENTICAL colliding plan again.
      # This is the honest analogue of "re-running produces the same
      # ordering again" for an implementation whose real behavior is refusal
      # rather than an implicit deterministic order: the SAME real refusal
      # must occur again, not sometimes succeed via a race.
      result_2 = ReconcileReactor.run(reconcile_opts)

      assert {:error, receipt_2} = result_2

      refute File.exists?(collision_out),
             "expected NEITHER target's content to have landed at the colliding path " <>
               "on the second run either"

      assert receipt_2.standing == :refused
      assert receipt_2.files == []
      refute Enum.any?(receipt_2.events, &(&1["activity"] == "ACTUATION_STARTED"))

      # -- Same real refused reason both times (structural equality on the
      # real, persisted metadata -- not just "both errored").
      assert receipt_1.reason == receipt_2.reason
      assert receipt_1.metadata["failed_step"] == receipt_2.metadata["failed_step"]
      assert receipt_1.metadata["failed_step"] == inspect(:admit)

      # -- GgenIgniter.Manifest never advances on either refused attempt.
      refute File.exists?(Manifest.path(project_dir))

      # -- Both refusals are genuinely durable: re-reading from disk (not the
      # in-memory struct) shows two real, persisted :refused receipts.
      persisted = Receipt.read_all!(project_dir)
      assert length(persisted) == 2
      assert Enum.all?(persisted, &(&1["standing"] == "refused"))
    end
  end
end
