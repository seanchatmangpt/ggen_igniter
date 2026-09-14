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
# The fix, part 1: stop asking "did ANY HTTP server answer?" and instead run
# the same real SPARQL-protocol round trip this codebase already trusts for
# this exact decision -- `GgenIgniter.EngineRegistry`'s own
# `qlever_reachable?/2` (`lib/ggen_igniter/engine_registry.ex`) already does
# this correctly: real `Ontology.load!/1` + real `Query.Qlever.load_store!/2`
# + a real `Query.Qlever.run/2` SELECT against the endpoint, `rescue ->
# false`.
#
# GI-13 follow-up 2 (2026-09-14, same day, next hosted run 34826784317 on
# SHA ec038f7): part 1 alone was NOT sufficient -- real, evidenced,
# reproduced on a SECOND independent hosted CI run. That run's own
# `Excluding tags: [:requires_ash_r2rml]` line again omitted
# `:requires_qlever_server`, i.e. THIS EXACT round-trip probe (below) still
# returned `true` there, yet 3 of the 9 `:requires_qlever_server`-tagged
# tests still failed for real, including two with the identical real
# `** (RuntimeError) ... :econnrefused` seen on the first hosted run, AND
# (most tellingly) `ggen_igniter_engine_registry_test.exs`'s own "all"-engine
# test failed on `left: {:ok, [:oxigraph, :sparql]}` vs
# `right: {:ok, [:oxigraph, :sparql, :qlever]}` -- meaning
# `EngineRegistry.resolve/2`'s OWN internal call to this exact same
# `qlever_reachable?/2` technique, moments later in the SAME run, correctly
# found the endpoint UNREACHABLE. Two independent invocations of the
# identical real round-trip technique, on the identical `127.0.0.1:7020`
# literal IP:port (no DNS involved), disagreed within the same run: this
# probe (very first thing this suite does, before `ExUnit.start/1`) got
# `true`; the same technique run again minutes later got `false` (a real
# `:econnrefused`, proven by the sibling failures in the same run). That
# is real, direct, reproduced (now twice, across two independently
# triggered CI runs) evidence of TIME-DEPENDENT transience on the hosted
# runner's `127.0.0.1:7020` -- reachable at the very earliest possible
# moment in the job, refused shortly after -- not a technique defect (the
# technique itself, a real SPARQL round trip, is exactly right; asking it
# once, at the earliest possible instant, is what's wrong). The exact
# mechanism on the runner side is still not independently identified (no
# shell access to the ephemeral runner), but pinning that is unnecessary for
# a correct fix here.
#
# The fix, part 2: a real round trip is trusted for this decision only if it
# still succeeds a second time, after a short real, deliberate pause -- this
# targets the exact observed failure shape (transiently-true, then
# durably-false) directly, without guessing at its cause. A real,
# continuously-running local QLever server (the normal dev-machine case
# these tests were written for) trivially still answers a moment later; a
# transient early-boot artifact on a hosted runner does not.
qlever_reachable? =
  try do
    graph = GgenIgniter.Ontology.load!("config/gno/test/store.ttl")
    store = GgenIgniter.Query.Qlever.load_store!(graph, "http://example.com/Qlever")
    query = "SELECT ?s WHERE { ?s ?p ?o } LIMIT 1"

    GgenIgniter.Query.Qlever.run(store, query)
    Process.sleep(2_000)
    GgenIgniter.Query.Qlever.run(store, query)
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
