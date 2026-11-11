# Observability & OCEL 2.0 Telemetry Projection (v26.11.10)

Architecture and verification specification for Object-Centric Event Log (OCEL 2.0) telemetry emission,
process mining projection via `beam4pm`, and the mandatory log sealing protocol.

- **Release Version:** `26.11.10`
- **Observability Standing:** `OCEL_PROCESS_ALIVE`
- **Process Mining Importer:** `beam4pm` / `Rust4PM`
- **Machine Evidence:** [evidence/conformance.json](evidence/conformance.json)

---

## 1. Why Process Mining Telemetry is a First-Class Artifact

Standard software logging treats operations as unstructured string messages. In an ontology-driven generative engine, however, every generation run is a state machine executing business morphisms:
1. Ontology facts are read and admitted.
2. Generator tasks are planned and composed.
3. Code artifacts are mutated and serialized.
4. Refusals and errors are typed and recorded.

To guarantee formal auditability and enable automated process conformance checks, `ggen_igniter` projects its execution trace into the **OCEL 2.0 (Object-Centric Event Log)** international standard. This enables tools like `beam4pm` to mathematically verify whether the engine followed lawful paths.

---

## 2. OCEL 2.0 Serializer Architecture

Telemetry emission is managed by `GgenIgniter.Telemetry.Ocel2Export` (`lib/ggen_igniter/telemetry/ocel2_export.ex`).

### 2.1 Core Entities in the Object-Centric Graph
Unlike traditional event logs where events belong to a single case ID, OCEL 2.0 allows events to relate to multiple heterogeneous objects:

- **Objects:**
  - `Plan`: Represents the overall manufacture plan.
  - `Pack`: The RDF pack defining the transformation rules (e.g. `amp:AshManufacturePack`).
  - `Capability`: The upstream generator capability being invoked (e.g. `ash.gen.resource`).
  - `Artifact`: The target file being created or modified (e.g. `lib/book_library/catalog/book.ex`).
  - `Refusal`: An explicit typed refusal when a capability cannot be admitted.

- **Activities:**
  - `plan_composed`: Initial composition of generator tasks.
  - `capability_admitted`: Formal admission of a generator task into the execution plan.
  - `capability_refused`: Typed refusal of an unmanufacturable construct.
  - `ast_patched`: Successful AST transformation in memory via Sourceror.
  - `disk_actuated`: Coordinated atomic file write to disk.
  - `execution_sealed`: Final verification seal appended to the event log.

---

## 3. The Log Sealing Protocol (`mix ggen_igniter.ocel.seal`)

A critical timing vulnerability exists in code generation pipelines: **in-memory decision vs. disk actuation divergence**.

```
[In-Memory Planning] -----> [Igniter In-Memory AST Rewrite] -----> [Disk Actuation]
         |                                                                |
         v                                                                v
(Event: capability_admitted)                                      (Event: execution_sealed)
```

During `igniter/1`, tasks are composed in memory. If the BEAM VM crashes or power fails before files are flushed to disk, an unsealed log would falsely claim the code was manufactured.

### 3.1 Sealing Mechanics
The task `lib/mix/tasks/ggen_igniter.ocel.seal.ex` solves this:
1. It is invoked immediately following the completion of `do_or_dry_run/2`.
2. It inspects the actual exit code, file write results, and compiler status.
3. It appends an `execution_sealed` event containing:
   - `exit_code`: integer exit status (must be `0`).
   - `files_written`: list of paths successfully modified on disk.
   - `tree_digest`: SHA-256 hash of the resulting source tree.
   - `seal_timestamp`: ISO 8601 UTC timestamp.
4. **Conformance Rule:** Any log lacking an `execution_sealed` event is classified as an **unlawful execution trace** and refused by `beam4pm`.

---

## 4. Process Mining Importer Verification (`beam4pm`)

The sealed OCEL 2.0 log is verified against the `beam4pm` process mining engine:

```bash
mix ggen_igniter.ocel.verify --log priv/telemetry/run.ocel.json
```

### 4.1 Verification Results (Recorded in evidence/conformance.json)
- **Log Schema:** Valid OCEL 2.0 JSON.
- **Total Events:** 42 events recorded.
- **Conformance Violations:** `0`.
- **Morphism Conservation:** Every admitted capability corresponds to an executed or cleanly idempotent task.
- **Refusal Conformance:** All 9 unsupported or broken capabilities emitted valid `capability_refused` events without halting the pipeline.
