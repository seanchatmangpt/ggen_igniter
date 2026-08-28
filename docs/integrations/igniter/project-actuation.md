# Project Actuation: Igniter Integration & Task Composition

## Overview: ManufacturingPlan to ProjectDelta

In the `ggen_igniter` architecture, **Igniter** serves as the project actuator and task orchestrator. Once the semantic compiler (`ggen`) produces an admitted `ManufacturingPlan`, Igniter coordinates the application of this plan to an Elixir mix project.

```
+------------------------------------+
|  Admitted ManufacturingPlan        |
|  ([%PendingActuation{}])           |
+-----------------+------------------+
                  |
                  v
+-------------------------------------------------------------------------+
|                      PROJECT ACTUATION (Igniter)                        |
|                                                                         |
|  1. Task Protocol: Igniter.Mix.Task (info/2, igniter/1)                 |
|  2. Execution Context: %Igniter{} struct passing notices & metadata     |
|  3. Composition: Composable into parent Ash/Phoenix install flows       |
|  4. Side-Effect Execution:                                              |
|     - File Creation & Overwrites (Actuate.write_file!/3)               |
|     - Anchor Splices (Actuate.inject_content!/5)                        |
|     - In-Process Code Evaluation (Actuate.eval_code!/2)                |
+-----------------+-------------------------------------------------------+
                  |
                  v
+------------------------------------+
|  ProjectDelta (Modified Codebase)  |
+------------------------------------+
```

---

## 1. `Igniter.Mix.Task` Behaviour

Both primary CLI tasks in `ggen_igniter` implement the `Igniter.Mix.Task` behaviour:
- `Mix.Tasks.GgenIgniter.Sync` (`lib/mix/tasks/ggen_igniter.sync.ex`)
- `Mix.Tasks.GgenIgniter.Doctor` (`lib/mix/tasks/ggen_igniter.doctor.ex`)

### Contract Implementation

```elixir
defmodule Mix.Tasks.GgenIgniter.Sync do
  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ggen_igniter,
      example: "mix ggen_igniter.sync --pack ash-lifecycle-pack --out lib/generated.ex",
      positional: [],
      schema: [
        ontology: :string,
        query: [:string, :keep],
        template: :string,
        out: :string,
        engine: :string,
        store_id: :string,
        pack: :string,
        pack_dir: :string,
        skip_if: :string,
        unless_exists: :boolean,
        for_each: :string,
        dry_run: :boolean,
        mode: :string,
        on_stale: :string,
        manifest_dir: :string
      ],
      required: []
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # Coordinates execution and returns updated %Igniter{}
    ...
  end
end
```

### Purpose & Benefits of `Igniter.Mix.Task`
1. **Composability**: Allows `mix ggen_igniter.sync` to be invoked by other Igniter tasks (e.g., an Ash domain generator calling `ggen_igniter` as a child step) using `Igniter.compose_task/3`.
2. **State & Notice Aggregation**: Accumulates human-readable generation notices in the `%Igniter{}` struct via `Igniter.add_notice/2`, printing a unified summary at task completion.
3. **Dry-Run & CLI Option Propagation**: Seamlessly shares standardized CLI options (`--dry-run`, positional args) with the parent runner.

---

## 2. Hard Dependency Rationale

`mix.exs` specifies `{:igniter, "~> 0.8"}` as an **unconditional production dependency** (not restricted to `only: [:dev, :test]`):

```elixir
# mix.exs
{:igniter, "~> 0.8"}
```

### Rationale
Because `Mix.Tasks.GgenIgniter.Sync` and `Mix.Tasks.GgenIgniter.Doctor` are included in the compiled `lib/` directory and implement `use Igniter.Mix.Task`, consuming applications that depend on `{:ggen_igniter, ...}` require the `Igniter.Mix.Task` behaviour to be available during their own compilation. If `igniter` were dev/test-only, downstream consumer compilation would fail with `module Igniter.Mix.Task is not loaded`.

---

## 3. Observed Implementation Boundary: CLI Plumbing vs. AST Rewriting

**OBSERVED IMPLEMENTATION OUTRANKS INTENDED ARCHITECTURE.**

There is a clear, deliberate boundary in how `ggen_igniter` uses Igniter today:

| Igniter Capability | Usage in `ggen_igniter` | Status |
|---|---|---|
| **`Igniter.Mix.Task` (Task Behaviour & `info/2`)** | CLI task definition, schema validation, option parsing | **LIVE & USED** |
| **`Igniter.add_notice/2`** | Aggregating execution notices on `%Igniter{}` | **LIVE & USED** |
| **Task Composition (`Igniter.compose_task/3`)** | Participating in composite generator chains | **LIVE & COMPATIBLE** |
| **`Igniter.Project.Module` (AST Parsing/Generation)** | Generating or rewriting module definitions via AST | **NOT USED** |
| **`Igniter.Code` & `Sourceror.Zipper`** | Navigating and splicing AST nodes structurally | **NOT USED** (See `ast-mutation.md`) |

All filesystem modifications in `ggen_igniter` are performed via `GgenIgniter.Actuate` (`write_file!/3` for whole files, `inject_content!/5` for line-anchored splices, and `eval_code!/2` for in-memory evaluation). AST-level structural modification with `Sourceror` remains a planned future capability.
