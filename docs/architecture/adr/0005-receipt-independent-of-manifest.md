# ADR-0005: Receipt as an Independent, Append-Only Attempt History Distinct from the Manifest

## Status

**Accepted.** Live in `GgenIgniter.Receipt`, written by
`GgenIgniter.Reactors.ReconcileReactor.run/1` on every path (success or any
of three failure standings).

## Context

`GgenIgniter.Manifest` already records current state: what a recipe's most
recent **successful** run wrote. But a real, consequential problem remains
unaddressed by a manifest alone: if `:actuate` genuinely writes files and
`:verify` then fails, real `undo/4` compensation restores the pre-run
bytes — and in a manifest-only world, there is **no record that this
attempt ever happened**. The manifest never moved (it only advances on
`:alive`), and the files are back to their old content, yet disk was
genuinely written to, twice.

Quoting the user directive preserved verbatim in `receipt.ex`'s own
moduledoc, because it is the precise justification for this decision:

> If files were actually changed — even temporarily — then a consequential
> physical actuation occurred... the run receipt should record
> ACTUATION_STARTED -> files A,B changed -> verification failed ->
> compensation started -> A,B restored -> resulting project hash == pre-run
> hash -> standing = COMPENSATED.

## Decision

Build `GgenIgniter.Receipt` as a **second, independent** durable record —
not a replacement for the Manifest, and not sharing its write discipline:

| | Manifest | Receipt |
|---|---|---|
| Records | current state (what the last successful run wrote) | history (what was attempted, every time) |
| Advances on | `:alive` only | every admitted attempt, any of the four standings |
| Write style | atomic rename (crash-safe snapshot) | append-only (`File.write!/3, [:append]`) |
| Failure mode | a single point-in-time snapshot, protected from partial overwrite | a torn last line on a real crash, recoverable by discarding it |

`ReconcileReactor.run/1` (not a bare `Reactor.run/4` call) is the one entry
point that guarantees this: it persists a receipt on `{:ok, _}` and on
every `{:error, _}`, deriving one of four closed-set standings
(`:alive`/`:refused`/`:compensated`/`:build_broken`) from which step failed
and why.

## Consequences

- `:finalize_evidence` persists the receipt **strictly before** attempting
  manifest promotion — making "manifest advanced but no receipt exists to
  explain why" structurally impossible. A manifest-promotion failure alone
  is caught locally and does not roll back an otherwise-good, verified run.
- This guarantee is real and tested, but **scoped to the opt-in Reactor
  path only** (see ADR-0003). `GgenIgniter.Reconcile.run/1` and the CLI's
  inline pipeline write no receipt on any outcome — a failure there raises,
  full stop, with nothing durable to read back beyond whatever partial
  file state was already written.
- Every `Receipt.append!/2` call also fires a real `:telemetry.execute/3`
  under `[:ggen_igniter, :reconcile, :ocel]`, independent of whether
  anything is accumulating events into a receipt.

## See also

- `docs/reference/evidence/receipts.md`, `docs/reference/evidence/standing.md`
- `docs/reference/evidence/recovery.md` — the full evidence-ordering proof
