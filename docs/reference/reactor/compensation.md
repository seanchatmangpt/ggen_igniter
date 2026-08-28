# Compensation: `compensate/4` vs `undo/4`, With Real Source Citations

Source: `lib/ggen_igniter/reactors/reconcile_reactor.ex` lines 199-221
(moduledoc section "`compensate/4` vs `undo/4` -- real Reactor semantics,
not folklore"), lines 336-379 (`:actuate` step declaration), lines 890-948
(`actuate_pending/2`). Cross-checked directly against
`deps/reactor/lib/reactor/step.ex` and
`deps/reactor/documentation/tutorials/02-error-handling.md`, per the
moduledoc's own disclosed method ("confirmed by reading ... directly, not
assumed").

## CURRENT vs TARGET Implementation Comparison

| Dimension | CURRENT Implementation (`ReconcileReactor`) | TARGET Architecture |
|---|---|---|
| **Compensation Trigger** | Downstream failure in `:verify` triggers `:actuate`'s `undo/4`; `:actuate` self-heal reverts partial writes within `run/3` | Declarative rollback hooks across all side-effecting steps in the Reactor DAG |
| **Evidence Preservation** | Rollback never deletes or erases receipts. Receipts record `COMPENSATION_STARTED` and `FILES_RESTORED` with `pre_run_hash == post_run_hash` | Immutable append-only audit trail guaranteeing physical actuation history is permanently recorded |
| **State Restoration** | `revert_all/1` restores exact prior bytes for existing files (`File.write!/2`) and deletes newly created files (`File.rm/1`) | Snapshot-based or content-addressed filesystem state restoration |
| **Manifest Protection** | Manifest is untouched on compensation (advances only on `:alive` standing in `:finalize_evidence`) | Manifest remains strictly synchronized with verified `:alive` states |

## Durable State Restoration Without Erasing Evidence History

A critical architectural property of `ReconcileReactor` is that **compensating physical side effects does NOT erase execution evidence**.

When a verification failure occurs:
1. Physical files are restored to their exact pre-run content or removed if newly created (`revert_all/1`).
2. The project's post-restoration hash matches its pre-run hash (`post_run_hash == pre_run_hash`).
3. An immutable receipt is appended to `.ggen_igniter/receipts/<date>.jsonl` with standing `:build_broken` (or `:compensated`).
4. The receipt records the full OCEL event trace: `ACTUATION_STARTED -> FILES_CHANGED -> VERIFICATION_FAILED -> COMPENSATION_STARTED -> FILES_RESTORED`.

This ensures that although the project filesystem returns to a clean, working state, the audit history preserves an indisputable record that physical actuation was attempted, failed verification, and was successfully compensated.

## The Two Real Hooks and Their Genuinely Different Triggers

Reactor's `Reactor.Step` behaviour (`deps/reactor/lib/reactor/step.ex`)
defines two separate rollback callbacks:

- **`compensate/4`** (`@callback compensate/4`, `step.ex:141`) -- fires when
  THIS step's OWN `run/3` returns `{:error, reason}`. It decides whether to
  retry, continue, or fail; it does not by itself revert a DIFFERENT,
  already-successful step.
- **`undo/4`** (`@callback undo/4`, `step.ex:172`) -- fires when a LATER
  step in the same Reactor run fails, and Reactor needs to roll back THIS
  already-successful step's own work.

This module's key correctness property -- `:verify` (a later step) failing
after `:actuate` has genuinely written files -- is exactly `undo/4`'s real
trigger, never `compensate/4`'s. `:actuate` implements both, and each does
something different because each is answering a different question.

## `:actuate`'s `compensate/4`: a real no-op, by design

```elixir
compensate fn _reason ->
  :ok
end
```

(`reconcile_reactor.ex:344-353`)

This is a genuine `:ok`, not a stub -- `run/3`'s own body already self-heals
any partial writes from ITS OWN failure before ever returning `{:error,
...}`. Concretely, `actuate_pending/2`'s error branch (lines 917-947):

1. Splits `tagged` results into `oks`/`errors` via `Enum.split_with/2`.
2. If `errors != []`: builds `tracked` from whatever DID succeed so far in
   THIS SAME invocation, emits real `"FILES_CHANGED"` then
   `"COMPENSATION_STARTED"` OCEL events, calls `revert_all(tracked)` (line
   934) to actually restore/delete those files RIGHT THERE, emits
   `"FILES_RESTORED"` with the real pre/post hash comparison, and only then
   returns `{:error, {:actuate_failed, reasons}}`.

By the time Reactor would ever call `compensate/4` for this step, there is
nothing left on disk to revert -- the self-heal already happened inside
`run/3` itself. `compensate/4` returning `:ok` is therefore the honest
answer, not a placeholder.

## `:actuate`'s `undo/4`: the real, tested revert path

```elixir
undo fn %{tracked: tracked}, %{reconcile_opts: opts} ->
  event_sink = opts[:event_sink]
  paths = Map.keys(tracked)
  pre_hash = Receipt.hash_entries(prior_entries(tracked))

  OcelEmitter.emit(event_sink, "COMPENSATION_STARTED", file_objects_for_paths(paths), %{"paths" => paths})

  revert_all(tracked)

  post_hash = Receipt.hash_files(paths)

  OcelEmitter.emit(event_sink, "FILES_RESTORED", file_objects_for_paths(paths), %{
    "paths" => paths,
    "pre_run_hash" => pre_hash,
    "post_run_hash" => post_hash,
    "matches_pre_run_hash" => post_hash == pre_hash
  })

  :ok
end
```

(`reconcile_reactor.ex:355-376`)

This is Reactor's real invocation when `:verify` (declared strictly after
`:actuate` in the dependency graph) fails: Reactor calls `:actuate`'s
`undo/4` with `:actuate`'s own successful result (`%{tracked: tracked}`,
matching the `{:ok, %{results:, tracked:}}` shape `run/3` returned) plus the
step's arguments (`%{reconcile_opts: opts}`).

`revert_all/1` (lines 1005-1008) is the real mechanism both this `undo/4`
and the internal self-heal call:

```elixir
defp revert_all(tracked) when is_map(tracked) do
  Enum.each(tracked, fn {path, %{prior: prior}} -> revert_one(path, prior) end)
  :ok
end

defp revert_one(path, {:existed, prior_content}), do: File.write!(path, prior_content)

defp revert_one(path, :new) do
  case File.rm(path) do
    :ok -> :ok
    {:error, :enoent} -> :ok
    {:error, reason} -> raise RuntimeError, "failed to revert (delete) #{path}: #{inspect(reason)}"
  end
end
```

`prior` is captured PER-TARGET at write time (`actuate_one/2`, line 964:
`prior = if File.exists?(pa.target), do: {:existed, File.read!(pa.target)},
else: :new`), so revert is byte-exact when a file previously existed and a
real delete when it did not -- never a guess.

### Real, passing proof

`test/ggen_igniter_reconcile_reactor_test.exs`, "a real failure at `:verify`
reverts every file `:actuate` wrote" -> "restores pre-existing content,
deletes the new file, and persists a real `:build_broken` receipt":

- A pre-existing file with KNOWN content is overwritten by a broken
  template's output.
- A NEW file (did not exist before the run) is created by the same broken
  run.
- `:verify` fails for real (a genuinely invalid Elixir template, `mix
  compile --warnings-as-errors` genuinely fails).
- Reactor's real `undo/3` (Reactor's internal naming for what the DSL
  exposes as `undo/4` at the step level) runs, and the test asserts, reading
  real disk state back (not the in-memory Reactor result):
  - `File.read!(existing_path) == original_content` -- the pre-existing
    file's ORIGINAL bytes are restored.
  - `refute File.exists?(new_path)` -- the file that did not exist before
    this run is deleted again.
  - `receipt.pre_run_hash == receipt.post_run_hash` -- the real,
    checkable claim that compensation genuinely restored prior state.
  - The real OCEL activity sequence (`"ACTUATION_STARTED"`,
    `"FILES_CHANGED"`, `"VERIFICATION_FAILED"`, `"COMPENSATION_STARTED"`,
    `"FILES_RESTORED"`) is present in the persisted receipt verbatim.
- A SECOND, corrected run afterward succeeds cleanly, proving the reverted
  state is a genuinely healthy starting point, not subtly corrupted.

Real, passing run backing this (this session): see
`docs/reference/reactor/overview.md#verification`.

## `max_retries 0` on both `:actuate` and `:verify`

Both steps set `max_retries 0` explicitly (`reconcile_reactor.ex:378` for
`:actuate`, `:407` for `:verify`) -- confirmed directly at the source
lines, not inferred. This overrides the Reactor DSL's own default of
`max_retries: :infinity` (`deps/reactor/lib/reactor/dsl/step.ex:21`, applies
to every OTHER step in this module that does not override it -- see
`steps.md`'s per-step "Retry policy" rows).

`Retries_actuation = 0` is therefore a real, cited fact: line 378,
`step :actuate do ... max_retries 0 end`. The reasoning (not stated as
literal source but consistent with why both steps make the same choice):
retrying a failed write without changing any input would either repeat the
identical failure or, worse, blindly re-attempt a write whose surrounding
plan is now stale -- 0 retries plus a real `undo/4` revert is the safe
choice here, not a retry loop. Same logic for `:verify` (line 407): a
failing `mix compile` will not succeed differently on a bare retry with no
code change.

## Steps with NO compensation declared, and why that is correct

Every step besides `:actuate` has neither `compensate` nor `undo` declared
(confirmed by reading each step block in `reconcile_reactor.ex`):
`:observe_prior_manifest`, `:load_ontology`, `:resolve_pack`,
`:run_queries`, `:render`, `:admit`, `:verify`, `:finalize_evidence`. This is
correct, not an oversight, for two different reasons depending on which
side of `:actuate` the step sits:

- **Before `:actuate`** (`:observe_prior_manifest` through `:admit`): these
  steps never write to the filesystem, so there is nothing for either
  callback to revert.
- **After `:actuate`** (`:verify`, `:finalize_evidence`): these steps'
  OWN failures have nothing of their own to undo (`:verify` only reads;
  `:finalize_evidence`'s writes -- `Receipt.append!/2`,
  `Manifest.persist!/2` -- are handled by its own local `try/rescue` for
  the manifest-promotion sub-step, per `steps.md`'s `:finalize_evidence`
  entry, correction B). When either of these fails, Reactor's real
  rollback mechanism is `:actuate`'s OWN `undo/4` being invoked (an
  EARLIER step being rolled back because THIS LATER step failed) -- not a
  callback that would need to live on `:verify` or `:finalize_evidence`
  themselves.

## See also

- `docs/reference/reactor/steps.md` -- full per-step contract, including
  the exact `max_retries` value for every step
- `docs/reference/reactor/failure-semantics.md` -- how a compensated/
  reverted run maps to the `:compensated`/`:build_broken` standings
- `docs/reference/reactor/concurrency.md` -- the internal self-heal branch
  this doc describes runs inside `:actuate`'s own `Task.async_stream/3`
  fan-out, so it must revert every target that DID succeed even when only
  one target's write raised
