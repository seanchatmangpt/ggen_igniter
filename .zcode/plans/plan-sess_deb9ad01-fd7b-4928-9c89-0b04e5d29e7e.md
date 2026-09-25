# Sever prose→WorkOrder; typed *and admitted* origin authority in sJira (v26.9.24, order SJ-002)

**Law:** `WorkOrder = μ(AdmittedAuthority, …)`. Every WorkOrder carries exactly one `sj:originAuthority` resolving to an **admitted** `sj:CodeWorkAuthority` (`sj:StrategicObjective` | `sj:GoalCheckpoint`); typed-alone is refused. Prose/propositions become observation-only (`Prose ↛ WorkOrder`). The change itself is admitted as `sj:WorkOrder` `SJ-002` in the pack ontology.

**Branch:** `feat/sjira-origin-authority` off `main@292e40a`. Commit 1 = the 6 dirty release-prep files verbatim (`chore(release): v26.9.23 notes` — they document merged PR #28). Later commits exclude unrelated state.

## 1. Ontology — `priv/ggen/semantic-jira-pack/ontology.ttl`

New "Code work origin authority" section beside PVOCAB:
- `sj:CodeWorkAuthority a rdfs:Class`; `sj:StrategicObjective a rdfs:Class ; rdfs:subClassOf sj:CodeWorkAuthority`; existing `sj:GoalCheckpoint` gains `rdfs:subClassOf sj:CodeWorkAuthority`; `sj:ProseObservation a rdfs:Class ; rdfs:subClassOf sj:Proposition`; `sj:Proposition` comment extended (propositions are never code-work authority — extends PR-001).
- Properties `sj:originAuthority` (exactly 1 per WorkOrder, IRI, must resolve to an *admitted* CodeWorkAuthority) and `sj:originObservation` (optional, max 1, IRI).
- `sj:admissionDigest` (exists for Propositions) — comment widened: **admission witness for propositions AND CodeWorkAuthority individuals**; `sha256(admission-context + IRI + sorted canonical N-Triples)`, recomputable.
- `rdfs:comment` on `sj:WorkOrder`: origin must derive from admitted semantic authority, never directly from prose/chat/Markdown/unadmitted proposition.
- **Backfill 33 existing orders** (SJ-001 + GALL-001..032 — recount confirmed; not 34): each gets exactly one `sj:originAuthority` (SJ-001 → `sj:objective-semantic-jira-mvp`; GALL fabric → `sj:objective-project-manufacturer`).
- StrategicObjective individuals carry committed `sj:admissionDigest` values (computed by the new `Authority.admission_digest/2`; a test recomputes and asserts byte-equality — replay gate).
- **`SJ-002`** ("Prose never originates code work; typed≠admitted origin authority"): full SHACL tuple, `sj:originAuthority sj:objective-code-work-authority`, `sj:originObservation` = the review that found the defect; acceptance/falsifier = the gates in §8.

## 2. Shapes — `shapes/work-order.shacl.ttl` (supported surface only: OPTIONAL+BOUND, BIND, BGP, FILTER)

- `sj:WorkOrderShape`: register `sj:originAuthority` (min 1, max 1, nodeKind IRI) and optional `sj:originObservation` (max 1, IRI) — required because the shape is `sh:closed true`.
- New `sj:WorkOrderOriginShape a sh:NodeShape ; sh:targetClass sj:WorkOrder` with three `sh:sparql` rows:
  1. **Type law**: origin has `a sj:StrategicObjective` or `a sj:GoalCheckpoint` (UNION of two OPTIONALs; violation when neither bound) → `REFUSED(NON_SEMANTIC_WORK_AUTHORITY): origin is not code-work authority.`
  2. **Witness law (typed ≠ admitted)**: origin must carry `sj:admissionDigest` matching `^sha256:[0-9a-f]{64}$` → `REFUSED(NON_SEMANTIC_WORK_AUTHORITY): origin authority carries no admission witness.`
  3. **Anti-prose falsifier**: origin typed `a sj:Proposition` → refusal regardless of any other typing.
- `shapes/proposition.shacl.ttl`: admit `sj:authorityClaim` hasValue `"NONE"` (observe output stamps it).

## 3. Authority admission — new `lib/ggen_igniter/semantic_jira/authority.ex`

Mechanical admission witness, mirroring the proposition `admissionDigest` machinery:
- `admission_digest/2` — deterministic sha256 over context `"code-work-authority:v1"` + IRI + sorted canonical N-Triples of the node's description (same construction as Prose's).
- `admit/2` — validate an authority graph (StrategicObjective/GoalCheckpoint shapes) and stamp `sj:admissionDigest` on each authority; the GoalCheckpoint admission transition (`Prose.admit_goal/1` now calls it on success — validates, then stamps; still never touches WorkOrders).
- `verify_origin/3` — **canonical-resolution rule**: for a candidate WorkOrder's `originAuthority`, the authority node with byte-equal `admissionDigest` must exist in the *canonical admitted ontology graph*; a fresh node self-declared in the candidate graph is refused even when it forges a well-formed digest. Wired into `Observation.shacl/2` (the candidate-merge point) so merged-graph validation can never smuggle a rogue origin.

## 4. Kernel — `lib/ggen_igniter/semantic_jira.ex`

- `origin_authority` → `@required` (non-empty IRI string; refusal names the field) and `@definition_fields` (law-bearing origin enters the definition digest).
- **`origin_authority` and `origin_observation` → `@semantic_fields`** so `semantic_diff/2` reports authority-origin and observation-provenance changes as semantic drift. (`origin_observation` stays out of `@definition_fields`, following the optional-Friday-field precedent.)

## 5. Bootstrap graph→kernel — `bootstrap/work_orders.rq` + `bootstrap.ex`

`UNION { ?work_order sj:originAuthority ?value . BIND("origin_authority" AS ?field) }` (IRI-row handling mirrors `checkpoint_of`).

## 6. Observation edge — invariant **A**, deliberately chosen and fenced

**Choice: A — an authority-bound process observation may manufacture an executable WorkOrder.** The fences that make it lawful: (1) `Observation.candidate/3` gains required `:origin_authority` — refused without one; (2) the origin must pass `Authority.verify_origin/3` against the canonical ontology (typed ≠ admitted enforced here); (3) SHACL admission; (4) frontier selection still requires UNKNOWN standing + satisfied typed deps; (5) the module itself never selects/actuates — persistence is a separate BRCE act. Alternative B (candidate-only until a further transition) is recorded as an explicit exclusion in ADR-012. Candidate Turtle emits `sj:originAuthority <IRI>` + `sj:originObservation <finding-IRI>`; task/CLI gain `--origin-authority` (refusal when absent).

## 7. Prose edge → powerless observation

- `prose.ex`: excise all manufacture (`manufacture/4`, `construct/3`+`bind/2`, `expected_orders/3`+`delta_order?/2`, `conservation/2`, `admit_orders/2`, `order_iri/2`, `witness_graph/3`, `read_receipts/1`, `delta_kinds/0`, orders half of `write!/check/output_files`/summary). `compile/1` → `observe/1`: inputs → find_root (root.rq kept, shared with bootstrap) → byte-provenance validation → stamp `sj:candidateStanding "UNKNOWN"` + `sj:authorityClaim "NONE"` → domain refusals (`contradictions/foreign_requirements/uncovered_gates.rq` kept) → writes **only** `propositions.ttl`. Keep `names?/2` (bootstrap/receipts.ex:270), `admit_goal/1` (now the authority-admission court, §3), `proposition_iri/5`, `render_refusal/1`.
- New `lib/mix/tasks/semantic_jira.observe_prose.ex` (`Mix.Tasks.SemanticJira.ObserveProse`); delete `semantic_jira.compile_prose.ex`; drop `--receipts-dir`; keep source/candidates/goal/out-dir/pack-dir/check/admit-goal/context.
- Delete `priv/ggen/semantic-jira-pack/prose/delta.construct.rq` (the manufacture rule). Update `test/fixtures/semantic-jira-prose/README.md`.

## 8. Falsifiers — every new gate must witness a firing

- **Authority-admission falsifier (the §3 centerpiece)**: candidate graph = ontology + fresh `sj:objective-rogue a sj:StrategicObjective` + WorkOrder with `originAuthority` → rogue. (a) rogue without digest → SHACL witness-law refusal; (b) rogue with forged well-formed digest → SHACL passes but `verify_origin/3` refuses (canonical resolution). Both asserted via real `Shacl.validate` and real `Observation.candidate` — proving `typed ≠ admitted`.
- **Anti-vacuity twin**: a conforming order (origin = `sj:objective-code-work-authority` with committed digest) must be admitted — the gate refuses and admits.
- Prose test rewrite: observe emits only propositions (UNKNOWN + authorityClaim NONE, no admissionDigest), **zero `sj:WorkOrder` in any output**; renamed subprocess; drift + provenance + `--admit-goal` (now stamping) kept.
- SHACL test: shape list 19 → 20; mutations for each origin-law row.
- Kernel/event-sourcing/reconciler/descriptor/cli fixtures: `origin_authority` added; `semantic_diff` case for origin change; digests recalibrate.
- Bootstrap + goal-checkpoint fixture `goal.ttl`: orders get `originAuthority` → fixture root checkpoint; root gets its `admissionDigest` (computed by `Authority.admission_digest`, committed); extraction asserts the row.
- Pack test (real `mix ggen_igniter.sync`) green; `mix ggen_igniter.doctor` check 19 green.

## 9. Projection + docs + ledger

- `mix ggen_igniter.sync --pack semantic-jira-pack:jira --for-each work_orders` → `docs/jira/SJ-002.md` (+ deterministic regeneration of any fabric tickets the fan-out emits; commit wholesale, never hand-edit).
- `ADR-012-prose-never-originates-work-orders.md`: the law, typed≠admitted boundary, invariant A + recorded B exclusion, verification citations.
- `docs/reference/cli/index.md`: compile_prose → observe_prose. `mix.exs` → `26.9.24`; `CHANGELOG.md` `## v26.9.24`. `HANDWRITTEN.md`: prose.ex row shrinks (manufacture excised); new rows for kernel origin field + `authority.ex` with `UNSUPPORTED(generator-capability)` text; ledger delta in receipt. Pack `VOCABULARY.md` updated with the new terms.

## Verify ladder (exit codes captured for the receipt)

1. `mix test test/ggen_igniter_semantic_jira_shacl_test.exs` → 2. authority-admission falsifier suite → 3. prose/observe + observation tests → 4. kernel/bootstrap/reconciler/descriptor/cli/goal_checkpoint → 5. `ggen_igniter_semantic_jira_pack_test.exs` (real sync) → 6. full `mix test` + `mix ggen_igniter.doctor` → 7. falsifier receipts: rogue-origin graphs refused with typed messages, output preserved.

Atomic commits (ontology+shapes → authority+kernel/bootstrap/observation → prose surgery → tests → projections/docs/ledger); no merge without explicit request.