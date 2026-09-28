# ADR-011: Reduce `sj:` toward oslc_cm / dcterms / PROV-O / SHACL

Status: PARTIAL_ALIVE (2026-09-28). Milestone v26.9.20. Step 4 (additive
mappings) is implemented for two terms only; steps 1-3 are argued per term in
`priv/ggen/semantic-jira-pack/VOCABULARY.md` ("ADR-011 step 4 mappings").
Removal of any `sj:` term remains PLANNED and is not done.

## Context

`priv/ggen/semantic-jira-pack/ontology.ttl` declares a pack-local `sj:`
vocabulary (WorkOrder, Court, EvidenceRequirement, AcceptanceCriterion,
Falsifier, Action, Checkpoint, Projection, and their properties). Prior art
covers much of this: OSLC Change Management (`oslc_cm:`) for change requests,
Dublin Core Terms (`dcterms:`) for identity/title/dates/relations, PROV-O
(`prov:`) for evidence and derivation, and SHACL for the constraint layer (the
pack already uses SHACL shapes under `shapes/`).

## Decision

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

- Only two edges exist: `sj:WorkOrder rdfs:subClassOf oslc_cm:ChangeRequest`
  and `sj:Receipt rdfs:subClassOf prov:Entity`. Both are subsumption, not
  equivalence. Every other candidate is rejected with a reason in
  VOCABULARY.md (StandingTransition/prov:Activity, EvidenceRequirement,
  Action/ProjectionSpec vs prov:Plan, replayIdentity vs dcterms:identifier,
  and others). No dcterms edge was added: identity/title/description are
  already native dcterms.
- No `sj:` term was removed; no instance is dual-typed. The oslc_cm/PROV-O fit
  beyond these two edges is UNVERIFIED.
- Gates are not re-run against a public-only form (nothing was removed), so
  the removal precondition in Decision 4 is UNVERIFIED.

## Verified (2026-09-28)

`test/ggen_igniter_semantic_jira_vocab_mapping_test.exs`: the edge set
reaching public namespaces is exactly the two above; rejected candidates are
absent (falsifier); no shape targets a public class, and public-typed nodes
with arbitrary properties are not pulled under closed `sj:` shapes
(SJ-002 R3); SHACL verdict, violations and focus-node count are identical with
and without the edges; no `sj:` declaration at HEAD was dropped. Digests are
computed from the kernel map (`@definition_fields`), not graph triples, so
none moved.

## Falsifier

A pack gate or SHACL shape whose result differs between the `sj:` form and the
mapped public form.
