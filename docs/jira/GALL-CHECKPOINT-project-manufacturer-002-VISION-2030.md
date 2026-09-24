# Vision 2030 — ggen_igniter as the Semantic Project Factory

> **Design horizon, not prediction.**
>
> Assume code generation is abundant. The enduring problem is whether a complete framework-native application can be reconstructed from admitted semantics without humans or models hand-synchronizing framework state.

## 1. Thesis

By 2030, `ggen_igniter` is the **semantic project factory** for framework-native systems.

Its job is not to print Elixir.

Its job is to take an admitted semantic subject and drive the real framework manufacturers that already know how to create a lawful Ash/Phoenix/Igniter system:

[
O^*
ightarrow
ManufacturerPlan
ightarrow
Igniter/Ash
ightarrow
ProjectProjection
ightarrow
Attestation
ightarrow
Replay
]

The project source tree becomes a materialized view of semantic state plus admitted manufacturer machinery.

## 2. Why this remains scarce in 2030

LLMs can generate plausible framework code.

That does not mean they know every coupled mutation a framework generator owns.

The scarce invariant is **complete framework-native construction**:

- configuration;
- registration;
- generated source;
- migrations;
- snapshots;
- supervision;
- action surfaces;
- dependency wiring;
- version-specific conventions;
- framework-owned invariants.

By 2030, the rule is:

[
FrameworkGeneratorOwns(x) Rightarrow AgentMustCompose(x)
]

not imitate it.

## 3. The project as a projection

The 2030 project is modeled as:

[
P = mu_{framework}(O^*, M)
]

where:

- (O^*) is admitted semantic state;
- (M) is exact manufacturer identity;
- (P) is the complete project projection.

A repository may contain thousands of files, yet the authoritative input surface remains much smaller:

- ontology;
- manifest;
- admitted generator capabilities;
- templates only where no upstream generator owns the mutation;
- receipts;
- qualification rules.

## 4. Zero handwritten generated state

The strategic end state:

[
HumanAuthority(GeneratedProjection)=0
]

[
LLMAuthority(GeneratedProjection)=0
]

Humans and AI may propose semantic changes.

They do not directly patch framework-owned projections and call the project complete.

A generated source edit is interpreted as one of:

- drift;
- emergency privileged intervention with a bounded receipt;
- evidence that the ontology/manufacturer model is incomplete.

The normal path is always:

[
Intent
ightarrow SemanticDelta
ightarrow Admission
ightarrow Manufacture
]

## 5. Generator capability ontology

By 2030, every upstream generator is represented semantically:

[
GeneratorCapability =
{
inputs,
outputs,
preconditions,
frameworkVersion,
sideEffects,
ownedMutations,
verification,
standing
}
]

This allows ggen_igniter to select and compose generators without embedding brittle, handwritten orchestration logic for every project shape.

A generator can be:

- discovered;
- admitted;
- composed;
- version-fenced;
- replayed;
- refused.

## 6. Project reconstitution

The 2030 crown property is project reconstitution.

Given only:

- admitted semantic source;
- exact manifest;
- admitted generator set;
- dependency artifacts;
- manufacturer receipt;

the project can be regenerated into an equivalent operational projection.

[
Delete(ProjectProjection)
+
O^*
+
ManufacturerSet
Rightarrow
Equivalent(ProjectProjection')
]

This changes disaster recovery, migration, onboarding, modernization, and software maintenance.

The source tree is no longer precious.

The manufacturing law is precious.

## 7. Framework evolution

A major framework release no longer requires manual migration across thousands of repositories.

The system computes:

[
Delta_{framework}
+
Delta_{semantic}
ightarrow
Delta_{project}
]

and qualifies the new projection through framework-native generators and exact falsifiers.

This enables:

- Ash upgrades;
- Phoenix upgrades;
- database changes;
- security-policy evolution;
- new runtime targets;
- cross-version replay.

## 8. MachineExperience compile-back

By 2030, qualified experience can improve manufacturing without becoming an ambient authority source.

The loop is:

[
ObservedDefect
ightarrow
VerifiedExperience
ightarrow
SemanticDelta
ightarrow
Admission
ightarrow
ManufacturerUpdate
ightarrow
Regeneration
]

No MachineExperience object may directly patch generated project files.

Experience teaches the manufacturer; it does not bypass it.

## 9. Project manufacturing economics

Today, framework expertise is repeatedly spent on:

- setup;
- wiring;
- migrations;
- compatibility;
- generated boilerplate;
- drift repair.

By 2030, those patterns are encoded as manufacturer capabilities.

The unit of expertise becomes reusable machinery.

The important metric is:

[
ManualFrameworkMutationRate ightarrow 0
]

for governed surfaces.

## 10. 2030 crown capabilities

1. Semantic-to-Ash project manufacture
2. Generator capability discovery
3. Exact framework-version fencing
4. Deterministic multi-stage generator composition
5. Generated/manual source distinction
6. Projection drift refusal
7. Post-run byte attestation
8. Project reconstitution
9. Schema/migration manufacture
10. MachineExperience compile-back
11. Cross-project reusable manufacturer packs
12. Framework upgrade manufacture

## 11. Human role

Humans remain valuable where the system does not yet have admitted semantics.

They decide:

- what the system should mean;
- which constraints matter;
- which outcomes are acceptable;
- which authority is legitimate;
- when a new generator capability is required.

They do not spend premium attention manually maintaining boilerplate the framework can already manufacture.

## 12. GALL trajectory

GALL-002 is the first pier:

[
SemanticSubject
ightarrow
ExactManufacturer
ightarrow
AttestedProjection
]

By 2030 that expands into:

[
EnterpriseSemanticState
ightarrow
FrameworkFactory
ightarrow
ReconstitutableApplicationFleet
]

## 13. 2030 falsifiers

The vision fails if:

- framework-owned mutations are still routinely handwritten;
- generated files become canonical state;
- project regeneration depends on hidden local state;
- framework upgrades require mass artisanal patching;
- MachineExperience can bypass admission/manufacture;
- two equivalent admitted subjects manufacture materially different projects without a typed reason.

## 14. Final compression

By 2030:

[
oxed{
ggen_igniter =
	ext{semantic application factory}
}
]

The goal is not to make AI better at writing Ash code.

The goal is to make writing Ash code the wrong abstraction for everything the framework already knows how to manufacture.
