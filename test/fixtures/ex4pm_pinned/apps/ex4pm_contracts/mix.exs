defmodule Ex4pmContracts.MixProject do
  use Mix.Project

  @version "26.8.22"
  @source_url "https://github.com/seanchatmangpt/ex4pm"

  def project do
    [
      app: :ex4pm_contracts,
      version: @version,
      description: "Executable ontology, WIT, SHACL and receipt contracts for ex4pm",
      source_url: @source_url,
      package: package(),
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      start_permanent: Mix.env() == :prod,
      deps: [{:ex4pm_core, "~> 26.8.22", in_umbrella: true}]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp package,
    do: [licenses: ["MIT"], links: %{"GitHub" => @source_url}, files: ["lib", "priv", "mix.exs"]]
end
