# Stream sj-vocab-reduction: ADR-011 additive alignment of sj: to public vocabularies

Version: v26.9.20. Branch `errc/sj-vocab-reduction`, base
`dcebc422978498fefff90854a475b1001804f17a`. Implements the additive phase of
`docs/architecture/adr/ADR-011-reduce-sj-toward-public-vocabularies.md`: every declared
`sj:` class and property in `priv/ggen/semantic-jira-pack/ontology.ttl` is either aligned to a
public term (oslc_cm / dcterms / PROV-O / SKOS) or declared sj-native residue with a reason,
enforced by a new anti-join gate and by `PackHealth`. No `sj:` term is renamed or removed.

## Status rows for the integrator

Consolidate into `docs/status.md` (this stream does not edit it):

| Capability | Status | Evidence |
|---|---|---|
| Reduce `sj:` toward oslc_cm/dcterms/PROV-O/SHACL (ADR-011), additive phase | PARTIAL_ALIVE | 16 of 67 declared sj: terms aligned by additive axioms, 51 declared sj-native residue with reasons; gate `047_public_vocab_alignment.rq` returns 0 rows on both engines; `mix test test/ggen_igniter_semantic_jira_public_alignment_test.exs`. Not done: no sj: term replaced or removed; no SHACL shape rewritten against the public form; a2a:/gi: terms not covered. |
| Alignment gate wired into doctor's `semantic_jira_pack` check | ALIVE | `PackHealth` refuses on any `public_vocab_alignment` row, on the gate being absent/renamed, and on the gate being vacuous (six-probe self-test); forced-failure tests copy the real pack and break exactly one component; qualifier falsifier file `test/ggen_igniter_semantic_jira_public_alignment_falsifier_test.exs` 8 tests, 0 failures after hardening (was 8 failures at 7cb6845). |

ADR-011 status: PLANNED -> PARTIAL (additive alignment + gate IMPLEMENTED; term
replacement/removal NOT done, by design).

## Equivalence rule applied

ADR-011 decision item 3: adjacency is not equivalence. An axiom is asserted only when it is a
sound specialization:

- `sj:C rdfs:subClassOf P`: every instance of `sj:C` is legitimately an instance of `P`.
- `sj:p rdfs:subPropertyOf q`: every `(x sj:p v)` legitimately entails `(x q v)`, including the
  shape of the domain and value.
- A term is residue when its best public candidate fails one of those tests. The failing
  argument is stored in the ontology as `sj:residueReason` (a `skos:note` subproperty), so the
  refutation is data, not commentary.

Alignment kinds the gate accepts: `rdfs:subClassOf`, `rdfs:subPropertyOf`, `owl:equivalentClass`,
`owl:equivalentProperty`, `skos:exactMatch`, `skos:closeMatch`, targeting an IRI in the oslc_cm,
OSLC core, dcterms, PROV-O, SKOS or SHACL namespaces that the ontology registers as a public
term (`<term> rdfs:isDefinedBy <vocab>`, the closed 8-term registry inside the
`sj-public-alignment` block). Pack-local targets (`a2a:`), string-literal targets and
unregistered (invented or mistyped) targets do not count. `skos:relatedMatch` is not an
alignment. Term universe: any `sj:` term typed `rdfs:Class`, `owl:Class`, `rdfs:Datatype`,
`rdf:Property`, `owl:ObjectProperty`, `owl:DatatypeProperty` or `owl:AnnotationProperty`.
A residue reason must be a literal with at least 12 non-whitespace characters.

## Aligned terms and the argument for each

- `sj:WorkOrder rdfs:subClassOf oslc_cm:ChangeRequest`: a work order is a request to change an
  exact repository subject from a base SHA. Namespace verified against the OSLC CM vocabulary
  (`http://open-services.net/ns/cm#`, class list includes `ChangeRequest`).
- `sj:Receipt`, `sj:PreparedAuthorityReceipt`, `sj:MachineExperience`, `sj:ProcessFinding`,
  `sj:Projection`, `sj:Subject`, `sj:RepositorySubject` `rdfs:subClassOf prov:Entity`: each
  denotes a recorded or generated artifact, or an exactly identified thing. PROV-O calls such
  things entities. Low-information but sound; not aligned to a narrower class because none of
  `prov:Plan`, `prov:Bundle`, `prov:Revision` was shown equivalent.
- `sj:Actuation rdfs:subClassOf prov:Activity`: a consequential actuation occurs over time and
  acts on entities.
- `sj:subject rdfs:subPropertyOf dcterms:subject`: the value is the topic (exact subject) the
  order is about.
- `sj:requiresCourt`, `sj:requiresEvidence` `rdfs:subPropertyOf dcterms:requires`: a required
  resource supporting the order's delivery; the property names already state the relation.
- `sj:receiptClass`, `sj:projectionType` `rdfs:subPropertyOf dcterms:type`: the value names the
  genre of the receipt or projection.
- `sj:extension rdfs:subPropertyOf dcterms:format`: a file extension names the file format
  (range caveat: DCMI recommends media types; an extension is a weaker identifier).
- `sj:residueReason rdfs:subPropertyOf skos:note`: the meta-annotation introduced by this pass.

Already public and untouched: `dcterms:identifier`, `dcterms:title`, `dcterms:description`,
`dcterms:references` are used directly, and `sh:` shapes already carry the constraint layer.
`sj:WorkOrder rdfs:subClassOf a2a:Task` and `sj:Action rdfs:subClassOf a2a:Skill` predate this
pass and stay.

## Full mapping table

Generated from the graph (real oxigraph query over `ontology.ttl`), not hand-typed: edit the
ontology and regenerate, never this table. Cell text is the ontology's own `sj:residueReason`.

### Classes (22)

| sj: term | Status | Public term / axiom | Reason (residue) |
|---|---|---|---|
| `sj:AcceptanceCriterion` | residue | | Checkable predicate a WorkOrder must satisfy to be accepted; oslc_rm:Requirement is a stated need, not an acceptance predicate. No oslc_cm/dcterms/PROV-O class found. |
| `sj:Action` | residue | | Admitted next step already specializing a2a:Skill; no oslc_cm/dcterms/PROV-O class for an admitted next action found. |
| `sj:Actuation` | aligned | `rdfs:subClassOf` `prov:Activity` | |
| `sj:Checkpoint` | residue | | Admission boundary that closes only after a real court executes; oslc_cm:State (workflow lifecycle value) and prov:Plan (steps) are adjacent, neither is a closable boundary. |
| `sj:Court` | residue | | Independent verification procedure bound to an exact-head receipt; prov:Plan (intended steps) and oslc_qm:TestPlan (test scope) are adjacent, not equivalent. ADR-011 names Court irreducible. |
| `sj:DependencyEdge` | residue | | Reified typed edge carrying dependencyType, requiredStanding and upstreamWorkOrder; dcterms:requires is a plain binary property and cannot carry a required standing. |
| `sj:EvidenceRequirement` | residue | | Individuals denote evidence KINDS a court must observe, not produced evidence; a prov:Entity subclass would assert each requirement is itself evidence. The ADR-011 prov hypothesis is falsified for this class. |
| `sj:Falsifier` | residue | | Observation that defeats a claim; no public class found. ADR-011 names Falsifier irreducible. |
| `sj:LeaseRequest` | residue | | Bounded runtime authority REQUEST that grants nothing; prov:Delegation records an assignment already made, so the subclass axiom would be false. |
| `sj:MachineExperience` | aligned | `rdfs:subClassOf` `prov:Entity` | |
| `sj:Prediction` | residue | | Candidate-only prediction with observed standing UNKNOWN; no oslc_cm/dcterms/PROV-O class for a forecast found. |
| `sj:PreparedAuthorityReceipt` | aligned | `rdfs:subClassOf` `prov:Entity` | |
| `sj:ProcessFinding` | aligned | `rdfs:subClassOf` `prov:Entity` | |
| `sj:Projection` | aligned | `rdfs:subClassOf` `prov:Entity` | |
| `sj:ProjectionSpec` | residue | | Deterministic generator recipe with projectionType, extension, generatorIdentity and authorityClaim NONE; prov:Plan (intended steps) does not carry a generator identity or an authority claim. |
| `sj:Receipt` | aligned | `rdfs:subClassOf` `prov:Entity` | |
| `sj:Refusal` | residue | | Typed admission refusal record (REFUSED with a class); no oslc_cm/dcterms/PROV-O class for a typed refusal found. |
| `sj:RepairLineage` | residue | | Failure-to-repair derivation record; prov:Bundle and prov:wasDerivedFrom are candidates but no instance or consumer exists to confirm bundle semantics (UNVERIFIED). |
| `sj:RepositorySubject` | aligned | `rdfs:subClassOf` `prov:Entity` | |
| `sj:StandingTransition` | residue | | Intent to move a WorkOrder between evidence-bounded standings (from/to/observed); oslc_cm:state is workflow lifecycle, not epistemic standing. |
| `sj:Subject` | aligned | `rdfs:subClassOf` `prov:Entity` | |
| `sj:WorkOrder` | aligned | `rdfs:subClassOf` `oslc_cm:ChangeRequest` | |

### Properties (45)

| sj: term | Status | Public term / axiom | Reason (residue) |
|---|---|---|---|
| `sj:acceptance` | residue | | Links a WorkOrder to the criterion that defines acceptance; dcterms:requires is a need, not an accepted-when-satisfied relation. |
| `sj:active` | residue | | Lease-in-force flag; oslc_cm:closed and oslc_cm:inProgress are change-request workflow booleans with different domain and semantics. |
| `sj:authority` | residue | | Points at a prepared authority; prov:qualifiedDelegation has a different domain and asserts a completed delegation. |
| `sj:authorityCeiling` | residue | | Authority lattice ceiling (OBSERVE, SELECT, CONSTRUCT); oslc_cm:authorizer names an agent, not a ceiling on consequence. |
| `sj:authorityClaim` | residue | | Authority a projection claims (always NONE); no public counterpart, gate 046 and the projection shape enforce it. |
| `sj:authorityRequirement` | residue | | Authority level a work order requires (NONE, SELECT, CONSTRUCT, ...); part of the pack authority lattice, no public counterpart. |
| `sj:baseSha` | residue | | Exact git commit identity of the base; no public git-revision property in the four vocabularies (prov:wasRevisionOf links entities, it does not carry a SHA). |
| `sj:candidateOnly` | residue | | Marks a Prediction as candidate-only (never standing); no public counterpart. |
| `sj:candidateSha` | residue | | Exact git identity of the candidate head; no public git-revision property. |
| `sj:concurrencyKey` | residue | | Exclusivity scope key for lease requests; no public counterpart. |
| `sj:dependencyType` | residue | | Kind of dependency carried by a DependencyEdge; no public counterpart (DependencyEdge is residue). |
| `sj:dependsOn` | residue | | Range is a DependencyEdge node, not the required resource; dcterms:requires would assert the edge itself is required, which is false. |
| `sj:evidenceCeiling` | residue | | Highest evidence class an order may claim; no public counterpart. ADR-011 names evidence ceiling residue. |
| `sj:exclusive` | residue | | Lease exclusivity flag; no public counterpart. |
| `sj:extension` | aligned | `rdfs:subPropertyOf` `dcterms:format` | |
| `sj:falsifier` | residue | | Links a WorkOrder to the observation that would defeat its claim; no public counterpart (class Falsifier is residue). |
| `sj:fromStanding` | residue | | Source standing of a StandingTransition; standing vocabulary is residue (a2a:fromStanding is a separate a2a: term). |
| `sj:generatorIdentity` | residue | | Literal generator identity string; prov:wasGeneratedBy and prov:wasAttributedTo need resource values, and minting agent nodes is a rename-class change out of scope. |
| `sj:lease` | residue | | Points at a bounded runtime lease request; no public counterpart (LeaseRequest is residue). |
| `sj:nextAction` | residue | | Links a WorkOrder to its admitted next Action; no oslc_cm/dcterms/PROV-O property found. |
| `sj:nextCheckpoint` | residue | | Range includes non-WorkOrder Checkpoint individuals, so oslc_cm:relatedChangeRequest (change request to change request) would be false for those values. |
| `sj:normativeMutation` | residue | | Flag stating an observation must not mutate normative law; no public counterpart. |
| `sj:observedStanding` | residue | | Observed standing recorded on a Prediction or transition; standing vocabulary is residue. |
| `sj:pathScope` | residue | | Repository-relative path prefixes a work order may touch; dcterms:spatial and prov:atLocation denote places, not file scopes. |
| `sj:projection` | residue | | Value is a ProjectionSpec recipe, not the projected resource; dcterms:hasFormat needs the format variant itself and prov:wasDerivedFrom runs in the opposite direction. |
| `sj:projectionType` | aligned | `rdfs:subPropertyOf` `dcterms:type` | |
| `sj:promotionRule` | residue | | Normative text stating when standing may advance; dcterms:conformsTo names a standard, not a promotion rule. |
| `sj:receipt` | residue | | Order-to-receipt evidence link; PROV-O relations run entity to generator or derivation source and a receipt is neither, so prov:wasGeneratedBy and prov:wasDerivedFrom would be false. |
| `sj:receiptClass` | aligned | `rdfs:subPropertyOf` `dcterms:type` | |
| `sj:replayIdentity` | residue | | Replay identity string; a dcterms:identifier subproperty would give a WorkOrder two identifiers and violate the single-identifier shape under entailment. |
| `sj:repository` | residue | | owner/name repository slug string for the base; no oslc_cm/dcterms/PROV-O property for a source-repository slug found (dcterms:source expects a related resource, not a slug). |
| `sj:requiredReceiptDigest` | residue | | sha256 digest of the receipt a dependency requires; no public counterpart. |
| `sj:requiredStanding` | residue | | Standing an upstream order must hold for a dependency to be satisfied; standing vocabulary is residue. |
| `sj:requiresCourt` | aligned | `rdfs:subPropertyOf` `dcterms:requires` | |
| `sj:requiresEvidence` | aligned | `rdfs:subPropertyOf` `dcterms:requires` | |
| `sj:requiresGitGroundTruth` | residue | | Opt-in flag forcing a real git work-tree check of baseSha; pack-specific admission switch with no public counterpart. |
| `sj:requiresReceiptClass` | residue | | Receipt classes a WorkOrder requires; dcterms:type describes the resource itself, and this constrains a different resource (the receipt). |
| `sj:residueReason` | aligned | `rdfs:subPropertyOf` `skos:note` | |
| `sj:standing` | residue | | Evidence-bounded epistemic standing (UNKNOWN, PARTIAL_ALIVE, ALIVE, BLOCKED, ...); oslc_cm:status/oslc_cm:state are workflow lifecycle, and a closed change is not ALIVE. ADR-011 names standing residue. |
| `sj:subject` | aligned | `rdfs:subPropertyOf` `dcterms:subject` | |
| `sj:subjectSha` | residue | | Exact git identity of the subject; a dcterms:identifier subproperty would violate the single-identifier shape under entailment. |
| `sj:toStanding` | residue | | Target standing of a StandingTransition; standing vocabulary is residue. |
| `sj:upstreamWorkOrder` | residue | | Domain is the DependencyEdge, not the dependent order, so dcterms:requires would be asserted from the wrong subject; a property chain from sj:dependsOn is future work. |
| `sj:workOrderDigest` | residue | | sha256 definition digest of a WorkOrder; a dcterms:identifier subproperty would violate the single-identifier shape under entailment. |
| `sj:worker` | residue | | Runtime worker assignment; prov:wasAssociatedWith has domain prov:Activity, so a subproperty axiom would entail every WorkOrder is an Activity. |

## Gate and health registration

- `priv/ggen/semantic-jira-pack/gates/047_public_vocab_alignment.rq` follows the existing
  numbering (040 nodes, 045-046 integrity gates, 050 frontier). It anti-joins every declared
  `sj:` term against (a) an accepted alignment (IRI target, accepted namespace, registered in
  the ontology) and (b) a substantive `sj:residueReason`. Rows are violations: neither, or
  both. Line 1 carries the marker `# ggen:zero-row-gate`.
- Written with `OPTIONAL` + `FILTER(!BOUND())` (no `NOT EXISTS`, `UNION`, property paths) so it
  returns identical rows on the `oxigraph` and `sparql` engines; the pack test asserts that
  equality on every mutation. `SELECT DISTINCT` collapses a term typed with two kinds.
- `GgenIgniter.SemanticJira.PackHealth` refuses (doctor's `semantic_jira_pack` reports an error
  naming the gate and each offending term) when: (1) a required violation gate
  (`@zero_row_gates`: `public_vocab_alignment`) is absent from `gates/`, so deleting or renaming
  it is no longer a clean run; (2) any violation gate (by name or by the in-file
  `# ggen:zero-row-gate` marker) returns a row; (3) the vacuity self-test fails: six probe
  terms (bare, blank reason, one-character reason, string-literal target, `owl:Class`-typed,
  unregistered target) appended to a copy of the packaged graph must ALL come back as
  violation rows, so a gate emptied, filtered to nothing, or regressed to a bypassable form
  is refused although it returns zero rows on the real graph. The gate is intentionally not
  consumed by a projection template, so an operator `--ontology` override that adds its own
  `sj:` terms keeps manufacturing tickets.
- Existing tripwire `test/ggen_igniter_semantic_jira_pack_test.exs` "every pack gate executes
  cleanly" now expects 13 gates (was 12). Integration hazard: another stream that also adds a
  gate must reconcile this count on merge.
- Integration hazard: any merged branch that declares a NEW `sj:` class or property in
  `ontology.ttl` (for example the shapes/a2a stream) must add an alignment axiom or an
  `sj:residueReason` in the same change. Otherwise the merged tree fails the alignment gate,
  the new `PackHealth` check, and the partition test, each naming the unclassified term.

## Falsifier record (ADR-011 "Falsifier" section)

ADR-011 falsifier: a pack gate or SHACL shape whose result differs between the sj: form and the
mapped form. Executed in `ggen_igniter_semantic_jira_public_alignment_test.exs`: the alignment
block (`# BEGIN/END sj-public-alignment`) is stripped to produce the sj:-only form, then every
pre-existing gate runs on both forms on both engines and the SHACL report is compared. Results
are identical; at least 10 of the gate/engine cells are non-empty so equality is not vacuous.

Observed hazards, not claimed away:

1. Entailment vs closed shapes. `sh:closed true` on `sj:WorkOrderShape` lists no `dcterms:requires`
   or `dcterms:subject`. No engine here materializes RDFS entailment, so shapes pass. A consumer
   that materializes these axioms BEFORE SHACL admission would get closed-shape violations.
   Materialize after admission, or extend the shape (`shapes/` belongs to another stream).
2. `dcterms:identifier` subproperty axioms were rejected for `sj:replayIdentity`,
   `sj:subjectSha`, `sj:workOrderDigest`: entailment would give a WorkOrder several identifiers
   against the single-identifier shape.
3. UNVERIFIED: the alignments are judgments about semantics; a search of oslc_cm, dcterms,
   PROV-O, SKOS did not find counterparts for the residue terms, which is not proof of absence.
4. UNVERIFIED: `oslc_rm:Requirement` and `oslc_qm:TestPlan` are named in residue reasons as
   adjacent candidates from prior knowledge; their namespaces were not fetched this pass.
   The oslc_cm namespace contents were fetched and checked.
5. Engine defect observed (sparql 0.3.12): `VALUES ?kind { rdfs:Class rdf:Property }` returns
   wrong rows (unrelated individuals such as `sj:acceptance-gall-018` on the canonical graph,
   where the correct result is empty) while oxigraph returns the right ones.
   Gate 047 therefore uses a nested group instead; other gates should not use `VALUES` while the
   pack still runs under `--engine sparql`.

6. Enforcement hardening after qualification (repair pass). Qualifiers found the first gate
   bypassable and `PackHealth` fail-open: a whitespace-only or one-character reason, a string
   literal as alignment target, `owl:Class`/`owl:ObjectProperty`-typed terms, an invented term in
   an accepted namespace, and deletion or rename of the gate file all read as healthy. Each is
   now a permanent test on both engines (falsifier file plus the "gate 047 hardening" and
   PackHealth describes in the alignment test) and, for the gate-content bypasses, a runtime
   probe in `PackHealth`. Residual limits, not claimed away: the gate checks the ontology
   registers a public target, not that the public vocabulary defines it (fetching vocabularies
   is UNSUPPORTED here; the test pins the registry to a closed expected list); a 12+ character
   nonsense reason passes (a floor, not a semantic check); an author who rewrites the gate AND
   the probes AND the ontology together is out of reach of any in-repo check. The pre-existing
   alignment test `aligning to a public term clears the violation` now targets registered
   `dcterms:format` instead of unregistered `dcterms:relation`: the contract tightened.
7. Concurrency. Two qualifier agents were pointed at this one worktree (commits 2348f01,
   7cb6845 landed on top of builder head fd700f5). The falsifier file was red on purpose at
   7cb6845 and is green at the repair head; serialize qualifier runs per worktree.

## Prior art consulted

- `~/ggen-marketplace/packs/receipt-provenance-unification-pack/ontology.ttl` aligns its own
  classes with `prov:Entity`, `prov:SoftwareAgent`, `dcat:Dataset` and `skos:Concept` by
  `rdfs:subClassOf`, and `rp:` properties by `rdfs:subPropertyOf dcterms:source`. Same additive
  subclass/subproperty style adopted here.
- `~/ggen-marketplace/packs/consumer-realization-frontier-pack/` types its contract as
  `prov:Entity`. No marketplace pack maps to `oslc_cm:`; `oslc_cm:ChangeRequest` alignment is new
  capital.

## Generated vs handwritten

- Handwritten (irreducible): the alignment axioms and residue reasons. Equivalence is a semantic
  judgment; no generator in the pack can derive it. `UNSUPPORTED(generator-capability)`: there
  is no ggen template that projects an alignment axiom set from a public-ontology registry.
- Generated: the mapping table above (one-off script over the real graph, not a pack template).
- Handwritten and tested: gate query, `PackHealth` violation-gate hook, presence check and vacuity self-test probes.

## Not done

- No `sj:` term renamed, replaced or removed (ADR-011 item 4 second half).
- `a2a:` and `gi:` vocabularies are out of scope (owned by the a2a stream).
- No SHACL shape rewritten against the public form.
- A property chain `sj:dependsOn / sj:upstreamWorkOrder` to `dcterms:requires` needs a new sj:
  superproperty; deferred.

## See Also

- `docs/architecture/adr/ADR-011-reduce-sj-toward-public-vocabularies.md`
- `priv/ggen/semantic-jira-pack/gates/047_public_vocab_alignment.rq`
- `test/ggen_igniter_semantic_jira_public_alignment_test.exs`
- `lib/ggen_igniter/semantic_jira/pack_health.ex`
