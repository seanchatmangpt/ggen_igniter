# RFC v26.9.26 — enterprise architecture bootstrap seed

## Ownership
ggen_igniter bootstraps a project/system from admitted enterprise-architecture semantics. It propagates architecture identity; it does not self-declare origin authority.

## Definition of done
1. Add an EA-aware ignition input that binds an exact ArchitectureContract, selected/qualified SBB and origin authority.
2. Generate project scaffolding from admitted SBB composition rather than vendor-specific presets.
3. Persist exact ABB/SBB/contract/provenance digests in the generated project.
4. Refuse mutable qualification, missing originAuthority, UNKNOWN standing and authority widening.
5. Support regeneration after SBB substitution without losing architecture identity.
6. Add deterministic migration receipt for SBB replacement.
7. Consume marketplace/ggen outputs rather than duplicate EA schemas.
8. Add positive and negative fixtures for substitute SBBs satisfying the same ABB.

No generated project may manufacture new consequential authority.

## Implementation status (v26.9.26 hardening pass)
`GgenIgniter.EA.Ignition` (`lib/ggen_igniter/ea/ignition.ex`) is the admission kernel for
DoD 1, 3, 4, 5, 6 and 8: exact digest binding of contract/ABB/SBB/origin/provenance,
a deterministic lock (`lock/1`, `verify_lock/2`), typed refusals for mutable
qualification, missing `originAuthority`, non-ALIVE standing and authority widening,
SBB substitution that preserves architecture identity, and a deterministic migration
receipt that refuses stale, duplicated, reordered and tampered delivery.
Tests: `test/ggen_igniter_ea_ignition_test.exs`. Benchmark: `bench/ea_ignition_bench.exs`,
numbers and regression bounds in `receipts/v26.9.26/ea-ignition-bench.json`.

Not yet implemented (UNSUPPORTED): DoD 2 (scaffold generation from admitted SBB
composition) and DoD 7 (consuming marketplace/ggen EA schemas — no ABB/SBB/originAuthority
vocabulary exists in ggen-marketplace `origin/main` at this pass; the input shape here is
the seam such a pack would project into).
