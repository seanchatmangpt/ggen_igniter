# Architecture Decision Records

Each ADR here is grounded in **current implementation** — real code read
directly, cited by file:line, with a real passing test run where one exists
— not in a plan or an aspiration. **Accepted** means the decision is live in
`lib/` today, not merely proposed. Where a decision has a real, disclosed
gap (e.g. real but opt-in, or real but only on one of two coexisting
pipelines), that is stated in the ADR's own Consequences section rather than
inflating the status.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-oxigraph-default-query-engine.md) | Oxigraph as the default SPARQL query engine | Accepted |
| [0002](0002-ash-phoenix-optional-consumer-side.md) | Ash and Phoenix remain optional, consumer-side integrations | Accepted |
| [0003](0003-plain-reactor-for-coordination.md) | Plain Reactor (not Ash.Reactor) for the target coordination pipeline | Accepted |
| [0004](0004-manifest-keyed-by-recipe-identity.md) | Reconciliation manifest keyed by `(template_path, out_template)` recipe identity | Accepted |
| [0005](0005-receipt-independent-of-manifest.md) | Receipt as an independent, append-only attempt history distinct from the Manifest | Accepted |
| [0006](0006-marker-based-injection-not-ast-patch.md) | Marker-based line splice for injection, deferring real AST-based mutation | Accepted |

See `docs/status.md` for the current implementation status of the systems
these decisions govern, and `docs/architecture/overview.md` for how they fit
into the whole system.
