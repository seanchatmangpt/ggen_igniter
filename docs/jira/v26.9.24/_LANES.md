# SJ-002 fan-out — lanes, runbook, resolutions (2026-09-24)

Branch `feat/sjira-origin-authority` (base: main@292e40a + release-prep commit 390e363).
Ten lanes, one canonical checkout, disjoint file ownership. Wave 1: 10 Explore agents
produced exact edit plans (2026-09-24). Wave 2: 10 implementation agents apply them
under the resolutions below. Coordinator owns every git transition, all placeholder
digest substitution, and the verify ladder.

## Lanes (file ownership — exclusive)

| Lane | Owned files |
|---|---|
| L1 | priv/ggen/semantic-jira-pack/ontology.ttl |
| L2 | priv/ggen/semantic-jira-pack/shapes/work-order.shacl.ttl, shapes/proposition.shacl.ttl |
| L3 | lib/ggen_igniter/semantic_jira/authority.ex (new), lib/ggen_igniter/semantic_jira.ex |
| L4 | lib/ggen_igniter/semantic_jira/bootstrap.ex, bootstrap/**, priv/ggen/semantic-jira-pack/bootstrap/work_orders.rq, test/ggen_igniter_semantic_jira_bootstrap_test.exs, test/ggen_igniter_semantic_jira_goal_checkpoint_test.exs, test/fixtures/semantic-jira-bootstrap/goal.ttl, test/fixtures/semantic-jira-goal-checkpoint/goal.ttl |
| L5 | lib/ggen_igniter/semantic_jira/observation.ex, lib/ggen_igniter/semantic_jira/cli.ex, lib/mix/tasks/semantic_jira.observe.ex, test/ggen_igniter_semantic_jira_observe_court_map_test.exs |
| L6 | lib/ggen_igniter/semantic_jira/prose.ex, lib/mix/tasks/semantic_jira.observe_prose.ex (new), lib/mix/tasks/semantic_jira.compile_prose.ex (delete), priv/ggen/semantic-jira-pack/prose/delta.construct.rq (delete), test/fixtures/semantic-jira-prose/README.md |
| L7 | test/ggen_igniter_semantic_jira_prose_test.exs, test/fixtures/semantic-jira-prose/{candidates.ttl,prose.md,extract.json} (no edits planned) |
| L8 | test/ggen_igniter_semantic_jira_shacl_test.exs, test/ggen_igniter_semantic_jira_authority_test.exs (new) |
| L9 | test/ggen_igniter_semantic_{work_order→semantic_work_order,event_sourcing_kernel,reconciler,descriptor,cli,reconcile_task,kernel_differential,autonomics_crown,git_ground_truth,pack}_test.exs, test/fixtures/semantic_jira/**, test/fixtures/kernel_differential/v26.9.22/orders.json |
| L10 | docs/architecture/adr/ADR-012-*.md (new), priv/ggen/adr-index-pack/ontology.ttl + docs/architecture/adr/README.md (regenerated), docs/reference/cli/index.md, CHANGELOG.md, mix.exs, HANDWRITTEN.md, priv/ggen/semantic-jira-pack/VOCABULARY.md |
| C (coordinator) | CLAUDE.md, docs/jira/v26.9.24/**, git transitions, digest substitution, verify ladder, semantic_work_order.ex (verified no-change-needed), test/ggen_igniter_admission_atomicity_test.exs (verified no-change-needed), docs/reference/cli/{doctor,packs,sync}.md (no change needed) |

## Resolutions (binding over any lane plan)

R1. `origin_authority` → `@required` + `@definition_fields` + `@semantic_fields`.
    `origin_observation` → `@semantic_fields` only (optional everywhere else).
    Every definition/work-order digest moves once; accepted.
R2. SHACL originAuthority is GLOBAL minCount 1 (all WorkOrders; L1 backfills all 33).
    kernel_differential orders.json gains origin_authority (L9).
R3. `sj:ProseObservation` is a STANDALONE class — NO `rdfs:subClassOf sj:Proposition`
    (the hand-rolled Shacl's targetClass follows subClassOf*; the subclass link would
    drag observations under the closed PropositionShape). `sj:PropositionShape` drops
    `sh:targetSubjectsOf sj:admissionDigest` (objectives now carry digests → closed
    shape catastrophe) and targets `sh:targetClass sj:Proposition`. New
    `sj:AdmissionDigestShape` (targetSubjectsOf admissionDigest, sha256 lexical law)
    covers every digest carrier. Anti-prose law: FILTER(?cls = sj:Proposition
    || ?cls = sj:ProseObservation).
R4. proposition.shacl.ttl: `sj:authorityClaim` minCount 1 + maxCount 1 + hasValue
    "NONE"; prose pipeline stamps (UNKNOWN + NONE) BEFORE the propositions SHACL
    court (pipeline order: inputs → root → provenance admission → stamp → court →
    domain rules → write).
R5. Authority API (canonical): `admission_digest(graph, iri)` (IRI or string);
    `admit(graph, opts \\ [])` → `{:ok, stamped_graph, report} | {:error,
    {:refused_authority_admission, atom}}` (stamps/replaces digests, no SHACL inside —
    callers court first); `verify_origin(candidate, canonical, order_iri)` →
    `:ok | {:error, {:refused_origin, :order_absent | :origin_authority_missing |
    {:ambiguous_origin_authority, iris} | {:authority_not_admitted, iri} |
    {:authority_digest_mismatch, iri} | {:authority_type_mismatch, iri}}}`.
R6. Prose task stdout (pinned): `OBSERVED: 9 candidate propositions (7 required,
    2 not required)` / `KINDS: Postcondition=3 …` / `propositions.ttl sha256:…` /
    `WROTE: <out-dir>/propositions.ttl` / `CHECK: <out-dir>/propositions.ttl
    recomputes byte-identically` / `GOAL ADMITTED: <goal> (N GoalCheckpoints,
    M authorities stamped)`. Prose summary keeps admitted/required/not_required/
    required_by + source_document/observed/by_kind/admission_context/
    propositions_sha256; orders/witnessed/delta keys die.
R7. `Prose.admit_goal/1` ok-summary gains `:stamped` (map iri-string → digest) and
    `:stamped_ttl` (stamped graph Turtle); stamping REPLACES any pre-existing
    sj:admissionDigest (placeholder-proof, idempotent).
R8. Goal-checkpoint mutation-table row for originAuthority expects violation shape
    `work_order_shape`, constraint `:min_count`, path `sj:originAuthority`.
R9. `test/ggen_igniter_semantic_jira_pack_test.exs` → L9 (factory twin + refusal pins).
R10. Shape list in shacl_test: 19 → 21 (work_order_origin_shape + admission_digest_shape).
R11. L10 also lands the adr-index-pack individual + regenerates docs/architecture/adr/README.md.
R12. Integration (coordinator): substitute computed digests for every
     "sha256:PENDING-SJ-002" (ontology objectives ×3, bootstrap fixture root t:GC-T,
     goal-checkpoint fixture root sj:gc-fixture-root) via Authority.admission_digest
     over the final graphs, then verify ladder.

## History

- 2026-09-24 | OPEN | branch feat/sjira-origin-authority@390e363 | release-prep committed | wave 1 (10 Explore lane plans) complete; resolutions fixed | wave 2 dispatch next

## Receipt (2026-09-24, SJ-002 complete on branch, unmerged)

- base `main@292e40a` → branch head with commits 390e363 (release-prep, verbatim), 4988ac6 (pack facts), 89f3e5a (kernel), fcb0c95 (edges), dc27242 (prose surgery, BREAKING task rename), 9fed968 (falsifiers+fixtures), 9fb6a3b (docs/ledger/version), 4d3a334 + follow-ups (protocol/gitignore/doc repairs, 9c817d8).
- Waves: 10 Explore plan lanes → 10 implementation lanes (zero file collisions, per-lane MIX_BUILD_ROOT) → 10 Explore auditors (9 PASS; L10 FAIL → 3 factual doc repairs) → 10 adversarial default-agent courts.
- Verify ladder (all exit 0): shacl+authority 38/38; prose+observe 33/33; bootstrap+goal_checkpoint+kernel family 129/129 after 33→34/35 calibrations; pack+differential 68/68; full suite 1391 tests (1 failure = topology-guard commit-ordering artifact, green post-commit); doctor all ✔ incl. check 19 (projection.md.eex origin column was the caught hole).
- Falsifiers attempted: forged-digest end-to-end (A1: kernel presence-only residue recorded — layered defense, no single-path admission), bootstrap cold determinism (A2), descriptor origin-in-definition + authority NONE (A3), observe manufacture-proof incl. hostile candidates (A4), ticket byte-replay 34/34 IDENTICAL (A5), per-law SHACL isolation (A6: benign E3a co-fire recorded), admission atomicity (A7), docs-vs-code (A8: 2 repairs), cross-pack blast radius 14/14 packs exit 0 (A9), restart-stable digests + semantic_diff coverage (A10).
- Standing: SJ-002 fabric ALIVE on this branch (graph, shapes, kernel, edges, falsifiers); standing stays UNKNOWN→receipt-pending per promotionRule — no promotion claimed without an exact-head court receipt.
- Operator did NOT write: any line of this change. Every byte was manufactured through the lane protocol; the operator's inputs were the review corrections and the fan-out orders.
