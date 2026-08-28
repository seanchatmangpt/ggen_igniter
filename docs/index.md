# Documentation Index

`ggen_igniter` docs organized [Diataxis](https://diataxis.fr)-style: Tutorials
(learn by doing), How-to guides (accomplish a specific task), Reference
(look up a fact), Explanation (understand why it works this way). Start with
[the README](../README.md) for the project's first-screen summary, or
[status.md](status.md) for what's really implemented today.

## Tutorials — learn by doing

Step-by-step, in order. Every command in these was actually run and its real
output pasted in.

1. [Getting Started](tutorials/getting-started.md) — install, compile,
   `mix ggen_igniter.doctor`, your first `mix ggen_igniter.sync` run.
2. [Your First Pack](tutorials/first-pack.md) — the `priv/ggen/<pack>/`
   convention, using this repo's own `test/fixtures/sample-pack/`.
3. [Your First Reconciliation](tutorials/first-reconciliation.md) —
   self-contained frontmatter templates, the reconciliation manifest, and
   what `--on-stale refuse/prune/preserve` actually does to a renamed
   ontology's old output.
4. [The Reactor Path](tutorials/reactor-path.md) — opting into the
   `ReconcileReactor` coordinator and reading a real success receipt and a
   real compensated-failure receipt.

## How-to guides — accomplish a task

- [Adding a Pack](contributing/adding-a-pack.md) — directory shape, query/
  template discovery rules, manifest-key implications, marketplace fetch.
- [Adding a Step to `ReconcileReactor`](contributing/adding-a-reactor-step.md)
  — the step DSL, `compensate/4` vs `undo/4`, where new coordination logic
  does and does not belong.
- [Testing](contributing/testing.md) — running the suite, property tests,
  the separate `mix e2e` tier, known seed-dependent flakiness.
- [Debugging](operations/debugging.md) — `mix ggen_igniter.doctor`'s 17
  checks, known open gaps, a practical triage order for a broken build.
- [Failure Recovery](operations/failure-recovery.md) — reading a receipt,
  the four standings, the practical recovery playbook for each one.

## Reference — look up a fact

**CLI**

- [CLI overview](reference/cli/index.md)
- [`mix ggen_igniter.sync`](reference/cli/sync.md) — every flag
- [`mix ggen_igniter.doctor`](reference/cli/doctor.md) — all 17 checks
- [Packs](reference/cli/packs.md) — `--pack`/`--pack-dir`/`--pack NAME:TEMPLATE`
- [Engines](reference/cli/engines.md) — `oxigraph`/`sparql`/`qlever`

**Reactor** (opt-in coordination pipeline)

- [Overview](reference/reactor/overview.md)
- [Steps](reference/reactor/steps.md) — the real 9-step dependency graph
- [Failure Semantics](reference/reactor/failure-semantics.md) — the four standings
- [Compensation](reference/reactor/compensation.md) — `compensate/4` vs `undo/4`
- [Concurrency](reference/reactor/concurrency.md) — what actually runs in parallel

**Reconciliation**

- [Manifest](reference/reconciliation/manifest.md)
- [Idempotency](reference/reconciliation/idempotency.md)
- [Stale Artifacts](reference/reconciliation/stale-artifacts.md) — `--on-stale` policies
- [Destructive Evolution](reference/reconciliation/destructive-evolution.md) — rename/remove behavior per ontology-element kind

**Evidence**

- [Receipts](reference/evidence/receipts.md)
- [Standing](reference/evidence/standing.md)
- [OCEL Event Log](reference/evidence/ocel.md)
- [Telemetry](reference/evidence/telemetry.md)
- [Recovery](reference/evidence/recovery.md) — compensation and evidence ordering

**Operations**

- [Runtime Topology](operations/runtime.md) — what starts, which pipeline runs
- [Controller](operations/controller.md)

## Explanation — understand why

**Architecture**

- [Overview](architecture/overview.md) — real ownership table (ggen/Igniter/Ash/Reactor/OTP/Controller/Manifest/Receipt), CURRENT vs. TARGET
- [Component Boundaries](architecture/component-boundaries.md)
- [Control Plane](architecture/control-plane.md) — OTP supervision, the two opt-in flags
- [Reconciliation Lifecycle](architecture/reconciliation-lifecycle.md) — both pipelines' real step graphs, diagrammed
- [State Model](architecture/state-model.md) — Manifest vs. Receipt vs. Controller state
- [Architecture Decision Records](architecture/adr/) — accepted decisions, grounded in current code

**Integrations**

- ggen: [Semantic Compilation](integrations/ggen/semantic-compilation.md), [Packs](integrations/ggen/packs.md), [Planning Boundary](integrations/ggen/planning-boundary.md)
- Igniter: [Project Actuation](integrations/igniter/project-actuation.md), [AST Mutation](integrations/igniter/ast-mutation.md), [Safety](integrations/igniter/safety.md)
- Ash (optional): [Overview](integrations/ash/overview.md), [Domains](integrations/ash/domains.md), [Resources](integrations/ash/resources.md), [Actions](integrations/ash/actions.md), [Reactor vs. Ash.Reactor](integrations/ash/reactor.md)
- Phoenix (optional): [Overview](integrations/phoenix/overview.md), [LiveView](integrations/phoenix/liveview.md)

**Testing philosophy**

- [Chicago-School Discipline](testing/chicago.md)
- [Concurrency](testing/concurrency.md)
- [Failure Injection](testing/failure-injection.md)
- [Definition of Done](testing/definition-of-done.md) — the four-criterion scorecard
- [E2E Lifecycle](testing/e2e-lifecycle.md)
- [Adversarial Verification](testing/adversarial.md)

**Contributing rules**

- [Architecture Rules](contributing/architecture-rules.md) — who owns what, four hard invariants

## Project-level reference

- [Glossary](glossary.md) — one canonical definition per term
- [Status](status.md) — real IMPLEMENTED/PARTIAL_ALIVE/PLANNED status of every capability
- [Documentation Audit](DOCUMENTATION_AUDIT.md) — classification of every `.md` file in this repo as of 2026-08-27
