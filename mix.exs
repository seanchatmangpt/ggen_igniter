defmodule GgenIgniter.MixProject do
  use Mix.Project

  @source_url "https://github.com/seanchatmangpt/ggen_igniter"

  def project do
    [
      app: :ggen_igniter,
      version: "26.8.27",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        # `:mix` is excluded from the PLT by default (it's a build-time-only
        # app, not a runtime dependency), but `lib/mix/tasks/ggen_igniter.sync.ex`
        # and `lib/mix/tasks/ggen_igniter.doctor.ex` both `use Mix.Task` and call
        # real Mix APIs (`Mix.Project.config/0`, `Mix.shell/0`, `Mix.Task.run/1,2`,
        # `Mix.Task.task_name/1`, `Mix.Project.umbrella?/0`). Without `:mix` in
        # the PLT, dialyzer can't see those modules' specs and reports them as
        # `unknown_function`/`callback_info_missing` -- a well-known false
        # positive for any project with `Mix.Task`-based CLI entry points, not a
        # real type error in this project's code. Verified: adding this and
        # rebuilding the PLT eliminates all 12 of those warnings with zero new
        # findings.
        plt_add_apps: [:mix]
      ]
    ]
  end

  defp aliases do
    [e2e: ["run test/e2e/run_e2e.exs"]]
  end

  def application do
    [extra_applications: [:logger], mod: {GgenIgniter.Application, []}]
  end

  defp description do
    "An Elixir bootstrap of ggen's ontology-to-code pipeline: RDF ontology + SPARQL + " <>
      "template + write-safety, with pluggable sparql/qlever/oxigraph query engines."
  end

  defp package do
    [
      description: description(),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib native/ggen_graph_nif/Cargo.toml native/ggen_graph_nif/src mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp deps do
    [
      {:rdf, "~> 3.0"},
      {:sparql, "~> 0.3"},
      # NOT dev/test-only: `lib/mix/tasks/ggen_igniter.sync.ex` and
      # `lib/mix/tasks/ggen_igniter.doctor.ex` (the real CLI entry points a
      # consumer app actually runs) both `use Igniter.Mix.Task` -- real
      # compile-time production code, not test tooling. Marking this
      # `only: [:dev, :test]` here silently drops it for ANY consuming
      # application regardless of that consumer's own Mix.env (verified via
      # a minimal path-dependency repro: `mix deps.get`/`mix compile` in a
      # fresh consumer app depending on `{:ggen_igniter, path: ...}` never
      # fetches `:igniter` at all, then fails with "module Igniter.Mix.Task
      # is not loaded and could not be found" at
      # lib/mix/tasks/ggen_igniter.doctor.ex:38 / .sync.ex:109) -- the exact
      # same failure class the E2E suite hit for `:gno`/`Tesla` below, just
      # masked there because that particular scaffolded consumer already
      # pulls in `:igniter` transitively via its own ash/ash_phoenix install
      # chain.
      {:igniter, "~> 0.8"},
      {:toml, "~> 0.7"},
      {:yaml_elixir, "~> 2.9"},
      {:rustler, "~> 0.36"},
      # `optional: true`, NOT `only: [:dev, :test]`: `lib/ggen_igniter/pack.ex`
      # (`Tesla.client`/`Tesla.get`, the marketplace `fetch_pack!/2` HTTP path)
      # is real compile-time production code, not test support, so `only:
      # [:dev, :test]` would silently drop it for ANY consuming application
      # regardless of that consumer's own Mix.env -- exactly the failure class
      # documented on `:gno` below. `optional: true` is the correct tool
      # instead: Hex/Mix still resolves and compiles `:tesla` for *this*
      # project's own dev/test/prod (optional deps of the declaring app are
      # fetched normally), while a *consuming* app that adds `ggen_igniter` as
      # a dependency without itself depending on `:tesla` compiles clean --
      # `pack.ex`'s `http_get!/1` guards its `Tesla` call site with
      # `Code.ensure_loaded?(Tesla)` and raises a clear, actionable
      # `RuntimeError` if a consumer actually reaches `fetch_pack!/2` (the
      # github:/hex: pack-fetch path) without `:tesla` in its own deps.
      {:tesla, "~> 1.8", optional: true},
      # `optional: true`, NOT `only: [:dev, :test]`: `lib/ggen_igniter/query/
      # qlever.ex` (`Gno.Store.Adapters.Qlever`) and `lib/ggen_igniter/engine.ex`
      # (`GgenIgniter.Engine.Qlever`'s `--engine qlever` dispatch) are real
      # compile-time production code, not test support. `only: [:dev, :test]`
      # here is what caused a real E2E failure: `mix compile
      # --warnings-as-errors` on a freshly-scaffolded consumer app raised
      # "Gno.Store.Adapters.Qlever.__struct__/1 is undefined" (qlever.ex:62)
      # and "Tesla.Env.__struct__/1 is undefined" (pack.ex:334), because a
      # dependency's own `only:` restriction is dropped entirely for any
      # consuming app (not merely restricted to matching envs) -- confirmed
      # directly via a minimal ash-free `{:ggen_igniter, path: ...}` repro
      # whose `mix deps.get` never even fetched `:gno`.
      #
      # `optional: true` fixes this the standard Elixir way: `:gno` still
      # resolves/compiles for *this* project's own dev/test (needed for this
      # project's own test suite -- `mix deps.get`/`mix compile` here are
      # unaffected), but a consumer without `:gno` in its own deps now
      # compiles clean too, because `lib/ggen_igniter/query/qlever.ex` wraps
      # its real `%Qlever{}`-struct-using implementation in `if
      # Code.ensure_loaded?(Gno.Store.Adapters.Qlever) do ... else ... end` --
      # the `else` branch compiles a stub `GgenIgniter.Query.Qlever` whose
      # `load_store!/2` and `run/2` raise a clear, actionable `RuntimeError`
      # instead of a struct-expansion compile error. `GgenIgniter.Engine.Qlever`
      # (`lib/ggen_igniter/engine.ex`) adds its own `Code.ensure_loaded?`
      # guards at its `--engine qlever` dispatch call sites for the same
      # reason (it calls `Application.ensure_all_started(:tesla)` and
      # `GgenIgniter.Query.Qlever.load_store!/2` directly).
      #
      # Real bare-probe-project proof this actually eliminates the coupling:
      # see the "eliminate optional tesla/gno coupling" work log -- a fresh
      # `mix new` consumer with `{:ggen_igniter, path: ...}` and neither
      # `:tesla` nor `:gno` in its own deps now runs `mix deps.get` + `mix
      # compile --warnings-as-errors` clean.
      {:gno, "~> 0.1", optional: true},
      {:stream_data, "~> 1.2", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]}
    ]
  end
end
