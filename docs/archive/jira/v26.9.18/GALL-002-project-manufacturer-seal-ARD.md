# ARD v26.9.18 — GALL-002: Project Manufacturer Seal

**Status:** DRAFT ARCHITECTURE SPEC  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/ggen_igniter`  
**Owner:** ggen_igniter  
**Dependencies:** GALL-001 when consuming a ggen-produced pack  
**Authority ceiling:** CONSTRUCT only

## Architectural objective

An admitted semantic subject can reconstruct an attested Ash/Igniter project projection with generator-owned mutations and no handwritten semantic drift.

The architecture follows the Chatman separation laws:

[
Received \neq Admitted,\quad Candidate \neq Authority,\quad SELECT \neq CONSTRUCT \neq DO
]

and every consequence/evidence claim is bounded by exact subject identity and replayable receipts.

## Load-bearing components

- `GgenIgniter.Pack.Manifest` — strict bootstrap identity
- `GgenIgniter.EphemeralManufacture` — attestation boundary
- `GgenIgniter.Receipt` — post-run file-set identity
- real `Igniter.compose_task/4` Ash/Igniter generator path
- `test/gall_checkpoint_002_project_manufacturer_test.exs` — crown court

## Data / control flow

`Admitted graph + manifest -> manufacturer identity -> upstream generators -> projection set -> post-run hash -> attestation -> regeneration receipt`

## Interfaces

- Input: GALL-001 receipt/pack where applicable + admitted graph/manifest
- Output: manufacturer/project receipt
- Downstream: GALL-003 semantic subject and GALL-005 composition

## Required invariants

1. Bind graph, strict pack manifest, profile, generator set and lock/toolchain into one manufacturer subject.
2. Compose real Ash/Igniter generators wherever the framework owns the mutation.
3. Bind generated projection identity to the exact receipted file set.
4. Verify current receipted bytes equal post_run_hash before attestation; use the same in-memory bytes for projection provenance.
5. Typed-refuse direct generated-source drift, missing post_run_hash, stale cache/native state and generator identity changes.
6. Prove clean deterministic regeneration.
7. Route MachineExperience compile-back through normal admission/manufacture only.

## Failure and refusal boundaries

- Required generator not composable => UNSUPPORTED(generator capability)
- Post-run bytes differ => REFUSED
- Stale build cache changes machinery => no standing
- Compile-back would patch generated source => REFUSED

A refusal is a valid architectural result. The implementation MUST NOT add model inference, private state, ambient dependencies, alternate authority paths or hand-written generated projections merely to make a court green.

## Repository-native qualification court

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix test test/ggen_igniter_ephemeral_manufacture_test.exs`
- `mix test test/gall_checkpoint_002_project_manufacturer_test.exs`
- `mix test`
- `mix e2e` when scaffold boundary is claimed

Each command is recorded with exact head SHA, relevant lock/toolchain identities, exit status and artifact digests. A later run against a different subject does not inherit this standing.

## Evidence contract

The checkpoint receipt MUST contain enough identity to let the next boundary validate:

- producer repository and exact SHA;
- semantic/manufacturer/runtime subject as applicable;
- predecessor receipt digests;
- court/falsifier identities;
- exact output artifact digests;
- standing and evidence ceiling.

## Security / authority

Authority is never inferred from capability, model output, successful parsing, observation, conformance, generated source or prior execution. Secrets and bearer credentials are never embedded into cross-repository evidence receipts; only opaque grant/principal identities needed for correlation are allowed.

## Definition of architectural closure

The architecture is closed only when the positive witness executes and every required negative witness is actually attempted against the exact subject. Configuration, source inspection or absence of a violation without an attempted falsifier is insufficient.
