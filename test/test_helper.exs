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
# callback runs, ExUnit has already decided to run that specific test, so a
# `setup`-local `ExUnit.configure(exclude: [:requires_qlever_server])` call
# can never exclude the very test whose `setup` invoked it (nor, reliably,
# any other already-scheduled test) -- confirmed the hard way: six real test
# files (`ggen_igniter_engine_registry_test.exs`,
# `ggen_igniter_engine_parity_test.exs`, `ggen_igniter_e2e_all_engines_test.exs`,
# `ggen_igniter_sync_qlever_engine_test.exs`, `ash_r2rml_gate_qlever_test.exs`)
# each independently reimplemented this same broken per-`setup` pattern, and
# every `:requires_qlever_server`-tagged test in them genuinely FAILED (not
# skipped) against a real no-QLever-server environment, contradicting the
# very docstrings describing the pattern as "only runs when a real QLever
# server is reachable."
#
# GI-13 follow-up (2026-09-14): the probe used to be a bare
# `:httpc.request(:get, {~c"http://localhost:7020", []}, ...)`, treating ANY
# `{:ok, _}` -- including a non-2xx HTTP response from ANY server, QLever or
# not -- as "reachable". Real, same-run evidence from hosted CI (run
# 34822966689 on SHA d617ec6) proved this false-positives there: the log's
# own `Excluding tags: [:requires_ash_r2rml]` line omitted
# `:requires_qlever_server` entirely, so all 9 `:requires_qlever_server`-tagged
# tests actually ran (not skipped) and 7 failed for real -- including
# `ash_r2rml_gate_qlever_test.exs`'s "exact query shape" test (no `~/ash_r2rml`
# fixture involved) raising `** (RuntimeError) ... :econnrefused` from a REAL
# `SPARQL.Client` round trip to this same `config/gno/test/store.ttl`'s
# `127.0.0.1:7020` endpoint, in that very run. That is direct, in-run proof
# that nothing speaking the real SPARQL protocol was listening there --
# whatever answered the bare `:httpc.request` GET to `http://localhost:7020`
# (no path, `localhost` not `127.0.0.1`) was not a QLever endpoint; the exact
# process/service that did answer was not independently identified (no shell
# access to the ephemeral hosted runner), but `:inets`/`:httpc` failing to
# start is RULED OUT as the mechanism -- real local evidence: `tesla`'s own
# `mix.exs` declares `extra_applications: [:logger, :ssl, :inets]`, so
# `Application.ensure_all_started(:tesla)` above already, deterministically,
# starts `:inets` too, identically in both environments (same code path, not
# environment-dependent) -- confirmed locally via
# `:application.which_applications/0` showing `:inets` present before this
# probe ever runs.
#
# The fix: stop asking "did ANY HTTP server answer?" and instead run the
# same real SPARQL-protocol round trip this codebase already trusts for this
# exact decision -- `GgenIgniter.EngineRegistry`'s own `qlever_reachable?/2`
# (`lib/ggen_igniter/engine_registry.ex`) already does this correctly: real
# `Ontology.load!/1` + real `Query.Qlever.load_store!/2` + a real
# `Query.Qlever.run/2` SELECT against the endpoint, `rescue -> false`. This
# is not a guess that the replacement works in the target environment: the
# SAME hosted CI run's own log shows this exact technique (invoked from
# `EngineRegistry.resolve/2` inside `ggen_igniter_engine_registry_test.exs`,
# against this exact `config/gno/test/store.ttl` store) logging "the QLever
# endpoint at --store-id ... is unreachable (or its ontology could not be
# resolved/loaded)" -- i.e. this technique already proved itself correct, in
# situ, on the exact runner this fix targets.
qlever_reachable? =
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
# on disk, that could never actually exclude an already-scheduled test.
unless File.exists?(Path.expand("~/ash_r2rml")) do
  ExUnit.configure(exclude: [:requires_ash_r2rml])
end

ExUnit.start()
