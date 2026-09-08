# OCEL v2 projection of the ticket-03/04 Ash validation harness — GGEN-1908

> **SUPERSEDED — this ticket was executed.** The projection specified here exists and
> runs. [00-OVERVIEW.md](00-OVERVIEW.md)'s status table records ticket 06 as EXECUTED,
> and [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md) rung H is the closing
> evidence. The harness this ticket names — tickets 03/04's `--allow-sh` shell-out —
> was itself superseded, so the projection was wired to the composed manufacture path
> instead. Read the spec below as the pre-execution design.

## Status

**EXECUTED.** The "no code written" line below is false as of the qualification run.
What exists now:

- `lib/ggen_igniter/telemetry/ocel2_export.ex` — the OCEL 2.0 serializer, with a
  Chicago-style suite at `test/ggen_igniter_ocel2_export_test.exs`.
- `lib/mix/tasks/ggen_igniter.ocel.seal.ex` — appends the outcome the caller actually
  observed, because the manufacture task emits its decisions from inside `igniter/1`,
  which runs *before* Igniter applies anything. An unsealed log is a conformance
  violation. See 08 §B1.
- Both run-1 and run-2 logs import into the real `BeamPM.Rust4PM.import_ocel_json/2`
  (rung H, `44-beam4pm-import.log`), returning `{:ok, %{"ocel_handle" => n}}`.
  Compatibility is tested against the real importer, not asserted against a fixture
  the same author read — see 08 §B3.

Standing: `OCEL_PROCESS_ALIVE`, with the bound 08 records — the *format* is verified
against a foreign importer, but the *semantics* of the conformance check remain
partly a closed authorial loop.

## Status as originally written (pre-execution, superseded)

**PLANNED / NOT STARTED.** No code written for this ticket. This document specs wiring
existing infra only; nothing below has been implemented or run.

## Scope note — distinct from v26.9.1

This ticket lives under `docs/jira/v26.9.8/`, a different version line from
`docs/jira/v26.9.1/` (the fortune5-ready bundle installer epic, all DONE/merged-pending
per that directory's `00-OVERVIEW.md`). Zero code-path overlap; do not conflate.

## Charter (Define)

The v26.9.8 ticket set (00–05, all written; 01 and 03 DRY-RUN VERIFIED per
`DRY-RUN-RECEIPT.md`) specs a new real `test/fixtures/book_library/` Ash fixture
(now on disk, untracked) — a genuine separate `mix.exs` project with
`{:ash, "~> 3.0"}`, `{:ash_postgres, "~> 2.0"}`, in contrast to `test/fixtures/ash-lifecycle-pack`
(no `mix.exs`, never compiled against a real `ash` dep, confirmed this session) — as the real
validation vehicle for whether `ggen_igniter` can drive Ash Igniter tasks (`mix ash.gen.domain`,
`mix ash.gen.resource`, etc.) executably and idempotently via `sh_before:`/`sh_after:` frontmatter
(`lib/mix/tasks/ggen_igniter.sync.ex` line 236 schema, line 709 help text, `check_allow_sh!/3`
around line 1161), gated behind `--allow-sh`, per this session's decision that mode (2) is correct
for Ash tasks specifically (they are themselves real Igniter tasks doing correct AST-aware
`config.exs` editing that an EEx template would duplicate worse — see `test/fixtures/ash-lifecycle-pack/templates/domain.ex.eex`
for the mode-(1) contrast).

This ticket (GGEN-1908) specs **one slice** of that validation: wiring the existing
`GgenIgniter.Telemetry.OcelEmitter` into ticket-03's harness so every Tier-1 Ash mix-task
invocation during the ticket-04 two-run idempotency protocol emits real OCEL v2 events. Per the
user's own words: "OCEL v2 logs should be projected so that we know exactly what is happening" —
this ticket is the mechanism for that, not new OCEL infra.

## Existing infra this ticket wires into (do not rebuild)

- `lib/ggen_igniter/telemetry/ocel_emitter.ex` — `GgenIgniter.Telemetry.OcelEmitter`, real public
  API: `telemetry_event/0`, `new_sink/0`, `drain_sink/1`, `peek_sink/1`,
  `emit/4(sink, activity, objects, attributes \\ %{})`, `file_object/1`, `run_object/1`,
  `find_last/2`, `any?/2`.
- Precedent tests: `test/ggen_igniter_ocel_emitter_test.exs`,
  `test/ggen_igniter_sync_ocel2_ekg_pack_test.exs`, `test/ggen_igniter_sync_beam4pm_bench_pack_test.exs`.
- Real OCEL2/EKG pack: `priv/ggen/ocel2-ekg-pack/` (`templates/ocel2.ex.eex`).
- Docs: `doc/ocel.md`, `docs/reference/evidence/ocel.md`.

## What this ticket specs (Develop, not yet built)

1. **Activity-naming scheme**: one activity per Tier-1 mix-task invocation, named
   `<task_snake_case>_run`, e.g. `ash_gen_resource_run`, `ash_postgres_migrate_run`,
   `ash_gen_domain_run`. One `emit/4` call per real invocation (not per file).
2. **Attributes** carried on each `emit/4` call: `mix_task` (string), `mix_args` (list of
   strings, the real argv passed to `System.cmd`), `exit_code` (integer), `run_number` (`1` or
   `2`, per the ticket-04 two-run idempotency protocol), `git_diff_empty?` (boolean, computed
   from the real `git diff` ticket 04 already runs after each invocation).
3. **Objects**: `run_object/1` for the sync invocation's own run id (one object per two-run
   protocol execution, shared across both runs so they correlate); `file_object/1` for each file
   the task touched, sourced from the same git-diff output ticket 04 computes — no new diff logic,
   reuse ticket 04's.
4. **Wiring point**: this is pure instrumentation of ticket 03's harness — likely a thin wrapper
   script or mix task around each real `mix <ash task>` invocation that calls `emit/4` before
   (activity start, `run_number`) and after (attributes finalized with `exit_code`,
   `git_diff_empty?`) the real `System.cmd` call. No new OCEL emitter code, no new pack.
5. **Evidence collection for this ticket set's own status claims**: `drain_sink/1` after each
   two-run protocol execution, so the ticket-04 acceptance evidence can cite real OCEL event
   counts/contents alongside the git-diff and exit-code evidence, not instead of it.

## Open question — explicitly not decided

Whether this ticket set should also export/replay the captured events into a real `beam4pm`
instance (a separate real repo at `~/beam4pm`, also `~/beam4pm-wt-ferroplan`, `~/beam4pm_ws2`
worktrees — process-mining/OCEL2 event-knowledge-graph tooling: DFG discovery, conformance
checking) for actual process-mining analysis, versus just emitting events locally via
`drain_sink/1` for this ticket set's own evidence. **Not assumed in scope.** Requires explicit
user confirmation before any `beam4pm` integration work is planned or started.

## Non-goals

- Building new OCEL emitter/pack infrastructure (none needed; `OcelEmitter` already covers this).
- The ticket-03 harness itself (referenced, not specified here).
- The ticket-04 two-run idempotency protocol itself (referenced, not specified here — this ticket
  consumes its git-diff output, does not compute it).
- Any `beam4pm` integration (see Open Question above).

## See Also

- `00-OVERVIEW.md` (this directory) status table and `DRY-RUN-RECEIPT.md` — tickets 01/03
  reached DRY-RUN VERIFIED on 2026-09-08; no OCEL wrapper was built or tested in that pass (it
  was not in scope), so this ticket remains PLANNED / NOT STARTED. The harness it would
  instrument is `test/fixtures/ash_tier_matrix_pack/bin/run_pending_receipts.sh`.
- `docs/jira/v26.9.1/00-OVERVIEW.md` — the unrelated, prior, DONE v26.9.1 ticket set (different
  epic, coincidental version-number collision pattern already documented there).
- `docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md` — structural precedent for this document's
  status-vocabulary discipline and evidence-citation style.
- `lib/ggen_igniter/telemetry/ocel_emitter.ex`, `doc/ocel.md`, `docs/reference/evidence/ocel.md`.

Claude-Session: https://claude.ai/code/session_01K6xoATrg9HDDL9JBvjpPNC
