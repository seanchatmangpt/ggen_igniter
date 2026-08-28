# Adversarial & Destructive Verification

Adversarial testing evaluates system boundaries against edge cases, hostile inputs, engine divergences, and destructive ontology evolutions.

Status: **PARTIAL**. Core destructive change suites and manifest pruning are verified green; known engine and cross-file ripple constraints remain documented.

---

## 1. Destructive Ontology Changes & Orphan Reconciliation

When an ontology undergoes destructive changes (such as renaming or deleting an entity), code generators risk leaving orphaned artifacts on disk that continue to compile and cause subtle bugs.

[`test/ggen_igniter_destructive_change_agent3_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_destructive_change_agent3_test.exs) exercises 10 destructive evolution shapes against real `mix ggen_igniter.sync` runs:

| Scenario | Ontology Fixture | Destructive Delta | Verification |
|---|---|---|---|
| 1 | `ontology_v2_add_attribute.ttl` | Add attribute (`:priority`) | Super-set check (new attribute present, old retained) |
| 2 | `ontology_v3_rename.ttl` | Rename attribute (`assignee` $\to$ `assigned_to`) | Old field removed, new field present in AST |
| 3 | `ontology_v4_remove_attribute.ttl` | Remove attribute (`status`) | Attribute removed from resource AST |
| 4 | `ontology_v5_rename_action.ttl` | Rename action (`archive` $\to$ `close`) | Action block renamed, old action gone |
| 5 | `ontology_v6_remove_action.ttl` | Remove action (`archive`) | Action block completely removed |
| 6 | `ontology_v7_rename_relationship.ttl` | Rename relationship (`customer` $\to$ `client`) | Relationship block updated |
| 7 | `ontology_v8_remove_relationship.ttl` | Remove relationship (`customer`) | Relationship block completely removed |
| 8 | `ontology_v9_rename_resource.ttl` | Rename resource (`Ticket` $\to$ `Case`) | New resource created; old `ticket.ex` pruned when `--on-stale prune` is active |
| 9 | `ontology_v10_remove_resource.ttl` | Remove resource (`Ticket`) | `ticket.ex` deleted from disk under `--on-stale prune` |
| 10 | `ontology_v11_change_domain_association.ttl` | Change domain association | Domain registration updated |

### Reconciling Stale Artifacts
[`test/ggen_igniter_reconciliation_manifest_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_reconciliation_manifest_test.exs) tests `--on-stale` modes:
- **`--on-stale refuse` (Default)**: If an ontology rename creates orphaned files, sync fails closed before performing any disk writes.
- **`--on-stale prune`**: Stale output paths tracked by `.ggen_igniter/manifest.json` are automatically deleted via `File.rm/1`.
- **`--on-stale preserve`**: Leaves stale files on disk but stops tracking them in the manifest.

---

## 2. Engine Divergences & Literal Quoting Discrepancies

### Oxigraph vs. SPARQL String Literal Quoting
During cross-engine verification ([`test/ggen_igniter_cross_engine_equivalence_properties_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_cross_engine_equivalence_properties_test.exs)), an adversarial discrepancy was discovered:
- **Oxigraph NIF**: Wraps untyped string literals in N-Triples double quotes:
  ```text
  "\"SupportDesk.Support.Ticket\""
  ```
- **SPARQL.ex (Hex)**: Returns bare string terms:
  ```text
  "SupportDesk.Support.Ticket"
  ```
- **Mitigation & Testing**:
  In templates used with both engines, paths and variables normalize quotes (`String.replace(var, "\"", "")`), and property tests verify equivalence after canonical normalization.

---

## 3. Conflicting Injection Rules & Safety Invariants

[`test/ggen_igniter_actuate_properties_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_actuate_properties_test.exs) validates the strict, non-ambiguous precedence order of `GgenIgniter.Actuate.write_file!/3`:

```text
1. unless_exists: true && target exists       --> :skipped_exists
2. skip_if: pattern && target matches         --> :skipped_match
3. target exists && content byte-identical    --> :unchanged
4. otherwise                                  --> :written
```

### Invariant Proofs:
- **`unless_exists` Short-Circuit**: If a file exists, `unless_exists: true` returns `:skipped_exists` even if the content matches identically (precedence over `:unchanged`).
- **`skip_if` Precedence**: If content contains the skip marker, `:skipped_match` is returned regardless of whether new content is identical or different.
- **Idempotency ($\mu(\mu(O)) = \mu(O)$)**: Writing the same content twice sequentially always returns `{:ok, :written}` followed by `{:ok, :unchanged}`, with unchanged `mtime`.

---

## 4. Cyclic Imports & Broken Pack Discovery

[`test/ggen_igniter_pack_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_pack_test.exs) and [`test/ggen_igniter_pack_discovery_matrix_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_pack_discovery_matrix_test.exs) test broken packs (`test/fixtures/broken-pack/`):
- Missing templates directory returns `{:error, :none}` cleanly.
- Missing `ontology.ttl` falls back gracefully to pack-level queries.
- Invalid frontmatter blocks raise structured `ArgumentError` without crashing the parent process.
