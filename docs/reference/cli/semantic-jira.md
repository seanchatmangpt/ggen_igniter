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

## Frontier to XaaS and back

The next three tasks close the loop between the frontier and the XaaS/Ultracode
fabric. They are pure projections: they select nothing, lease nothing and move
no standing (`GgenIgniter.SemanticJira.Descriptor`, `.Observation`).

### `mix semantic_jira.descriptor`

```bash
mix semantic_jira.descriptor --work-orders PATH --ledger PATH --identity ID \
  --alias owner/repo=alias --verifier-suite NAME [--out PATH]
```

Refuses unless `ID` is on the current frontier of the ledger projection. Prints
the exact key set `Xaas.Ultracode.SemanticWork.admit/1` requires
(`work_order_iri`, `checkpoint_iri`, `graph_digest`, `repository_identity`,
`execution_repo_alias`, `base_sha`, `goal`, `provider` = `zcode`,
`verifier_suite`, `execution_policy` = `autonomic_wave_attempt`,
`dependencies`) plus one extra key, `bridge`. XaaS keeps unknown keys, so the
whole object can be passed to `SemanticWork.materialize/2` unchanged; XaaS must
echo `bridge` verbatim in its receipt export. `--alias` (repeatable) and
`--verifier-suite` are required: nothing is defaulted. Dependencies come from
the ledger's ALIVE events (`receipt_digest`, `receipt_iri`), never from the
work order.

`bridge`:

| Key | Meaning |
| --- | --- |
| `identity`, `definition_digest` | Stable identity of the work order definition. |
| `source_snapshot_digest` | Projected snapshot the worker was given. |
| `ledger_tail` | Ledger tail at descriptor time (also encoded in `checkpoint_iri`). |
| `repository`, `base_sha`, `subject`, `evidence_ceiling`, `replay_identity` | Bound onto the receipt. |
| `requires` | `courts`, `acceptance`, `falsifiers` the receipt must speak to. |

### `mix semantic_jira.xaas_receipt`

```bash
mix semantic_jira.xaas_receipt --bridge PATH --xaas-receipt PATH [--out PATH]
```

`--bridge` is the descriptor's `bridge` (or the whole descriptor). The XaaS
receipt export is:

```json
{"epoch_id": "...", "run_id": "...", "receipt_id": "...",
 "receipt_digest": "sha256:...", "outcome": "alive",
 "final_head": "<40-hex>", "head_verified": true,
 "fabric_verifier": {"status": "pass",
   "steps": [{"id": "court:test", "status": "pass"}],
   "court_receipt": {"acceptance_results": {"...": true},
                     "falsifier_results": {"...": "survived"}}},
 "bridge": {}}
```

`receipt_digest` is `sha256:` + hex of the canonical JSON (recursively
key-sorted, compact) of the receipt without that key
(`Descriptor.receipt_digest/1`). Output feeds `mix semantic_jira.reconcile
--receipt`. Refusals (exit `1`, JSON on stderr): `invalid_receipt_digest`,
`receipt_digest_mismatch`, `bridge_mismatch`, `invalid_final_head`,
`unsupported_outcome`, `head_verified_not_boolean`,
`alive_without_head_verification`, `alive_without_verifier_pass`. Standing is
never inferred from `outcome`: a required court passes only on a passing step
with that exact `id`; acceptance and falsifier results come only from
`court_receipt` and only count when the fabric verifier passed; fabric-only
evidence reaches at most the `repository-local` ceiling.

### `mix semantic_jira.observe`

```bash
mix semantic_jira.observe --finding PATH --base-work-order PATH \
  [--ontology PATH] [--repair PATH] [--identity ID] [--out PATH]
```

Runs the kernel's `process_finding/1` (and `repair_work_order/2` with
`--repair`), maps the result onto a candidate WorkOrder that reuses the base
order's typed courts, evidence, projections and path scope, admits it with the
kernel, then validates its RDF node against the pack shapes over the canonical
graph (`--ontology`, default the pack ontology) so global uniqueness constraints
apply. Prints the admitted work order, its Turtle and the SHACL report; writes
nothing to the graph.

Every task in this section: success prints JSON on stdout (and to `--out`);
a refusal or bad invocation prints typed JSON on stderr and exits `1` or `2`.

## See Also

- `lib/ggen_igniter/semantic_jira/reconciler.ex` — pure projection and reconcile
- `lib/ggen_igniter/semantic_jira/ledger.ex` — file-backed ledger and locking
- `lib/ggen_igniter/semantic_jira/descriptor.ex` — descriptor and XaaS receipt contract
- `lib/ggen_igniter/semantic_jira/observation.ex` — observation edge
