# Stream: transition-store (ERRC Create)

Branch `errc/transition-store`, base `dcebc42`. Milestone v26.9.20. Updated 2026-09-21 (repair round).

Stream note for the integrator: `docs/status.md`, `CHANGELOG.md` and the `mix.exs` version are
deliberately not edited on this branch. The rows below are proposed status entries; the ADR-010
amendment is proposed text.

## Charter

Give the append-only standing-transition log (ADR-010) a storage behaviour, and add a real
Postgres-backed store that enforces the same invariants in SQL, without changing the public
`TransitionLog` API or the on-disk file format.

## Delivered

| Path | Role |
|---|---|
| `lib/ggen_igniter/semantic_jira/transition_log/store.ex` | `@behaviour`: `append/3`, `list/1`, `stream/1`, `get/2`, `head/1`; `resolve/1,2` spec normaliser (binary, charlist/chardata, `{module, ref}`, struct); shared `event_digest/1` and `admit/1` |
| `lib/ggen_igniter/semantic_jira/transition_log/file_store.ex` | Original file implementation moved behind the behaviour (same layout) plus `expected_seq`, `get/2`, `head/1`, lazy `stream/1`; the digest claim is now a protocol with release, wait, re-claim and stale takeover (see Repair round) |
| `lib/ggen_igniter/semantic_jira/transition_log/postgres_store.ex` | Postgrex store (`event json`); definition-level catalog verification; stub module when `:postgrex` is absent |
| `lib/ggen_igniter/semantic_jira/transition_log.ex` | Facade: `read/1` and `append/2` unchanged in signature and behaviour; additive `append/3`, `stream/1`, `get/2`, `head/1` |
| `lib/ggen_igniter/semantic_jira/reconciler.ex` | `reconcile/4` honours `store:`; third argument accepts a path, `{module, ref}` or a store struct |
| `mix.exs` | `{:postgrex, "~> 0.19", optional: true}` (already in `mix.lock` via `ash_postgres`; lock unchanged) |
| `test/support/{transition_store_case,transition_log_postgres,semantic_jira_fixtures}.ex` | Shared store contract, Postgres probe, WorkOrder/receipt fixtures |
| `test/ggen_igniter_semantic_jira_transition_store_{file,postgres}_test.exs` | Contract runs against both stores; backward-compat and Postgres-only invariants |
| `test/fixtures/transition_log_golden/` | Log directory written by the pre-refactor implementation at `dcebc42` |

## Invariants and where each is enforced

| Invariant | FileStore | PostgresStore |
|---|---|---|
| Exclusive per-digest claim | exclusive-create `digest-*.claim` | `UNIQUE(digest)` + `ON CONFLICT (digest) DO NOTHING` |
| Exclusive per-seq claim | exclusive-create `seq-*.claim` | `UNIQUE(seq)`, `CHECK (seq > 0)` |
| Append-only | never rewrite an event file | triggers reject `UPDATE`/`DELETE`/`TRUNCATE` (SQLSTATE 23001) |
| Event agrees with its columns | n/a (filename) | total `CHECK`: JSON object, numeric `seq` = `seq`, `event_digest` = `digest`; a missing key is rejected, not NULL-accepted |
| Optimistic concurrency | `expected_seq`: claim exactly that seq or `{:error, {:seq_conflict, head}}` | same; without `expected_seq` a `UNIQUE(seq)` loser re-reads head and retries (bounded) |
| Fail closed | n/a | `connect/1`/`new/2` verify DEFINITIONS (constraint text vs a TEMP reference table built by the same DDL, columns, trigger `tgtype`/enabled/`WHEN`/function source) and refuse a table whose definitions differ, not just one whose names are missing |

## Design choices retained and rejected

- Retained: behaviour keyed on a `ref` (path or struct) so `TransitionLog` stays a thin facade and a
  bare path still means the file store.
- Rejected: `Ecto.Repo`/`ash_postgres` as the store (runtime-scoped Ash is a repo non-goal; Postgrex
  is the smaller dependency and is optional).
- Rejected: advisory-lock serialisation of appends (pessimistic; the task asks for optimistic
  concurrency and the unique constraints are the arbiter).
- Rejected: gap-free `seq` via a sequence or lock. The file store also permits gaps; contiguity is
  observed, not promised.

## Repair round (2026-09-21): qualifier findings and their guards

Eleven findings from two independent qualifiers were collapsed to six root causes. Each has a
permanent test that was RED before the fix.

| Root cause | Fix | Permanent guard |
|---|---|---|
| FileStore: a strict writer that lost the seq race released its digest claim while duplicates were parked in `await/3`, which never re-checked the claim, so they returned `{:ok, nil, :already_recorded}` (new code, needs no crash). Same code path returned nil for a crash-orphaned claim (inherited from `dcebc42`). | `await` returns only a stored event; when the claim is released it re-enters the claim protocol (`attempt/3`), when its mtime has not changed for `claim_stale_ms` (default 5 s, min 1 s, one-second mtime resolution) it takes the claim over under an exclusive `.takeover` lock with a re-check; the owner touches the claim while it searches for a seq, re-checks that nobody stored the digest before renaming, and releases the claim on an exception. | qualifier falsifier 1 (20 of 48 strict appends were nil); file_test `claim protocol` describe: released claim re-claimed, mixed strict/lenient duplicates never nil, orphan claim + 16 duplicates stores once, orphaned `.takeover` lock, live owner (touching) not taken over. Mutation check: returning `{:ok, find(...)}` on release reproduces `20 of 48` and fails 3 tests. |
| PostgresStore CHECK was NULL-accepting for a missing key. | `CHECK (COALESCE(json_typeof(event)='object' AND json_typeof(event->'seq')='number' AND event->>'event_digest' = digest AND (event->>'seq')::bigint = seq, false))` | qualifier falsifier 2; postgres_test `CHECK is total` (empty object, array, digest only, seq only, string seq, numeric digest); hollow test with the original NULL-accepting CHECK is refused. |
| Catalog verification compared names only. | `invariants/1` compares constraint definitions to a TEMP reference table, columns, and trigger structure and function source. New keys `columns`, `seq_positive`. `migrate!/1` still only creates what is absent (it re-creates the trigger function, which it owns by name). | qualifier falsifier 3; 11 table-driven hollow-definition tests (UNIQUE over another column, CHECK true, NULL-accepting CHECK, UPDATE-only trigger, AFTER trigger, disabled trigger, WHEN false, truncate trigger on wrong event, no-op function) each refused with the exact key; migrate: true refuses hollow constraints/triggers and repairs only a no-op function. |
| `Store.resolve/1` had no clause for a charlist; `Path.t()` is IO.chardata (regression vs `dcebc42`). | `resolve/1` normalises any list with `IO.chardata_to_string/1`. | compat falsifier; file_test charlist describe (TransitionLog read/append/head/get and `Reconciler.reconcile/3,4`). |
| `event_digest` was computed with the existing `event_digest` key still in the input, so re-appending a stored event, or copying a log between stores, produced a new digest. | `Store.event_digest/1` drops `"seq"` and `"event_digest"`; both stores use it. An event carrying neither key keeps its old digest (golden fixture bytes unchanged). | compat falsifiers (file, Postgres, file-to-Postgres migration keeps digests and seq). |
| (Beyond the filed list; RED in the compat falsifier file) `jsonb` rewrites `1.0e16` to an integer and `-0.0` to `0.0`, so the stored event's `event_digest` was not re-derivable on Postgres; `\u0000` was storable in files, not in Postgres. | Column type `json` (the stored text is the record); `Store.admit/1` refuses U+0000 in any string in both stores (`{:error, {:unstorable_event, :nul_character}}`). This narrows FileStore: it used to accept U+0000. | compat falsifier cross-store tests; file_test `Store.admit/1`. |

Consequences to know: existing tables created by the pre-repair `migrate!/1` (`event jsonb`, NULL-accepting
CHECK) are refused by `connect/1` with `{:missing_invariants, [:columns, :event_consistent]}` and are not
altered; only the throwaway test database has such tables.

Residual, not claimed away (FileStore): an owner suspended (SIGSTOP, huge GC pause) for longer than
`claim_stale_ms` between its final "nobody stored this digest" re-check and its rename can still publish a
duplicate of an event a taker already stored. The `.takeover` lock's own staleness rests on wall-clock
seconds. Not verified: `pg_rewrite` rules, `session_replication_role`, roles and grants on the Postgres
side.

Real crash qualification (not committed): a BEAM running 30 concurrent writers was killed with `kill -9`; it
left 31 events, 60 digest claims, 29 orphan claims. Replaying 600 events through the repaired store: 0 nil
events, 0 errors, 600 events with 600 distinct digests, no leftover `.takeover` locks.

## Status rows (proposed for docs/status.md)

| Capability | Status | Evidence |
|---|---|---|
| Transition-log storage behaviour + FileStore refactor | IMPLEMENTED | file store passes the shared contract and the claim-protocol guards (27 tests) and the pre-existing reconciler, crown and descriptor suites; on-disk bytes equal the golden fixture written by the pre-refactor code |
| Postgres transition-log store (`PostgresStore`) | ALIVE (observed against local Postgres 14.19) | 44 tests against a real database, including 60 concurrent writers on two pools with no duplicate seq (an uncommitted ad hoc script ran 400 writers on two pools: 0 errors, seq 1..400 in 2.0 s) |
| Replay from PostgresStore equals replay from FileStore | ALIVE for the tested scenarios | sequential scenario: event lists equal exactly; concurrent scenario: event sets and projections equal |

## Falsifiers run

Each mutation was applied to `postgres_store.ex`, the Postgres suite run, and the file restored.

| Mutation | Result |
|---|---|
| remove `UNIQUE(seq)` | 29/29 fail (connect refuses the table) |
| make trigger creation a no-op | 29/29 fail (connect refuses the table) |
| remove `ON CONFLICT (digest) DO NOTHING` | 4 fail (same-event concurrency) |
| remove the seq-collision retry | 7 fail (concurrent writers) |
| ignore `expected_seq` | 2 fail |
| replace the consistency `CHECK` with `true` | 1 fail |

Observed side effect: tables left in the throwaway database by the mutated runs (no `UNIQUE(seq)`)
collided with later tests that reused the same per-VM counter in their table name, and `connect/1`
correctly returned `{:missing_invariants, [:unique_seq]}`. That produced 3 intermittent failures in 12
runs. Test tables are now named with a millisecond timestamp plus the counter, cleanup is registered
before connect, and "a pre-existing table that lacks an invariant is refused" is a permanent test.
After the fix: 15 consecutive runs of the Postgres suite, 0 failures, 0 leaked tables or functions.

## BLOCKED / UNSUPPORTED / not claimed

- UNVERIFIED: a real consumer project without `:postgrex`. Evidence is narrower: the module file was
  compiled by a VM whose code path lacks Postgrex, producing the stub (no warnings); its functions
  raise the actionable error.
- Not claimed: tamper-evidence (signing/hash chain), compaction, cross-database or multi-node
  consistency beyond one Postgres primary, `seq` gap-freedom, other SQL engines.
- Not claimed: the stream is observed at READ COMMITTED with autocommit inserts; a reader can briefly
  see `seq` n+1 before n commits. `SemanticJira.project/2` sorts by `seq`, so a settled log replays
  deterministically.
- Resolved in the repair round: `FileStore` duplicate waiters returning `{:ok, nil, :already_recorded}` (both the
  strict-loser variant and the crashed-writer variant); see Repair round for the residual.
- HAND-WRITTEN: all of the above. UNSUPPORTED(generator-capability): no ggen pack or Igniter
  generator covers an Elixir storage behaviour or a Postgres migration for a log table; the store and
  its DDL are hand-written residue. The DDL is not an Ash resource, so the Ash hand-write guard does
  not apply.

## Proposed ADR-010 amendment

Replace "No cross-host or networked log; the log is local files." with: the log has two stores behind
`TransitionLog.Store`: local files (default) and a Postgres table enforcing the same invariants in SQL.
Cross-host visibility exists only through the Postgres store; signing and compaction remain unclaimed.

## See Also

- `docs/architecture/adr/ADR-010-event-sourced-standing.md`
- `test/CLAUDE.md` for the Chicago-style test conventions applied here
