# `mix semantic_jira.*` — receipt reconciler CLI

Receipts are the clock: a verified receipt becomes an append-only, hash-chained
standing transition, and the projection feeds the next frontier. A WorkOrder's
standing is never edited in place; it is projected from the ledger.

## `mix semantic_jira.reconcile`

```bash
mix semantic_jira.reconcile --work-orders PATH --ledger PATH --receipt PATH
```

| Flag | Meaning |
| --- | --- |
| `--work-orders PATH` | JSON array of WorkOrders, or `{"work_orders": [...]}`. |
| `--ledger PATH` | ndjson standing ledger; created on first append. |
| `--receipt PATH` | JSON receipt (fields in `GgenIgniter.SemanticJira.Reconciler.reconcile/3`). |

Prints one JSON object. Exit `0`: `applied` or `already_applied` (same
`receipt_digest` replayed). Exit `1`: typed refusal, for example
`{"status":"refused","reason":["reconcile_refused","definition_mismatch"]}`.
Exit `2`: invalid invocation.

## `mix semantic_jira.frontier`

```bash
mix semantic_jira.frontier --work-orders PATH --ledger PATH
```

Prints `eligible`, `blocked`, `standings` (identity to projected standing),
`events` and `ledger_tail`. A tampered ledger is refused with exit `1`, never
silently projected.

## See Also

- `lib/ggen_igniter/semantic_jira/reconciler.ex` — pure projection and reconcile
- `lib/ggen_igniter/semantic_jira/ledger.ex` — file-backed ledger and locking
