# ggen_igniter v26.9.16 — RFC Closure Contract

Status: DRAFT IMPLEMENTATION PR.

## Canonical Jira tickets

- A2A-2608 — projected-ephemeral software invariant
- A2A-2612 — machine-experience compile-back

## RFC ownership

This repo owns the Elixir/Ash construction surface that turns admitted semantic inputs into generated application/runtime artifacts without letting generated code become the semantic source of truth.

## Required closure

1. Require exact admitted semantic subject + manufacturer identity before construction.
2. Bind every generated artifact set to graph/manufacturer/projection digests.
3. Provide a regeneration court proving the same admitted subject yields the same declared projection identity within profile.
4. Refuse direct semantic-authority promotion from generated source edits.
5. Accept machine-experience output only after qualification/admission and project it through the normal manufacturer path.
6. Emit construction evidence suitable for SA2A semantic-subject/receipt binding.

## Chicago falsifiers

- hand-edit generated output and preserve standing without regenerating from the admitted source;
- construct with an unknown/unadmitted semantic subject;
- generator version changes without changing the manufacturer digest;
- generated code grants itself authority;
- compile-back bypasses the same manufacturer/admission path used for ordinary semantic construction.

## Definition of done

Exact-head tests establish content identity, deterministic regeneration within profile, fail-closed drift, and compatibility with the ash_r2rml and ash_a2a v26.9.16 semantic-subject evidence path.
