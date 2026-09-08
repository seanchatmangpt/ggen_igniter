defmodule BookLibrary.MixProject do
  use Mix.Project

  def project do
    [
      app: :book_library,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      # These tests exercise MANUFACTURED resources, so they must live in this
      # fixture -- but this fixture sits inside the parent repo's `test/` tree,
      # and Mix globs `test/**/*_test.exs`. Named `*_test.exs` they were
      # collected by ggen_igniter's OWN suite, where BookLibrary.DataCase does
      # not exist, and broke it with a CompileError. Verified, not theorised:
      # `mix test` in the parent failed with "module BookLibrary.DataCase is
      # not loaded" at loan_test.exs:43.
      #
      # A suffix disjoint from the parent's default is the fix that keeps the
      # tests real and runnable HERE without the parent ever seeing them.
      #
      # The knob is `:test_load_filters`, NOT `:test_pattern`. In Elixir 1.19
      # `:test_pattern` only finds CANDIDATE files (default "*.{ex,exs}");
      # `:test_load_filters` decides which candidates are loaded, and its
      # default is [&String.ends_with?(&1, "_test.exs")]. Setting
      # `test_pattern: "*_exec.exs"` here collected nothing at all -- verified,
      # `mix test` printed "There are no tests to run" while an explicit path
      # ran 6 tests green. The parent keeps the default filter, so it never
      # loads these.
      test_load_filters: [&String.ends_with?(&1, "_exec.exs")],
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases()
    ]
  end

  # Day zero (ticket 01): no `mod:` -- there is no Application module and no
  # Repo yet. Matrix row 11 (`mix ash_postgres.install`) is the step that
  # creates BookLibrary.Repo, BookLibrary.Application, and the repo config.
  def application do
    [
      extra_applications: [:logger],
      mod: {BookLibrary.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      # Deviation from ticket 01's three-dep list, disclosed: the ticket 03
      # harness runs `mix ggen_igniter.sync` from INSIDE this fixture (cwd =
      # fixture root), so the parent repo must be resolvable as a path dep.
      # dev/test only -- a build-time tool, not a runtime dep. Deps are
      # fetched from Hex; the path dep only adds ggen_igniter's own transitive
      # deps to mix.lock.
      {:ggen_igniter, path: "../../..", only: [:dev, :test]}
    ]
  end

  defp aliases() do
    [test: ["ash.setup --quiet", "test"], setup: "ash.setup"]
  end
end
