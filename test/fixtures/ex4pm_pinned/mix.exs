defmodule Ex4pm.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "26.8.28",
      start_permanent: Mix.env() == :prod,
      deps: [{:stream_data, "~> 1.0"}, {:decimal, "~> 3.1", override: true}],
      aliases: aliases(),
      preferred_cli_env: [
        verify: :test,
        "test.stress": :test,
        chicago: :test,
        "ex4pm.powl.court": :test,
        "ex4pm.sabotage.court": :test,
        "ex4pm.lint.truth": :test,
        "ex4pm.crown": :test
      ],
      dialyzer: [
        plt_core_path: "priv/plts/core.plt",
        plt_file: {:no_warn, "priv/plts/project.plt"},
        plt_add_apps: [:ex_unit, :mix]
      ],
      releases: [
        ex4pm_umbrella: [
          applications: [
            ex4pm: :permanent,
            ex4pm_web: :permanent,
            ex4pm_engine: :permanent,
            ex4pm_domain: :permanent,
            ex4pm_runtime: :permanent,
            ex4pm_evidence: :permanent,
            ex4pm_core: :permanent,
            ex4pm_contracts: :permanent,
            ex4pm_stream: :permanent,
            ex4pm_information: :permanent,
            ex4pm_qualification: :permanent
          ]
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        verify: :test,
        "test.stress": :test,
        chicago: :test,
        "ex4pm.powl.court": :test,
        "ex4pm.sabotage.court": :test,
        "ex4pm.lint.truth": :test,
        "ex4pm.crown": :test
      ]
    ]
  end

  defp aliases do
    [
      verify: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "ex4pm.lint.truth",
        "test",
        "ex4pm.powl.court",
        "ex4pm.sabotage.court"
      ],
      "test.stress": ["test apps/ex4pm_engine/test/benchmarks/stress_benchmark_test.exs"],
      chicago: ["do --app ex4pm test --only chicago --seed 0"]
    ]
  end
end
