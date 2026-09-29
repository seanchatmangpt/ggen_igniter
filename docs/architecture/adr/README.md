# Architecture Decision Records

Each ADR here is grounded in **current implementation** — real code read
directly, cited by file:line, with a real passing test run where one exists
— not in a plan or an aspiration. **Accepted** means the decision is live in
`lib/` today, not merely proposed. Where a decision has a real, disclosed
gap (e.g. real but opt-in, or real but only on one of two coexisting
pipelines), that is stated in the ADR's own Consequences section rather than
inflating the status.

The table below is generated, not hand-maintained: it is reconciled from
`priv/ggen/adr-index-pack/ontology.ttl` (one `adr:Decision` individual per
ADR) via

    mix ggen_igniter.sync --pack adr-index-pack --engine sparql \
      --out docs/architecture/adr/README.md

Add a new ADR to this index by adding an `adr:Decision` individual to that
ontology and re-running the command above -- never by hand-editing the
table below directly (a future re-run would just overwrite a hand-edit).

| ADR | Title | Status |
|---|---|---|
| [0001](0001-oxigraph-default-query-engine.md) | Oxigraph as the default SPARQL query engine | Accepted |
| [0002](0002-ash-phoenix-optional-consumer-side.md) | Ash and Phoenix remain optional, consumer-side integrations | Accepted |
| [0003](0003-plain-reactor-for-coordination.md) | Plain Reactor (not Ash.Reactor) for the target coordination pipeline | Accepted |
| [0004](0004-manifest-keyed-by-recipe-identity.md) | Reconciliation manifest keyed by `(template_path, out_template)` recipe identity | Accepted |
| [0005](0005-receipt-independent-of-manifest.md) | Receipt as an independent, append-only attempt history distinct from the Manifest | Accepted |
| [0006](0006-marker-based-injection-not-ast-patch.md) | Marker-based line splice for injection, deferring real AST-based mutation | Accepted |
| [0007](0007-sync-always-attempts-receipts.md) | `mix ggen_igniter.sync` Always Attempts the Reactor Pipeline (Receipts on Every Run), Gated Only by Delegatability | Accepted |
| [0008](0008-evidence-ranked-multi-engine-registry.md) | Evidence-Ranked Multi-Engine Registry for `--engine` Comparison Mode | Accepted |
| [0009](0009-runtime-shape-semantic-ir.md) | RuntimeShape as the shared admitted semantic IR | Accepted |
| [ADR-001](ADR-001-reactor-coordination-kernel.md) | Reactor as the Coordination Kernel | Accepted (`IMPLEMENTED`) |
| [ADR-002](ADR-002-igniter-structured-elixir-mutation.md) | Igniter & Structured Elixir Mutation Boundaries | Accepted (`PARTIAL_ALIVE` / `PLANNED`) |
| [ADR-003](ADR-003-ggen-semantic-compilation.md) | ggen Semantic Compilation Integration | Accepted (`IMPLEMENTED`) |
| [ADR-004](ADR-004-ash-optional-integration.md) | Ash Framework Optional Integration Boundary | Accepted (`IMPLEMENTED`) |
| [ADR-005](ADR-005-manifest-manufacturing-ownership.md) | Manifest Manufacturing Ownership & Stale Detection | Accepted (`IMPLEMENTED`) |
| [ADR-006a](ADR-006-actuation-single-boundary.md) | Single Actuation Boundary & Deferred Execution | Accepted (`IMPLEMENTED`) |
| [ADR-006b](ADR-006-generational-resilience-manufacture.md) | Generation-Bound Cyber-Resiliency Manufacture | Accepted for v26.9.26 experimental implementation |
| [ADR-007](ADR-007-compensation-restores-state-preserves-evidence.md) | Compensation Restores State While Preserving Evidence | Accepted (`IMPLEMENTED`) |
| [ADR-008](ADR-008-cli-as-adapter.md) | CLI as a Thin Adapter over the Kernel | Accepted (`IMPLEMENTED`) |
| [ADR-009](ADR-009-a2a-pack-local-vocabulary.md) | Pack-local `a2a:` vocabulary for the Semantic Jira A2A projection | Accepted |
| [ADR-010](ADR-010-event-sourced-standing.md) | Event-sourced standing (definition_digest + append-only log) | Accepted |
| [ADR-011](ADR-011-reduce-sj-toward-public-vocabularies.md) | Reduce `sj:` toward oslc_cm/dcterms/PROV-O/SHACL | PLANNED |
| [ADR-012](ADR-012-prose-never-originates-work-orders.md) | Prose never originates work orders | Accepted |

See `docs/status.md` for the current implementation status of the systems
these decisions govern, and `docs/architecture/overview.md` for how they fit
into the whole system.
