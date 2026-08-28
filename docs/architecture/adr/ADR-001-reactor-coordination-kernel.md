# ADR-001: Reactor as the Coordination Kernel

## Status
Accepted (`IMPLEMENTED`)

## Context
Reconciliation involves multi-stage orchestration: loading ontologies, running queries, rendering templates, checking admission, writing files, verifying build validity, and updating evidence. Coordinating these steps imperatively leads to fragile error handling, partial mutation leaks, and complex rollback logic.

## Decision
Adopt `use Reactor` (`Reactor` hex package) as the formal coordination kernel for reconciliation in `GgenIgniter.Reactors.ReconcileReactor`.

## Rationale
1. **Dependency DAG:** Steps (`observe_prior_manifest`, `load_ontology`, `resolve_pack`) with disjoint dependencies execute concurrently without manual process management.
2. **First-Class Rollback:** Reactor provides explicit `undo/4` hooks that trigger when downstream steps (e.g. `:verify`) fail, enabling automatic restoration of on-disk pre-images.
3. **Purity of Steps:** Each step is modeled as a discrete function returning explicit success/failure tuples.

## Consequences
- **Positive:** Clear stage visibility, reliable compensation guarantees, clean separation of planning vs actuation.
- **Trade-off:** Requires an opt-in flag (`use_reactor: true`) during transition from the legacy linear pipeline (`GgenIgniter.Reconcile.run/1`).
