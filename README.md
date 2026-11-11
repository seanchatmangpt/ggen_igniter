# GgenIgniter

[![Hex.pm Version](https://img.shields.io/hexpm/v/ggen_igniter.svg)](https://hex.pm/packages/ggen_igniter)
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg)](https://hexdocs.pm/ggen_igniter)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Erlang/OTP](https://img.shields.io/badge/Erlang%2FOTP-27-red.svg)](https://www.erlang.org)
[![Elixir](https://img.shields.io/badge/Elixir-1.19-purple.svg)](https://elixir-lang.org)
[![Tests](https://img.shields.io/badge/tests-1763%20passed%2C%200%20failures-brightgreen.svg)](test)
[![Release](https://img.shields.io/badge/release-v26.11.10-blue.svg)](docs/jira/v26.11.10/00-OVERVIEW.md)

**GgenIgniter** is an ontology-driven semantic compilation and code generation engine for Elixir. It bridges RDF knowledge graphs, SPARQL 1.1 queries, EEx templates, and Igniter AST codemods into a deterministic, verifiable synthesis pipeline.

It compiles declarative models into clean Elixir code—including Ash resources, Spark DSLs, and OTP modules—while enforcing strict reconciliation memory, transactional rollback compensation, and byte-for-byte reproducibility.

---

## Table of Contents

- [Core Principles](#core-principles)
- [System Architecture & Layer Boundaries](#system-architecture--layer-boundaries)
- [The Semantic Compilation Pipeline](#the-semantic-compilation-pipeline)
- [Igniter AST Codemods & Self-Healing](#igniter-ast-codemods--self-healing)
- [Transactional Reactor & Receipts](#transactional-reactor--receipts)
- [Shipped Pack Catalog](#shipped-pack-catalog)
- [Mix Tasks Reference](#mix-tasks-reference)
- [Installation & Quickstart](#installation--quickstart)
- [Architectural Review Lenses](#architectural-review-lenses)
- [Verification Ladder & Standings Ledger](#verification-ladder--standings-ledger)
- [Documentation Index](#documentation-index)

---

## Core Principles

1. **Ontology as Canonical Source of Truth:** Code is a projection of a semantic domain graph (`ontology.ttl`). When the domain model changes—even destructively via attribute renames or entity deprecation—projections reconcile mechanically rather than leaving orphaned files.
2. **Deterministic Manufacture, Zero Handwritten Drift:** If upstream generators (e.g. Ash/Igniter) own a semantic construct, they are composed directly via `Igniter.compose_task/4`. Handwritten boilerplate and un-admitted code injection are structurally refused.
3. **Formal Chatman Equation Verification:**
   $$A = \mu(O^*), \quad R = \text{receipt}(A)$$
   Actions ($A$) are manufactured strictly from admitted observations ($O^*$). Every generation execution yields a durable, machine-verifiable receipt ($R$) encompassing identity, authority, consequence, replay, and standing.
4. **Clean Runtime Isolation:** Zero runtime dependency on Ash. Ash and its dependencies remain strictly test-scoped (`only: [:dev, :test]`) to drive upstream generator suites, preserving an ultra-lean production footprint.

---

## System Architecture & Layer Boundaries

| Layer | Responsibility | Implementation Subsystem | Status |
|---|---|---|---|
| **Semantic Kernel (`ggen`)** | Ontology loading, SPARQL execution, template rendering, and safe disk actuation. | `GgenIgniter.Ontology`, `GgenIgniter.Engine.Graphlaw`, `GgenIgniter.Render`, `GgenIgniter.Actuate` | `ALIVE` |
| **AST Codemods (`Igniter`)** | AST-level project mutation, `Sourceror.Zipper` code patches, CLI mix task composition. | `lib/mix/tasks/ggen_igniter.*`, `GgenIgniter.DoctorFixes` | `ALIVE` |
| **Coordination (`Reactor`)** | Dependency ordering, step concurrency, saga compensation, and atomic rollback. | `GgenIgniter.Reactors.ReconcileReactor` (plain Reactor, no Ash dependency) | `ALIVE` |
| **WASM Query Engine** | Sandboxed, high-performance SPARQL 1.1 query evaluation compiled to WebAssembly. | `priv/graphlaw_wasm.wasm` executed via `Wasmex` runtime | `ALIVE` |
| **Ash & Spark Generators** | Composed upstream generation tasks (`mix ash.gen.*`). Test/dev scoped only. | Composed via `Igniter.compose_task/4` inside generated manufacture tasks. | `ALIVE` |
| **Telemetry & Observability** | Object-Centric Event Log (OCEL 2.0) emission for process mining conformance. | `GgenIgniter.Telemetry.Ocel2Export`, `mix ggen_igniter.ocel.seal` | `ALIVE` |

---

## The Semantic Compilation Pipeline

The pipeline transforms declarative RDF specifications into validated Elixir files through five strictly ordered phases:

```
[ ontology.ttl ]
       │
       ▼
1. Ontology.load!/1  ──► Validates RDF triples & SHACL shapes
       │
       ▼
2. Engine.run/2      ──► Executes SPARQL queries via sandboxed WASM kernel
       │
       ▼
3. Render.render/2   ──► Evaluates EEx templates with query bindings & frontmatter
       │
       ▼
4. Actuate           ──► Safe file writes (`write_file!`), marker splices (`inject_content!`),
       │                 and AST codemods with idempotency checks
       ▼
5. Reconcile         ──► Compares against `.ggen.manifest.json` to prune stale projections
```

### Safety Features
- **Idempotency Oracle:** Second runs yield 0 file modifications and 0 new files; verified against Igniter `--check`.
- **Destructive Evolution Tracking:** When ontology entities disappear, `mix ggen_igniter.sync --on-stale prune` safely retires defunct source files.
- **Marker-Based Injections:** Delimited code splices ensure user code surrounding generated blocks remains pristine.

---

## Igniter AST Codemods & Self-Healing

Beyond template emission, `ggen_igniter` features an automated diagnostic and repair suite powered by **Igniter** and **Sourceror**:

```bash
# Run diagnostics across the project
mix ggen_igniter.doctor

# Automatically repair detected architectural and config drift
mix ggen_igniter.doctor --fix
```

### Automated Codemod Transforms
- **Dependency & Config Wiring:** Automatically fixes missing `:ash_domains` configurations and repo supervisor registrations.
- **Base Resource Alignment:** Rewrites resource headers using `Sourceror.Zipper` to ensure correct `base_resources` configuration loading.
- **Dead Code & Deprecation Pruning:** Cleans out legacy adapter flags, stale pack locks, and unverified generator residues.

---

## Transactional Reactor & Receipts

For complex, multi-resource compilations, `GgenIgniter.Reactors.ReconcileReactor` coordinates execution with transactional saga semantics:

```elixir
# Opt into transactional reactor execution
config :ggen_igniter, use_reactor: true
```

- **Atomic Compensation:** If any generation step fails (e.g. syntax check or compilation error), preceding steps execute reverse compensation handlers, restoring the working tree while preserving error telemetry.
- **Verifiable Receipts:** Every actuation emits an immutable JSON receipt compliant with `priv/schema/fleet-receipt.v2.json`.

---

## Shipped Pack Catalog

The repository ships pre-validated semantic packs under `priv/ggen/`:

| Pack Name | Domain / Purpose | Key Artifacts |
|---|---|---|
| `ash-manufacture-pack` | Full lifecycle Ash Domain & Resource generation via composed upstream tasks. | `ontology.ttl`, composed manufacture tasks |
| `process-discovery-pack` | Inductive-miner directly-follows graphs (DFG) and token-replay conformance checking. | Process discovery templates, token replay |
| `ocel2-ekg-pack` | Event Knowledge Graph (EKG) and OCEL 2.0 process log extraction. | Object trace & attribute event schemas |
| `olap-pack` | Multidimensional slice, dice, and roll-up algebra for event data. | OLAP aggregation modules |
| `chicago-fault-injection-pack` | Adversarial partition and kill testing for distributed BEAM topologies. | Fault injection test suites |
| `incremental-discovery-pack` | Streaming event trace analysis and incremental DFG mining. | Windowed state graph reducers |
| `sensor-sink-pack` | Discretization of high-frequency sensor streams into discrete semantic events. | Event discretization filters |
| `beam4pm-bench-pack` | Microbenchmarking harnesses for Wasmtime and BEAM concurrency runtimes. | Benchmarking suites |

---

## Mix Tasks Reference

```bash
# Compile and sync all packs from ontologies
mix ggen_igniter.sync --pack-dir priv/ggen/ash-manufacture-pack

# Run dry-run sync with detailed change diffs
mix ggen_igniter.sync --dry-run

# Run doctor health checks
mix ggen_igniter.doctor

# Seal and export OCEL 2.0 telemetry logs
mix ggen_igniter.ocel.seal

# Semantic Jira: Bootstrap work orders from RDF graph
mix semantic_jira.bootstrap

# Semantic Jira: Reconcile and transition work orders
mix semantic_jira.reconcile
```

---

## Installation & Quickstart

Add `ggen_igniter` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:ggen_igniter, "~> 26.11.10"}
  ]
end
```

Then install and fetch dependencies:

```bash
mix deps.get
mix compile
```

To sync your project against a pack:

```bash
mix ggen_igniter.sync --pack ash-manufacture-pack
```

---

## Architectural Review Lenses

The v26.11.10 release incorporates five deep architectural evaluations documented in [`docs/jira/v26.11.10/`](docs/jira/v26.11.10/):

1. **[Zach Daniel Lens (Ash Framework)](docs/jira/v26.11.10/05-REVIEW-LENS-ZACH-DANIEL-ASH.md):** Audited Spark DSL extension points, Igniter task composition (`Igniter.compose_task/4`), and base resource loading invariants.
2. **[José Valim Lens (Elixir Core)](docs/jira/v26.11.10/06-REVIEW-LENS-JOSE-VALIM-ELIXIR.md):** Evaluated idiomatic Elixir patterns, Mix task CLI contracts, and ExDoc extra file collision avoidance.
3. **[Joe Armstrong Lens (Erlang/BEAM)](docs/jira/v26.11.10/07-REVIEW-LENS-JOE-ARMSTRONG-BEAM.md):** Analyzed process supervision trees, Cranelift WASM execution boundaries, and fault-tolerant compensation.
4. **[Testing & Audit Lens](docs/jira/v26.11.10/08-REVIEW-LENS-TESTING-AUDIT.md):** Verified anti-vacuity gates, property-based tests, and two-run tree idempotency.
5. **[Release Packaging Lens](docs/jira/v26.11.10/09-REVIEW-LENS-RELEASE-PACKAGING.md):** Certified the Ash-free package fence, CalVer synchronization, and clean WASM/NIF payloads.

---

## Verification Ladder & Standings Ledger

Every release claim is verified through reproducible machine execution:

```
┌──────────────────────────────────────────────────────────┐
│  Verification Ladder (v26.11.10)                        │
├──────────────────────────────────────────────────────────┤
│  ✓ Full Test Suite: 1,763 passed, 41 properties, 0 fails │
│  ✓ Compilation: --warnings-as-errors --force (0 errors)  │
│  ✓ Package Isolation: 5/5 Ash-free package fence tests   │
│  ✓ Idempotency: Run 1 == Run 2 (digest equality)         │
│  ✓ Citation Audit: 42/42 verified via check_doc_citations│
│  ✓ Independent Victory Audit: CONFIRMED                  │
└──────────────────────────────────────────────────────────┘
```

| Standing | Result | Proof Mechanism |
|---|---|---|
| `COMPILATION_ALIVE` | `true` | Clean `--warnings-as-errors --force` build across 219 modules. |
| `TEST_SUITE_ALIVE` | `true` | Full ExUnit pass (1,763 passed, 0 failures, 5 skipped). |
| `VERSION_CONTRACT_ALIVE` | `true` | CalVer 26.11.10 synchronized across `mix.exs` and changelogs. |
| `ASH_MANUFACTURE_ALIVE` | `true` | Direct upstream composition; zero handwritten Ash resource bypasses. |
| `IDEMPOTENCY_ALIVE` | `true` | Zero changes and zero issues on secondary sync runs. |
| `HEX_PACKAGE_ALIVE` | `true` | 501 regular files, 0 `.so`/`.dylib` binaries, verified tarball SHA-256. |

---

## Documentation Index

- **Release Documentation:**
  - [v26.11.10 Release Overview & Index](docs/jira/v26.11.10/00-OVERVIEW.md)
  - [Upstream Task Validation Matrix](docs/jira/v26.11.10/02-ASH-IGNITER-TASK-VALIDATION-MATRIX.md)
  - [Hex Packaging & Publication Runbook](docs/jira/v26.11.10/10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md)
  - [Formal Release Receipt](docs/jira/v26.11.10/RECEIPT.md)
- **Architecture & System Design:**
  - [Architecture Overview](docs/architecture/overview.md)
  - [Control Plane Specification](docs/architecture/control-plane.md)
  - [Architectural Decision Records (ADRs)](docs/architecture/adr/README.md)
- **Integration & Tooling:**
  - [Igniter AST Mutation Guide](docs/integrations/igniter-ast-mutation.md)
  - [Ash Resource Integrations](docs/integrations/ash-resources.md)
  - [OCEL 2.0 Process Mining](docs/reference/telemetry-ocel.md)
- **Release Archives:**
  - Historical release records are preserved under [`docs/archive/jira/`](docs/archive/jira/).

---

## License

`ggen_igniter` is released under the MIT License. See [LICENSE](LICENSE) for details.
