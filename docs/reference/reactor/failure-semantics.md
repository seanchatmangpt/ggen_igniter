# Reactor Failure Semantics: The Four Standings

Source: `lib/ggen_igniter/reactors/reconcile_reactor.ex`
(`standing_for_failure/2`, lines 494-528; `failed_step_info/1`, lines
476-492), `lib/ggen_igniter/receipt.ex` (`@standings`, line 98; moduledoc
"the four real standings", lines 45-68). Confirmed by real, passing test
runs -- see `docs/reference/reactor/overview.md#verification`.

## CURRENT vs TARGET Implementation Comparison

| Dimension | CURRENT Implementation (`ReconcileReactor`) | TARGET Architecture |
|---|---|---|
| **Actuation Retries** | Explicit `max_retries 0` on `:actuate` (`Retries_actuation = 0`) | `Retries_actuation = 0` strictly enforced across all actuation steps |
| **Receipt Generation** | Persisted via `Receipt.append!/2` on both success (`:alive`) and failure (`:refused`, `:compensated`, `:build_broken`) | Unconditional append-only JSONL receipt chain with cryptographic parent hashing |
| **Manifest Rollback** | Manifest promotion is attempted only after `:verify` succeeds and receipt is flushed; promotion errors do not rollback files | Complete decouple of ephemeral cache (manifest) from immutable audit trail (receipts) |
| **Error Taxonomy** | Four discrete standings (`:alive`, `:refused`, `:compensated`, `:build_broken`) mapped via `standing_for_failure/2` | Formal algebraic standing types with fine-grained error diagnostic taxonomy |

## The `Retries_actuation = 0` Rule

In `ReconcileReactor`, the `:actuate` and `:verify` steps are explicitly declared with:
```elixir
max_retries 0
```
This is a foundational safety invariant: **retrying non-idempotent or state-dependent actuation without re-running the full observation and planning pipeline is strictly prohibited**.

### Why Retrying Actuation is Prohibited:
1. **Non-Idempotent Side Effects & Drift:** If an actuation fails partially midway (e.g., disk I/O error, permission glitch, concurrent file modification), immediately retrying the write operation against dirty state risks corrupting files or creating split-brain state.
2. **Deterministic Failures:** If a rendered output cannot be written or causes a compiler break during `:verify`, repeating the exact same actuation with the exact same inputs will deterministically yield the exact same failure. Retrying wastes execution resources and delays rollback.
3. **Rollback over Retry:** When an actuation fails or fails verification, the correct autonomic action is **instant compensation** (reverting modified files to `pre_run_hash` via `undo/4`), persisting an immutable receipt (`:compensated` or `:build_broken`), and returning a clean failure. Any subsequent attempt must start fresh from `:observe_prior_manifest`.

## Refusal Conditions and Short-Circuiting

The `:admit` step acts as a fail-closed gate before `:actuate` is reached. It short-circuits the pipeline if:
1. **Duplicate Output Paths (`:refused_duplicate_output_path`):** Two targets resolve to the same file path in a multi-target run.
2. **Unowned Deletions (`:refused_unowned_delete`):** A stale prune candidate is not owned by the recipe.
3. **Stale Outputs under Refuse Policy (`:refused_stale_outputs`):** Generated files from a previous run no longer exist in the new plan and `--on-stale refuse` is active.

Because `:admit` precedes `:actuate`, all refusal conditions produce a `:refused` standing with zero disk mutations.

## The Closed Set of Standings

`GgenIgniter.Receipt.standing/0` is a closed set of exactly four atoms
(`receipt.ex:98`, `Receipt.new/1` raises `ArgumentError` on anything else --
line 164-167):

| Standing | Meaning (per `receipt.ex` moduledoc) |
|---|---|
| `:alive` | The attempt succeeded: files written, verification passed, admitted, manifest advanced (or genuinely pending -- see below). |
| `:refused` | Fail-closed refusal BEFORE any actuation. Nothing was ever written to disk. |
| `:compensated` | Files WERE written, verification then failed for a reason other than a build/syntax break, undo restored the prior bytes, and the resulting hash matches the pre-run hash. |
| `:build_broken` | Same shape as `:compensated` (written then restored), but specifically because the generated content itself does not parse/compile. |

## How `run/1` derives the standing on failure

`run/1` (lines 439-474) never fabricates a standing from nothing -- it always
starts from `failed_step_info/1`, which pulls the real
`{step_name, original_reason}` back out of Reactor's own error struct
(`%Reactor.Error.Invalid{errors: [%Reactor.Error.Invalid.RunStepError{step:
%Reactor.Step{name: ...}, error: ...}, ...]}`, matched structurally as
`%{step: %{name: _}, error: _}` rather than against the exact struct name --
the moduledoc discloses this was "confirmed empirically against a real
minimal reactor, not assumed").

`standing_for_failure/2` (lines 504-528) is then a real `cond`, not a lookup
table invented for this doc:

```elixir
cond do
  step_name in [
    :observe_prior_manifest, :load_ontology, :resolve_pack,
    :run_queries, :render, :admit
  ] -> :refused

  step_name == :verify ->
    case reason do
      {:compile_failed, _output} -> :build_broken
      _ -> :compensated
    end

  step_name in [:actuate, :finalize_evidence] -> :compensated

  true -> :refused
end
```

## Standing-to-step mapping (real, exhaustive)

| Step that failed | Real reason shapes seen | Standing |
|---|---|---|
| `:observe_prior_manifest` | any raised exception (e.g. bad `manifest_dir`) | `:refused` |
| `:load_ontology` | missing ontology path (`ArgumentError`), `Ontology.load!/1` failure | `:refused` |
| `:resolve_pack` | `Pack.resolve_dir!/1` failure | `:refused` |
| `:run_queries` | engine/query failure | `:refused` |
| `:render` | template read/render failure | `:refused` |
| `:admit` | `{:refused_duplicate_output_path, _}`, `{:refused_unowned_delete, _}`, `{:refused_stale_outputs, _}` | `:refused` |
| `:verify` | `{:compile_failed, output}` | `:build_broken` |
| `:verify` | any other reason | `:compensated` |
| `:actuate` | `{:actuate_failed, reasons}` (its own internal self-heal path) | `:compensated` |
| `:finalize_evidence` | `Receipt.append!/2` raising | `:compensated` |
| anything unmatched (`failed_step_info/1`'s `{:unknown, _}` fallback) | -- | `:refused` (the `true ->` catch-all) |

This table's `:verify`/`:actuate`/`:finalize_evidence` rows are each proven
by a real, currently-passing test (not merely asserted by this doc):

- `:build_broken` via `:verify` -- `test/ggen_igniter_reconcile_reactor_test.exs`,
  "restores pre-existing content, deletes the new file, and persists a real
  `:build_broken` receipt" (asserts `receipt.standing == :build_broken` and
  `receipt.pre_run_hash == receipt.post_run_hash`).
- `:refused` via `:admit` -- same file, "two targets whose `--out` resolves
  to the SAME real path are refused" (asserts `receipt.standing == :refused`,
  `receipt.files == []`, and no `"ACTUATION_STARTED"` event was ever
  emitted).
- `:alive` on success, including the manifest-promotion-pending sub-case --
  `test/ggen_igniter_finalize_evidence_ordering_test.exs` (asserts
  `receipt.standing == :alive` even when `Manifest.persist!/2` itself fails,
  because that failure is caught locally inside `:finalize_evidence` rather
  than propagated as a step error -- see `steps.md`'s `:finalize_evidence`
  entry).

No real test in this repo currently exercises the generic `:compensated`
(non-`:build_broken`) branch of `:verify`, nor `:actuate`'s own
`{:actuate_failed, _}` self-heal path, nor `:finalize_evidence`'s
`Receipt.append!/2`-raises branch, directly -- these three are real code
paths (the `cond`/`rescue` clauses exist and are reachable) but their
standing is UNVERIFIABLE by an executed test in this repo as of this pass,
as distinct from the two paths above which ARE test-proven. Labeling that
distinction plainly rather than implying uniform test coverage across all
nine cells of the table.

## `:alive` has two real sub-shapes

A success (`{:ok, receipt}` from `:finalize_evidence`, no Reactor error at
all) is always `standing: :alive`, but `receipt.metadata["manifest_promotion"]`
can independently be:

- `"promoted"` -- `Manifest.persist!/2` succeeded (the common case).
- `"unchanged"` -- no recipe's outputs actually changed, so the manifest
  write was never attempted (`manifest_changed?` stayed `false` through
  `commit_recipe/5`'s reduction).
- `"{:pending, <message>}"` (inspected) -- files were written and verified,
  but the manifest CACHE promotion itself failed (e.g. a real permission
  error on `.ggen_igniter/`). This is still `:alive`, deliberately -- per
  the moduledoc's correction B, rolling back real, verified work because a
  cache update failed would be wrong. Proven by
  `test/ggen_igniter_finalize_evidence_ordering_test.exs`.

## `:refused` carries no files, by construction

Every `:refused` standing comes from a step strictly before `:actuate` in
the dependency graph (see `steps.md`'s graph) -- `:actuate` is the sole
filesystem-mutation boundary, so a failure at or before `:admit`
structurally cannot have touched a real file. The test suite asserts this
directly: `receipt.files == []` and no `"ACTUATION_STARTED"` event in the
refused-duplicate-path test.

## `:compensated` / `:build_broken` both assert `pre_run_hash ==
post_run_hash`

Both standings represent "files were written, then genuinely reverted."
`Receipt.hash_entries/1` / `hash_files/1` (`receipt.ex:191-221`) compute a
single order-independent digest over exactly the files one attempt touched
(not a whole-repository hash). The real, checkable claim for both standings
is that this digest, computed once from the pre-image (captured before
`:actuate` wrote anything) and once from the real post-compensation disk
state, are equal -- proven directly in the `:build_broken` test above.

## Known gap, disclosed rather than silently assumed

`:finalize_evidence` has no `max_retries 0` override (see `steps.md`), so it
defaults to `:infinity` per the Reactor DSL. If `Receipt.append!/2` (a plain
`File.write!/3` with `[:append]`) were to fail transiently and Reactor
retried the whole step, a naive re-run of `finalize_evidence/1` would
attempt to build and append a SECOND receipt line for what is really the
same attempt (the function has no idempotency guard against being invoked
twice for one Reactor run). This is a real, live property of the current
code, not exercised by any test in this repo as of this pass -- flagged
here as a genuine open question for a future pass, not fixed (this agent's
scope is `docs/reference/reactor/**` only).

## See also

- `docs/reference/reactor/steps.md` -- full per-step contract this table is
  drawn from
- `docs/reference/reactor/compensation.md` -- the mechanism (`compensate/4`
  vs `undo/4`) that produces the `:compensated`/`:build_broken` file-revert
  behavior
- `docs/reference/reactor/overview.md#verification` -- the real test command
  and output backing every proven claim above
