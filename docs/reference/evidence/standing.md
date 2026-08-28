# Standing: Process & Audit Taxonomies

Status: **IMPLEMENTED** (Code-level closed set and step derivation verified against `lib/ggen_igniter/receipt.ex` and `lib/ggen_igniter/reactors/reconcile_reactor.ex`).

---

## 1. Standing Taxonomies: Code vs. System Audit

The term **standing** is used across `ggen_igniter` in two complementary contexts:
1. **Code-Level Process Standing**: A closed set of four atoms enforced by `GgenIgniter.Receipt` to record the physical and logical outcome of a reconciliation attempt.
2. **Factory / System Audit Standing**: The broader taxonomy used across audit matrices, verification reports, and findings ledgers to categorize claims, subsystem capabilities, and invariants.

---

## 2. Complete Taxonomy of Status Atoms & Concepts

### A. Code-Level Closed Set (`@standings`)

Defined in [`lib/ggen_igniter/receipt.ex`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/receipt.ex#L98-L101):
```elixir
@standings [:alive, :refused, :compensated, :build_broken]
```
`Receipt.new/1` raises `ArgumentError` if `:standing` is any value outside this four-atom set.

| Standing Atom | String Form | Definition & Physical State Criteria |
|---|---|---|
| **`:alive`** | `"alive"` | **Success**. All pipeline steps (`:observe`, `:load`, `:resolve`, `:query`, `:render`, `:admit`, `:actuate`, `:verify`, `:finalize_evidence`) completed without error. Files were written, compilation/formatting checks passed, and the production manifest advanced. |
| **`:refused`** | `"refused"` | **Fail-Closed Refusal Pre-Actuation**. The reconciliation attempt was halted *before* any filesystem mutations took place (e.g., path-traversal guard, duplicate output target collision, missing precondition, or `--on-stale refuse` with stale outputs). `files` list is empty, and `ACTUATION_STARTED` was never emitted. |
| **`:compensated`** | `"compensated"` | **Rolled Back After Semantic / Pipeline Failure**. Files were written to disk, but a subsequent step failed (for reasons other than a syntax/compilation error) or `:actuate`'s own batch write failed mid-stream. Reactor `undo/3` or internal self-heal restored all touched files, verified by `post_run_hash == pre_run_hash`. |
| **`:build_broken`** | `"build_broken"` | **Rolled Back After Compiler Failure**. Files were written to disk, but `:verify` (`mix compile --warnings-as-errors`) failed specifically due to generated syntax errors, missing module references, or compiler warnings. Compensation restored all files (`post_run_hash == pre_run_hash`). Distinguished from `:compensated` to isolate pack code generation bugs. |

### B. Extended Audit & Capability Taxonomy

The wider project architecture and audit ledgers use three additional status concepts:

| Status Atom / Token | Context | Definition & Assignment Criteria |
|---|---|---|
| **`:partial_alive`** / `PARTIAL_ALIVE` | Capability Matrix & Invariants | **Partially Implemented / Conditionally Active**. Used when an invariant or capability is fully implemented and tested on specific code paths (such as `ReconcileReactor.run/1`), but is not yet active across default or un-migrated paths (such as the legacy `Reconcile.run/1` or `Mix.Tasks.GgenIgniter.Sync` when `use_reactor: false`). |
| **`:unknown`** / `UNKNOWN` | Error Taxonomy & Unmapped States | **Unclassified / Diagnostic Fallback**. Used in `ReconcileReactor.failed_step_info/1` when Reactor returns an unrecognized error structure (`{:unknown, other}`), defaulting conservatively to `:refused` standing. |
| **`:unsupported`** / `UNSUPPORTED` | Feature Boundaries & Guard Rails | **Explicitly Refused / Out of Scope**. Assigned when a feature or specification is parsed but rejected by fail-closed guards (e.g., unsupported injection options like `scope: "file"` or `occurrence: "last"` in `MatchRule`). |

---

## 3. Assignment Criteria in `ReconcileReactor`

In `GgenIgniter.Reactors.ReconcileReactor`, standings are assigned via two distinct paths:

### 1. The Success Path (`:finalize_evidence`)
When `:admit`, `:actuate`, and `:verify` all succeed, `:finalize_evidence` constructs an `:alive` receipt directly ([`reconcile_reactor.ex:1075-1095`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/reactors/reconcile_reactor.ex#L1075-L1095)).

### 2. The Failure Path (`run/1` and `standing_for_failure/2`)
On any `{:error, error}` returned by `Reactor.run/4`, `ReconcileReactor.run/1` extracts `{step_name, reason}` via `failed_step_info/1` and evaluates `standing_for_failure/2` ([`reconcile_reactor.ex:504-528`](file:///Users/sac/ggen_igniter/lib/ggen_igniter/reactors/reconcile_reactor.ex#L504-L528)):

```elixir
def standing_for_failure(step_name, reason) do
  cond do
    step_name in [
      :observe_prior_manifest,
      :load_ontology,
      :resolve_pack,
      :run_queries,
      :render,
      :admit
    ] ->
      :refused

    step_name == :verify ->
      case reason do
        {:compile_failed, _output} -> :build_broken
        _ -> :compensated
      end

    step_name in [:actuate, :finalize_evidence] ->
      :compensated

    true ->
      :refused
  end
end
```

### Assignment Decision Matrix

| Failed Pipeline Step | Error Shape / Reason | Assigned Standing | Physical State on Disk |
|---|---|---|---|
| `:observe_prior_manifest` | Missing manifest / parse error | `:refused` | Untouched |
| `:load_ontology` | Missing `.ttl` / invalid RDF | `:refused` | Untouched |
| `:resolve_pack` | Pack directory or query not found | `:refused` | Untouched |
| `:run_queries` | SPARQL query syntax / engine error | `:refused` | Untouched |
| `:render` | EEx syntax error / unbound variable | `:refused` | Untouched |
| `:admit` | Duplicate target collision, unowned delete, or stale outputs | `:refused` | Untouched (`files: []`) |
| `:actuate` | Mid-stream write failure (self-healed in `run/3`) | `:compensated` | Restored (`pre == post`) |
| `:verify` | `{:compile_failed, output}` from `mix compile` | `:build_broken` | Restored (`pre == post`) |
| `:verify` | Other non-compiler verification failure | `:compensated` | Restored (`pre == post`) |
| `:finalize_evidence` | Receipt append failure | `:compensated` | Restored (`pre == post`) |
| `{:unknown, _}` | Unclassified error | `:refused` | Conservative refusal |

---

## 4. The Core Invariant: `ActuationOccurred => ReceiptExists`

A central correctness invariant of `ggen_igniter` is:
> **If files were physically modified on disk (even temporarily before rollback), a durable receipt MUST be appended to document the actuation and its outcome.**

### Observed Implementation Status: `PARTIAL_ALIVE`

1. **Active on `GgenIgniter.Reactors.ReconcileReactor` (`use_reactor: true`)**:
   - Every admitted attempt guarantees receipt persistence.
   - Refusals generate `:refused` receipts.
   - Compile breakages generate `:build_broken` receipts with hash proofs.
   - Semantic failures generate `:compensated` receipts.
   - Manifest promotion failures maintain `:alive` standing with durable receipt evidence.
2. **Inactive on Legacy Pipeline (`GgenIgniter.Reconcile.run/1`)**:
   - `Reconcile.run/1` has zero interaction with `GgenIgniter.Receipt` or `GgenIgniter.Manifest`.
   - Exceptions raise directly without durable receipt or compensation.
   - Because `use_reactor` defaults to `false` in `Mix.Tasks.GgenIgniter.Sync`, the invariant holds on the Reactor coordination path, but not universally across un-migrated defaults.

---

## 5. Verification & Test Evidence

- **Closed Set Validation**: [`test/ggen_igniter_receipt_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_receipt_test.exs#L20-L47) tests all four standing atoms and verifies `ArgumentError` on invalid atoms.
- **`:build_broken` Derivation**: [`test/ggen_igniter_reconcile_reactor_test.exs:191-291`](file:///Users/sac/ggen_igniter/test/ggen_igniter_reconcile_reactor_test.exs#L191-L291) injects invalid Elixir code, triggers compiler verification failure, and asserts `receipt.standing == :build_broken`.
- **`:refused` Derivation**: [`test/ggen_igniter_reconcile_reactor_test.exs:360-401`](file:///Users/sac/ggen_igniter/test/ggen_igniter_reconcile_reactor_test.exs#L360-L401) injects duplicate output targets, triggers admission failure, and asserts `receipt.standing == :refused`.
- **`:alive` with Manifest Pending**: [`test/ggen_igniter_finalize_evidence_ordering_test.exs`](file:///Users/sac/ggen_igniter/test/ggen_igniter_finalize_evidence_ordering_test.exs) induces manifest permission error, asserts `receipt.standing == :alive` with durable receipt record.
