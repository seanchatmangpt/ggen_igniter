# ADR-012: Prose never originates work orders

Status: accepted (2026-09-24). Milestone v26.9.24. Order SJ-002, branch
`feat/sjira-origin-authority`.

## Context

The v26.9.23 first mile (GC-26.9.23, GC23-0/GC23-2) ended in a
prose-to-WorkOrder manufacture edge: `GgenIgniter.SemanticJira.Prose.compile/1`
admitted candidate propositions and then ran `prose/delta.construct.rq`, which
manufactured one `sj:WorkOrder` per required, unwitnessed
Postcondition/Invariant/Falsifier proposition — an executable order, minted
because a sentence in an accepted prose document required it. Authority was
conferred by text alone: nothing on the manufactured order named an admitted
work authority, and no check distinguished "prose stated it" from "a witnessed
authority admits it". The same edge let a hostile or simply wrong candidate
file turn narrative claims into executable work, and the CLI surface
(`mix semantic_jira.compile_prose`, with `--receipts-dir` feeding the witness
projection) made that manufacture the documented first-mile behavior.

## Decision (IMPLEMENTED)

1. **The law (SJ-002).** Prose never originates code work. A `sj:WorkOrder`
   must carry exactly one `sj:originAuthority` — an admitted instance of
   `sj:CodeWorkAuthority` — before it is admissible. An observation of prose
   (`sj:ProseObservation`) is a record of propositions, never a source of
   orders.
2. **`compile_prose` -> `observe_prose`.** The task is renamed
   `lib/mix/tasks/semantic_jira.observe_prose.ex` and demoted to observation
   only: it admits prose propositions (candidateStanding "UNKNOWN",
   authorityClaim "NONE") and writes zero WorkOrders. `prose/delta.construct.rq`
   is deleted from the pack and the `--receipts-dir` witness-projection flag is
   removed — the delta half of the old compiler no longer exists.
3. **Vocabulary** (`priv/ggen/semantic-jira-pack/ontology.ttl`): `sj:CodeWorkAuthority`
   is the class of admitted work authorities; `sj:StrategicObjective` and
   `sj:GoalCheckpoint` are `rdfs:subClassOf sj:CodeWorkAuthority`;
   `sj:ProseObservation` is a standalone observation class;
   `sj:originAuthority` is exactly-one per WorkOrder; `sj:originObservation`
   is optional; `sj:admissionDigest` is widened to witness authorities as well
   (for admitted propositions it remains present exactly when
   `sj:candidateStanding` is absent).
4. **SHACL** (`priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`):
   `sj:WorkOrderOriginShape` carries the type law (origin is a
   CodeWorkAuthority), the admission-witness law (the origin carries an
   admissionDigest), and the anti-prose falsifier (a ProseObservation is not a
   lawful origin), with messages of the form
   `REFUSED(NON_SEMANTIC_WORK_AUTHORITY): ...`; `sj:AdmissionDigestShape`
   constrains the digest itself.
5. **Typed ≠ admitted** (`lib/ggen_igniter/semantic_jira/authority.ex`):
   `GgenIgniter.SemanticJira.Authority` — `admission_digest/2`, `admit/2`
   (validate-and-stamp; the caller's court runs first), `verify_origin/3`.
   A type triple does not admit: `verify_origin/3` resolves the order's
   origin against the CANONICAL graph — the authority must exist there,
   typed and `sj:admissionDigest`-stamped — and any candidate restatement of
   the authority must match the canonical digest set byte-for-byte
   (`:authority_digest_mismatch`); a fresh self-declared objective has no
   canonical admission to resolve to (`:authority_not_admitted`). The
   recomputation itself is `admission_digest/2`'s, and the replay gate
   (below) recomputes every committed witness from the ontology graph.
6. **Kernel** (`lib/ggen_igniter/semantic_jira.ex`): `origin_authority`
   joins `@required` and the closed `@definition_fields` take, so an order
   without an origin is inadmissible and an origin change moves the definition
   digest by law (the one-time digest move across existing orders is absorbed
   exactly as ADR-010's receipt-invalidation law prescribes); the origin
   fields join `@semantic_fields`.
7. **Observation invariant A adopted; invariant B recorded as the exclusion.**
   Invariant A: an authority-bound observation may manufacture an executable
   WorkOrder — fenced by the required origin, `verify_origin/3`, the SHACL
   origin shapes, and the frontier's evidence rules. Invariant B (an order
   stays candidate-only until a further, separate transition) is deliberately
   NOT implemented and is recorded here as the standing exclusion — a
   decision, not drift.
8. **Bootstrap extraction** (`priv/ggen/semantic-jira-pack/bootstrap/work_orders.rq`):
   the cold bootstrap extracts `sj:originAuthority` alongside the rest of the
   order tuple, so bootstrap-built graphs carry origins from the first run.

## Consequences

- The manufacture rule is gone: `observe_prose` cannot emit a WorkOrder even
  under a hostile candidate file — the delta query it would need no longer
  exists in the pack.
- The 33 pre-existing canonical work orders are backfilled with
  `sj:originAuthority` pointing at their admitted authorities, so no
  grandfathered order bypasses the law. With SJ-002 itself the pack carries
  34 WorkOrders, 34/34 with an origin (32 `objective-project-manufacturer`,
  1 `objective-semantic-jira-mvp`, 1 `objective-code-work-authority`).
- Frontier selection enforces the law, not only admission (AC-04): an order
  is eligible only when its `origin_authority` RESOLVES in an authority
  index (`Authority.index/1` + `resolve/2`) — typed
  `sj:StrategicObjective`/`sj:GoalCheckpoint`, not also typed as prose, with
  exactly one `sj:admissionDigest` that recomputes. Unresolved origins are
  blocked `origin_not_admitted`; `Reconciler.reconcile/4` applies the same
  check before promotion, and `verify_origin/3` shares the law.
- The `origin_authority` addition to the closed `@definition_fields` take
  moves every order's definition digest once; ADR-010's law absorbs exactly
  this move (receipts made against pre-origin digests are invalidated by
  design, not by accident).
- Ledger paydown: the WorkOrder-delta half of the prose row in
  `HANDWRITTEN.md` is excised (`PAYDOWN REALIZED 2026-09-24`); the row shrinks
  to the observation-only surface.

## Not claimed

- Invariant B (candidate-only orders) is not implemented; the exclusion above
  is its entire status.
- No new LLM edge: extraction remains the only LLM step, unchanged, recorded
  via `sj:extractedBy` and never trusted.
- No new `sj:StrategicObjective` individuals are minted beyond the three the
  change carries.

## Falsifier suite

`test/ggen_igniter_semantic_jira_shacl_test.exs` executes the graph-side laws
over the real ontology and mutations: the type law, the admission-witness law,
and the anti-prose falsifier (a `sj:Proposition` origin refuses with
`REFUSED(NON_SEMANTIC_WORK_AUTHORITY)`, even a well-witnessed one), plus the
conformance hole itself pinned — a typed origin carrying a well-formed forged
digest passes the court, which is why the second layer exists.
`test/ggen_igniter_semantic_jira_authority_test.exs` executes the admission
layer: the digest laws (determinism, the `sj:admissionDigest` exclusion that
makes stamping idempotent), the replay gate (every committed objective witness
recomputes from the ontology graph), `admit/2` stamping and idempotency, the
`verify_origin/3` refusals (`:authority_not_admitted` for the self-declared
objective, `:authority_digest_mismatch` for the forged restatement), and the
centerpiece — one graph where the forged witness passes the court and
`verify_origin/3` refuses it in the same execution.
`test/ggen_igniter_semantic_jira_prose_test.exs` asserts the zero-order
guarantee: `observe_prose` over the admitted prose fixture writes only
`propositions.ttl` and manufactures zero WorkOrders.

## Evidence

`lib/ggen_igniter/semantic_jira/authority.ex`,
`lib/ggen_igniter/semantic_jira.ex` (`@required`, `@definition_fields`,
`@semantic_fields`), `lib/ggen_igniter/semantic_jira/prose.ex`,
`lib/mix/tasks/semantic_jira.observe_prose.ex`,
`priv/ggen/semantic-jira-pack/ontology.ttl`,
`priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl`,
`priv/ggen/semantic-jira-pack/bootstrap/work_orders.rq`,
`test/ggen_igniter_semantic_jira_authority_test.exs`,
`test/ggen_igniter_semantic_jira_prose_test.exs`.
