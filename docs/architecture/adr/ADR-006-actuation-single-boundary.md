# ADR-006: Single Actuation Boundary & Deferred Execution

## Status
Accepted (`IMPLEMENTED`)

## Context
Scattering filesystem I/O across query, render, or templating modules makes rollback impossible and invites partial write corruption.

## Decision
Isolate all filesystem modifications and code evaluation strictly to `GgenIgniter.Actuate` and the `:actuate` Reactor step. Rendering produces a pure `%PendingActuation{}` plan; actuation consumes the admitted plan.

## Rationale
Centralizing mutations ensures that pre-images can be systematically recorded before any byte is modified, enabling exact bitwise compensation if verification fails.

## Consequences
- **Positive:** Guaranteed single mutation boundary, clean concurrency via `Task.async_stream/3`, robust self-healing.
- **Trade-off:** Requires threading `%PendingActuation{}` IR through admission before writing.
