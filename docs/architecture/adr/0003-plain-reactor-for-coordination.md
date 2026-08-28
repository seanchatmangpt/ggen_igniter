# ADR-0003: Plain Reactor (not Ash.Reactor) for the Target Coordination Pipeline

## Status

**Accepted** for the code that exists: `GgenIgniter.Reactors.ReconcileReactor`
is real, compiles, and is exercised by real, currently-passing, no-mock
tests. **Not yet the default** — this ADR records a real, live decision
about *which* coordination mechanism to build, not a claim that it has
replaced the plain pipeline as the default execution path (that is a
separate, not-yet-made decision — see Consequences).

## Context

`ggen_igniter` needed dependency-ordered, concurrent, compensable
coordination of its observe → load → resolve → query → render → admit →
actuate → verify → finalize-evidence spine. Ash ships its own `Ash.Reactor`
DSL, which would have been a natural fit given the project's most
thoroughly exercised consumer targets Ash — but ADR-0002 already commits
to Ash being optional and consumer-side only.

## Decision

Build the coordinator as a plain `use Reactor` module
(`GgenIgniter.Reactors.ReconcileReactor`), explicitly not `Ash.Reactor`, so
Reactor-based coordination does not itself force an Ash dependency onto
every `ggen_igniter` consumer. Dispatch to it only when a consumer
explicitly opts in via `config :ggen_igniter, use_reactor: true` (default
`false`) — two independent call sites read this same flag
(`Mix.Tasks.GgenIgniter.Sync.use_reactor?/0` and
`GgenIgniter.Controller.run_pipeline/1`).

## Consequences

- `{:reactor, "~> 1.0"}` is a real, unconditional (non-`only:`)
  `mix.exs` dependency — it must compile for every consumer even though
  running it is opt-in, the same reasoning applied to `{:igniter, "~> 0.8"}`.
- The Reactor pipeline gets real capabilities the plain pipeline does not:
  a `%PendingActuation{}` plan/admit boundary, real per-target concurrency
  (`Task.async_stream/3`), real `compensate/4`/`undo/4` rollback, and a
  guaranteed persisted `GgenIgniter.Receipt` on every path (success or
  failure).
- **Two coordination paths coexist today, and this ADR does not resolve
  that**: `GgenIgniter.Reconcile.run/1` (a plain function pipeline, no
  admission/compensation/receipt) is still the actual default whenever
  `use_reactor` is left at its default `false` — which is every consumer
  that hasn't explicitly configured otherwise. `Mix.Tasks.GgenIgniter.Sync`
  additionally has its own third, separate inline implementation of this
  same spine that predates both. Unifying these three onto one coordinator
  is disclosed, real, future work (see `docs/architecture/overview.md`'s
  CURRENT-vs-TARGET table and `docs/contributing/architecture-rules.md`'s
  "no duplicate coordinator" invariant) — this ADR records the decision
  about *what the target coordinator is built from*, not that migration to
  it is complete.

## See also

- `docs/reference/reactor/overview.md` — full pipeline detail
- `docs/integrations/ash/reactor.md` — the Reactor-vs-Ash.Reactor distinction in depth
- `docs/contributing/architecture-rules.md` — "Reactor owns coordination — where implemented"
