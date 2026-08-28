# State Model & Knowledge Projection

> [!NOTE]
> **Core Architectural Principle:** In this documentation suite, **observed implementation outranks intended architecture**.
> Every architectural claim is explicitly labeled with its empirical status: `IMPLEMENTED`, `PARTIAL_ALIVE`, `PLANNED`, `UNSUPPORTED`, or `DEPRECATED`.

This document delineates the distinct lifecycles in `ggen_igniter` and establishes the formal state projection model: $\text{ProjectOwnedState}_t = \text{Projection}(\text{AdmittedKnowledge}_t)$.

---

## 1. The Three Lifecycles

In autonomic software manufacturing, conflating workflow coordination with process supervision or application runtime causes subtle state corruption. `ggen_igniter` strictly separates three lifecycle tiers:

```mermaid
flowchart TD
    subgraph Tier1["1. Workflow Lifecycle (Coordination Kernel)"]
        W1[ReconcileReactor Execution] --> W2[Single Attempt Ephemeral DAG]
        W2 --> W3[Steps: observe -> load -> query -> render -> admit -> actuate -> verify -> finalize]
        W3 --> W4[Compensates or Finalizes within one invocation]
    end

    subgraph Tier2["2. Process Lifecycle (OTP Supervised Control Plane)"]
        P1[GgenIgniter.Application Tree] --> P2[GgenIgniter.Controller GenServer]
        P2 --> P3[Supervision & Restart Policies]
        P3 --> P4[In-Memory Continuity across multiple Workflow runs]
    end

    subgraph Tier3["3. Application Runtime (Project Domain State)"]
        A1[Customer Application Target] --> A2[Generated Ash / Phoenix Modules]
        A2 --> A3[Database Schemas & Business Logic]
        A3 --> A4[End-User Runtime Traffic]
    end

    Tier1 -->|Actuates Code into| Tier3
    Tier2 -->|Orchestrates| Tier1
```

| Lifecycle Tier | Entity / Boundary | State Storage | Reset Trigger |
|---|---|---|---|
| **Workflow Lifecycle** | `ReconcileReactor` instance | Transient Reactor Context | Every reconciliation run |
| **Process Lifecycle** | `GgenIgniter.Controller` | In-process GenServer state | Process crash / Node restart |
| **Application Runtime** | Host Project Source & Database | Disk (`.ex` files), DB tables | Recompile / Migration / Deploy |

---

## 2. Mathematical State Projection Model

$$\text{ProjectOwnedState}_t = \text{Projection}(\text{AdmittedKnowledge}_t)$$

Where:
- $\text{AdmittedKnowledge}_t = \mathcal{G}_t \cap \text{AdmittedRules}(\mathcal{P})$ is the verified knowledge graph content that passes admission invariants at time $t$.
- $\text{Projection}(\cdot)$ is the deterministic mapping defined by SPARQL queries and templates.
- $\text{ProjectOwnedState}_t$ represents the exact set of filesystem artifacts owned by the manufacturing recipe.

### Properties:
1. **Determinism:** Given identical $\text{AdmittedKnowledge}_t$, $\text{Projection}(\text{AdmittedKnowledge}_t)$ produces identical ASTs and byte contents.
2. **Safe Orphaning Elimination:** Any state $S \in \text{ProjectOwnedState}_{t-1} \setminus \text{ProjectOwnedState}_t$ is detected as *stale* and either safely pruned or refused before destructive loss.
3. **Immutability of History:** While $\text{ProjectOwnedState}_t$ reflects only the current projection, the evidence ledger $\mathcal{E}_t$ retains every historical attempt.
