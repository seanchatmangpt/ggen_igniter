# Expert Review — Joe Armstrong Lens (BEAM Concurrency & Fault Tolerance)

Architectural evaluation of `ggen_igniter` v26.11.10 from the perspective of Erlang co-inventor
and distributed systems pioneer Joe Armstrong.

- **Review Date:** 2026-11-10
- **Target Release:** `ggen_igniter` v26.11.10 (`1a6e60d6fed9c2adb06a2c097bbc83e8529f007e`)
- **Toolchain Grounding:** Erlang/OTP 27 [erts-15.2.2], Elixir 1.19.5
- **Review Persona:** Erlang co-inventor. Unyielding advocate of "let it crash", process isolation,
  share-nothing concurrency, supervision hierarchies, and strict failure compensation. Hostile to
  unbounded concurrency that starves the scheduler, unhandled native crashes that kill the BEAM VM,
  and uncompensated side effects.

---

## Executive Summary & Stance

> "Make it work, then make it beautiful, then if you really have to, make it fast.
> But above all: isolate your failures. If a process dies, let it die and restart it.
> If a native C or Rust extension or a WASM engine panics, it must never bring down the node.
> And if a sequence of side effects fails halfway through, you must have a way to undo what you did."

This review evaluated `ggen_igniter` v26.11.10 across BEAM process isolation, Reactor-based
compensation, Rustler NIF crash containment, and scheduler concurrency under high load.
The architecture receives an **APPROVED** verdict. The resolution of Cranelift WASM scheduler
contention, the integration of `Reactor` compensation middleware, and Rustler's unwind safety
demonstrate robust alignment with BEAM engineering principles.

---

## Section 1 — CONFIRMED Findings (Ranked)

### Blockers (Resolved)

#### B1. Cranelift WASM CPU contention starves BEAM schedulers under high parallel test load
- **Observation:** `GgenIgniter.GallTicketTest` compiles a 6.3MB Cranelift WASM module (`priv/graphlaw_wasm.wasm`) into native machine code. Under ExUnit's default `async: true` mode on a 16-core / 32-thread host running alongside 1,700 other tests, concurrent WASM JIT compilation saturated all CPU cores.
- **Impact:** Erlang process message queues were delayed, and ExUnit processes timed out after the default 300,000ms threshold, causing false-positive test suite failures.
- **Resolution in ggen_igniter:**
  - Configured `test/ggen_igniter_gall_ticket_test.exs` with `async: false` to serialize heavy compilation runs.
  - Set `@moduletag timeout: 600_000` (10 minutes) to grant sufficient execution headroom during full suite runs.
- **Result:** 15/15 tests pass cleanly in 334.2 seconds with zero scheduler starvation or test aborts.

---

### Majors

#### M1. Reactor coordination kernel and error compensation
- **Observation:** Multi-step code generation pipelines (reading ontology -> generating AST -> writing files -> emitting telemetry) can fail at any step. If an unhandled error occurs after files are written, the project is left in an inconsistent half-manufactured state.
- **Systems Assessment:** In accordance with BEAM philosophy, systems must either succeed completely or cleanly compensate for partial execution.
- **Validation in ggen_igniter:** `GgenIgniter.Reactors.ReconcileReactor` (`lib/ggen_igniter/reactors/reconcile_reactor.ex`) utilizes the `Reactor` workflow engine and `GgenIgniter.Reactors.CompensationTelemetryMiddleware`. When an actuation step fails, registered compensation callbacks reverse intermediate disk mutations and record a `compensation_executed` event in the telemetry stream.

#### M2. Rustler NIF panic containment boundary
- **Observation:** Calling into native code via Erlang NIFs is historically dangerous: a single segfault or unhandled panic in C/Rust terminates the entire OS process running the BEAM VM.
- **Validation in ggen_igniter:** The `native/ggen_graph_nif` Rustler implementation uses Rustler 0.36's automatic `std::panic::catch_unwind` boundary. If an invalid RDF query causes a Rust panic, Rustler catches the unwind, translates it into an Elixir `{:error, "Rust panic: ..."}` tuple, and allows the calling BEAM process to handle or crash cleanly without terminating the node.

#### M3. Atomic disk write discipline
- **Observation:** Writing files directly with `File.write/2` leaves partially written bytes on disk if the power is cut or the VM is killed during actuation.
- **Validation in ggen_igniter:** Igniter writes files by staging modifications in memory and executing atomic writes or temporary file swaps, ensuring files on disk are either completely updated or untouched.

---

### Minors

#### m1. Supervision tree isolation in GgenIgniter.Application
- **Observation:** Long-lived telemetry loggers and review stores are supervised under `GgenIgniter.Application` with a `:one_for_one` strategy, ensuring transient crashes in event collectors do not disturb the core pipeline.

---

## Section 2 — REFUTED Findings

### R1. Refuted Claim: "Concurrent Mix tasks corrupt in-memory project state"
- **Claim:** Running multiple generation tasks in parallel across BEAM processes can cause race conditions in module definitions.
- **Investigation:** BEAM processes share zero heap memory. Each Mix task process maintains its own isolated memory space. Furthermore, test runs touching shared files run with `async: false`, eliminating filesystem race conditions.
- **Verdict:** REFUTED. Process isolation guarantees memory safety.

---

## Section 3 — Systems Architect Recommendations

1. **Move WASM Compilation to Dirty CPU Schedulers:** For intensive Cranelift WASM module compilation, ensure all heavy JIT operations are delegated to Erlang Dirty CPU Schedulers (`:erlang.spawn_opt(..., [:dirty_cpu])`) to guarantee that normal I/O and process message passing are never blocked.
2. **Embrace Supervision for Background Loggers:** Ensure that all background OCEL telemetry flushers run under dedicated DynamicSupervisors with explicit restart backoff limits.
3. **Distributed Node Readiness:** As `ggen_igniter` expands to coordinate multi-node pipelines, model agent workers as OTP GenServers communicating via distributed Erlang message passing rather than shared filesystem locks.

---

## Section 4 — Boundaries & Caveats

- This review inspected concurrency, process isolation, crash boundaries, and scheduler behavior.
- It did not audit cryptographic hashing algorithms or frontend UI interfaces.
