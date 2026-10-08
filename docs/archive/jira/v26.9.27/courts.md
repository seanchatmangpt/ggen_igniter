# v26.9.27 courts preservation list (epoch-007)

Law: tests are the judge, not the candidate. `Test_t(A_26.10.1)` — a court written before the implementation it judges — is an independent historical falsifier. Carried courts run against the new projection byte-identical; a carried court that fails is evidence against the projection, never a reason to edit the court. Classification below covers all 176 `test/*.exs` files by the families they belong to; per-file spot list for the boundary-relevant families, family rule for the rest.

| family (test files) | count | verdict | reason |
|---|---:|---|---|
| `ggen_igniter_epoch_{freshness,admission}_test.exs` | 2 | CARRY | judges the epoch law itself; written against the contract (Test_t for any future epoch machinery) |
| `ggen_igniter_{agent_guard,topology}_test.exs` | 2 | CARRY | behavioral guards over real subprocesses/repo topology; independent of implementation internals |
| `ggen_igniter_semantic_jira_*` (pack, kernel, cli, descriptor, observe_court_map, git_ground_truth, prose, goal_checkpoint, event_sourcing, reconcile_task, …) | ~40 | CARRY | Chicago-style: real graph, real SHACL, real subprocess mix, printed verdicts — judges admission behavior, not module shape |
| `mix_semantic_jira_admit_candidates_test.exs` | 1 | CARRY | printed-verdict contract of the admission CLI (epoch gate's no-regression witness) |
| `ggen_igniter_ash_*` alignment/pack/coverage families + `ggen_igniter_agent_*` | ~12 | CARRY | judge the ontology→manufacture→projection path against upstream Ash generators; the qualified A–L ladder is the reference |
| receipt/manifest/artifact-identity/digest/frontmatter families (`ggen_igniter_{receipt,manifest,artifact_identity,digest,frontmatter,…}_test.exs`) | ~25 | CARRY with caveat | judge attribution behavior (the receipts-admit mechanism); re-derive only if the extraction (wave W1) changes public behavior — then the NEW court must first reproduce the old verdicts |
| actuation/actuate families (`actuate*`, `ggen_igniter_actuation*`, `admission_atomicity`) | ~10 | CARRY with caveat | behavioral ceilings; same caveat as attribution on W-extraction |
| `engine_test`, `sync*`/`verify` families, `query`/`sparql` engine A/B tests | ~15 | CARRY with caveat | pipeline behavior; ORDER-BY corruption note is a permanent tripwire |
| base-code/render fixture families (`ggen_igniter_base_*`, `render*`) | ~30 | RETIRE-with-subject | coupled to current rendered-task shapes; v26.10.1 re-manufactures the render layer — these follow their subject, replaced by the new layer's courts (which must first reproduce the invariants these pinned) |
| `ggen_igniter_{ocel,telemetry,eds,ea,discovery,stream,reactor,gall,…}` domain projections | ~35 | RETIRE-with-subject | each judges one projection family; retirement requires that family's extraction receipt + fresh manufacture + carried-court-equivalent in the new projection |
| fixture-driven integration (`e2e_case_unit`, `ash_r2rml_gate_*`, `frontier_release_plan`, `fortune5`, …) | ~4 | CARRY with caveat | acceptance over public behavior where the public behavior survives the epoch |

Rule at the boundary: RETIRE-with-subject means the file dies when its subject dies, in the same change that deletes the subject — never before (a court deleted early is an unjudged epoch), and its replacement court must reproduce the invariants this list records. There is no third category; a file whose subject cannot be named is CARRY.
