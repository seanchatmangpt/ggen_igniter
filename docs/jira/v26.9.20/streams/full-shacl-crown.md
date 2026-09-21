# Stream: full-shacl-crown (ERRC Raise)

v26.9.20 stream note for the integrator. Branch `errc/full-shacl-crown`, base
`dcebc422978498fefff90854a475b1001804f17a`. Status rows below are for the
integrator to fold into `docs/status.md`; this stream does not edit
`docs/status.md`, `CHANGELOG.md` or the `mix.exs` version.

## Change

The autonomics crown test admitted candidate WorkOrders through an inline
four-constraint subset of the pack shape (identifier, repository, baseSha,
standing). It now admits them through the FULL shipped shape
`priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`.

- `lib/ggen_igniter/semantic_jira/admission.ex` (new): `Admission.admit/2`
  projects candidate WorkOrder maps (plus optional `:work_orders` context) into
  the ontology graph the shape describes and runs `Shacl.validate/2` with the
  shipped shape file. `Admission.to_graph/1` is the pure projection.
  `Admission.shapes_path/0` resolves the shape from the app priv dir.
- `lib/ggen_igniter/semantic_jira/reconciler.ex`: `reconcile/4` accepts
  `admission: :shacl` (default `:kernel`, behaviour unchanged), `work_orders:`
  and `shapes_path:`. With `:shacl` the candidate is admitted through the full
  shape after the kernel court and before `promote/3`; a violation refuses as
  `{:error, {:refused, {:refused_work_order, {:shacl_violations, violations}}}}`
  and nothing is appended. An unknown mode is
  `{:error, {:refused, {:unknown_admission_mode, mode}}}`.
- `test/ggen_igniter_semantic_jira_autonomics_crown_test.exs`: crown, negative
  cases, concurrent-writer and replay-after-kill properties now run
  `reconcile(..., admission: :shacl, work_orders: graph)`.
- `test/ggen_igniter_semantic_jira_admission_test.exs` (new): unit proofs for
  the projection and the court.

Seed fix (not a shape fix): the crown seed lacked properties the full shape
requires. It now carries `authority_ceiling`, `authority_requirement`,
`path_scope`, `required_receipt_classes`, `next_action`, `next_checkpoint`; the
receipt evidence carries the `verification` receipt class the seed now requires.
The shape file is unchanged.

## Public API compatibility

Kept: `SemanticJira.promote/3`, `definition_digest/1`, `project/2`,
`frontier_from_events/3`, `execution_package/2`, `admit_work_order/1`,
`Reconciler.reconcile/4` (default options behave as before; asserted by the
test "default reconcile (no admission option) is unchanged"), `TransitionLog`,
`Descriptor`, `Shacl`, `SemanticA2A`. No signature removed or changed.

## Falsifier

A WorkOrder that is missing a required property, that the inline subset and
the kernel both accept, must be REFUSED by the full shape. Witnessed for six
properties (`path_scope`, `authority_ceiling`, `authority_requirement`,
`required_receipt_classes`, `next_action`, `next_checkpoint`) by the
`FULL shipped shape is stricter than the retired inline subset (falsifier)`
tests: each asserts the inline subset conforms, `admit_work_order/1` admits,
`Admission.admit/1` returns a `:min_count` violation on the exact ontology
path, `reconcile/4` returns the typed refusal, and the log is empty. The old
crown seed run directly through `Admission.admit/1`:

```text
FULL SHAPE REFUSED old crown seed: min_count@nextAction; min_count@authorityRequirement;
min_count@authorityCeiling; min_count@pathScope; min_count@nextCheckpoint;
min_count@requiresReceiptClass
```

## Status rows

- Full-shape SHACL admission of candidate WorkOrders (`Admission.admit/2`): ALIVE.
  Evidence: `test/ggen_igniter_semantic_jira_admission_test.exs` and the crown
  negatives; real shape file, real `Shacl` validator.
- `Reconciler.reconcile/4` with `admission: :shacl` before `promote/3`: ALIVE.
  Evidence: crown test `crown: failing repo -> ... -> replay`; refused
  candidates never reach the log.
- Concurrent writers and replay-after-kill under full-shape admission: ALIVE.
  Evidence: crown tests `concurrent writers under full-shape admission ...` and
  `replay after kill ...`.
- WorkOrder map -> RDF projection is generated: UNSUPPORTED(generator-capability).
  Hand-written residue, see "Generated vs handwritten".
- `sh:closed` reachable from the map projection: UNSUPPORTED(generator-capability).
  The projection emits only declared predicates; closedness stays proven over
  the ontology in `test/ggen_igniter_semantic_jira_shacl_test.exs`.
- Dialyzer over the new modules: UNKNOWN. No PLT is built in this checkout; not run.

Constraint families exercised as negatives through `reconcile/4`: `sh:minCount`
(scalars and typed nodes), `sh:pattern` (authority ceiling, identifier, base
SHA), `sh:datatype` (`sj:requiresGitGroundTruth`), `sh:class`
(`sj:upstreamWorkOrder`), and `sh:sparql` (identifier uniqueness, replay
identity uniqueness, dependency resolution, ALIVE receipt integrity, ALIVE
court/receipt, authority/lease/worker binding).

## Not claimed

- The default `reconcile/4` mode is still kernel-only; production callers opt
  in with `admission: :shacl`. No production caller in `lib/` was switched.
- Cross-order constraints see only the graph the caller passes in
  `work_orders:`; there is no automatic loading of the canonical ontology as
  context.
- The `receipt` map key (typed `sj:Receipt` node) is a projection convention
  introduced here for ALIVE definitions; the kernel has no such field.

## Generated vs handwritten

Handwritten: `admission.ex` (projection), the `reconciler.ex` option branch,
both test files. UNSUPPORTED(generator-capability): no admitted ggen pack or
framework generator manufactures a kernel-map -> ontology-graph projection (the
pack gates `020_work_orders.rq`/`030_properties.rq` go the other way). The
shape file consumed is the shipped artifact and is not duplicated.

## See Also

- `docs/architecture/adr/ADR-010-event-sourced-standing.md`
- `docs/architecture/adr/ADR-011-reduce-sj-toward-public-vocabularies.md`
- `priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`
- `test/ggen_igniter_semantic_jira_shacl_test.exs`
