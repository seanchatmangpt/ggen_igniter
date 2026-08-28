# Control Plane Architecture: Controller vs CLI Adapter

> [!NOTE]
> **Core Architectural Principle:** In this documentation suite, **observed implementation outranks intended architecture**.
> Every architectural claim is explicitly labeled with its empirical status: `IMPLEMENTED`, `PARTIAL_ALIVE`, `PLANNED`, `UNSUPPORTED`, or `DEPRECATED`.

This document contrasts the persistent BEAM-native control plane (`GgenIgniter.Controller`) with the ephemeral CLI adapter (`Mix.Tasks.GgenIgniter.Sync`).

---

## 1. Architectural Comparison

```mermaid
flowchart TD
    subgraph EphemeralCLI["CLI Mode: mix ggen_igniter.sync"]
        UserCLI[Developer / Terminal] --> MixTask[Mix.Tasks.GgenIgniter.Sync]
        MixTask --> Pipeline1[GgenIgniter.Reconcile.run / ReconcileReactor]
        Pipeline1 --> Disk1[Disk Manifest: manifest.json]
        Disk1 -.-> OSExit[Process Exits: State Destroyed]
    end

    subgraph BEAMNative["Persistent Control Plane: GgenIgniter.Controller"]
        AppTree[OTP Supervision Tree] --> ControllerProc[GgenIgniter.Controller (GenServer)]
        Caller[LiveView / Ash / Test Suite / CLI] -->|GenServer.call| ControllerProc
        ControllerProc --> Pipeline2[GgenIgniter.Reconcile.run / ReconcileReactor]
        ControllerProc --> InMemState[In-Process State Map<br/>reconciliation_count, history, receipts]
        InMemState -.-> PreservedState[State Preserved Across Invocations]
    end
```

---

## 2. Key Differences & Operational Matrix

| Dimension | CLI Entrypoint (`mix ggen_igniter.sync`) | Persistent Controller (`GgenIgniter.Controller`) | Status |
|---|---|---|---|
| **Lifecycle Model** | Ephemeral OS process; booted on command, killed on completion. | Persistent OTP `GenServer` living in the BEAM application tree. | `IMPLEMENTED` |
| **State Continuity** | Zero in-memory continuity across runs. Prior state recoverable only from disk (`manifest.json`). | Holds live in-process state across successive `reconcile/2` calls. | `IMPLEMENTED` |
| **Reconciliation Counter** | Cannot distinguish re-runs from first runs without disk timestamps. | Tracks exact in-memory `reconciliation_count` per `pack_key`. | `IMPLEMENTED` |
| **Fault Isolation** | Pipeline crash halts the entire Mix task and exits the OS process. | Catches pipeline exceptions in `handle_call/3`, returning `{:error, reason}`; process stays alive and other pack keys remain unaffected. | `IMPLEMENTED` |
| **Delegation Path** | Detects running `GgenIgniter.Controller` via `Process.whereis/1` and delegates when within bounded scope. | Direct public API: `reconcile/3`, `status/2`. | `IMPLEMENTED` |

---

## 3. Controller State Model & Invariants

The `GgenIgniter.Controller` state maintains an explicit map of reconciliation records:

```elixir
%{
  last_reconciliations: %{
    pack_key => %{
      ontology_path: String.t(),
      manifest: %{optional(String.t()) => atom()},
      reconciliation_count: pos_integer(),
      last_run_at: DateTime.t(),
      receipt: map()
    }
  }
}
```

### Invariants:
1. **Fault Quarantine:** A failure reconciling key $A$ leaves the stored record of key $B$ strictly unmodified.
2. **Economic Claim:** In-process status queries (`Controller.status(server, pack_key)`) resolve in $\mathcal{O}(1)$ time without reading the filesystem.
3. **Supervision Boundary:** Controller startup is gated behind `Application.get_env(:ggen_igniter, :start_controller, false)` (opt-in).
