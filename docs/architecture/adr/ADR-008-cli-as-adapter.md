# ADR-008: CLI as a Thin Adapter over the Kernel

## Status
Accepted (`IMPLEMENTED`)

## Context
CLI tasks often become tangled with core business logic, preventing reuse from Web UIs, persistent GenServers, or test suites.

## Decision
Model `Mix.Tasks.GgenIgniter.Sync` as a thin CLI adapter that delegates to `GgenIgniter.Controller` (when running) or directly invokes `GgenIgniter.Reactors.ReconcileReactor` / `GgenIgniter.Reconcile`.

## Rationale
Ensures 100% of pipeline capabilities are accessible programmatically via standard BEAM message passing and function calls.

## Consequences
- **Positive:** Zero duplication of query, render, or actuation logic between CLI and OTP applications.
- **Trade-off:** CLI must handle graceful fallback when controller is not running.
