# `GgenIgniter.Lock`

Source: `lib/ggen_igniter/lock.ex` (`GgenIgniter.Lock`). Status:
**UNVERIFIABLE-pending-integration** — this pass finds real, present code
(the module now exists on disk, unlike the prior pass's "module does not
exist" finding) but cannot certify it end-to-end, because a real invocation
of its only real caller (`mix ggen_igniter.sync`) fails downstream of the
lock, in a different module, before a full lock acquire/release cycle
completes. See "What this pass verified" below for the exact boundary.

This repo is being edited concurrently by other agents on this same working
tree per the task that produced this doc; the note above (and every status
below) reflects only what was true in a real command run executed during
this pass, not a final, merged, crown-gate state.

## Purpose

A real, file-based cross-process lock (not `:global`/`GenServer` — see the
moduledoc's "Mechanism" section) serializing concurrent mutating
`ggen_igniter` invocations against the same target project. Per the PRD's
FR-5, only mutating verbs (`mix ggen_igniter.sync`; a future re-actuation
mode of `mix ggen_igniter.replay`, not yet implemented — see `replay.md`)
acquire it. `mix ggen_igniter.doctor` and `mix ggen_igniter.plan` are
read-only and never call `acquire/2` — confirmed by `plan.md`'s own
"Read-only, no lock (FR-5)" section and a real `grep -n "Lock\."
lib/mix/tasks/ggen_igniter.plan.ex lib/mix/tasks/ggen_igniter.doctor.ex`
returning zero matches, this pass.

## What this pass verified

- **The module exists and compiles.** `find lib -iname "*lock*"` now
  returns `lib/ggen_igniter/lock.ex` (142 lines) — the prior pass's
  "zero matches" finding is superseded. `mix compile --warnings-as-errors`
  succeeds with zero warnings from this repo's own `lib/` (one pre-existing,
  unrelated `:preferred_cli_env` deprecation warning from `mix.exs` itself,
  not from `Lock` or any caller).
- **`sync.ex` genuinely calls it.** `grep -n "Lock\."
  lib/mix/tasks/ggen_igniter.sync.ex` shows `GgenIgniter.Lock.acquire/2` at
  line 449 and `GgenIgniter.Lock.release/1` at line 466, inside a
  `try/after` — matching the moduledoc's documented call-site contract.
- **A real invocation does NOT raise `UndefinedFunctionError` on `Lock`
  anymore.** Reproducing the prior pass's exact repro command:

  ```
  $ mix ggen_igniter.sync --ontology test/fixtures/audit_trail_ontology.ttl \
      --query spec=test/fixtures/spec.rq \
      --template test/fixtures/extension.ex.eex --out /tmp/probe.ex
  ** (ArgumentError) errors were found at the given arguments:
    * 1st argument: the table identifier does not refer to an existing ETS table
      (stdlib 7.2) :ets.insert(Reactor.Executor.ConcurrencyTracker, ...)
      (reactor 1.0.6) lib/reactor/executor/concurrency_tracker.ex:75: ...
      (ggen_igniter 26.8.27) lib/ggen_igniter/reactors/reconcile_reactor.ex:640: GgenIgniter.Reactors.ReconcileReactor.run/1
      (ggen_igniter 26.8.27) lib/mix/tasks/ggen_igniter.sync.ex:530: Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3
  ```

  This is a **different, real failure** than the one `docs/status.md`
  previously recorded — the crash is now inside `Reactor.Executor`'s own
  concurrency-pool ETS table (missing, presumably because the `:reactor`
  OTP application's supervision tree is not started when `mix
  ggen_igniter.sync` runs as a bare CLI invocation outside `mix test`), not
  inside `GgenIgniter.Lock`. Whether `Lock.acquire/2` itself ran and
  succeeded before this crash, and whether `Lock.release/1` in the `after`
  block correctly ran to clean up the lock file despite the crash, was
  **not directly observed** this pass (no lock-file existence check was
  made mid-crash) — call this **UNVERIFIABLE-pending-integration**, not
  IMPLEMENTED, until a full run (or a targeted unit test) passes.
- **No dedicated test file exists.** `find test -iname "*lock*"` returns
  zero matches. `GgenIgniter.Lock` has no unit test in this working tree —
  its acquire/release/stale-recovery logic has not been exercised by any
  automated test, only read by inspection this pass.
- **`mix test`'s full-suite result was still resolving as this doc was
  written this pass** — see `docs/status.md`'s `mix test` row for the
  authoritative, freshest count; do not treat this doc's narrower `sync`
  repro above as a substitute for that full-suite number.

## Mechanism (real, by inspection — see full moduledoc in `lock.ex`)

- `acquire/2`: `File.open/2` with `[:write, :exclusive]` against
  `<lock_key>/.ggen_igniter/.sync.lock` — genuine OS-level exclusive-create
  semantics, not an in-BEAM lock, so it correctly serializes two separate
  `mix` OS processes, not just two processes in the same VM. Retries every
  `retry_interval_ms` (default 50ms) until `timeout_ms` (default 30000ms)
  elapses, then raises `RuntimeError` naming the held path.
- Stale-lock recovery: a lock file older than 5 minutes (`@stale_after_ms`)
  is treated as abandoned and removed automatically before retrying — a
  crashed holder cannot permanently wedge future runs.
- `release/1`: `File.rm/1` on the lock path; idempotent (a missing file is
  not an error), matching `sync.ex`'s `try/after` "leave nothing held"
  requirement.

## What remains unverified / open

- End-to-end proof that a real `mix ggen_igniter.sync` run acquires,
  holds, and releases the lock around a full plan+actuate cycle — blocked
  behind the separate `Reactor.Executor.ConcurrencyTracker` ETS issue
  documented above, which is not a `Lock` defect but does prevent observing
  `Lock` in a complete real run.
- Concurrent-process contention (two real OS processes racing
  `acquire/2` against the same `lock_key`) — no test exercises this;
  `docs/status.md`'s "Concurrent-writer safety on `manifest.json`" row
  already flags the adjacent, still-open manifest-race gap this lock is
  presumably meant to close, but that closure itself is not test-proven.
- Stale-lock recovery (the 5-minute abandonment window) — real code,
  reviewed by inspection, not exercised by any test.

## See also

- `docs/status.md` — `GgenIgniter.Lock` row and `sync`-always-attempts-
  receipts row, both updated this pass to reflect the module's existence
- `docs/reference/cli/plan.md` — "Read-only, no lock (FR-5)" — the verbs
  that deliberately never call this module
- `docs/reference/cli/replay.md` — the future re-actuation mode that will
  become this module's second real caller
- `docs/architecture/adr/0007-sync-always-attempts-receipts.md` — the
  design decision `GgenIgniter.Lock` exists to make safe
