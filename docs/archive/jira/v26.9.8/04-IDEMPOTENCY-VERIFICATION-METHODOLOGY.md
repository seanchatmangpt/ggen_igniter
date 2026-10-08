# Idempotency verification methodology — book-library Ash fixture

> **SUPERSEDED — the methodology was executed, by a different mechanism.** The
> five-part definition this ticket specifies still stands and is restated in
> [00-OVERVIEW.md](00-OVERVIEW.md). What proved it was not this ticket's
> per-Tier-1-task shell-out protocol but
> [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md)'s rung G, using two
> independent oracles: Igniter's own `--check` (which halts on any change, warning,
> issue, queued task, move or removal) and a byte-level T1/T2 tree digest. Standing:
> `IDEMPOTENCY_ALIVE` **for the generated tree only** — database idempotency is not
> covered, a gap [08-REVIEW-MANUFACTURE-PATH.md](08-REVIEW-MANUFACTURE-PATH.md)
> records rather than repairs. Read the protocol below as the pre-execution spec.

## Status

**EXECUTED — by 07's rung G, not by the protocol below.** `00-OVERVIEW.md`'s status
table records this ticket as EXECUTED via Igniter `--check` plus a tree diff, and the
receipt's `idempotency` block carries the result: both phases exit 0 under `--check`
(`20-idempotency-check-base.log`, `21-idempotency-check-core.log`), and
`tree_T1_sha256 == tree_T2_sha256 == 65c2ec4e…` with an empty `T1-vs-T2.diff`.

The unchecked boxes below were never ticked because the protocol they belong to was
superseded before it ran — not because idempotency went unverified. They are the
pre-execution spec, kept for the definition they encode.

## Status as originally written (pre-execution, superseded)

**PLANNED / NOT STARTED.** This ticket specs the verification methodology only. It
depends on tickets 01–03 (book-library fixture scaffold, per-task ggen_igniter
wiring, and the harness that drives all Tier-1 tasks) being implemented first.
No command in this document's two-run protocol has been run against this repo;
every checkbox below is unchecked.

**Dry-run precondition satisfied (2026-09-08, HEAD `1738ad1`, uncommitted).** Tickets
01 and 03 are now DRY-RUN VERIFIED (not executed): `test/fixtures/book_library/`
compiles at day zero, and the harness invocation this ticket reuses —
`cd test/fixtures/book_library && mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack --for-each ash_tier_task_query --allow-sh`,
wrapped by `test/fixtures/ash_tier_matrix_pack/bin/matrix_run.sh` — plans 26 receipts
in rank order under `--dry-run` (exit 0, zero files written) and is refused without
`--allow-sh` (exit 1, `ArgumentError` from `check_allow_sh!/3`). See
[DRY-RUN-RECEIPT.md](DRY-RUN-RECEIPT.md). That is the precondition for step 3
("Run 1") below, not step 3 itself: **no `mix ash.*` task has executed, run 1 has
not happened, and nothing in the matrix below is proven.** Two facts the dry run
surfaced that this protocol must account for when it does run: rows 3, 5, 6, 7, 8
(`ash.gen.base_resource/change/preparation/validation/custom_expression`) declare no
`--ignore-if-exists` switch in `ash 3.33.1`, so their run 2 is expected to exit
nonzero (`alp:idempotencyMechanism NONE` in the pack ontology) — a real
ticket-02-vs-deps disagreement, not yet resolved in ticket 02; and rows 22–26 run in
a disposable `mktemp -d` copy of the fixture per the runner's `# destructive: true`
handling. Ticket numbering follows the `docs/jira/v26.9.1/` convention (`00-OVERVIEW.md`
index, numbered `NN-TOPIC.md` files, `GGEN-####` ticket IDs, real evidence citations
only — never a bare status claim).

## Scope note

This ticket set records a pivot: the `xaas`-side `Next Read` case study
(`docs/case-studies/next-read/` in `~/xaas` — `README.md`,
`ILS-AND-EXPLANATION-SUBSTITUTION.md`, `DEFINITION-OF-DONE.md`,
`RCA-ggen-tool-confusion.md`, `FMEA-ggen-tool-selection.md`) is **paused, not
cancelled**, until `xaas` is ready to go live. `ggen_igniter` gets its own new
`test/fixtures/book_library/` — a real, separate `mix.exs` project with
`{:ash, "~> 3.0"}` and `{:ash_postgres, "~> 2.0"}` as actual deps — as the
validation vehicle for whether `ggen_igniter` can drive real Ash Igniter tasks
executably and idempotently. Contrast: `test/fixtures/ash-lifecycle-pack` has no
`mix.exs` and is never compiled against a real `ash` dep; `book_library` must be a
real, compilable Ash project.

## Idempotency definition (stated once; other tickets reference this section)

Running the **same** `ggen_igniter` sync invocation twice against a repo already in
the post-first-run state must produce:

- (a) zero new files on run 2;
- (b) zero changed lines in any previously-generated file (real `git diff`, not
  message text);
- (c) the underlying `mix` task's own natural idempotency mechanism actually
  exercised — `--ignore-if-exists`/`--conflicts=ignore` where the task supports it,
  or the task's own equivalent (e.g. Ecto's applied-migration tracking for
  `ash_postgres.migrate`);
- (d) exit code 0 on both runs;
- (e) no duplicate `config.exs` entries and no duplicate migration files.

## The two-run protocol

1. **Fresh day-zero fixture.** Start from an unmodified `test/fixtures/book_library/`
   checkout (ticket 01's scaffold).
2. **Real git baseline.** `git init` and a first commit inside the fixture directory
   before any sync run, so `git status --short` / `git diff` are a precise signal
   against a known tree, not against an untracked directory.
3. **Run 1.** Invoke the ticket-03 harness once (the harness that drives all
   Tier-1 tasks against the fixture) with the identical, fixed argument set that
   will be reused for run 2. Capture `git status --short` and `git diff --stat` as
   "run 1 diff" — expected to be non-empty (this is the first real generation).
4. **Commit run 1's output** as a second real commit.
5. **Run 2.** Invoke the **identical** invocation, unchanged — same flags, same
   fixture state, same working directory. Capture "run 2 diff" the same way.
6. **The idempotency claim is exactly**: run 2's `git diff --stat` is empty, and
   run 2's `git status --short` shows no new/modified/deleted paths. A non-empty
   run 2 diff is a real defect, not a formality to explain away, unless the task is
   a named exception below.

## Named per-task exceptions to "run 2 diff is empty"

- **`ash_postgres.generate_migrations`** may legitimately create a new file on a
  re-run *if resource state actually changed* between run 1 and run 2. The
  no-op case (resource state unchanged) must be verified via Ash's real
  snapshot-comparison mechanism at `priv/resource_snapshots/` — the task's own
  drift check between the resource module and its last recorded snapshot — rather
  than assumed. Evidence for this task's idempotency claim is: unchanged snapshot
  file content in `priv/resource_snapshots/` plus zero new migration file, not
  merely "the command exited 0."
- **`ash.codegen`, `ash.setup`, `ash.migrate`** are designed to be safely re-run
  but are expected to print re-run-specific log output (e.g. "already up",
  "nothing to do") rather than produce a byte-identical silent run. Evidence for
  these three is: exit code 0 on both runs, plus the log text matching an
  "already applied"-style pattern on run 2 — not literally zero stdout.
- Every other Tier-1 task (see matrix below) is expected to satisfy the strict
  "run 2 diff is empty" rule with no exception.

## Evidence bar (every task claim needs all of these, or a named exception above)

- `git diff --stat` output for run 1 and run 2 (or the named-exception reasoning,
  with the specific mechanism cited — snapshot file, log pattern).
- `mix compile --warnings-as-errors` clean, captured before run 1 and again after
  run 2.
- The standing Chicago-style mock grep, zero matches, run inside the fixture:
  ```
  grep -rn "unittest.mock\|Mock(\|MagicMock\|patch(\|monkeypatch\|Mox\b\|:meck\|meck\." \
    test/fixtures/book_library/test/ test/fixtures/book_library/lib/
  ```
- Exit code of both runs (`echo $?` immediately after each harness invocation, not
  inferred from absence of error text).

## Tier-1 validation matrix (one checkbox per task, unchecked)

Every checkbox below is a claim that must be proven per the two-run protocol above,
against `test/fixtures/book_library/`, once tickets 01–03 land. None are checked
today.

- [ ] `ash.gen.domain`
- [ ] `ash.gen.resource`
- [ ] `ash.gen.base_resource`
- [ ] `ash.gen.enum`
- [ ] `ash.gen.change`
- [ ] `ash.gen.preparation`
- [ ] `ash.gen.validation`
- [ ] `ash.gen.custom_expression`
- [ ] `ash.extend`
- [ ] `ash.patch.extend`
- [ ] `ash.codegen` (log-pattern exception applies)
- [ ] `ash.setup` (log-pattern exception applies)
- [ ] `ash.migrate` (log-pattern exception applies)
- [ ] `ash.rollback`
- [ ] `ash.reset`
- [ ] `ash.tear_down`
- [ ] `ash.set.domains`
- [ ] `ash.manifest.dump`
- [ ] `ash.generate_resource_diagrams`
- [ ] `ash.generate_policy_charts`
- [ ] `ash.generate_livebook`
- [ ] `ash_postgres.install`
- [ ] `ash_postgres.create`
- [ ] `ash_postgres.drop`
- [ ] `ash_postgres.generate_migrations` (snapshot-comparison exception applies)
- [ ] `ash_postgres.migrate` (log-pattern exception applies)
- [ ] `ash_postgres.rollback`
- [ ] `ash_postgres.squash_snapshots`

## Protocol-level checkboxes

- [ ] Two-run protocol itself executed end-to-end at least once against the full
      Tier-1 matrix in a single fixture lifecycle (not per-task in isolation).
- [ ] `--allow-sh` negative path verified: the harness's `sh_before:`/`sh_after:`
      hooks refuse to run without `--allow-sh` (per `check_allow_sh!/3`,
      `lib/mix/tasks/ggen_igniter.sync.ex` around line 1161), and this refusal is
      itself asserted by a real test, not a code-reading claim.

## Deliberately out of scope (Tier 2 — deferred, not silently dropped)

`ash_admin.install`, `ash_authentication.install`, `ash_authentication_phoenix.install`,
`ash_double_entry.install`, `ash_events.install`, `ash_graphql.install`,
`ash_json_api.install`, `ash_money.install`, `ash_oban.install`,
`ash_onetime.install`, `ash_phoenix.gen.*`, `ash_rate_limiter.install`,
`ash_state_machine.install`, `ash_typescript.install`,
`ash_postgres.setup_vector` (pgvector not needed for this fixture), and
`ash_postgres.gen.resources` (reverse-generation, the opposite direction from what
this ticket set validates).

## Cross-links

- Depends on: ticket 01 (`book_library` fixture scaffold — on disk, DRY-RUN
  VERIFIED, uncommitted), ticket 02 (the 26-row matrix — encoded in
  `test/fixtures/ash_tier_matrix_pack/ontology.ttl`, zero rows executed), ticket 03
  (the harness driving Tier-1 tasks against the fixture — on disk, DRY-RUN VERIFIED,
  no hook fired for real).
- `DRY-RUN-RECEIPT.md` — the dry-run evidence behind the precondition note above.
- Prior art (different epic, same repo, same real-evidence discipline):
  `docs/jira/v26.9.1/00-OVERVIEW.md`,
  `docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md`.
- Checklist convention cited: `~/xaas/docs/case-studies/next-read/DEFINITION-OF-DONE.md`.
- Real Ash task source consulted: `deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex`,
  `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex`.
- `sh_before:`/`sh_after:` mechanism: `lib/mix/tasks/ggen_igniter.sync.ex` (schema
  at line 236, help text at line 709, `check_allow_sh!/3` around line 1161),
  verified by `test/ggen_igniter_sync_sh_hooks_test.exs:71`.
- Real OCEL2/EKG infra this fixture's sync runs should also emit events through
  (not built here, wired into): `lib/ggen_igniter/telemetry/ocel_emitter.ex`.
