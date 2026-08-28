# Architecture Consistency Review: Conceptual Boundaries & Authority Leaks

**Reviewer ID:** ADVERSARIAL REVIEWER C (Architecture Consistency Reviewer)  
**Target Document Scope:** `docs/architecture/**`, `docs/integrations/**`, `docs/reference/reactor/**`, `docs/reference/reconciliation/**`, `docs/reference/evidence/**`, `docs/operations/**`  
**Evaluation Date:** 2026-08-27  
**Verdict:** **PASSED WITH HONEST DISCLOSURES** (Zero critical split-brain leaks; all conceptual boundaries rigorously defined and aligned with empirical codebase reality).

---

## Executive Summary

An adversarial audit of the `ggen_igniter` documentation suite was conducted to detect conceptual boundary violations, split-brain authority leaks, circular dependencies, and conflations of responsibility.

The audit evaluated five core architectural relationships:
1. **Controller vs. Reactor**: Lifecycle coordination kernel vs. persistent BEAM GenServer request/state owner.
2. **ggen vs. Igniter**: Semantic compiler vs. Elixir AST project actuator.
3. **Manifest vs. Receipt**: Current production state memory vs. append-only historical audit evidence.
4. **Ash & Phoenix**: Optional consumer-side application semantic verifier vs. core runtime dependency.
5. **CLI vs. Control Plane**: Ephemeral adapter vs. persistent in-process control plane.

Every claim was tested against the empirical codebase and verified for conceptual purity.

---

## Evaluation Matrix

| Category / Focus Area | Boundary Health | Authority Leak Risk | Status |
|---|---|---|---|
| **1. Controller vs. Reactor** | Strict | Low (Disambiguated `record.receipt` vs `%Receipt{}`) | `CONFIRMED` |
| **2. ggen vs. Igniter** | Strict | Low (Disclosed line-splice vs. planned AST zipper) | `CONFIRMED` |
| **3. Manifest vs. Receipt** | Strict | None (Strict two-phase durability ordering) | `CONFIRMED` |
| **4. Ash & Phoenix** | Strict | None (Zero compile/runtime dependencies in `mix.exs`) | `CONFIRMED` |
| **5. CLI vs. Control Plane** | Strict | Low (Disclosed inline sync vs. delegated Controller) | `CONFIRMED` |

---

## Detailed Findings by Focus Area

### 1. Controller vs. Reactor

#### Core Boundary Question
*Is Reactor clearly the lifecycle coordination kernel while Controller is the persistent BEAM GenServer request/state owner?*

#### Analysis & Evidence
- **Reactor (`GgenIgniter.Reactors.ReconcileReactor`)**:
  - Acts as an ephemeral, single-attempt execution DAG (`observe -> load -> resolve -> query -> render -> admit -> actuate -> verify -> finalize_evidence`).
  - Owns step dependency resolution, concurrency via `Task.async_stream/3`, fail-closed admission gating, physical mutation rollback (`undo/4`), and durable evidence writing (`Receipt.append!/2`).
  - Does **not** hold long-term state across independent runs; state is discarded when the workflow finishes or compensates.
- **Controller (`GgenIgniter.Controller`)**:
  - Implemented as an OTP `GenServer` supervised under `GgenIgniter.Application` (opt-in via `start_controller: true`).
  - Holds persistent in-memory state across multiple successive reconciliations (tracking non-disk-derivable metrics such as `reconciliation_count`, execution timestamps, and per-pack status).
  - Implements request serialization, query APIs (`status/2`), and fault isolation between independent pack keys.
  - Does **not** implement workflow scheduling, step DAG execution, or rollback logic of its own; it delegates the actual reconciliation run to `ReconcileReactor` (when `use_reactor: true`) or `Reconcile.run/1`.
- **Potential Split-Brain / Leak Point Analyzed**:
  - `Controller` maintains an in-memory map under the key `:receipt` in its state record (`record.receipt`). The documentation explicitly flags this potential naming confusion in `docs/reference/evidence/receipts.md` (Section 5), clearly distinguishing the Controller's ephemeral in-memory return map from the durable, schema-enforced `%GgenIgniter.Receipt{}` written by `ReconcileReactor`.
- **Architecture Rules Compliance**:
  - `docs/contributing/architecture-rules.md` explicitly mandates: *"GenServer (Controller) does not become a workflow engine."*

#### Finding Status: `CONFIRMED`

---

### 2. ggen vs. Igniter

#### Core Boundary Question
*Is ggen clearly the semantic compiler while Igniter is the Elixir AST project actuator?*

#### Analysis & Evidence
- **ggen (Semantic Compiler)**:
  - Encompasses RDF ontology ingestion (`GgenIgniter.Ontology`), multi-backend SPARQL query compilation (`GgenIgniter.Engine` / `Query.*`), single-row root promotion (`build_bindings/2`), multi-row fan-out (`for_each`), and template rendering (`GgenIgniter.Render` for EEx and Tera).
  - Emits a pure, in-memory intermediate representation: `%GgenIgniter.PendingActuation{}` (`ManufacturingPlan`).
  - Performs **zero** direct filesystem mutations or project code modifications.
- **Igniter (Project Actuator & CLI Harness)**:
  - Encompasses task composition (`Igniter.Mix.Task` behaviour in `Mix.Tasks.GgenIgniter.Sync` and `Doctor`), notice accumulation (`Igniter.add_notice/2`), CLI option parsing, and project mutation.
  - Actuation is strictly quarantined to `GgenIgniter.Actuate` (`write_file!/3`, `inject_content!/5`, `eval_code!/2`) consuming the admitted `PendingActuation` plan.
- **Boundary Reality Check (AST Mutation vs. Text Injection)**:
  - The documentation accurately and honestly discloses that while `{:igniter, "~> 0.8"}` is an unconditional dependency (for task behaviors), deep AST zipper transformations (`Sourceror.Zipper` / `Igniter.Code`) are `PLANNED` / `UNSUPPORTED`. Current file modification utilizes deterministic, line/regex-anchored text splices (`Actuate.inject_content!/5`) with fail-closed safety gates (`FM-WRITE-003`, `FM-WRITE-004`) and idempotency checks.
- **Architecture Rules Compliance**:
  - `docs/contributing/architecture-rules.md` explicitly separates: *"Igniter owns Elixir project mutation"* from *"ggen owns semantic compilation"*.

#### Finding Status: `CONFIRMED`

---

### 3. Manifest vs. Receipt

#### Core Boundary Question
*Is Manifest clearly current production state memory while Receipt is append-only historical audit evidence?*

#### Analysis & Evidence
- **Manifest (`.ggen_igniter/manifest.json`)**:
  - **Purpose**: Current-state cache and manufacturing ownership memory.
  - **Keying**: Keyed by recipe identity `(template_path, out_template)` via `Manifest.recipe_key/2`.
  - **Lifecycle**: Advances **only** on successful, verified `:alive` reconciliations.
  - **Write Discipline**: Atomic file rename (`tmp` file rename to `manifest.json`), preventing partial writes.
  - **Scope**: Tracks whole-file writes (`mode: file`); excludes `mode: eval`, skipped files, and injected text (`inject: true`). Enables automated stale-artifact detection and pruning.
- **Receipt (`.ggen_igniter/receipts/YYYY-MM-DD.jsonl`)**:
  - **Purpose**: Complete chronological audit ledger of all physical actuation attempts.
  - **Lifecycle**: Appended on **every** admitted run across all four closed-set standings (`:alive`, `:refused`, `:compensated`, `:build_broken`).
  - **Write Discipline**: Append-only JSON Lines (`File.write!/3` with `[:append]`).
  - **Payload**: Contains unique `receipt_id`, start/finish timestamps, pre/post cryptographic hashes (`pre_run_hash`, `post_run_hash`), affected file paths, failure reasons, and ordered OCEL 2.0 telemetry events.
- **Durability Ordering & Split-Brain Elimination**:
  - `docs/reference/evidence/recovery.md` and `docs/reference/reactor/steps.md` establish the strict evidence-first finalization protocol:
    1. Prepare new manifest and receipt in memory.
    2. Write append-only receipt to disk (`Receipt.append!/2`). If this fails, the run fails and triggers Reactor `undo/4` rollback.
    3. Promote manifest via atomic rename (`Manifest.persist!/2`). If this fails, the error is caught locally, leaving the receipt with `metadata["manifest_promotion"] = "{:pending, ...}"` and standing `:alive`. The durable receipt guarantees that project history can be replayed and the manifest reconstructed.

#### Finding Status: `CONFIRMED`

---

### 4. Ash & Phoenix

#### Core Boundary Question
*Is Ash clearly an optional consumer application semantic verifier rather than a core runtime dependency?*

#### Analysis & Evidence
- **Dependency Audit**:
  - `mix.exs` contains zero direct or indirect dependencies on `:ash`, `:ash_phoenix`, `:ash_postgres`, `:phoenix`, or `:phoenix_live_view`.
  - `lib/ggen_igniter/` contains zero `use Ash.*` or `use Phoenix.*` macros.
- **Coordination Kernel Decoupling**:
  - `GgenIgniter.Reactors.ReconcileReactor` uses standalone `use Reactor` from the `{:reactor, "~> 1.0"}` Hex package, explicitly avoiding `Ash.Reactor`.
- **Ash as a Consumer Semantic Verifier**:
  - Ash DSL artifacts (`Ash.Resource`, `Ash.Domain`) are generated outputs produced by generator packs (such as `test/fixtures/ash-lifecycle-pack/`).
  - Ash acts as a consumer-side semantic verifier during the `:verify` step: when `mix compile --warnings-as-errors` runs, Spark DSL extension verifiers execute at compile-time to validate entity attributes, types, actions, and relationship integrity before the run can achieve `:alive` standing.
- **Phoenix Boundary**:
  - Phoenix LiveView generation is entirely downstream, initiated by consumer commands (e.g. `mix ash_phoenix.gen.live`), and is completely decoupled from core `ggen_igniter` execution.
- **Doctor Check Independence**:
  - `GgenIgniter.DoctorFixes` scans consumer code textually for `use Ash.Domain` without requiring `Ash` to be compiled into `ggen_igniter`.

#### Finding Status: `CONFIRMED`

---

### 5. CLI vs. Control Plane

#### Core Boundary Question
*Is the CLI clearly an ephemeral adapter rather than the control plane itself?*

#### Analysis & Evidence
- **CLI (`Mix.Tasks.GgenIgniter.Sync`, `Doctor`)**:
  - Functions as an ephemeral, short-lived OS process interface invoked from the terminal.
  - Contains command-line argument parsing, environment variable inspection, and console formatting.
  - Checks for a running `GgenIgniter.Controller` via `Process.whereis/1`. When present, delegates work to the Controller; otherwise, directly invokes the pipeline.
  - Discards all process memory upon task termination.
- **Control Plane (`GgenIgniter.Controller`)**:
  - Functions as the long-lived, BEAM-native state holder and request supervisor.
  - Maintains in-memory continuity across invocations, tracking exact invocation counts and previous run summaries without needing disk re-reads.
  - Provides fault isolation: errors in one pack key do not crash the GenServer or corrupt the state of other pack keys.
- **Disclosed Current vs. Target Unification**:
  - Documentation across `docs/architecture/control-plane.md`, `docs/operations/runtime.md`, and `docs/contributing/architecture-rules.md` explicitly discloses that three execution paths coexist during the migration phase (the CLI's inline pipeline, `Reconcile.run/1`, and `ReconcileReactor.run/1`). This split is transparently labeled `PARTIAL_ALIVE`, with clear architectural rules prohibiting the introduction of competing coordinators.

#### Finding Status: `CONFIRMED`

---

## Architectural Invariants Verification Summary

| Invariant | Documented Rule | Empirical Codebase Status | Verdict |
|---|---|---|---|
| **No Filesystem Mutation Before Admission** | `docs/architecture/component-boundaries.md:71-76` | Pure `PendingActuation` IR validated in `:admit` prior to `:actuate`. | `CONFIRMED` |
| **Single Mutation Boundary** | `docs/architecture/component-boundaries.md:66-70` | Isolated strictly to `GgenIgniter.Actuate` (`write_file!`, `inject_content!`, `eval_code!`). | `CONFIRMED` |
| **Receipt Precedes Manifest** | `docs/architecture/component-boundaries.md:81-87` | In `:finalize_evidence`, `Receipt.append!` executes before `Manifest.persist!`. | `CONFIRMED` |
| **Deterministic Compensation** | `docs/reference/reactor/compensation.md` | Reactor `undo/4` restores pre-run bytes; $\text{pre\_hash} == \text{post\_hash}$ on `:compensated`/`:build_broken`. | `CONFIRMED` |
| **Zero Ash Core Coupling** | `docs/architecture/adr/ADR-004-ash-optional-integration.md` | Zero Ash dependencies in `mix.exs`; plain `Reactor` used for kernel. | `CONFIRMED` |

---

## Conclusion & Recommendations

The architecture documentation demonstrates rigorous conceptual clarity and consistency. Responsibilities are clearly partitioned across all layers, and there are no hidden authority leaks or circular dependencies between the compiler, actuator, state memory, evidence ledger, control plane, and consumer applications.

### Future Maintenance Guidance
1. **Unify CLI on `ReconcileReactor`**: As planned in ADR-0003 and `docs/operations/runtime.md`, continue deprecating the legacy inline pipeline in `Mix.Tasks.GgenIgniter.Sync` in favor of delegating exclusively to `ReconcileReactor`.
2. **Preserve Struct Disambiguation**: Continue enforcing the clear naming distinction between `Controller`'s in-memory summary map (`record.receipt`) and the formal `%GgenIgniter.Receipt{}` event ledger.
3. **AST Mutation Roadmap**: When implementing `Sourceror`/`Igniter.Code` structural AST editing, ensure it integrates into `PendingActuation` and executes strictly within the `:actuate` boundary.
