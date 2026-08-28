# Failure Recovery: Receipts, Standings, Compensation

This describes what happens when a reconciliation attempt fails partway
through, and how to find out what happened afterward. **The guarantees on
this page apply only to the Reactor pipeline** (`GgenIgniter.Reactors.ReconcileReactor`,
opt-in via `config :ggen_igniter, use_reactor: true` — see
`docs/operations/runtime.md`). The plain `GgenIgniter.Reconcile.run/1`
pipeline and `Mix.Tasks.GgenIgniter.Sync`'s own inline pipeline (today's
default paths) write **no receipt and perform no compensation** — a failure
there raises, full stop; there is nothing durable to read back afterward
beyond whatever partial file state was already written.

## Two different durable records, on purpose

- **`GgenIgniter.Manifest`** (`<base_dir>/.ggen_igniter/manifest.json`) — the
  **current-state cache**: what does this recipe's most recent
  *successful* run actually write, right now. It only ever advances on a
  real `:alive` standing.
- **`GgenIgniter.Receipt`** (`<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`,
  one JSON object per line, append-only) — the **history**: what was
  *attempted*, every time, regardless of outcome.

A manifest-only world has no record of an attempt at all once undo restores
the pre-run bytes — the manifest never moved, and the files are back to
their old content, yet disk was genuinely written to, twice. The receipt is
what keeps that operational evidence (what keeps failing verification here?
how often? what does the failure loop look like?).

## The four real standings

`GgenIgniter.Receipt.standing/0` is a closed set — `Receipt.new/1` raises on
anything else, so a future caller cannot silently invent a fifth meaning.

| Standing | Meaning | Files touched? |
|---|---|---|
| `:alive` | The attempt succeeded: files written, verification passed, admitted, manifest advanced. | Yes, and they stay. |
| `:refused` | A fail-closed refusal **before** any actuation — a path-safety guard, a missing precondition, a bad input. | No. Nothing ever hit disk. |
| `:compensated` | Files **were** written, verification then failed for a reason other than a build/syntax break, undo restored the prior on-disk bytes, and the resulting hash was confirmed to match the pre-run hash. | Yes, then reverted. |
| `:build_broken` | Same shape as `:compensated` (written, then restored), but specifically because the generated content itself does not parse/compile — "the pack produced broken code," distinguished so this failure mode isn't conflated with a generic verification failure. | Yes, then reverted. |

## Reading a receipt

One line of `.ggen_igniter/receipts/<date>.jsonl`:

```json
{
  "id": "rcpt_...",
  "recipe_key": "templates/resource.ex.eex=>lib/.../<%= ... %>.ex",
  "standing": "compensated",
  "started_at": "2026-08-27T12:00:00.000000Z",
  "finished_at": "2026-08-27T12:00:00.050000Z",
  "pre_run_hash": "sha256:...",
  "post_run_hash": "sha256:...",
  "files": ["lib/support_desk/support/ticket.ex"],
  "events": [ {"activity": "ACTUATION_STARTED", "...": "..."}, ... ],
  "reason": "verification failed: ...",
  "metadata": {}
}
```

`pre_run_hash`/`post_run_hash` are a single digest over the **exact set of
files this attempt touched** (via `GgenIgniter.Receipt.hash_files/1` /
`hash_entries/1`) — not a whole-repository hash. On a `:compensated` or
`:build_broken` receipt, `pre_run_hash == post_run_hash` is the real,
checkable claim that compensation genuinely restored prior state. Read
receipts back programmatically with `GgenIgniter.Receipt.read_all!/1`
(returns `[]`, not an error, when no receipts directory exists yet).

## The event trail: OCEL-shaped, via `GgenIgniter.Telemetry.OcelEmitter`

Each receipt's `events` list is built from real, structured events emitted
during the run (object-centric event log shape):

```
ACTUATION_STARTED -> FILES_CHANGED -> VERIFICATION_FAILED ->
COMPENSATION_STARTED -> FILES_RESTORED -> STANDING_SET
```

(or, on the happy path: `ACTUATION_STARTED -> FILES_CHANGED ->
VERIFICATION_SUCCEEDED -> ADMITTED -> STANDING_SET`.) Every `emit/4` call
also fires a real `:telemetry.execute/3` under `[:ggen_igniter, :reconcile,
:ocel]`, independent of whether anything is accumulating events into a
receipt — attach a handler there for live observability (logging, metrics)
without needing to read receipts after the fact.

## How compensation actually works (Reactor `undo/3` vs `compensate/3`)

Reactor's real `Step` behaviour gives each step two distinct rollback
hooks with different triggers — this is not folklore, it was confirmed by
reading Reactor's own source and tutorial directly:

- **`compensate/4`** fires when a step's **own** `run/3` returns
  `{:error, reason}`. It decides retry/continue/fail; it does not by itself
  revert a *different*, already-successful step.
- **`undo/4`** fires when a **later** step in the same run fails, and
  Reactor needs to roll back *this* already-successful step's work.

`:actuate` implements both, honestly, for two different real scenarios:

- `:verify` (a later step) failing after `:actuate` has genuinely written
  files is `undo/4`'s real trigger — this is the tested revert path (see
  `test/ggen_igniter_receipt_compensated_test.exs`: a genuinely invalid
  Elixir template makes a real `mix compile --warnings-as-errors` fail,
  Reactor's real `undo/3` restores the real pre-run file content, and the
  persisted receipt's `pre_run_hash == post_run_hash` is asserted from the
  real file on disk — no mock anywhere in that chain).
- `:actuate`'s **own** run failing mid-loop (one target's write raising)
  self-heals *inside* `run/3`, reverting every write that same invocation
  already made, before ever returning `{:error, ...}` — so `compensate/4`
  itself has nothing left to do and correctly returns `:ok`.

## Receipt-before-manifest ordering (why a receipt can never be missing for an `:alive` run)

`:finalize_evidence` does, in this exact order:

1. Prepares both the next manifest content and the new receipt payload
   entirely in memory — nothing durable written yet.
2. Persists the receipt **first** (`Receipt.append!/2`, a real append-only
   write). If this itself raises, the step fails like any other — since
   `:actuate` already wrote real files, Reactor's own `undo/3` rolls them
   back (a real `:compensated` outcome).
3. Only once the receipt append genuinely succeeds does it attempt to
   promote the manifest via `Manifest.persist!/2`'s own atomic
   temp-file-then-rename protocol. If **this** specific call fails, it is
   caught locally (not re-raised) — the attempt is still genuinely
   `:alive` (files were written and verified correctly; rolling them back
   because the manifest cache failed to update would be wrong).
   `metadata["manifest_promotion"]` records the pending state instead, with
   the now-durable receipt as the real recovery anchor for a retry.

This ordering makes "manifest advanced but no receipt exists to explain
why" structurally impossible — see
`test/ggen_igniter_finalize_evidence_ordering_test.exs` for the real,
no-mock proof (the manifest's target path is pre-created as a directory so
`File.rename!/2` genuinely raises, and the test asserts the receipt file
already contains the `:alive` line while the manifest path is still
untouched).

## Known, disclosed limitation: no cross-run orphan detection (REFUTED finding, currently open)

`GgenIgniter.Manifest`'s reconciliation model is scoped to a **single
recipe's own tracked outputs** (`(template, out_template)` keyed — see
`docs/contributing/adding-a-pack.md` for the recipe-key identity model).
Real, reproduced gap (`.ggen_igniter_factory/ADVERSARIAL.md`, "MUST FIX #3",
re-verified 2026-08-27): a resource **rename** or **whole-resource
removal** in the source ontology produces a clean new/updated file, but
leaves the **previously-generated file for the old identifier** completely
untouched on disk — no warning, no error, exit code `0`. `--on-stale prune`
only prunes paths a recipe's *own* manifest entry previously recorded as
stale relative to that *same* recipe's current run; it has no mechanism for
"this identifier no longer exists in the ontology at all." Treat a stale,
orphaned generated file after a rename/removal as an expected, currently
unmitigated consequence, not a bug in the reconciliation pipeline itself —
plan a manual cleanup pass after any rename/removal until this is closed.

## Practical recovery playbook

1. **A run exited non-zero / raised.** If it went through the Reactor path,
   read the newest line of today's `.ggen_igniter/receipts/<date>.jsonl` —
   `standing` tells you which of the four buckets you're in, and `reason`
   names the real failure. If it went through the plain
   `Reconcile.run/1`/CLI path, there is no receipt — read the raised
   exception message directly; any files already written by that run were
   **not** automatically reverted (no compensation exists on that path).
2. **`:build_broken`** — the generated content didn't compile. Fix the
   template/query, not the pipeline; re-run once the output would actually
   compile. Files were already reverted, so there is nothing to clean up on
   disk.
3. **`:compensated`** — verification failed for a non-compile reason
   (whatever `mix compile --warnings-as-errors` reported that isn't a bare
   syntax/parse error, since `:verify`'s scope today is exactly that one
   subprocess check — see `docs/operations/debugging.md`). Files were
   reverted; confirm `pre_run_hash == post_run_hash` in the receipt as a
   sanity check before re-running.
4. **`:refused`** — nothing was written; the message names the exact
   pre-actuation guard that fired (duplicate output path within one run,
   an unowned `:delete` candidate, or `--on-stale refuse`'s default policy
   meeting a real stale path). Fix the input and re-run; no cleanup needed.
5. **Manifest shows `"manifest_promotion": "{:pending, ...}"`** — files are
   genuinely correct and verified; only the manifest cache write failed
   (e.g. a permissions issue, or the manifest path collided with a
   directory). The receipt is the recovery anchor: re-run the same recipe
   once the manifest path issue is fixed, and the next successful run's
   manifest promotion will catch it up.

## See Also

- `docs/operations/runtime.md` — which pipeline (plain vs. Reactor) actually runs by default
- `docs/operations/debugging.md` — `mix ggen_igniter.doctor` and general triage
- `docs/contributing/adding-a-reactor-step.md` — the `compensate`/`undo` contract from a step-author's perspective
- `lib/ggen_igniter/receipt.ex`, `lib/ggen_igniter/reactors/reconcile_reactor.ex`, `lib/ggen_igniter/telemetry/ocel_emitter.ex` — source of record
