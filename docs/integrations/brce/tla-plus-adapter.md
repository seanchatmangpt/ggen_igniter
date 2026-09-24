# TLA+ generation adapter for BRCE

**Specification status:** FINAL_SPEC v0.1 (v26.9.24)  
**Implementation standing:** PLANNED / not claimed  
**Role:** ontology-to-formal-spec projection

## 1. Purpose

The adapter manufactures TLA+ specifications from semantic source material so transition-system verification can be added without turning hand-written TLA+ into a second source of truth.

Target pipeline:

[
CanonicalGraph
\rightarrow SHACL/SPARQL admission
\rightarrow ggen\_igniter
\rightarrow (.tla,.cfg,manifest)
\rightarrow TLC/TLAPS
\rightarrow evidence
]

The verifier invocation is outside generation.

## 2. Prior-art seed

The syntax/metamodel layer SHOULD be mechanically aligned with the official TLA+ parser representation (SANY AST/XML schema) rather than being invented from examples.

The semantic layer SHOULD add the verification concepts the ecosystem needs:

```text
Module
StateVariable
InitialCondition
Action
TransitionRelation
Invariant
SafetyProperty
LivenessProperty
FairnessConstraint
TemporalProperty
Refinement
Model
ModelBound
VerificationRun
Counterexample
ProofObligation
```

The syntax layer and verification-semantics layer MUST remain distinguishable.

## 3. Proposed pack shape

The implementation SHOULD follow the repository-native pack convention:

```text
priv/ggen/tla-plus-pack/
  ontology.ttl
  gates/
    010_module.rq
    020_variables.rq
    030_actions.rq
    040_invariants.rq
    050_liveness.rq
    060_model_bounds.rq
  templates/
    module.tla.eex
    model.cfg.eex
    verification-manifest.json.eex
```

If additional SHACL assets are needed, they SHOULD live in a documented pack-adjacent validation surface rather than silently changing the fixed `--pack` discovery contract.

## 4. BRCE mapping

The first reference model SHOULD target BRCE:

```text
RECEIVED
PARSED
ROUTED
ADMISSION_PENDING
ADMITTED
CONSTRUCTED
AUTHORITY_PENDING
AUTHORIZED
PREPARED
DO
EXECUTION_OBSERVED
RECEIPTED
VERIFIED
REPLAYABLE
STANDING
```

Required invariants include:

[
DO \Rightarrow ValidAuthority
]

[
Standing \Rightarrow ValidReceipt
]

[
Standing \Rightarrow Verified
]

[
SELECT \Rightarrow \neg Consequence
]

[
CONSTRUCT \Rightarrow \neg Consequence
]

and for at-most-once consequences:

[
count(effect(consequenceId)) \le 1
]

A progress model SHOULD represent:

[
Admitted
\leadsto
Receipted \lor Refused \lor Blocked \lor Unsupported
]

## 5. Generated/handwritten boundary

The ontology, SPARQL gates, and templates are authoritative manufacturing inputs.

Generated `.tla`, `.cfg`, and manifests are projections.

Handwritten TLA+ is permitted only for semantics that cannot be represented by an admitted generator capability, and that residue SHOULD be named explicitly as:

```text
UNSUPPORTED(generator-capability)
```

The implementation SHOULD prefer:

[
reuse \rightarrow compose \rightarrow extend \rightarrow invent
]

## 6. Verification court

A later verification court may invoke SANY/TLC/TLAPS against the generated artifacts.

That court MUST bind:

```text
subject
ontology_digest
spec_digest
config_digest
tool_identity
tool_version
command
properties_checked
bounds
exit_code
result
counterexample_digest
stdout_digest
stderr_digest
```

A PASS has the evidence ceiling:

> the named properties held for the reachable state space explored by this exact model, configuration, bounds, and verifier invocation.

It does not prove production behavior.

## 7. Counterexamples

Counterexamples are successful falsifier outputs, not disposable logs.

A counterexample SHOULD be preserved with:

```text
property
initial_state_digest
transition_trace_digest
terminal_state_digest
spec_digest
config_digest
replay_command
```

After repair, the trace SHOULD become a permanent regression witness.

## 8. Reference fault corpus

The first BRCE qualification SHOULD deliberately introduce and detect at least:

- DO without authority;
- receipt-before-execution standing;
- expired-authority actuation;
- duplicate retry causing duplicate consequence;
- stale reconciler promoting UNKNOWN;
- construct substitution after authorization;
- target substitution;
- verification replay causing new consequence.

The pack is not qualified until these defects are observed as counterexamples under the exact generated model.

## 9. Receipt boundary

`ggen_igniter` may emit a manifest describing what it generated.

It MUST NOT claim a TLA+ verification receipt merely because files exist.

Formal execution evidence SHOULD be handed to a receipt implementation through an adapter. Affidavit is one possible implementation; BRCE does not require it.

## 10. Admission criteria for implementation status

The capability remains `PLANNED` until all of the following have been observed at one exact subject:

1. ontology loads;
2. SPARQL gates return the required rows;
3. templates deterministically render `.tla` and `.cfg`;
4. a second generation is idempotent;
5. SANY accepts the generated module;
6. TLC detects every seeded reference fault;
7. TLC passes the repaired reference model under documented bounds;
8. exact inputs/toolchain/results are receipted;
9. replay reproduces the verification result without external BRCE consequence.

Only then may the specific generated-model court move beyond PLANNED/UNKNOWN according to the repository's evidence vocabulary.

## Falsifiers

The adapter design is invalid if generation itself:

- performs BRCE DO;
- grants authority;
- silently edits a generated projection by hand;
- calls verification success without observed verifier execution;
- promotes a bounded TLC result into a claim about unmodeled production behavior.


## Specification closure

The adapter contract is complete for v26.9.24. The executable capability remains `PLANNED` until the nine admission criteria above are observed at one exact subject. No specification label may promote that implementation standing.
