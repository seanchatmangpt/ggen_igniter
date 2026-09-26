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
