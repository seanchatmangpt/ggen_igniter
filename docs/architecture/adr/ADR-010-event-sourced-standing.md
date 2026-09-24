# ADR-010: Event-sourced standing (definition_digest + append-only transition log)

Status: accepted (2026-09-20). Milestone v26.9.20.

## Context

A Semantic Jira WorkOrder carries both a definition (subject, courts, evidence
requirements, falsifiers) and a standing (UNKNOWN, PARTIAL_ALIVE, ALIVE,
BLOCKED, ...). Mutating a single record conflates the two: a status edit is
indistinguishable from a definition edit, and a receipt made against an older
definition could silently apply to a changed one.

## Decision (IMPLEMENTED)

1. `GgenIgniter.SemanticJira.definition_digest/1` digests the WorkOrder
   definition only. Standing is not part of the digest.
2. A receipt carries the `definition_digest` it was made against.
   `GgenIgniter.SemanticJira.Reconciler.reconcile/4` refuses with
   `{:refused, :definition_mismatch}` when it differs from the current
   WorkOrder's digest. A stale `snapshot_digest` with a matching definition is
   admissible, so sibling transitions are not invalidated.
3. Admitted transitions are appended to
   `GgenIgniter.SemanticJira.TransitionLog`: one immutable JSON file per event
   (`<seq>-<event_digest>.json`), exclusive-create for `seq`, existing files
   never rewritten, replay of the same event idempotent (`:already_recorded`).
4. Current standing is the projection `SemanticJira.project/2` of the log over
   the graph; it is derived, not stored on the WorkOrder.
5. Authority stays NONE: the reconciler admits a state transition record, it
   does not perform DO.

## Consequences

- Definition edits invalidate outstanding receipts mechanically.
- Standing history is replayable and auditable from the log alone.
- Concurrent writers are serialised by exclusive create, not by a lock file.

## Not claimed

- No cross-host or networked log; the log is local files.
- No log compaction, signing, or tamper-evidence chain beyond per-event digests.

## Evidence

`lib/ggen_igniter/semantic_jira/reconciler.ex`,
`lib/ggen_igniter/semantic_jira/transition_log.ex`,
`test/ggen_igniter_semantic_jira_reconciler_test.exs`.
