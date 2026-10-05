# Refusal Vocabulary Reference

The closed, machine-readable set of typed refusal codes emitted by `lib/`.
Source of truth: `priv/schema/refusals.schema.json` (JSON Schema 2020-12;
`$defs.code` is the enum, the top-level `refusals` array is the registry).
Runtime access: `GgenIgniter.Refusals` (`all/0`, `known?/1`, `fetch/1`,
`format/2`, `parse/1`, `count/0`, `wrapped_reasons/0`). Terms: `docs/glossary.md`.

## Text forms

Canonical: `REFUSED:<CODE> <detail>`, for example
`REFUSED:PACK_DIGEST_MISMATCH pack=p expected=e actual=a`.

`GgenIgniter.Refusals.parse/1` accepts ONLY the canonical form. The two
D-lane-era legacy emitter shapes (`REFUSED(code) subject: detail` and bare
`REFUSED_<CODE> detail`) were removed from the grammar when their emitters
migrated; both parse to `{:error, :not_a_refusal}`.

## Adding a code

Add an entry to the `refusals` array and to `$defs.code.enum` in the schema.
`test/ggen_igniter_refusals_test.exs` scans `lib/**/*.ex` for refusal-code
literals, and the `{:error, :reason}` / `{:refused, :reason}` atoms of the
listed emitter modules, and fails while any is neither an enum code nor a
declared `wrapped_reasons` entry. Every entry needs a non-null `broken_term`
and a distinct `fix_hint` (or a shared `hint_group`).

## Registry

The registry holds 136 codes (`$defs.code.enum` count cascade: 132 -> 135 —
132 pre-existing, `SOVEREIGN_LEASE_REQUIRED` + `SOVEREIGN_LEASE_INVALID` from
the Sovereign Ceiling Lease law, and `SOVEREIGN` itself as the code the
exhaustiveness detector forces for the `{:refused_sovereign, reason}` wrapper
atom — then `PM4PYTEST_BINARY_NOT_FOUND` for the pm4pytest runner's missing
external binary) derived from the schema by `GgenIgniter.Refusals.count/0`, never
hand-maintained, plus 24 wrapped reasons (unchanged). Regenerate both tables below with:

```bash
mix run -e 'IO.puts(GgenIgniter.Refusals.markdown()); IO.puts(GgenIgniter.Refusals.wrapped_markdown())' 2>/dev/null | grep '^|'
```

`broken_term` is the term of `A = mu(O*)`, `R = receipt(A)` the refusal
violates. `not_applicable` means no term is broken; the entry then carries a
`not_applicable_reason` in the schema.

| code | family | retryable | broken_term | owner | fix_hint |
|---|---|---|---|---|---|
| `ABSOLUTE_PATH_IN_STATE` | semantic_jira_input | true | R_missing_replay | `GgenIgniter.SemanticJira.Bootstrap` | State must hold repo-relative paths only. |
| `ACTION_AMBIGUOUS_TARGET` | state_machine | false | mu_on_O | `GgenIgniter.Packs.StateMachine` | Rename one action so each action name transitions to a single target state. |
| `ASH_API_ACCEPT_DRIFT` | ash_api_surface | false | mu_unlawful | `GgenIgniter.Packs.AshApi` | Reconcile the existing action's accept list with the ontology, or regenerate the resource surface. |
| `ASH_API_SURFACE` | ash_api_surface | false | mu_on_O | `GgenIgniter.Packs.AshApi` | Repair the graph facts listed by gates/000_violations.rq; a malformed surface renders nothing. |
| `AUTHORITY_ADMISSION` | typed_tuple | false | R_missing_authority | `GgenIgniter.SemanticJira.Authority` | Declare and admit exactly one typed sj:CodeWorkAuthority node (no_typed_authority_node) before authority-bearing prose or work orders are admitted. |
| `AUTHORITY_ADMISSION_REFUSED` | semantic_jira_input | false | R_missing_authority | `GgenIgniter.SemanticJira.Prose` | Provide an admitted typed authority node. |
| `AUTHORITY_DIGEST_INVALID` | authority | false | R_missing_identity | `GgenIgniter.SemanticJira.Authority` | Recompute the authority digest. |
| `AUTHORITY_DIGEST_MISMATCH` | authority | false | R_missing_identity | `GgenIgniter.SemanticJira.Authority` | Authority changed after admission; re-admit. |
| `AUTHORITY_INDEX_CONFLICT` | authority | false | R_missing_authority | `GgenIgniter.SemanticJira.Authority` | Resolve conflicting authority index entries. |
| `AUTHORITY_NOT_ADMITTED` | authority | false | mu_on_O | `GgenIgniter.SemanticJira.Authority` | Admit the authority node first. |
| `AUTHORITY_TYPE_MISMATCH` | authority | false | R_missing_authority | `GgenIgniter.SemanticJira.Authority` | Authority node has the wrong rdf:type. |
| `CANDIDATE` | typed_tuple | false | R_missing_authority | `Mix.Tasks.SemanticJira.AdmitCandidates` | Candidates enter at standing UNKNOWN, authority_requirement NONE and a non-actuating evidence_ceiling; remove literal_standing, ceiling_exceeds_construct and duplicate identity/field candidate lines. |
| `CEILING_EXCEEDED` | hand_authored | false | R_missing_authority | `Mix.Tasks.GgenIgniter.HandAuthored` | The kind's admitted count is at its ceiling; retire a row first. |
| `COMPOSITION` | typed_tuple | false | mu_on_O | `GgenIgniter.SemanticJira` | Pass a non-empty list of valid upstream subjects to composition_subject; invalid_upstream lists the offenders and requires_upstreams means none were given. |
| `CONTRADICTION` | hand_authored | false | admission_vacuous | `Mix.Tasks.GgenIgniter.HandAuthored` | A file both marked manufactured and admitted hand-authored; remove one claim. |
| `COPY_READD` | epoch_verdict | false | mu_unlawful | `GgenIgniter.EpochFreshness` | Regenerate from the ontology; a pre-epoch blob re-added verbatim is not fresh manufacture. |
| `CORRUPT_MANIFEST` | manifest_export | false | R_missing_replay | `GgenIgniter.ManifestExport` | Restore or regenerate the manifest. |
| `CORRUPT_RECEIPT` | manifest_export | false | R_missing_consequence | `GgenIgniter.ManifestExport` | Remove or regenerate the unparseable receipt. |
| `CS2_BATCH` | typed_tuple | false | mu_on_O | `GgenIgniter.SemanticJira.CS2Batch` | Fix the CS2 batch document: it must be a map with one shared subject/repository/base_sha/source_digest, unique non-empty work identities, and acyclic dependencies (see the wrapped reasons). |
| `CS2_PROJECTION` | typed_tuple | false | mu_on_O | `GgenIgniter.SemanticJira.CS2Projection` | project_batch takes an admitted CS2 batch map; fix the batch (its reason is the CS2 batch refusal) and project again. |
| `DELETE_WRITE_COLLISION` | typed_tuple | false | mu_unlawful | `GgenIgniter.Reactors.ReconcileReactor` | The plan both deletes and writes the same target; drop the stale delete or the new render output so each path has one action. |
| `DESCRIPTOR` | typed_tuple | false | mu_on_O | `GgenIgniter.SemanticJira.Descriptor` | Rebuild the descriptor from an admitted work order: fix the invalid provider option, identity_mismatch, snapshot_drift, or admit the work order (unadmitted) and retry. |
| `DO` | typed_tuple | false | R_missing_authority | `GgenIgniter.SemanticJira` | DO needs an admitted origin (a refused_origin reason means fix the authority), an available claim store (claim_store_unavailable), and a matching precondition (missing_or_mismatched_precondition); DO flows only through BRCE. |
| `DOCTRINE` | typed_tuple | false | mu_on_O | `GgenIgniter.DoctrineAdmission.Applicability` | Fix the doctrine-admission input named by the boundary in the reason (source_identity, scope_guard, replay, evidence, method, etc.): supply the exact subject or the digest/standing/authority it names. |
| `DUPLICATE_OUTPUT_PATH` | typed_tuple | false | mu_unlawful | `GgenIgniter.Reactors.ReconcileReactor` | Two templates render to one output path; give each template a distinct out-template so every path has one owner. |
| `DUPLICATE_SOURCE_PATH` | hand_authored | false | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | The path is already admitted; edit the existing row. |
| `DUPLICATE_WORK_ORDER` | semantic_jira_input | false | mu_on_O | `GgenIgniter.SemanticJira.Bootstrap` | Remove the duplicate work order. |
| `ENTERPRISE_ARCHITECTURE` | typed_tuple | false | R_missing_authority | `GgenIgniter.EnterpriseArchitecture` | Fix the architecture input the wrapped reason names: DO authority is forbidden, requested authority may not exceed the origin, SBB must be qualified, and ABB/contract digests must match. |
| `EPHEMERAL_ATTESTATION` | typed_tuple | false | R_missing_identity | `GgenIgniter.EphemeralManufacture` | Attest only an alive receipt with a post_run_hash equal to the re-hashed files and a matching graph_hash and receipt_hash; re-run the manufacture to refresh them. |
| `EPHEMERAL_PROJECTION` | typed_tuple | false | mu_on_O | `GgenIgniter.EphemeralProjection` | Supply every required option with valid digests and resolved dependencies, and follow the allowed status transitions (verify before retire). |
| `EPOCH_CHECK` | typed_tuple | false | mu_on_O | `GgenIgniter.EpochFreshness` | Run inside a git work tree, pass a base_dir that contains every judged file, and record the watermark first (mix ggen_igniter.epoch.watermark) so watermark_not_found clears. |
| `EPOCH_INVARIANT` | typed_tuple | false | mu_unlawful | `GgenIgniter.SemanticEpoch` | The epoch declaration disagrees with the invariants the epoch requires; the reason maps each key to expected and observed, so correct those keys. |
| `EPOCH_LEGACY_EDIT` | epoch_plan | false | mu_unlawful | `GgenIgniter.SemanticJira.EpochPlan` | Plan fresh manufacture, not an edit of a path present in the watermark. |
| `EPOCH_PLAN` | typed_tuple | false | mu_unlawful | `GgenIgniter.SemanticJira.EpochPlan` | An epoch order line was refused by EpochPlan.check/2; the reason is one of legacy_edit, unattributed_implementation, reuses_pre_watermark_artifact or watermark_unavailable, so fix the plan accordingly. |
| `EPOCH_PLAN_REUSES_PRE_WATERMARK_ARTIFACT` | epoch_plan | false | mu_unlawful | `GgenIgniter.SemanticJira.EpochPlan` | Name only post-watermark artifacts in the plan. |
| `EPOCH_UNATTRIBUTED_IMPLEMENTATION` | epoch_plan | false | R_missing_authority | `GgenIgniter.SemanticJira.EpochPlan` | Attribute the planned implementation path to a generator or residue admission. |
| `EPOCH_WATERMARK` | typed_tuple | false | mu_on_O | `GgenIgniter.EpochWatermark` | Run in a git work tree over a non-empty implementation set; restamp_required means a watermark already exists for the epoch and must be re-stamped deliberately. |
| `EPOCH_WATERMARK_UNAVAILABLE` | epoch_plan | true | R_missing_identity | `GgenIgniter.SemanticJira.EpochPlan` | Run mix ggen_igniter.epoch.watermark and pass --epoch-manifest. |
| `ENGINE_COMPARISON_DIVERGENT` | engine_comparison | false | mu_unlawful | `Mix.Tasks.GgenIgniter.Sync` | Engines disagreed on row-set for a named --query. Inspect the --engine-report output, fix the query or the disagreeing engine artifact, then rerun. |
| `EXTENSION_SCHEMA` | extension_schema | false | admission_vacuous | `GgenIgniter.Packs.ReceiptedExtension` | Repair the rx:Extension graph reported by gates/000_violations.rq (sections, entities, transformer order, defaults). |
| `FILE_NOT_FOUND` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | The admitted file must exist on disk; create it first. |
| `FORBIDDEN_INPUT` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Bootstrap` | Remove the forbidden input (e.g. path outside allowed roles). |
| `FOREIGN_REQUIREMENT` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Prose` | A checkpoint requires a proposition outside the root's gates; fix the graph. |
| `FOREIGN_SUBJECT` | semantic_jira_input | false | mu_unlawful | `GgenIgniter.SemanticJira.Prose` | Do not edit goal nodes past admission. |
| `GATE_CONTRACT_INVALID` | gate_verify | false | mu_on_O | `GgenIgniter.GateVerify` | Fix the gate cardinality contract: mode must be ROWS or VALUES, ROWS needs exactly one of class/predicate, VALUES needs a predicate. |
| `GATE_SCRIPT_NOT_FOUND` | hand_authored | true | R_missing_replay | `Mix.Tasks.GgenIgniter.HandAuthored` | Restore the gate script the ontology names. |
| `GENERATED_ARTIFACT_MUTATED` | epoch_verdict | false | mu_unlawful | `GgenIgniter.EpochFreshness` | Restore the generated bytes and change the ontology/template, then re-render. |
| `GENERATIONAL_RESILIENCE` | typed_tuple | false | mu_on_O | `GgenIgniter.GenerationalResilience` | Fix the resilience profile: map-shaped, two distinct generations with valid ids and digests, all required fields, and known techniques with map policies. |
| `GOAL_INCOMPLETE` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Prose` | Fill the missing sj: predicate on the root GoalCheckpoint. |
| `GOAL_ROOT` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Prose` | Provide exactly one root GoalCheckpoint. |
| `INITIAL_STATE_MISSING` | state_machine | false | mu_on_O | `GgenIgniter.Packs.StateMachine` | Declare exactly one sm:initialState naming a declared state of the machine. |
| `INPUT_INVALID` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Bootstrap` | Repair the malformed input document. |
| `INPUT_UNREADABLE` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Bootstrap` | Make the input file readable. |
| `INSTALLER_CONFIG_INVALID` | igniter_installer | false | mu_on_O | `GgenIgniter.Packs.IgniterInstaller` | Complete the ii:Config (key, value) and target only config.exs or runtime.exs. |
| `INSTALLER_DEP_INCOMPLETE` | igniter_installer | false | mu_on_O | `GgenIgniter.Packs.IgniterInstaller` | Give the ii:Dep a name, requirement, mode and order. |
| `INSTALLER_INCOMPLETE` | igniter_installer | false | mu_on_O | `GgenIgniter.Packs.IgniterInstaller` | Supply every fact the ii:Installer template needs (module, task name, deps). |
| `INVALID_EXPIRY` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | --expires must be YYYY-MM-DD. |
| `INVALID_PACKAGE` | semantic_work_order | false | mu_on_O | `GgenIgniter.SemanticWorkOrder` | The execution package is missing schema, work_order, path, source_digest, artifacts or package_digest; regenerate it with execution_package/3. |
| `LEASE_REQUEST` | typed_tuple | false | R_missing_authority | `GgenIgniter.SemanticJira` | Supply every lease field with a non-empty allowed_operations list and a scope that is a non-empty subset of the work order's path_scope (scope_expansion, invalid_scope). |
| `LEDGER_REFUSED` | semantic_jira_input | false | mu_on_O | `GgenIgniter.SemanticJira.Bootstrap` | Repair the ledger the bootstrap refused. |
| `LEGACY_EDIT` | epoch_verdict | false | mu_unlawful | `GgenIgniter.EpochFreshness` | Regenerate the file from its ontology instead of editing the pre-epoch implementation. |
| `LLM_CREDENTIAL_PRESENT` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Bootstrap` | Unset LLM credentials in the environment; bootstrap must be deterministic. |
| `MACHINE_EXPERIENCE` | typed_tuple | false | R_missing_consequence | `GgenIgniter.SemanticJira` | Machine experience needs receipted evidence: prediction_only and incomplete_receipted_evidence both mean the recorded run lacks receipt fields. |
| `MARKED_FILE` | hand_authored | false | mu_unlawful | `Mix.Tasks.GgenIgniter.HandAuthored` | A manufactured (marked) file cannot be admitted as hand-authored. |
| `MISSCOPED` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | Path must sit under a manufactured root. |
| `MISSING_ACCEPTANCE_COMMAND` | hand_authored | true | admission_vacuous | `Mix.Tasks.GgenIgniter.HandAuthored` | Supply a real --acceptance-command. |
| `MISSING_EXPIRY` | hand_authored | true | R_missing_standing | `Mix.Tasks.GgenIgniter.HandAuthored` | Kinds that require it need --expires. |
| `MISSING_FIELD` | hand_authored | true | R_missing_authority | `Mix.Tasks.GgenIgniter.HandAuthored` | Supply --principal, --reason and an admitted-at date. |
| `MISSING_MANIFEST` | manifest_export | false | R_missing_consequence | `GgenIgniter.ManifestExport` | Run a sync so .ggen_igniter/manifest.json exists. |
| `MISSING_SUNSET_PLAN` | hand_authored | true | R_missing_standing | `Mix.Tasks.GgenIgniter.HandAuthored` | Kinds that require it need --sunset-plan. |
| `NO_ATTRIBUTION` | epoch_verdict | false | R_missing_authority | `GgenIgniter.EpochFreshness` | Generate the file through a receipted ggen_igniter run or add a dated HANDWRITTEN.md residue row. |
| `NO_RECEIPT` | extension_schema | false | R_missing_consequence | `GgenIgniter.Packs.ReceiptedExtension` | Declare a receipt on the resource that uses the receipted extension, so the verifier can admit it. |
| `NO_TYPED_AUTHORITY_NODE` | authority | false | R_missing_authority | `GgenIgniter.SemanticJira.Authority` | Declare an sj:CodeWorkAuthority node. |
| `ONTOLOGY_MALFORMED_SECTION` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | Repair the malformed hand-authored section of the ontology. |
| `ONTOLOGY_NOT_FOUND` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | Pass an existing --ontology path. |
| `ONTOLOGY_UNPARSEABLE` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | Fix the Turtle syntax error in the ontology. |
| `ORDER_ABSENT` | authority | false | mu_on_O | `GgenIgniter.SemanticJira.Authority` | The named order is not in the graph. |
| `ORIGIN` | typed_tuple | false | R_missing_authority | `GgenIgniter.SemanticJira` | Bind the work order to an admitted authority: declare its origin, resolve authority_index_conflict, and re-admit after authority_digest_invalid/mismatch/type_mismatch or not_admitted. |
| `ORIGIN_AUTHORITY_MISSING` | authority | false | R_missing_authority | `GgenIgniter.SemanticJira.Authority` | Work order lacks an origin authority. |
| `OUTPUT_DRIFT` | semantic_jira_input | true | R_missing_replay | `GgenIgniter.SemanticJira.Prose` | Existing output differs from recomputed bytes; regenerate. |
| `PACKAGE_DIGEST_MISMATCH` | semantic_work_order | false | R_missing_identity | `GgenIgniter.SemanticWorkOrder` | The rebuilt execution package digest differs from the recorded one; an artifact changed, so rebuild and re-record the package. |
| `PACK_DIGEST_MISMATCH` | pack_lock | false | R_missing_identity | `GgenIgniter.PackLock` | Pack bytes differ from the lock; re-lock (mix ggen_igniter.pack.lock) or restore the pack. |
| `PACK_FILE_UNREADABLE` | pack_lock | false | R_missing_identity | `GgenIgniter.PackLock` | A pack file cannot be read; fix permissions. |
| `PACK_IDENTITY_MISMATCH` | pack | false | R_missing_identity | `GgenIgniter.Pack` | Make pack.toml identity agree with the pack directory/ontology. |
| `PACK_LOCK_FAILED` | pack_lock | false | admission_vacuous | `Mix.Tasks.GgenIgniter.Sync` | An unclassified failure while checking the pack lockfile; rerun with the lockfile path and inspect the detail, then report it if it names no known lock state. |
| `PACK_LOCK_INVALID` | pack_lock | false | admission_vacuous | `GgenIgniter.PackLock` | The lockfile is unparseable or malformed; restore it from version control or regenerate deliberately with pack.lock --force-regenerate. |
| `PACK_LOCK_MISSING` | pack_lock | true | R_missing_identity | `GgenIgniter.PackLock` | Create the lockfile with mix ggen_igniter.pack.lock. |
| `PACK_MANIFEST` | typed_tuple | false | mu_on_O | `GgenIgniter.Reactors.ReconcileReactor` | The reconcile reactor refused the pack manifest; the reason carries the manifest error type and diagnostic, so fix pack.toml as it reports. |
| `PACK_MANIFEST_INVALID` | pack | false | mu_on_O | `GgenIgniter.Pack` | Fix pack.toml so it has exactly name, version, description. |
| `PACK_MANIFEST_MISSING` | pack | false | mu_on_O | `GgenIgniter.Pack` | Add pack.toml with name, version, description. |
| `PACK_ONTOLOGY_NOT_FOUND` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | Pass an existing --pack-ontology path. |
| `PACK_SYMLINK_ESCAPE` | pack_lock | false | R_missing_identity | `GgenIgniter.PackLock` | A symlink in the pack resolves outside the pack root; replace it with a regular file. |
| `PACK_VERIFY_FAILED` | verify | false | admission_vacuous | `Mix.Tasks.GgenIgniter.Verify` | A pack gate contract failed under mix ggen_igniter.verify; run it without --json-envelope to see which gate query violated its cardinality contract and fix the pack ontology or query. |
| `PATH_ESCAPES_ROOT` | typed_tuple | false | mu_unlawful | `GgenIgniter.Reactors.ReconcileReactor` | A rendered output resolves outside the project root; use a relative out-template that stays within the root. |
| `PM4PYTEST_BINARY_NOT_FOUND` | hand_authored | true | R_missing_replay | `Mix.Tasks.GgenIgniter.Pm4pytest` | Install the PM4Py CLI binary and point PM4PYTEST_BINARY at it. |
| `PRE_EPOCH_RECEIPT` | epoch_verdict | false | R_missing_standing | `GgenIgniter.EpochFreshness` | Re-run the generator after the watermark so a post-watermark alive receipt lists the file. |
| `PROJECT_MANUFACTURER` | typed_tuple | false | R_missing_identity | `GgenIgniter.Gall.ProjectManufacturer` | Build the manufacturer only from an alive receipt whose post_run_hash matches the re-hashed files; standing, post_run_hash_missing and projection_drift name the failed check. |
| `PROVENANCE_MISMATCH` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Prose` | Correct the proposition's provenance fields. |
| `REACTOR_CYCLE` | reactor_scaffold | false | mu_on_O | `GgenIgniter.Packs.ReactorScaffold` | Break the rx:dependsOn/rx:waitsFor cycle so the step graph is acyclic. |
| `REACTOR_DANGLING_EDGE` | reactor_scaffold | false | mu_on_O | `GgenIgniter.Packs.ReactorScaffold` | Point the rx:dependsOn/rx:waitsFor edge at a step declared in the same reactor. |
| `REACTOR_MALFORMED` | reactor_scaffold | false | mu_on_O | `GgenIgniter.Packs.ReactorScaffold` | Supply the facts the saga/step template requires; unbound optionals are refused, never dropped. |
| `REACTOR_UNKNOWN_STEP_KIND` | reactor_scaffold | false | mu_on_O | `GgenIgniter.Packs.ReactorScaffold` | Use a step kind the reactor-scaffold-pack ontology declares (see its rx:StepKind individuals). |
| `REPLAY_REFUSED` | typed_tuple | false | R_missing_replay | `GgenIgniter.SemanticJira` | Replay evidence is all-or-nothing: supply standing_transitions on both manifests or neither, and reconcile any identity_mismatch fields. |
| `SA2A_SEMANTIC_EVIDENCE` | typed_tuple | false | R_missing_identity | `GgenIgniter.SA2A.SemanticEvidence` | Supply a portable sa2a.semantic-evidence-envelope.v1 with an absolute exact-subject URN or https IRI, non-empty canonical fields and no authority-bearing claims; the envelope is evidence only and never grants standing. |
| `SEMANTIC_JIRA` | semantic_jira | false | mu_on_O | `GgenIgniter.SemanticJira` | Fix the work order named in the detail. |
| `SEMANTIC_JIRA_BASE_SHA_UNVERIFIED` | semantic_jira | true | R_missing_identity | `GgenIgniter.SemanticJira.GitGroundTruth` | Fetch the commit or correct baseSha. |
| `SEMANTIC_JIRA_SHACL` | semantic_jira | false | mu_on_O | `GgenIgniter.Reactors.ReconcileReactor` | Resolve the SHACL violations in the work-order graph. |
| `SHA_DRIFT` | hand_authored | true | R_missing_identity | `Mix.Tasks.GgenIgniter.HandAuthored` | Re-render, re-admit the new blob sha and rerun the gate. |
| `SHA_UNCOMPUTABLE` | hand_authored | true | R_missing_identity | `Mix.Tasks.GgenIgniter.HandAuthored` | The file could not be read for hashing; fix permissions/path. |
| `STALE_OUTPUTS` | typed_tuple | false | mu_unlawful | `GgenIgniter.Reactors.ReconcileReactor` | Previously generated outputs are no longer produced; rerun with --on-stale prune or preserve, or restore the template that produced them. |
| `STANDING_PROJECTION` | typed_tuple | false | R_missing_standing | `GgenIgniter.SemanticJira` | project_standing takes a list of admitted transition events; repair the event named in the reason so standing re-derives. |
| `STATE_DEAD_END` | state_machine | false | mu_on_O | `GgenIgniter.Packs.StateMachine` | Give the non-terminal state an outgoing sm:Transition, or mark it sm:terminal true. |
| `STATE_UNREACHABLE` | state_machine | false | mu_on_O | `GgenIgniter.Packs.StateMachine` | Add a transition into the named state from a reachable state, or remove the unreachable sm:State. |
| `SUBJECT_EXHAUSTED` | hand_authored | false | not_applicable | `Mix.Tasks.GgenIgniter.HandAuthored` | No free subject IRI after 200 attempts; pick another base. |
| `SUBJECT_PREFIX_UNDECLARED` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | Declare the subject namespace prefix in the ontology. |
| `TRANSITION` | typed_tuple | false | R_missing_standing | `GgenIgniter.SemanticJira` | Present a genuine intent: its transition_digest must re-derive (intent_digest_mismatch), its from must equal the current standing (stale_intent) and bind the work-order digest (intent_not_bound_to_work_order). |
| `TRANSITION_UNKNOWN_STATE` | state_machine | false | mu_on_O | `GgenIgniter.Packs.StateMachine` | Declare the from/to/initial state as an sm:State of the same machine, or correct the transition's state name. |
| `TARGET_PACK_MISMATCH` | semantic_work_order | false | mu_unlawful | `GgenIgniter.SemanticJira.Execute` | Execute against the pack the order names: pass the --pack-dir whose pack.toml [pack].name (or, absent a manifest, its directory basename) equals the order's sj:targetPack. |
| `TARGET_PACK_UNKNOWN` | semantic_work_order | true | R_missing_identity | `GgenIgniter.SemanticJira.TargetPack` | Create the pack at priv/ggen/<name> (cwd-relative) or pass --pack-dir with a real pack directory. |
| `UNADMITTED` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | Admit the file with mix ggen_igniter.hand_authored. |
| `UNCOVERED_GATE` | semantic_jira_input | true | mu_on_O | `GgenIgniter.SemanticJira.Prose` | Cover every gate of the root with at least one proposition. |
| `UNEXPLAINED_SIMILARITY` | epoch_verdict | false | mu_unlawful | `GgenIgniter.EpochFreshness` | Regenerate, or admit fresh residue that differs below the similarity threshold. |
| `UNKNOWN_KIND` | hand_authored | true | mu_on_O | `Mix.Tasks.GgenIgniter.HandAuthored` | --kind must name an admitted HandAuthoredKind. |
| `UNOWNED_DELETE` | typed_tuple | false | mu_unlawful | `GgenIgniter.Reactors.ReconcileReactor` | The plan deletes a path not recorded in the manifest; only delete outputs the manifest owns. |
| `UPGRADER_INCOMPLETE` | igniter_installer | false | mu_on_O | `GgenIgniter.Packs.IgniterInstaller` | Give the ii:Upgrader an installer, a version and a module. |
| `UPGRADER_STEP_INVALID` | igniter_installer | false | mu_on_O | `GgenIgniter.Packs.IgniterInstaller` | Use a known ii:Step kind and supply the facts that kind needs. |
| `UPGRADE_DOWNGRADE` | upgrade | false | mu_unlawful | `Mix.Tasks.GgenIgniter.Upgrade` | Downgrades are refused; pass a higher --to version. |
| `UPGRADE_INVALID_VERSION` | upgrade | true | mu_on_O | `Mix.Tasks.GgenIgniter.Upgrade` | Pass a valid version. |
| `USAGE` | semantic_jira_input | true | not_applicable | `GgenIgniter.SemanticJira.Bootstrap` | Fix the command-line arguments. |
| `VERIFICATION_EVIDENCE` | typed_tuple | false | R_missing_consequence | `GgenIgniter.SemanticJira` | Provide every required verification evidence field with valid values (invalid_fields) or repair the field the reason names. |
| `WORK_ORDER` | typed_tuple | false | mu_on_O | `GgenIgniter.SemanticJira` | admit_work_order takes a map with every required work-order field valid; fix the field named in the reason (expected_map means a non-map was passed). |
| `WORK_ORDER_ABSENT` | semantic_work_order | true | mu_on_O | `GgenIgniter.SemanticWorkOrder` | The execution package names a work order file that is missing on disk; restore it or rebuild the package. |
| `WORK_ORDER_DRIFT` | semantic_work_order | false | R_missing_identity | `GgenIgniter.SemanticWorkOrder` | The work order on disk no longer matches the digest recorded in the package; rebuild the execution package from the current work order. |
| `SOVEREIGN_LEASE_REQUIRED` | sovereign_lease | true | R_missing_authority | `Mix.Tasks.SemanticJira.AdmitCandidates` | Mint a SovereignLease carrying >= 2 EdDSA signatures from >= 2 distinct signers and present it in the candidate's sovereign_lease field. |
| `SOVEREIGN_LEASE_INVALID` | sovereign_lease | false | R_missing_authority | `Mix.Tasks.SemanticJira.AdmitCandidates` | Re-sign the canonical lease bytes with the configured --sovereign-keys signers and grant over a real ontology digest delta, never an unchanged digest. |
| `SOVEREIGN` | sovereign_lease | false | R_missing_authority | `GgenIgniter.SemanticJira.SovereignLease` | Fix the lease the wrapped reason names: at least 2 distinct EdDSA signers, all signatures verifying, and a real ontology digest delta from the current pack digest. |
| reason | surfaces under | note |
|---|---|---|
| `INTENT_DIGEST_MISMATCH` | `TRANSITION` | apply_transition wraps every intent check as {:refused_transition, reason} |
| `STALE_INTENT` | `TRANSITION` | apply_transition wraps every intent check as {:refused_transition, reason} |
| `INTENT_NOT_BOUND_TO_WORK_ORDER` | `TRANSITION` | apply_transition wraps every intent check as {:refused_transition, reason} |
| `SCOPE_EXPANSION` | `LEASE_REQUEST` | lease_request wraps scope checks as {:refused_lease_request, reason} |
| `INVALID_SCOPE` | `LEASE_REQUEST` | lease_request wraps scope checks as {:refused_lease_request, reason} |
| `TRANSITION_LOG_HALF_SUPPLIED` | `REPLAY_REFUSED` | replay_check wraps input-shape refusals as {:replay_refused, reason} |
| `ABB_MISMATCH` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `AUTHORITY_WIDENING` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `DO_AUTHORITY_FORBIDDEN` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `INPUT_NOT_MAP` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `INVALID_AUTHORITY` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `MUTABLE_SUBJECT` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `RECEIPT_DIGEST_MISMATCH` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `SUBSTITUTION_NOOP` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `UNKNOWN_STANDING` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `UNQUALIFIED_SBB` | `ENTERPRISE_ARCHITECTURE` | EnterpriseArchitecture returns {:error, {:refused, reason}} |
| `AMBIGUOUS_ANCHOR` | `GATE_CONTRACT_INVALID` | GateVerify.parse_contract returns the reason, load_cardinality wraps it as {:invalid_contract, stem, reason} |
| `MISSING_ANCHOR` | `GATE_CONTRACT_INVALID` | GateVerify.parse_contract returns the reason, load_cardinality wraps it as {:invalid_contract, stem, reason} |
| `MISSING_MODE` | `GATE_CONTRACT_INVALID` | GateVerify.parse_contract returns the reason, load_cardinality wraps it as {:invalid_contract, stem, reason} |
| `MISSING_PREDICATE` | `GATE_CONTRACT_INVALID` | GateVerify.parse_contract returns the reason, load_cardinality wraps it as {:invalid_contract, stem, reason} |
| `UNKNOWN_MODE` | `GATE_CONTRACT_INVALID` | GateVerify.parse_contract returns the reason, load_cardinality wraps it as {:invalid_contract, stem, reason} |
| `DUPLICATE_WORK_IDENTITY` | `CS2_BATCH` | CS2Batch.admit wraps every reason as {:refused_cs2_batch, reason} |
| `MISSING_WORK_IDENTITY` | `CS2_BATCH` | CS2Batch.admit wraps every reason as {:refused_cs2_batch, reason} |
| `INVALID_BATCH_SHAPE` | `CS2_BATCH` | CS2Batch.admit wraps every reason as {:refused_cs2_batch, reason} |
