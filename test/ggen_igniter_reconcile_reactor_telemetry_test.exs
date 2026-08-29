defmodule GgenIgniter.ReconcileReactorTelemetryTest do
  @moduledoc """
  Chicago-style: real collaborators only, no mocking. Uses a real
  `:telemetry.attach_many/4` handler process (forwarding events to `self()`
  via a real message send, never a mock), a real scratch tmp dir under
  `System.tmp_dir!/0`, a real minimal ontology/query/EEx-template fixture
  (same shape as `test/ggen_igniter_reconcile_reactor_test.exs`), a real
  scratch Mix project for `:verify`'s real `mix compile
  --warnings-as-errors` subprocess, and a real
  `GgenIgniter.Reactors.ReconcileReactor.run/1` execution end to end. This
  proves `Reactor.Middleware.Telemetry` (wired via this reactor's
  `middlewares do middleware Reactor.Middleware.Telemetry end` block) really
  emits `:telemetry.execute/3` events for a real run, not just that the DSL
  compiles.
  """

  # async: false -- :telemetry handler ids are global process-registry state
  # (ETS-backed), so attaching/detaching concurrently across async tests
  # risks one test's handler receiving another test's events.
  use ExUnit.Case, async: false

  alias GgenIgniter.Reactors.ReconcileReactor

  defp scratch_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ggen_igniter_reactor_telemetry_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp new_mix_project! do
    dir = scratch_dir!()
    File.mkdir_p!(Path.join(dir, "lib"))

    app = "reactor_telemetry_fixture_#{System.unique_integer([:positive])}"

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
    @prefix ex: <http://example.org/rrt#> .
    ex:Alpha a ex:Module ;
      ex:moduleName "GgenIgniterReactorTelemetryFixture.Alpha" ;
      ex:greeting "hello_from_telemetry_alpha" .
    """)

    path
  end

  defp write_query!(dir) do
    path = Path.join(dir, "spec_alpha.rq")

    File.write!(path, """
    PREFIX ex: <http://example.org/rrt#>
    SELECT ?module_name ?greeting WHERE {
      ex:Alpha ex:moduleName ?module_name ; ex:greeting ?greeting .
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

  describe "Reactor.Middleware.Telemetry wiring" do
    test "a real ReconcileReactor.run/1 emits real [:reactor, :run, :start|:stop] telemetry events" do
      fixtures = scratch_dir!()
      ontology_path = write_ontology!(fixtures)
      query_path = write_query!(fixtures)
      template_path = write_valid_template!(fixtures)

      project_dir = new_mix_project!()
      out_path = Path.join([project_dir, "lib", "alpha.ex"])

      handler_id = "telemetry-test-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [
          [:reactor, :run, :start],
          [:reactor, :run, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      opts = [
        engine: "sparql",
        ontology: ontology_path,
        query: "spec=#{query_path}",
        template: template_path,
        out: out_path,
        manifest_dir: project_dir,
        verify_cwd: project_dir
      ]

      assert {:ok, receipt} = ReconcileReactor.run(opts)
      assert receipt.standing == :alive
      assert File.exists?(out_path)

      assert_receive {:telemetry_event, [:reactor, :run, :start], start_measurements, _meta},
                     5_000

      assert is_integer(start_measurements.system_time)

      assert_receive {:telemetry_event, [:reactor, :run, :stop], stop_measurements, _meta}, 5_000
      assert is_integer(stop_measurements.system_time)
    end
  end
end
