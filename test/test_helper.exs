{:ok, _} = Application.ensure_all_started(:tesla)
{:ok, _} = Application.ensure_all_started(:ggen_igniter)

# This file decides which tags to exclude BEFORE `ExUnit.start/1`, not
# inside any test file's own `setup` block. `ExUnit.configure/1`'s
# `:exclude` option only affects which already-collected tests get
# DISPATCHED; by the time a per-test `setup` callback runs, ExUnit has
# already decided (in `ExUnit.Runner.prepare_tests/3`, via
# `ExUnit.Filters.eval/4`, against each test's STATIC `@tag`-collected tags
# only) whether to run that specific test -- a `setup`-local
# `ExUnit.configure(exclude: [...])` call can never exclude the very test
# whose `setup` invoked it. Confirmed the hard way (six real test files each
# reimplemented this exact broken per-`setup` pattern; every affected test
# genuinely FAILED, not skipped) and confirmed again (GI-13, 2026-09-14): a
# `setup` callback returning `{:skip, reason}` is not a distinct escape
# hatch either -- ExUnit 1.18.4's own `setup`/`setup_all` contract
# (`lib/ex_unit/lib/ex_unit/callbacks.ex`, read directly, not assumed) only
# accepts `:ok`, a keyword list, or a map; `{:skip, reason}` raises. There is
# no ExUnit-native way, in this Elixir version, to decide "skip this one
# test" at its own run time. Every such decision must be made here, in
# advance of `ExUnit.start/1`.
#
# GI-13 (2026-09-14) THE REAL BUG, found after three network-probe-tuning
# attempts and a hosted-CI diagnostic print all failed to fix hosted CI
# (runs 34822966689, 34826784317, 34829186413, 34832502336): this file used
# to call `ExUnit.configure(exclude: [:requires_qlever_server])` and, later,
# `ExUnit.configure(exclude: [:requires_ash_r2rml])` as two SEPARATE calls.
# `ExUnit.configure/1`'s real implementation
# (`lib/ex_unit/lib/ex_unit.ex`) is `Enum.each(options, fn {k, v} ->
# Application.put_env(:ex_unit, k, v) end)` -- a plain overwrite, not a
# merge. The SECOND call REPLACES the `:exclude` application env entirely;
# it does not append to it. Proven directly, locally, in isolation
# (`ExUnit.configure(exclude: [:tag_a])` then
# `ExUnit.configure(exclude: [:tag_b])` leaves
# `Application.get_env(:ex_unit, :exclude) == [:tag_b]`, `:tag_a` silently
# gone).
#
# This explains every one of the four prior hosted-CI failures, independent
# of whatever the qlever reachability probe computed: `~/ash_r2rml` never
# exists on the hosted runner, so the ash_r2rml `unless` block ALWAYS also
# ran there, and its `ExUnit.configure(exclude: [:requires_ash_r2rml])`
# ALWAYS clobbered whatever the qlever block had just set moments earlier --
# regardless of whether that qlever exclude decision was itself correct. The
# 2026-09-14 diagnostic run (34834542330) proved this precisely: it printed
# `ci?=true` (the reachability computation was definitely correct, forcing
# `qlever_reachable? = false`) immediately before the SAME run's "Excluding
# tags" line still showed only `[:requires_ash_r2rml]` -- the qlever
# exclusion was computed correctly and then silently lost.
#
# This also explains why every local verification of the three prior
# attempts passed: this development machine has `~/ash_r2rml` checked out,
# so the ash_r2rml `unless` block's condition is false there and its
# `configure/1` call never runs, never clobbering anything -- a real,
# reproducible environment difference that had nothing to do with qlever
# reachability at all, masking the actual bug throughout.
#
# The fix: accumulate every tag to exclude into ONE list and call
# `ExUnit.configure(exclude: ...)` exactly once.
excludes = []

# qlever is an optional query engine (oxigraph is the default -- see
# docs/architecture/adr/0001-oxigraph-default-query-engine.md); tests tagged
# `:requires_qlever_server` exercise the real `--engine qlever` path against
# a real, already-running QLever server and must not run (or fail) when no
# such server is available.
#
# Real hosted-CI history on this exact `127.0.0.1:7020` /
# `config/gno/test/store.ttl` precondition, before the real bug above was
# found: three independently-triggered runs each tried a different, more
# careful real-network reachability technique (a bare `:httpc` GET; the
# real `SPARQL.Client` round trip `GgenIgniter.EngineRegistry.
# qlever_reachable?/2` already uses; that same round trip required to
# succeed twice, 2 seconds apart) and each still, independently, looked like
# it was false-positiving on the hosted runner. With the real bug (the
# configure/1 overwrite above) now fixed, it is likely at least some of that
# apparent flakiness was actually this same clobbering bug wearing a
# network-timing disguise -- but not provably all of it (run 34826784317's
# `EngineRegistry.resolve/2`-internal call to the identical technique
# finding the endpoint unreachable, moments after this probe's own call
# found it reachable, is real, in-run evidence of at least some genuine
# transience too). Rather than spend a further hosted-CI round trip
# re-litigating how much of that was which cause, this keeps the simplest
# defensible layer: `CI` is the standard, deterministic, unconditionally-set
# signal every CI provider (confirmed here: GitHub Actions sets both
# `CI=true` and `GITHUB_ACTIONS=true`, verified directly via a hosted-run
# diagnostic print, not assumed) uses for "this is a CI job, not a real
# developer machine." This project's own `ci.yml` never starts a QLever
# server in any job (confirmed by reading the whole workflow: no
# `services:` block, no `qlever start` step, nothing binds port 7020
# deliberately) -- "hosted CI" and "no real QLever server, ever,
# structurally" are the same fact here, independent of whatever a network
# probe observes on that port. `CI` truthy short-circuits straight to
# excluded, no network call, no timing to get wrong; every non-CI
# environment (a real developer machine, the case these tests were actually
# written for) keeps the real round-trip probe, unaffected.
ci? = System.get_env("CI") not in [nil, "", "false", "0"]

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

excludes = if qlever_reachable?, do: excludes, else: [:requires_qlever_server | excludes]

# Same real external-fixture-dependency shape as qlever above
# (`test/ash_r2rml_gate_integration_test.exs`,
# `test/ggen_igniter_oxigraph_engine_test.exs`), but this precondition is
# genuinely stable for the lifetime of one `mix test` invocation -- nothing
# mid-run mounts or unmounts `~/ash_r2rml` -- so a plain, one-time
# `File.exists?/1` check (no network, no transience question) has always
# been the right technique for this specific tag; it was never the
# unreliable half of this file, only a silent victim of the configure/1
# overwrite bug above when it happened to run after the qlever block.
excludes =
  if File.exists?(Path.expand("~/ash_r2rml")) do
    excludes
  else
    [:requires_ash_r2rml | excludes]
  end

unless excludes == [] do
  ExUnit.configure(exclude: excludes)
end

# Many tests spawn real `mix` subprocesses (compile, sync, verify). Under a
# fully parallel run (max_cases 32, plus other work on the machine) a `mix`
# boot alone can exceed ExUnit's 60s default, which surfaced as
# `ExUnit.TimeoutError` flakes (reconcile_reactor, lock_staleness two-OS-process,
# reconciliation_manifest, e2e_all_engines) that pass in isolation. The
# timeout is a hang backstop, not an assertion; raise it (override with
# GGEN_TEST_TIMEOUT_MS).
timeout_ms =
  case Integer.parse(System.get_env("GGEN_TEST_TIMEOUT_MS", "")) do
    {n, ""} when n > 0 -> n
    _ -> 300_000
  end

ExUnit.start(timeout: timeout_ms)
