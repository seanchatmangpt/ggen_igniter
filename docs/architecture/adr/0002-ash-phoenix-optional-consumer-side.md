# ADR-0002: Ash and Phoenix Remain Optional, Consumer-Side Integrations

## Status

**Accepted.** Live since this project's inception, re-verified 2026-08-27.
Neither `:ash` nor `:ash_phoenix` nor `:phoenix`/`:phoenix_live_view`
appears anywhere in `mix.exs`'s real `deps/0` list (required, optional, or
test-only) — confirmed by reading the full dependency list directly.

## Context

`ggen_igniter` is a domain-agnostic ontology-to-code pipeline. Its most
thoroughly exercised proof-of-concept consumer (`test/fixtures/
ash-lifecycle-pack/`, driven by `test/e2e/lifecycle_test.ex`) happens to
generate `Ash.Resource`/`Ash.Domain` modules and, downstream, Phoenix
LiveView code via `mix ash_phoenix.gen.live`. This creates a real risk of
conflating "the fixture pack we test against" with "a core dependency."

## Decision

Ash and Phoenix are consumer-side concerns only:

- `ggen_igniter`'s own `lib/` tree has no `Ash.Resource`, `Ash.Domain`, or
  `use Ash.*`/`use Phoenix.*` anywhere.
- `mix ggen_igniter.doctor`'s Ash-domain check (check 7) scans a
  **consumer's** project textually for `use Ash.Domain` — it never requires
  `Ash` itself to be a dependency of `ggen_igniter`.
- Templates that generate Ash/Phoenix code (the `ash-lifecycle-pack`
  fixture) are pack **content**, not core pipeline code — a pack author
  choosing to target Ash does not make Ash a core dependency of the
  generation engine.
- `GgenIgniter.Reactors.ReconcileReactor` is a plain `use Reactor` module,
  explicitly not `Ash.Reactor`, specifically so Reactor-based coordination
  does not force an Ash dependency either (see ADR-0003).

## Consequences

- A project can depend on `ggen_igniter` and never install Ash or Phoenix
  at all — this is a real, load-bearing guarantee, not an aspiration.
- Ash's own compile-time domain-registration requirement
  (`config :OTP_APP, ash_domains: [...]`) is the **consuming application's**
  responsibility; `ggen_igniter` generates the `Ash.Domain` module but has
  no actuation path that writes application config for it.
- Phoenix/LiveView code downstream of a generated `Ash.Resource` is produced
  entirely by `ash_phoenix`'s own generator (`mix ash_phoenix.gen.live`),
  not by anything in this repo — `ggen_igniter`'s responsibility ends at a
  compilable `Ash.Resource`.
- This boundary is enforced as a standing architecture rule (see
  `docs/contributing/architecture-rules.md`, "Ash owns application
  semantics — in Ash consumers only") — new code under `lib/ggen_igniter/`
  or `lib/mix/tasks/` must not add a hard `Ash` dependency.

## See also

- `docs/integrations/ash/overview.md`, `docs/integrations/phoenix/overview.md`
- `docs/contributing/architecture-rules.md`
