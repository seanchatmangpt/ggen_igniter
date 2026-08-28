# Adding a Step to `ReconcileReactor`

This walks through extending `GgenIgniter.Reactors.ReconcileReactor`
(`lib/ggen_igniter/reactors/reconcile_reactor.ex`) — the opt-in Reactor
coordination pipeline (see `docs/operations/runtime.md` for when it runs vs.
the plain `Reconcile.run/1` pipeline, and
`docs/contributing/architecture-rules.md` for why coordination logic belongs
here and not in `GgenIgniter.Controller` or a second Reactor module).

## Before you add a step, know where you are in the spine

```
observe_prior_manifest  ─┐
load_ontology            ├─ run concurrently (each depends only on :reconcile_opts)
resolve_pack            ─┘
        ↓
run_queries → render → admit → actuate → verify → finalize_evidence
```

`:observe_prior_manifest`, `:load_ontology`, and `:resolve_pack` depend only
on the `:reconcile_opts` input, so Reactor's own dependency-graph scheduler
already runs them concurrently — no manual concurrency management needed
for that part. Everything from `:run_queries` onward is a real linear
dependency chain (each step's `argument` declarations name the prior
step(s) it needs via `result(:step_name)`).

## The step DSL, concretely

```elixir
step :my_new_step do
  argument :some_input, result(:some_prior_step)
  argument :reconcile_opts, input(:reconcile_opts)

  run fn %{some_input: value, reconcile_opts: opts}, _context ->
    # ... real work ...
    {:ok, %{whatever: :the_next_step_needs}}
  end
end
```

- `argument` wires either `input(:reconcile_opts)` (the reactor's own
  top-level input) or `result(:other_step)` (another step's return value).
- `run/1`'s function returns `{:ok, result}` or `{:error, reason}` — never
  raises for an expected failure mode; raising is reserved for genuine bugs
  (Reactor treats a raise as a crash, not a handled `{:error, ...}`).
- If your step can leave real, consequential side effects (writes files,
  makes an external call with effects) that a *later* step's failure should
  roll back, add `compensate` and/or `undo` — see the next section. A pure
  read/derive step (like `:observe_prior_manifest`, `:load_ontology`,
  `:render`) needs neither.

## `compensate/4` vs. `undo/4` — pick the right one, don't conflate them

These are Reactor's own two distinct rollback hooks, confirmed against
Reactor's real source (`deps/reactor/lib/reactor/step.ex`) rather than
assumed:

- **`compensate/4`** fires when **this step's own** `run/3` returns
  `{:error, reason}`. Use it to decide retry/continue/fail, or to
  self-heal partial work *this same invocation* already did before
  returning the error. It never reverts a *different*, already-successful
  step.
- **`undo/4`** fires when a **later** step in the same run fails, and
  Reactor needs to roll back *this* already-successful step's work. This is
  the real "a downstream step failed, revert what I did" mechanism.

`:actuate` is the reference example for both, side by side:

```elixir
step :actuate do
  # ...
  run fn %{admitted: admitted, reconcile_opts: opts}, _context ->
    actuate_pending(admitted, opts[:event_sink])
  end

  compensate fn _reason ->
    # run/3 above already self-heals any partial writes from ITS OWN
    # failure (inside actuate_pending/2) before ever returning
    # {:error, ...} — nothing left for compensate to do.
    :ok
  end

  undo fn %{tracked: tracked}, %{reconcile_opts: opts} ->
    # A LATER step (:verify) failed. Revert tracked's real writes here.
    revert_all(tracked)
    :ok
  end

  max_retries 0
end
```

If your new step writes anything real to disk (or makes an external call
with a side effect worth reverting), you almost certainly want `undo/4` —
`compensate/4` alone does not protect against a step *after* yours failing.

## Wiring into the return chain and evidence

- If your step should be able to refuse the *entire run* (a whole-plan
  invariant, like `:admit`'s duplicate-output-path/unowned-delete/stale-path
  checks), inspect the **full plan**, not just your own step's narrow
  input — `:admit`'s own comment explains why: "no single-item view could
  catch" a whole-plan conflict. Emit a real OCEL event
  (`OcelEmitter.emit(opts[:event_sink], "GUARD_REFUSED", [], %{"reason" =>
  ...})`) on refusal so the refusal shows up in the eventual receipt.
- If your step is inserted before `:finalize_evidence`, it participates in
  `run/1`'s (the module's public entry point, not `Reactor.run/4` directly)
  guarantee that **every** failure path gets a real, persisted
  `GgenIgniter.Receipt` — see `standing_for_failure/2`, which derives the
  receipt's `:standing` from *which* step failed. If you add a new step
  before `:actuate`, its failure should map to `:refused` (nothing written
  yet); a new step between `:actuate` and `:finalize_evidence` failing
  should map to `:compensated` (something was written and needs undo).
  Update `standing_for_failure/2`'s `cond` clauses accordingly — do not
  leave a new step falling through to the wrong bucket.
- Never call `GgenIgniter.Receipt.append!/2` or `GgenIgniter.Manifest.persist!/2`
  from inside your own new step. Evidence finalization is deliberately one
  boundary (`:finalize_evidence`), not scattered across steps — see
  `docs/operations/failure-recovery.md`'s "receipt-before-manifest ordering"
  section for why splitting this was a real, corrected bug in an earlier
  design (`:commit_manifest` + `:receipt` as two independent steps let a
  manifest advance with no receipt explaining why).

## Testing hooks already available (inert unless you opt in)

Two per-target opts keys exist purely to make `:actuate`'s real concurrency
independently observable from a test:

- `:test_delay_ms` — sleeps this many ms immediately before a target's real
  write.
- `:test_probe` — an ETS table atom; if given, start/stop timestamps are
  recorded around the write so a test can assert two targets' write windows
  actually overlapped.

If your new step also needs to prove real concurrency or ordering to a
test, prefer extending this same pattern (an inert-by-default opts key,
read only by your step) rather than adding a new global test-mode flag.

## Where NOT to put new coordination logic

- Not in `GgenIgniter.Controller` — it dispatches to this module (or to
  `Reconcile.run/1`) and adds only in-process state; see
  `docs/operations/controller.md` and `docs/contributing/architecture-rules.md`'s
  "GenServer does not become a workflow engine" rule.
- Not in `Mix.Tasks.GgenIgniter.Sync` — that task has its own, separate
  inline implementation of the same spine today (a real, disclosed
  unification gap, not a place to add Reactor-specific logic).
- Not as a second `use Reactor` module — extend this one spine.

## See Also

- `docs/operations/failure-recovery.md` — the receipt/standing/OCEL-event model your step's failures feed into
- `docs/contributing/architecture-rules.md` — the four hard invariants (admission-before-mutation, single coordinator, etc.) any new step must respect
- `test/ggen_igniter_reconcile_reactor_test.exs`, `test/ggen_igniter_receipt_compensated_test.exs`, `test/ggen_igniter_finalize_evidence_ordering_test.exs` — real, passing proofs of the mechanisms described above
