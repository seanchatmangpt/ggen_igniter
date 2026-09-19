# PRD v26.9.18 — GALL-002: Project Manufacturer Seal

**Status:** DRAFT IMPLEMENTATION SPEC  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/ggen_igniter`  
**Owner:** ggen_igniter  
**Dependencies:** GALL-001 when consuming a ggen-produced pack  
**Authority ceiling:** CONSTRUCT only

## Product thesis

An admitted semantic subject can reconstruct an attested Ash/Igniter project projection with generator-owned mutations and no handwritten semantic drift.

## Problem

Generated Ash source can look correct while missing framework-owned mutations or drifting after manufacture. A project needs a single admitted semantic/manufacturer identity and deterministic reconstruction through real Ash/Igniter generators.

## User / consumer

The primary consumer is another machine boundary in the GALL chain. Human maintainers need the same artifact to be inspectable, falsifiable and executable through repository-native courts. No downstream consumer is allowed to infer stronger standing than this checkpoint emits.

## Required product behavior

1. Bind graph, strict pack manifest, profile, generator set and lock/toolchain into one manufacturer subject.
2. Compose real Ash/Igniter generators wherever the framework owns the mutation.
3. Bind generated projection identity to the exact receipted file set.
4. Verify current receipted bytes equal post_run_hash before attestation; use the same in-memory bytes for projection provenance.
5. Typed-refuse direct generated-source drift, missing post_run_hash, stale cache/native state and generator identity changes.
6. Prove clean deterministic regeneration.
7. Route MachineExperience compile-back through normal admission/manufacture only.

## Acceptance criteria

1. Real admitted semantic fixture manufactures a complete Ash project through upstream generators.
2. Manufacturer digest changes when generator/config/lock subject changes.
3. Post-receipt output tamper is refused.
4. Delete/regenerate produces the same projection identity for the same admitted profile.
5. Handwritten substitute for a generator-owned mutation cannot satisfy the court.
6. `mix e2e` runs when the claim depends on a scaffolded real consumer project.

## Product outputs

The implementation MUST emit a machine-readable, content-addressed checkpoint artifact/receipt that binds the exact subject, evidence ceiling, falsifiers attempted, commands/courts executed and resulting standing. Prose documentation is explanatory only and cannot confer standing.

## Success metrics

- 0 generator-owned mutations implemented by ad hoc handwritten substitutes
- 100% receipted output bytes bound to attestation
- Deterministic projection digest for same admitted subject

## Non-goals

- Authority grant
- External DO
- Handwritten generated Ash
- Cross-repo crown

## Release semantics

- A configured workflow is not execution evidence.
- Source presence is not runtime standing.
- Local PASS, hosted PASS, runtime standing, merge and publication remain separate evidence classes.
- Any changed base/head SHA is a changed subject unless explicitly re-admitted.
- UNKNOWN/PARTIAL/REFUSED/BLOCKED states are preserved rather than collapsed into generic failure.

## Definition of done

An admitted semantic subject can reconstruct an attested Ash/Igniter project projection with generator-owned mutations and no handwritten semantic drift.

The exact v26.9.18 subject earns only the bounded standing proven by its repository-native court. No cross-repository promotion is implied.
