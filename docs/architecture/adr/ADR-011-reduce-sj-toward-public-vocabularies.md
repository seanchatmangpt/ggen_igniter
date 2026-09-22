# ADR-011: Reduce `sj:` toward oslc_cm / dcterms / PROV-O / SHACL

Status: PLANNED (2026-09-20). Milestone v26.9.20. Nothing in this ADR is
implemented; the current pack still declares every term under `sj:`.

## Context

`priv/ggen/semantic-jira-pack/ontology.ttl` declares a pack-local `sj:`
vocabulary (WorkOrder, Court, EvidenceRequirement, AcceptanceCriterion,
Falsifier, Action, Checkpoint, Projection, and their properties). Prior art
covers much of this: OSLC Change Management (`oslc_cm:`) for change requests,
Dublin Core Terms (`dcterms:`) for identity/title/dates/relations, PROV-O
(`prov:`) for evidence and derivation, and SHACL for the constraint layer (the
pack already uses SHACL shapes under `shapes/`).

## Decision (PLANNED)

1. Map candidate `sj:` terms to public terms by subclass/subproperty, keeping
   `sj:` as the extension point:
   - `sj:WorkOrder` -> `rdfs:subClassOf oslc_cm:ChangeRequest`
   - identity/title/created/references -> `dcterms:` properties
   - evidence, receipts, derivation -> `prov:Entity`/`prov:Activity`/
     `prov:wasDerivedFrom`
   - admission constraints -> SHACL shapes (already in use)
2. `sj:` is the irreducible residue: terms with no public equivalent
   (Court, Falsifier, evidence ceiling, standing vocabulary) stay in `sj:`.
3. Each reduction needs an equivalence argument before replacement
   (adjacency is not equivalence); a term is replaced only when the public
   term's semantics cover the pack's gates and shapes.
4. Mappings are additive first (`rdfs:subClassOf`/`rdfs:subPropertyOf`);
   removal of an `sj:` term happens only after the pack gates and SHACL shapes
   pass against the mapped form.

## Not claimed

- No mapping exists in the ontology today. Term-by-term equivalence is
  UNVERIFIED. The oslc_cm/PROV-O fit is a hypothesis to falsify.

## Falsifier

A pack gate or SHACL shape whose result differs between the `sj:` form and the
mapped public form.
