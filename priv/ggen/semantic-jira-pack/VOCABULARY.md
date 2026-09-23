# semantic-jira-pack vocabulary reduction — OSLC CM 3.0 / dcterms / PROV-O

Mission: the work/change/provenance semantics of this pack map to PUBLIC
vocabularies — OSLC CM 3.0, Dublin Core Terms (dcterms), and W3C PROV-O.
`sj:` is retained ONLY where an exact public equivalent is absent; every such
retention is residue and is documented below. SHACL
(`shapes/work-order.shacl.ttl`) remains the admission mechanism; nothing in
this document is authority-bearing.

Dispositions used in this document:

- **public-carried** — the fact is dual-asserted: once in public terms, once
  in `sj:` terms, same subject, same value. Admission (gates, SHACL) matches
  either form (dual-path), so a graph asserting a carried fact ONLY via the
  public term admits, and a legacy `sj:`-only graph admits unchanged.
- **residue** — `sj:`-only, no exact public equivalent, with the failed public
  candidates recorded (a near-miss is topology, not permission).
- **deprecated** — retired entirely. Zero this wave (conservative: carried +
  residue over retirement). Candidates are flagged in the residue notes.

<!-- machine-checkable sections: the "Carried (dual-asserted)" and
     "Residue (sj:-only)" tables below are compared against the canonical
     graph by test/ggen_igniter_semantic_jira_vocabulary_test.exs. -->

## Authority citations

- **OSLC CM 3.0** (OASIS, Committee Specification 01):
  - Part 2 Vocabulary — `https://docs.oasis-open-projects.org/oslc-op/cm/v3.0/change-mgt-vocab.html`
    (class `oslc_cm:ChangeRequest`; state vocabulary `oslc_cm:State` with
    individuals Closed/Inprogress/Fixed/Approved/Reviewed/Verified).
  - Part 3 Constraints — `https://docs.oasis-open-projects.org/oslc-op/cm/v3.0/change-mgt-shapes.html`
    §2.1 ChangeRequest shape: `dcterms:identifier` exactly-one, `dcterms:title`
    exactly-one, `dcterms:description` zero-or-one, `dcterms:creator`
    zero-or-many, `dcterms:created` zero-or-one (read-only),
    `oslc:serviceProvider` zero-or-many, `rdf:type` zero-or-many.
  - Part 1 Specification §2.9: `oslc_cm:status` is deprecated;
    `oslc_cm:state` + the state predicates (`oslc_cm:closed`,
    `oslc_cm:inProgress`, `oslc_cm:fixed`, `oslc_cm:approved`,
    `oslc_cm:reviewed`, `oslc_cm:verified`) are preferred.
  - Namespace: `http://open-services.net/ns/cm#` (`oslc_cm:`).
- **dcterms** — DCMI Metadata Terms, `https://www.dublincore.org/specifications/dublin-core/dcmi-terms/`.
  Namespace `http://purl.org/dc/terms/` (`dcterms:`).
- **PROV-O** — W3C Recommendation `https://www.w3.org/TR/prov-o/` (2013-04-30).
  Namespace `http://www.w3.org/ns/prov#` (`prov:`). Key slots used:
  `prov:Activity`, `prov:Entity`, `prov:Agent`, `prov:SoftwareAgent`
  (subclass of `prov:Agent`), `prov:used` (Activity → Entity),
  `prov:wasGeneratedBy` (Entity → Activity), `prov:wasAssociatedWith`
  (Activity → Agent), `prov:atTime` (Activity, xsd:dateTime).
- **SHACL** — W3C Recommendation `https://www.w3.org/TR/shacl/`. **SHACL 1.2
  Rules (W3C Working Draft) is NOT authority-bearing for this pack**: the
  admission court executes SHACL-core plus SELECT-only `sh:sparql`
  constraints as fixed by the SHACL 1.0 Recommendation surface, fails closed
  on constructs outside its supported surface, and borrows nothing (no
  SHACL Rules, no `sh:rule`, no inference) from the 1.2 Working Draft. A
  Working Draft confers no admission authority; only the executed shapes file
  does.

## Dual-typing law

A carried fact is asserted in BOTH vocabularies on the SAME subject with the
SAME value:

- every work order is `a sj:WorkOrder, oslc_cm:ChangeRequest`;
- every standing transition is `a sj:StandingTransition, prov:Activity` with
  `prov:used` mirroring `sj:transitionEvidence`;
- every receipt is `a sj:Receipt, prov:Entity`.

Consequences, all enforced:

1. **Dual-path admission.** Gates and SHACL target/accept either form.
   - Work-order identity: `{ a sj:WorkOrder } UNION { a oslc_cm:ChangeRequest }`.
   - Transition identity: `a sj:StandingTransition` OR carrying the residue
     anchor `sj:transitionId` (see below).
   - Receipt identity: `a sj:Receipt` OR `a prov:Entity`.
2. **Carried facts travel together.** A transition that carries `prov:used`
   must point at a `prov:Entity`-typed receipt; a receipt that carries
   `prov:wasGeneratedBy` must point at a `prov:Activity`. Carrying the public
   relation while refusing the public typing on the target is a SHACL
   violation.
3. **The residue anchor.** `sj:transitionId` stays on every transition in
   every lawful graph (it has no public equivalent); the transition shape
   targets `sh:targetClass sj:StandingTransition` and
   `sh:targetSubjectsOf sj:transitionId`, so the transition law (progression,
   immutability, chain anchoring) applies in legacy, dual, and public-only
   graphs alike. Targeting `prov:Activity` instead would over-target the
   provenance-only Activity nodes (fabric/worker runs), which carry no
   transition fields — refused by design, not pruned silently.
4. **Digest stability.** The immutable definition digest is BLIND to public
   dual-assertions. Kernel law: `GgenIgniter.SemanticJira @definition_fields`
   is a closed take (`Map.take/2`) — a field not in the list cannot enter the
   hash, so `rdf:type oslc_cm:ChangeRequest`, `prov:used`,
   `prov:wasAssociatedWith`, `prov:wasGeneratedBy`, and every other public
   assertion are excluded by construction. Graph law: the graph→kernel
   extraction (`GgenIgniter.Crown.extract_work_orders/1`) reads only the
   enumerated `sj:`/`dcterms:` definition predicates. Therefore adding a
   public triple to a work order never moves its definition digest; changing
   a residue/identity fact (e.g. `dcterms:title`, `sj:promotionRule`) moves
   it exactly as `@definition_fields` dictates. Proven both directions by
   `test/ggen_igniter_semantic_jira_vocabulary_test.exs`.
5. **No fabrication.** A public term is carried only when a persisted value
   exists. `oslc:serviceProvider` (ChangeRequest, zero-or-many) has no
   persisted service-provider identity in this pack — asserting a placeholder
   IRI would fabricate, so it is deferred, not pruned. `prov:atTime` requires
   a persisted timestamp; the kernel's `standing_transition_event` carries no
   timestamp field today (event order is the time), so none is asserted; the
   day the event grows a persisted timestamp, `prov:atTime` is carried from
   it — never from the wall clock of a renderer.

## Carried (dual-asserted)

| sj: term | disposition | public term | authority + note |
|---|---|---|---|
| `a sj:WorkOrder` | public-carried | `a oslc_cm:ChangeRequest` | OSLC CM 3.0 Part 2 Vocabulary, class ChangeRequest; Part 3 §2.1 allows `rdf:type` zero-or-many (dual typing is the spec-shaped use) |
| `a sj:StandingTransition` | public-carried | `a prov:Activity` | PROV-O §2.1 Activity: "occurs over a period of time and acts upon or with entities"; an append-only standing event is exactly a provenance activity |
| `a sj:Receipt` | public-carried | `a prov:Entity` | PROV-O §2.1 Entity |
| `sj:transitionEvidence` | public-carried | `prov:used` | PROV-O `prov:used`, domain Activity, range Entity — same subject (the transition), same value (the receipt) |
| (no sj: counterpart) | public-carried (additive) | `prov:wasAssociatedWith` | PROV-O, Activity → Agent: the reconciler `prov:SoftwareAgent` associated with the standing-transition activity. The Activity→Agent slot is the lawful rendering of "the reconciler produced this event" (`prov:wasGeneratedBy` runs Entity→Activity and cannot legally point at an Agent) |
| (no sj: counterpart) | public-carried (additive) | `prov:wasGeneratedBy` | PROV-O, Entity → Activity: each receipt is generated by the fabric verification run (a `prov:Activity`) that produced it; that run `prov:wasAssociatedWith` the worker `prov:SoftwareAgent` |
| `dcterms:identifier` / `dcterms:title` / `dcterms:description` | already public (native dcterms; kept) | same | OSLC CM 3.0 Part 3 §2.1 ChangeRequest shape constrains exactly these; the pack carried them before this reduction — the change requests were already OSLC-shaped below the `sj:` typing |
| `rdfs:label` on receipts/transitions | public-carried (additive) | `dcterms:title` | DCMI Terms; `dcterms:title` mirrors the persisted label value on receipt and transition rows so the public projection is self-describing. Both are asserted (dual), neither is fabricated |

Residue count below is measured against the canonical graph by the
vocabulary test: every `sj:` predicate the canonical graph uses, minus the
carried set above, must appear in the residue table (and vice versa).

## Residue (sj:-only)

Failed-edge law: each row records the nearest public candidates that were
considered and WHY they are not exact. `failed(edge) ≠ failed(G)`; a future
wave may carry an edge where the vocabulary or a persisted value arrives.

| sj: term | why no exact public equivalent (failed public candidates) |
|---|---|
| `sj:standing` | The DfCM standing ladder (UNKNOWN/PARTIAL_ALIVE/ALIVE/BLOCKED/BUILD_BROKEN/UNSUPPORTED/REFUSED(...)) is an evidence-and-receipt standing, not a change-request lifecycle. OSLC CM 3.0 `oslc_cm:state` individuals (Closed/Inprogress/Fixed/Approved/Reviewed/Verified) and the boolean state predicates (`oslc_cm:closed`, `oslc_cm:approved`, `oslc_cm:verified`, ...) assert lifecycle facts we cannot witness; `oslc_cm:status` is deprecated by CM 3.0 Part 1 §2.9; `dcterms:type` is a genre/resource-class term, not a state. Asserting `oslc_cm:verified` for ALIVE would fabricate a lifecycle claim. Failed edges: oslc_cm:state, oslc_cm:verified, dcterms:type. |
| `sj:subject` | The exact execution subject identity. `dcterms:subject` is topical keywords ("subject of the resource"), not an executable-subject binding. Failed edge: dcterms:subject. |
| `sj:repository` / `sj:baseSha` / `sj:candidateSha` / `sj:subjectSha` / `sj:finalHead` | Repository/commit identity has no OSLC CM 3.0 or PROV-O property. `oslc_cm:tracksChangeSet` links to an `oslc_config:ChangeSet` resource (outside the authorized set and a link, not the base identity); `dcterms:relation`/`rdfs:seeAlso` carry no identity discipline. sha256/40-hex identities are DfCM exact-head law. Failed edges: oslc_cm:tracksChangeSet, dcterms:relation, rdfs:seeAlso. |
| `sj:evidenceCeiling` / `sj:authorityCeiling` / `sj:authorityRequirement` / `sj:authority` / `sj:authorityClaim` / `sj:lease` / `sj:worker` | Authority/ceiling vocabulary is DfCM 権 law; OSLC CM 3.0 has no authorization ceiling concept; PROV-O agents carry no ceiling. |
| `sj:promotionRule` / `sj:replayIdentity` / `sj:requiresGitGroundTruth` / `sj:pathScope` / `sj:falsifier` | Promotion/replay/falsifier obligations are DfCM 偽/証 law; no public equivalent (OSLC CRs have no promotion rule; PROV has no falsifier). |
| `sj:requiresCourt` / `sj:requiresEvidence` / `sj:requiresReceiptClass` / `sj:receiptClass` / `sj:receipt` / `sj:nextAction` / `sj:nextCheckpoint` | Courts, evidence requirements, receipt classes, and the required action/checkpoint ladder are DfCM 証 law. `prov:wasInfluencedBy` was considered for `sj:receipt` and rejected: it is an untyped, undisciplined link (any-to-any), whereas the admission law requires exactly one typed receipt. `prov:hadRole`/`prov:qualifiedAssociation` describe agent roles, not evidence requirements. Failed edges: prov:wasInfluencedBy, prov:hadRole. |
| `sj:acceptance` | Acceptance criteria are neither OSLC requirements nor PROV entities in this graph. The natural OSLC carry (`oslc_cm:tracksRequirement` onto `oslc_rm:Requirement`-typed criteria) requires dual-typing acceptance criteria into the OSLC RM vocabulary — outside this wave's authorized set (OSLC CM 3.0, dcterms, PROV-O). Recorded as the next failed edge to revisit, not pruned. Failed edge: oslc_cm:tracksRequirement (blocked on oslc_rm authorization). |
| `sj:falsifier`'s class `sj:Falsifier`, `sj:Court`, `sj:EvidenceRequirement`, `sj:AcceptanceCriterion`, `sj:Action`, `sj:Checkpoint`, `sj:Projection`, `sj:ProjectionSpec`, `sj:Subject`, `sj:RepositorySubject`, `sj:DependencyEdge`, `sj:LeaseRequest`, `sj:PreparedAuthorityReceipt`, `sj:Actuation`, `sj:MachineExperience`, `sj:ProcessFinding`, `sj:RepairLineage`, `sj:Refusal`, `sj:Prediction` | DfCM-specific classes. Nearest candidates rejected: `prov:Plan` for `sj:Action` (a Plan is an Entity consulted by an activity, not a required next action); `oslc_cm:relatedChangeRequest` for `sj:DependencyEdge`/`sj:dependsOn` (untyped, symmetric, "no specific meaning" per the vocabulary — the pack's edges are typed and directional); `prov:Plan` again for ProjectionSpec (a deterministic manufacture spec is not a plan entity). `sj:Projection` (legacy, used only by SJ-001) vs `sj:ProjectionSpec` (the typed fabric) is a real duplication — flagged deprecated-candidate for a future wave, NOT retired this wave (conservative rule). |
| `sj:dependsOn` / `sj:dependencyType` / `sj:upstreamWorkOrder` / `sj:requiredStanding` / `sj:requiredReceiptDigest` | See `oslc_cm:relatedChangeRequest` failed edge above; also `dcterms:relation` (no typing). |
| `sj:projection` / `sj:projectionType` / `sj:extension` / `sj:generatorIdentity` | Deterministic projection specifications; PROV-O could model a manufactured ticket as an Entity with `prov:wasGeneratedBy` the pack, but the pack's projections are REQUIRED outputs (spec-side), not generated artifacts (receipt-side) — no exact slot. Failed edge: prov:wasGeneratedBy (spec-vs-consequence mismatch). |
| `sj:definitionDigest` / `sj:snapshotDigest` / `sj:workOrderDigest` / `sj:transitionId` | sha256 digests have no OSLC/PROV slot. `prov:quotation` was analyzed and REJECTED: it takes an Entity (a quoted take on an Entity), not a hash literal, and asserts take-down semantics, not content identity. `prov:value` (a qualified-generation placeholder Entity) would require reifying each digest as an Entity node — cost with no admission value. `sj:transitionId` additionally serves as the RESIDUE ANCHOR (dual-typing law §3): transition law keys on it, so it must remain `sj:` in every lawful graph. Failed edges: prov:quotation, prov:value. |
| `sj:fromStanding` / `sj:toStanding` / `sj:observedStanding` | The standing ladder itself is residue (see `sj:standing`), so its transition endpoints are residue with it. PROV-O has no state-machine vocabulary (PROV-PROV-N state extensions are not in scope). |
| `sj:witnessedBy` | Receipt-bound witnessing fact minted by the CROWN2 provisioning wave (W9-G5): an observation WorkOrder carries `sj:witnessedBy` the committed regression-guard test that must stay RED at the base head for the provisioning to be lawful. `prov:wasInformedBy`/`dcterms:references` were considered and rejected: the link is a typed witnessing obligation on an exact test artifact, not an influence or bibliographic reference. Failed edges: prov:wasInformedBy, dcterms:references. |
| `sj:concurrencyKey` / `sj:active` / `sj:exclusive` / `sj:candidateOnly` / `sj:normativeMutation` / `sj:transitionWorkOrder` | Lease fencing and event binding are DfCM 並/記 law. `sj:transitionWorkOrder`'s nearest slot, PROV-O `prov:wasInformedBy` (Activity→Activity), would assert the work order is itself an Activity — a type confusion the admission court must refuse. Failed edge: prov:wasInformedBy. |
| the `sj:EvidenceRequirement` individuals (`sj:source-evidence`, `sj:receipt-evidence`, `sj:replay-evidence`, and siblings) | Typed DfCM evidence individuals; no OSLC/PROV individual vocabulary for evidence classes at this granularity. |

## prov: nodes minted by this pack (public additions)

| node | type | role |
|---|---|---|
| `sj:reconciler-agent` | `prov:SoftwareAgent` | The graph reconciler that manufactures and appends standing-transition events (`prov:wasAssociatedWith` from each transition Activity) |
| `sj:fabric-worker-agent` | `prov:SoftwareAgent` | The fabric/worker that executed the verification producing a receipt |
| `sj:fabric-run-crown-001` | `prov:Activity` | The fabric verification run that generated `sj:receipt-crown-001` (`prov:wasGeneratedBy` source), associated with `sj:fabric-worker-agent` |

`prov:SoftwareAgent rdfs:subClassOf prov:Agent` (a true public axiom, PROV-O
§2.1.2) is asserted in the ontology so `sh:class prov:Agent` resolves
SoftwareAgent-typed agents under the SHACL-core `rdfs:subClassOf*` rule.

## Open carries (blocked, never silently pruned)

- `oslc:serviceProvider` — permitted zero-or-many by CM 3.0 Part 3 §2.1; no
  persisted service-provider identity exists in this pack. Blocked on a real
  service-provider resource, not on vocabulary work.
- `prov:atTime` — blocked on a persisted timestamp in the kernel event
  (`standing_transition_event` has none; log order is time). Never asserted
  from a renderer's wall clock.
- `oslc_cm:tracksRequirement` — blocked on dual-typing acceptance criteria as
  `oslc_rm:Requirement` (OSLC RM outside this wave's authorized set).
- `dcterms:creator` / `dcterms:created` on work orders — CM 3.0 Part 3
  permits them; the pack has persisted generator identity only at the
  ProjectionSpec level, not per work order. Blocked on persisted per-row
  provenance, which the reconciler may write in a future wave.
