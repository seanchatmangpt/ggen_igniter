# WBPR — GALL-002 Project Manufacturer Seal

**Working-backwards target. This is the future release state, not current standing.**

## Headline

**ggen_igniter makes an admitted semantic subject become a complete Ash application projection without handwritten semantic drift.**

## Subheadline

GALL-002 closes the manufacturer boundary from public semantic input to real Ash/Igniter generator execution, content-addressed project output, post-run attestation, deterministic regeneration, and typed refusal of generated-source drift.

## Announcement

At completion, `ggen_igniter` becomes the project-manufacture checkpoint in the Semantic A2A chain:

`admitted graph + manifest -> manufacturer identity -> Ash/Igniter generators -> project projection -> attestation -> replayable construction receipt`

The core promise is not “we can generate Elixir.” The promise is that every generated Ash mutation is owned by the semantic source and the real upstream generator that knows how to perform the complete mutation.

## Customer problem

A plausible Ash resource file is not an Ash application.

Handwritten generation misses coupled mutations such as:

- domain registration;
- base-resource configuration;
- action accept-list derivation;
- repo/data-layer wiring;
- migration snapshots;
- generator-specific compatibility behavior.

The result can compile and still be semantically incomplete.

The second failure mode is provenance drift: generated output is edited after manufacture and silently treated as if the semantic source changed.

## Product

GALL-002 gives every project manufacture an exact semantic/manufacturer identity:

`{graph_digest, manifest_identity, manufacturer_digest, projection_digest, profile}`

The manufacturer:

- admits the semantic subject;
- invokes the real Ash/Igniter generators;
- records exactly which generator identities participated;
- binds the full generated projection set;
- attests post-run bytes;
- regenerates deterministically;
- refuses unreceipted drift;
- routes qualified MachineExperience compile-back through the same manufacture path.

## Customer experience

The operator changes the semantic source, not generated resource files.

The system manufactures the application projection and returns a receipt that identifies the exact semantic source, generator machinery, output byte set, and replay result.

If somebody hand-edits generated output, standing falls until the semantic source is changed and the projection is lawfully regenerated.

## Core invariants

`AshKnowsHowToManufacture(x) => NoHandwrittenReplacement(x)`

`Projection != SemanticAuthority`

`ManufacturerIdentityChange => SubjectIdentityChange || REFUSED`

`AttestedBytes = ReceiptedBytes`

## Release proof

The release is complete only when one exact head proves:

1. an admitted graph/manifest creates a real Ash project projection;
2. the path uses upstream Ash/Igniter generators;
3. graph/manufacturer/projection identities are all bound;
4. post-run attestation binds the bytes that actually exist;
5. clean regeneration is deterministic within profile;
6. direct drift of generated source loses standing;
7. generator identity drift cannot retain the old subject identity;
8. compile-back cannot bypass ordinary admission/manufacture.

## Chicago relation

GALL-002 supplies construction/manufacturer evidence. It strengthens exact identity and executable-world evidence but carries no authority or DO standing.

## Non-claims

No claim is made that:

- generated code is semantic truth;
- compilation alone proves correctness;
- a generator can grant itself authority;
- this checkpoint proves external consequences;
- this checkpoint proves cross-repository SA2A closure.

## Release receipt

A releasable receipt names:

- exact repository SHA;
- graph + manifest identity;
- GALL-001 predecessor when applicable;
- manufacturer/toolchain identity;
- upstream generator tasks;
- generated projection set and digests;
- attestation identity;
- regeneration result;
- drift falsifier result;
- bounded standing.

## Working-backwards definition of done

A consumer can delete the generated projection, retain only the admitted semantic inputs plus admitted manufacturer machinery, and reconstruct the same project subject.

At that point project generation stops being artisanal source editing and becomes lawful manufacture.
