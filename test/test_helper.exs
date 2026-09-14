{:ok, _} = Application.ensure_all_started(:tesla)
{:ok, _} = Application.ensure_all_started(:ggen_igniter)

# qlever is an optional query engine (oxigraph is the default -- see
# docs/architecture/adr/0001-oxigraph-default-query-engine.md); tests tagged
# `:requires_qlever_server` exercise the real `--engine qlever` path against a
# real, already-running QLever server and must not run (or fail) when no such
# server is available.
#
# This probe -- and the resulting `ExUnit.configure(exclude: ...)` call --
# MUST happen here, before `ExUnit.start/1`, not inside any test file's own
# `setup` block. `ExUnit.configure/1`'s `:exclude` option only affects which
# already-collected tests get DISPATCHED; by the time a per-test `setup`
# callback runs, ExUnit has already decided (in `ExUnit.Runner.prepare_tests/3`,
# via `ExUnit.Filters.eval/4`, against each test's STATIC `@tag`-collected
# tags only) whether to run that specific test -- a `setup`-local
# `ExUnit.configure(exclude: [:requires_qlever_server])` call can never
# exclude the very test whose `setup` invoked it. This was tried, the hard
# way, twice, independently:
#
#   * Six real test files each reimplemented this exact broken per-`setup`
#     `ExUnit.configure(exclude: ...)` pattern; every `:requires_qlever_server`
#     -tagged test in them genuinely FAILED (not skipped) against a real
#     no-QLever-server environment.
#   * GI-13 (2026-09-14) tried the OTHER real ExUnit primitive for a
#     per-test runtime decision -- a `setup` callback returning
#     `{:skip, reason}` -- on the theory that this is a distinct mechanism
#     from `ExUnit.configure/1` and might not share its timing constraint.
#     Verified locally, for real, that it is NOT distinct: ExUnit 1.18.4's
#     own `setup`/`setup_all` callback contract
#     (`lib/ex_unit/lib/ex_unit/callbacks.ex`, confirmed by reading the
#     installed source, not assumed) only accepts `:ok`, a keyword list, or
#     a map as a `setup` return value; `{:skip, reason}` raises
#     `RuntimeError, "expected ExUnit setup callback ... to return the atom
#     :ok, a keyword, or a map"`. `ExUnit.Filters.eval/4`'s `:skip` handling
#     (`lib/ex_unit/lib/ex_unit/filters.ex`) only reads a test's STATIC
#     `tags[:skip]`, evaluated inside `prepare_tests/3` -- i.e. before any
#     `setup` callback for that test ever runs, the identical "too late"
#     shape as the original bug, confirmed by reading the actual installed
#     ExUnit source rather than assumed from a remembered API. There is no
#     ExUnit-native way, in this Elixir version, to decide "skip this one
#     test" at its own run time based on a check performed then. Every such
#     decision must be made in advance of `ExUnit.start/1`, using only
#     information available at that point -- which is exactly the
#     architecture this file already has.
#
# GI-13 (2026-09-14) real hosted-CI history, in order, on this exact
# `127.0.0.1:7020` / `config/gno/test/store.ttl` precondition (three
# independently-triggered runs: 34822966689, 34826784317, 34829186413):
#
#   1. A bare `:httpc.request(:get, {~c"http://localhost:7020", []}, ...)`
#      probe treated ANY `{:ok, _}` (any HTTP response, any status, from
#      any process) as "reachable" -- false-positived: 7 of 9
#      `:requires_qlever_server` tests ran for real and failed, one with a
#      real `:econnrefused` from an actual `SPARQL.Client` round trip to
#      the SAME endpoint this probe claimed was reachable.
#   2. Replacing the bare GET with the real SPARQL-protocol round trip this
#      codebase already trusts for this decision
#      (`GgenIgniter.EngineRegistry.qlever_reachable?/2`,
#      `lib/ggen_igniter/engine_registry.ex`) was NECESSARY but not
#      SUFFICIENT -- false-positived again: the identical technique,
#      invoked again moments later from inside `EngineRegistry.resolve/2`
#      during an actual test, correctly found the endpoint unreachable,
#      while this probe's own earlier call had returned `true`, in the SAME
#      run.
#   3. Requiring that same round trip to succeed TWICE, 2 seconds apart,
#      was STILL not sufficient -- false-positived a third time: both calls
#      returned `true`, yet a fresh identical round trip from an actual
#      test failed with real `:econnrefused` only ~3.4 real seconds after
#      this probe's own second success (timestamps: the "Excluding tags"
#      log line vs. the first qlever-tagged test failure, same run).
#
# Three real, network-technique-based attempts establish that no amount of
# retrying or delaying a REAL NETWORK PROBE reliably characterizes this
# specific hosted runner's `127.0.0.1:7020` behavior -- whatever is
# transiently true there flips on a timescale this file cannot safely
# out-wait without an unbounded guess, each guess costing a full ~20+
# minute real hosted CI round trip to (dis)confirm, and (per the ExUnit
# constraint established above) there is no way to defer the check to each
# test's own run time instead.
#
# The fix: stop trying to detect the hosted runner's transient network
# state at all, and instead use the standard, deterministic, universally-set
# signal for "is this a CI runner, not a real developer machine with real
# local services" -- the `CI` environment variable, which GitHub Actions
# (and effectively every other CI provider) sets unconditionally for every
# job. This is not a workaround for not being able to detect the real
# condition; it is a more accurate model of the real condition: this
# project's own `ci.yml` never starts a QLever server as part of any job
# (confirmed by reading the whole workflow -- no `services:` block, no
# `qlever start` step, nothing binds port 7020 deliberately), so "hosted CI"
# and "no real QLever server, ever, structurally" are the same fact here,
# independent of whatever noise a network probe observes on that port.
# `CI=true` is force-excluded without any network call; every non-CI
# environment (a real developer machine) keeps the real round-trip probe
# (`GgenIgniter.EngineRegistry.qlever_reachable?/2`'s own technique),
# unaffected, exactly as originally designed for the case these tests were
# actually written for: a developer with a real, locally-running QLever
# server.
ci? = System.get_env("CI") not in [nil, "", "false", "0"]

IO.puts(
  "ggen_igniter test_helper.exs diagnostic: System.get_env(\"CI\")=#{inspect(System.get_env("CI"))} " <>
    "System.get_env(\"GITHUB_ACTIONS\")=#{inspect(System.get_env("GITHUB_ACTIONS"))} ci?=#{inspect(ci?)}"
)

qlever_reachable? =
  not ci? and
    try do
      graph = GgenIgniter.Ontology.load!("config/gno/test/store.ttl")
      store = GgenIgniter.Query.Qlever.load_store!(graph, "http://example.com/Qlever")
      GgenIgniter.Query.Qlever.run(store, "SELECT ?s WHERE { ?s ?p ?o } LIMIT 1")
      true
    rescue
      _ -> false
    end

unless qlever_reachable? do
  ExUnit.configure(exclude: [:requires_qlever_server])
end

# Same bug class, same fix, for the `:requires_ash_r2rml` tag
# (`test/ash_r2rml_gate_integration_test.exs`, `test/ggen_igniter_oxigraph_engine_test.exs`):
# both files reimplemented an identical broken per-`setup`
# `ExUnit.configure(exclude: ...)` call, gated on whether `~/ash_r2rml` exists
# on disk, that could never actually exclude an already-scheduled test. This
# precondition is genuinely stable for the lifetime of one `mix test`
# invocation (nothing mid-run mounts or unmounts `~/ash_r2rml`), so, unlike
# qlever's network precondition above, a single check here, before
# `ExUnit.start/1`, is and remains the correct shape -- this half was never
# the unreliable part.
unless File.exists?(Path.expand("~/ash_r2rml")) do
  ExUnit.configure(exclude: [:requires_ash_r2rml])
end

ExUnit.start()
