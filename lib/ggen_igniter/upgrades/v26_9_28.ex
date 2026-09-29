defmodule GgenIgniter.Upgrades.V260928 do
  @moduledoc """
  Upgrader into v26.9.28: consumers get `import_deps: [:ggen_igniter]` in their
  root `.formatter.exs` so the package's `locals_without_parens` apply.

  Hand-written residue: no ontology models consumer migrations, so no generator
  covers this (UNSUPPORTED(generator-capability)); it is a single upstream
  `Igniter.Project.Formatter.import_dep/2` call, idempotent by construction.
  """

  @spec upgrade(Igniter.t(), keyword()) :: Igniter.t()
  def upgrade(igniter, _opts \\ []) do
    Igniter.Project.Formatter.import_dep(igniter, :ggen_igniter)
  end
end
