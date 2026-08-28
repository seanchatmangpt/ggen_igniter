# ADR-004: Ash Framework Optional Integration Boundary

## Status
Accepted (`IMPLEMENTED`)

## Context
While `ggen_igniter` frequently generates Ash resources and domain models, forcing a hard dependency on Ash Framework would prevent `ggen_igniter` from being used in non-Ash Phoenix or vanilla Elixir projects.

## Decision
Maintain Ash integration as an optional consumer-level capability:
1. `GgenIgniter.Reactors.ReconcileReactor` uses standalone `use Reactor`, NOT `Ash.Reactor`.
2. Ash-specific templates and query patterns are packaged in reusable generator packs (e.g. `ash-lifecycle-pack`) without requiring `{:ash, ...}` in core `mix.exs`.

## Rationale
Decoupling core compilation and actuation from Ash ensures maximum reusability across any Elixir project.

## Consequences
- **Positive:** Zero mandatory Ash runtime dependency in core `ggen_igniter`.
- **Trade-off:** Ash DSL-specific validations occur downstream at project compile time (`mix compile`).
