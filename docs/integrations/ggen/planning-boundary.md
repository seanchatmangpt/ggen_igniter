# The Planning Boundary: Knowledge to ManufacturingPlan

## Overview

The central architectural invariant of `ggen_igniter` is the strict separation between:
1. **Semantic Compilation (`ggen`)**: Pure computation transforming knowledge into an admitted `ManufacturingPlan`.
2. **Project Actuation (`Igniter`)**: Side-effectful filesystem execution of the admitted plan into a `ProjectDelta`.

Between these two stages lies the **Planning Boundary**. At this boundary, no filesystem mutations (file writes, code injections, deletions) are permitted. Instead, the compiler produces a pure Intermediate Representation (IR) wrapped in `%GgenIgniter.PendingActuation{}` records.

```
+-------------------------------------------------------------------------+
|                  SEMANTIC COMPILATION (Pure Knowledge)                  |
|  Ontology (.ttl) + Queries (.rq) + Templates (.eex) -> Rendered Intents |
+------------------------------------+------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                          PLANNING BOUNDARY                              |
|                                                                         |
|   1. Intermediate Representation: [%GgenIgniter.PendingActuation{}]     |
|   2. Admission Control (admit_pending/2):                               |
|      - Collision Detection (No duplicate target paths)                  |
|      - Ownership Invariant (Only delete previously-owned paths)         |
|      - Stale Policy Evaluation (Refusal on unadmitted drift)            |
+------------------------------------+------------------------------------+
                                     | Admitted Plan
                                     v
+-------------------------------------------------------------------------+
|                  PROJECT ACTUATION (Side-Effectful IO)                  |
|  Concurrent writes, guarded splices, AST verification, and rollback     |
+-------------------------------------------------------------------------+
```

---

## 1. The `PendingActuation` Intermediate Representation (IR)

`GgenIgniter.PendingActuation` (`lib/ggen_igniter/pending_actuation.ex`) defines the contract for planned file modifications. It mirrors Rust `ggen`'s `PendingWrite`/`SyncReport` IR (`ggen-engine/src/sync.rs:167-171`).

### Struct Definition & Fields

```elixir
defstruct [
  :logical_id,
  :target,
  :previous_hash,
  :desired_hash,
  :desired_content,
  :operation,
  :ownership,
  :semantic_source,
  :compensation_data
]
```

| Field | Type | Description |
|---|---|---|
| `logical_id` | `String.t()` | Stable identifier across runs: `recipe_key(template, out_template) <> "::" <> target`. |
| `target` | `String.t() \| nil` | Target filesystem path. `nil` for in-memory `:eval` operations. |
| `previous_hash` | `String.t() \| nil` | SHA-256 hash of the target file currently on disk (`nil` if target does not exist). |
| `desired_hash` | `String.t() \| nil` | SHA-256 hash of the rendered desired content (`nil` for `:delete` operations). |
| `desired_content` | `binary() \| nil` | The actual bytes to be written. Carried on the struct to prevent re-rendering during actuation. |
| `operation` | `operation()` | One of `:create`, `:replace`, `:inject`, `:delete`, or `:eval`. Derived from target existence and template mode. |
| `ownership` | `boolean()` | Whether this recipe's prior manifest entry recorded ownership of this path. |
| `semantic_source` | `map()` | Provenance metadata (`ontology_path`, `template_path`, `out_template`, query bindings). |
| `compensation_data` | `compensation_data()` | Rollback payload: `{:previous_content, binary}` or `:did_not_exist`. |

### Plan Constructors
- `for_file/6`: Constructs plan items for whole-file writes. Derives `:create` (if file absent) or `:replace` (if file present). Computes `previous_hash` and `desired_hash`.
- `for_delete/4`: Constructs plan items for stale files identified by manifest diffing (`desired_hash: nil`, `ownership: true`).
- `for_eval/3`: Constructs plan items for `mode: eval` in-process execution (`target: nil`, `ownership: false`).

---

## 2. Whole-Plan Admission Control (`admit`)

Before any disk I/O occurs, `GgenIgniter.Reactors.ReconcileReactor` passes the entire list of `PendingActuation` items through the `admit` step (`admit_pending/2` in `lib/ggen_igniter/reactors/reconcile_reactor.ex`):

### Admission Invariants

1. **Path Collision Prevention (No Last-Writer-Wins)**:
   - If two distinct plan items (e.g., from different queries or fan-out rows) resolve to the identical `target` path, the entire plan is refused:
     ```elixir
     {:error, {:refused_duplicate_output_path, collisions}}
     ```
   - Prevents silent race conditions and non-deterministic overwrites during concurrent actuation.

2. **Ownership Verification for Deletions**:
   - Every `operation: :delete` item must carry `ownership: true`.
   - The generator strictly refuses to delete any file that was not previously manufactured and recorded by this recipe in `manifest.json`.

3. **Stale Artifact Admission (`--on-stale`)**:
   - `refuse` (Default): If stale outputs exist from a prior run (e.g., an entity was renamed in the ontology), admission fails immediately before writing any files.
   - `prune`: Admits `:delete` items for execution during finalization.
   - `preserve`: Drops stale outputs from tracking while leaving files intact on disk.

---

## 3. Prune Timing and Rollback Guarantees

In `ReconcileReactor`, the planning boundary enforces strict ordering guarantees:

### Deferred Pruning
Unlike naive scripts that delete old files immediately, `ReconcileReactor` defers real `File.rm/1` pruning until the `:finalize_evidence` step—**strictly after** the newly generated codebase has passed compilation checks (`:verify` running `mix compile --warnings-as-errors`).

### Rollback Semantics (`compensate/4` vs `undo/4`)
- **Step-Local Compensation (`compensate/4`)**: Handled during `:actuate` if an individual write fails midway.
- **Whole-Plan Rollback (`undo/4`)**: If downstream verification (`:verify`) fails, Reactor triggers `undo/4` on `:actuate`, restoring all overwritten files from `compensation_data` (`{:previous_content, bytes}`) and deleting all newly created files (`:did_not_exist`).
- Emits OCEL telemetry events (`COMPENSATION_STARTED`, `FILES_RESTORED`) and records a `GgenIgniter.Receipt` with standing `:build_broken`.

---

## 4. Architectural Boundary Comparison

| Feature | Opt-in Reactor Pipeline (`ReconcileReactor`) | Default Inline Pipeline (`Reconcile.run/1` / `sync.ex`) |
|---|---|---|
| **Explicit IR** | `%GgenIgniter.PendingActuation{}` | Direct tuple `{bindings, content, out_path}` |
| **Admission Phase** | Formal `:admit` step evaluating whole-plan invariants | Inline validation checks in task |
| **Collision Refusal** | Fails closed on duplicate target paths | Last-iteration overwrite |
| **Rollback Capability** | Full transactional rollback (`undo/4`) | No rollback (partial writes remain on disk) |
| **Evidence Receipt** | Always persisted (`:alive`, `:refused`, `:build_broken`, `:compensated`) | No receipt tracking |
