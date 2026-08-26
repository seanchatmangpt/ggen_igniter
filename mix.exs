defmodule GgenIgniter.MixProject do
  use Mix.Project

  def project do
    [
      app: :ggen_igniter,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:rdf, "~> 3.0"},
      {:sparql, "~> 0.3"},
      {:igniter, "~> 0.8"},
      {:gno, "~> 0.1", only: [:dev, :test]}
    ]
  end
end
