# Stream: transition-store (ERRC Create)

Branch `errc/transition-store`, base `dcebc42`. Milestone v26.9.20. Updated 2026-09-21.

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
| `lib/ggen_igniter/semantic_jira/transition_log/store.ex` | `@behaviour`: `append/3`, `list/1`, `stream/1`, `get/2`, `head/1`; `resolve/1,2` spec normaliser |
| `lib/ggen_igniter/semantic_jira/transition_log/file_store.ex` | Original file implementation moved behind the behaviour (same layout, same claim protocol) plus `expected_seq`, `get/2`, `head/1`, lazy `stream/1` |
| `lib/ggen_igniter/semantic_jira/transition_log/postgres_store.ex` | Postgrex store; stub module when `:postgrex` is absent |
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
| Event agrees with its columns | n/a (filename) | `CHECK` on `event_digest` and `seq` inside the JSON document |
| Optimistic concurrency | `expected_seq`: claim exactly that seq or `{:error, {:seq_conflict, head}}` | same; without `expected_seq` a `UNIQUE(seq)` loser re-reads head and retries (bounded) |
| Fail closed | n/a | `connect/1`/`new/2` inspect the catalog and refuse a table missing any invariant |

## Design choices retained and rejected

- Retained: behaviour keyed on a `ref` (path or struct) so `TransitionLog` stays a thin facade and a
  bare path still means the file store.
- Rejected: `Ecto.Repo`/`ash_postgres` as the store (runtime-scoped Ash is a repo non-goal; Postgrex
  is the smaller dependency and is optional).
- Rejected: advisory-lock serialisation of appends (pessimistic; the task asks for optimistic
  concurrency and the unique constraints are the arbiter).
- Rejected: gap-free `seq` via a sequence or lock. The file store also permits gaps; contiguity is
  observed, not promised.

## Status rows (proposed for docs/status.md)

| Capability | Status | Evidence |
|---|---|---|
| Transition-log storage behaviour + FileStore refactor | IMPLEMENTED | file store passes the shared contract (20 tests) and the pre-existing reconciler, crown and descriptor suites; on-disk bytes equal the golden fixture written by the pre-refactor code |
| Postgres transition-log store (`PostgresStore`) | ALIVE (observed against local Postgres 14.19) | 31 tests against a real database, including 60 concurrent writers on two pools with no duplicate seq (an uncommitted ad hoc script ran 400 writers on two pools: 0 errors, seq 1..400 in 2.0 s) |
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
- Pre-existing, unchanged: `FileStore` duplicate waiters return `{:ok, nil, :already_recorded}` if the
  digest-claiming writer crashed before writing its file (`await/3` gives up after 500 tries).
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
