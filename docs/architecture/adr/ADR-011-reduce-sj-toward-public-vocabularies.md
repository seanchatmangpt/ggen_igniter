# ADR-011: Reduce `sj:` toward oslc_cm / dcterms / PROV-O / SHACL

Status: PARTIAL (updated 2026-09-21). Milestone v26.9.20. The additive alignment phase
(decision items 1, 2, 4-first-half) is IMPLEMENTED and gated; replacement or removal of any
`sj:` term (item 4, second half) is NOT done, by design. Exact residue below.

## Context

`priv/ggen/semantic-jira-pack/ontology.ttl` declares a pack-local `sj:` vocabulary (WorkOrder,
Court, EvidenceRequirement, AcceptanceCriterion, Falsifier, Action, Checkpoint, Projection, and
their properties). Prior art covers much of this: OSLC Change Management (`oslc_cm:`) for change
requests, Dublin Core Terms (`dcterms:`) for identity/title/dates/relations, PROV-O (`prov:`)
for evidence and derivation, and SHACL for the constraint layer (the pack already uses SHACL
shapes under `shapes/`).

## Decision

1. Map candidate `sj:` terms to public terms by subclass/subproperty, keeping `sj:` as the
   extension point:
   - `sj:WorkOrder` -> `rdfs:subClassOf oslc_cm:ChangeRequest` (IMPLEMENTED)
   - identity/title/created/references -> `dcterms:` properties (identifier, title and
     description were already used directly; `sj:subject`, `sj:requiresCourt`,
     `sj:requiresEvidence`, `sj:receiptClass`, `sj:projectionType`, `sj:extension` are now
     `rdfs:subPropertyOf` a `dcterms:` property)
   - evidence, receipts, derivation -> `prov:Entity`/`prov:Activity` (IMPLEMENTED for Receipt,
     PreparedAuthorityReceipt, MachineExperience, ProcessFinding, Projection, Subject,
     RepositorySubject -> `prov:Entity`; Actuation -> `prov:Activity`). `prov:wasDerivedFrom`
     was NOT adopted: no `sj:` property has a sound derivation reading (see the mapping table).
   - admission constraints -> SHACL shapes (already in use, unchanged)
2. `sj:` is the irreducible residue: terms with no public equivalent stay in `sj:`. Court,
   Falsifier, evidence ceiling and the standing vocabulary are confirmed residue. The ADR's
   original hypothesis that `sj:EvidenceRequirement` maps to `prov:Entity` was falsified:
   its individuals denote evidence kinds, not produced evidence.
3. Each reduction needs an equivalence argument before replacement (adjacency is not
   equivalence). The argument is stored per term in the ontology: either the alignment axiom
   (sound specialization) or `sj:residueReason` (the failing argument).
4. Mappings are additive first (`rdfs:subClassOf`/`rdfs:subPropertyOf`). Removal of an `sj:`
   term happens only after the pack gates and SHACL shapes pass against the mapped form. The
   additive form is in place and proven result-identical; no removal has been done.

## Enforcement

- `gates/047_public_vocab_alignment.rq` anti-joins every declared `sj:` class and property:
  each must be aligned to a public namespace XOR carry a non-empty `sj:residueReason`. Any
  row is a violation.
- `GgenIgniter.SemanticJira.PackHealth` (`mix ggen_igniter.doctor` `semantic_jira_pack`)
  refuses when that gate returns any row.

## Result

At 2026-09-21: 67 declared `sj:` terms (22 classes, 45 properties); 16 aligned, 51 sj-native
residue. Full table: `docs/jira/v26.9.20/streams/sj-vocab-reduction.md`.

## Not claimed

- Term-by-term equivalence is a semantic judgment, UNVERIFIED beyond the per-term arguments
  and the executed falsifier below. "No public counterpart" is a search, not a proof of absence.
- No `sj:` term is replaced or removed; generated code, gates and shapes still address the
  `sj:` IRIs.
- `a2a:` and `gi:` terms are not covered by this ADR's gate.
- Materializing the axioms before SHACL admission would violate the `sh:closed` WorkOrder
  shape (it does not list the entailed `dcterms:` properties). No engine in this pipeline
  materializes RDFS entailment.

## Falsifier

A pack gate or SHACL shape whose result differs between the `sj:` form and the mapped public
form. Executed: every pre-existing gate (on the `oxigraph` and `sparql` engines) and the SHACL
admission report return identical results with the alignment block stripped and present
(`test/ggen_igniter_semantic_jira_public_alignment_test.exs`, "ADR-011 falsifier"). Not
falsified so far; it remains the standing falsifier for any future replacement step.

## Evidence

`priv/ggen/semantic-jira-pack/ontology.ttl` (block `sj-public-alignment`),
`priv/ggen/semantic-jira-pack/gates/047_public_vocab_alignment.rq`,
`lib/ggen_igniter/semantic_jira/pack_health.ex`,
`test/ggen_igniter_semantic_jira_public_alignment_test.exs`.
