# ADR-005: Manifest Manufacturing Ownership & Stale Detection

## Status
Accepted (`IMPLEMENTED`)

## Context
When an ontology evolves (e.g. renaming an entity or deleting a resource), stateless code generators leave orphaned files on disk, causing build breaks or obsolete modules.

## Decision
Maintain a persistent reconciliation manifest at `.ggen_igniter/manifest.json` keyed by `recipe_key = template_path => out_template`. Track all previously written outputs and calculate stale paths: $\text{stale} = \text{old\_paths} \setminus \text{new\_paths}$.

## Rationale
Keying on `(template, out_template)` ensures stability across in-place ontology edits while enabling automated detection of renames and removals.

## Consequences
- **Positive:** Explicit stale output handling with safety modes (`refuse`, `prune`, `preserve`).
- **Trade-off:** Requires writing and reading `manifest.json` in the consumer project.
