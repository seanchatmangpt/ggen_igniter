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
qlever_reachable? =
  case :httpc.request(:get, {~c"http://localhost:7020", []}, [{:timeout, 1_000}], []) do
    {:ok, _} -> true
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
