# v26.9.27 ledger paydown plan (epoch-008)

Law: the 1% ledger shrinks monotonically per milestone; growth requires a paydown plan in the same change. `HANDWRITTEN.md` carries 16 rows (2026-09-19 → 2026-09-24). Every row's 26.10.1 disposition follows; CARRY rows name the exact missing capability and owner pack — a CARRY without a retirement condition is a violation to fix before the boundary.

| row (date) | disposition | owner pack | retirement condition |
|---|---|---|---|
| semantic-jira pack-integration proof tests (2026-09-19) | EXTRACT | semantic-jira-pack test-manufacturing family (`sj:ledger-unsupported-001`) | pack-integration-proof generator admitted → row retires |
| goal-checkpoint admission proofs + fixture (2026-09-22) | EXTRACT | same family (`sj:ledger-unsupported-002`) | mutation-case generator over `sh:*` constraints admitted |
| SHACL engine repairs (shacl.ex, kernel_differential.ex; 2026-09-22) | REGENERATE | an admitted SHACL engine (hex or NIF) | engine replaces `GgenIgniter.SemanticJira.Shacl` → edits and row retire with the court |
| sJira kernel/CLI refusal semantics (2026-09-23) | EXTRACT | semantic-jira-pack kernel-contract facts + `templates/cli_task.ex.eex` | refusal/option clauses rendered byte-identical from the pack (wave W3) |
| WO-03 Chicago proof tests (2026-09-23) | EXTRACT | test-manufacturing family (`sj:ledger-unsupported-001`) | same as row 1 |
| prose observe-only surface (2026-09-23, paydown partially realized) | EXTRACT | `sj:ledger-unsupported-003` + byte-span engine gap | engine exposes byte-span access; proof generator emits per-rule refusal cases |
| six sJira CLI task shells (2026-09-23, measured: igniter.gen.task emits wrong task type) | EXTRACT | `templates/cli_task.ex.eex` over option-schema facts | six shells rendered byte-identical; this is the measured paydown — the generator gap was reproduced, not assumed |
| observation edge (observation.ex; 2026-09-23) | EXTRACT | pack CONSTRUCT query (`prose/delta.construct.rq` pattern) | candidate manufactured by query; Elixir residue shrinks to SHACL invocation |
| remaining rows (2026-09-19…24, same families) | EXTRACT per family rule | as named in each row | each row already carries its retirement condition |

## Epoch disposition

1. Before the v26.10.1 stamp: the EXTRACT rows are the extraction backlog's order-1/2 families (extraction-backlog.md) — their paydown IS wave W1–W3.
2. At the boundary the ledger may only shrink: every v26.10.1 fresh residue row must be NEW hand-written semantics with a `UNSUPPORTED(generator, element)` row and a paydown plan in the same change.
3. A v26.10.1 manufacture that re-creates a retired row's semantics by hand is REFUSED at review: the pack facts exist; the generator owns the mutation.
