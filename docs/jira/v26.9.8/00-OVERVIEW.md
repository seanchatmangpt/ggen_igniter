# Book-Library Ash Validation Fixture v26.9.8 — Overview

Index ticket for this directory's eight numbered tickets (01-08): pivoting
`ggen_igniter`'s near-term Ash Igniter-task validation vehicle from the `xaas` repo's
Next Read case study to a new, purpose-built `test/fixtures/book_library/` fixture
inside this repo. Tickets 01-06 were written first, against the shell-out design;
07 and 08 replaced that design with an executed one and are the current authority.

> **SUPERSEDED IN PART.** The `sh_after:` + `--allow-sh` design this ticket set
> was written around is no longer the path. It is replaced by a composed
> `Igniter.Mix.Task` rendered from the ontology —
> [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md) — which has been
> executed for real, not dry-run. Tickets 01/03/04's dry-run findings remain
> historically accurate and are kept; their *conclusions* about how to drive
> Ash tasks are superseded. Read 07 first, then
> [08-REVIEW-MANUFACTURE-PATH.md](08-REVIEW-MANUFACTURE-PATH.md).

**Status as of 2026-09-08.** The narrow Book/Loan path is EXECUTED and
qualified, not dry-run. `bin/qualify.sh` ran 29 commands with 0 failures
against a day-zero fixture and a run-scoped database; run 2 exits 0 under
Igniter's own `--check` in both phases and the generated tree is
byte-identical (`T1 == T2`, `tree_T1_sha256` `65c2ec4e…`). Machine-readable proof:
[evidence/receipt.json](evidence/receipt.json). Every artifact path cited anywhere in
this directory is resolved by `bin/check_doc_citations.sh`.

Five standings, each from an observed execution:

| Standing | Result | What established it |
|---|---|---|
| `ONTOLOGY_ALIVE` | true | `mix ggen_igniter.sync --pack-dir ash_manufacture_pack` renders the composed task from 11 gates |
| `ASH_MANUFACTURE_ALIVE` | true | real `ash.install`/`ash_postgres.install`/`ash.gen.*` composed; `books` + `loans` tables exist in the run-scoped database |
| `IDEMPOTENCY_ALIVE` | true (tree only) | `--check` exit 0 in both phases; `T1 == T2`. Database idempotency is NOT covered — see 08 |
| `OCEL_PROCESS_ALIVE` | true | both logs import into beam4pm's real `process_mining` importer; conformance clean with 0 violations |
| `AGENT_HANDWRITE_REFUSAL_ALIVE` | true | `refuse-handwritten-ash.sh` exercised through the real stdin hook protocol: 2 block cases, 2 allow cases |

Two capability counts are in play and they are not in conflict — read the
denominator before comparing them:

- **16** — the tasks on the manufacture path, as carried in `receipt.json`
  `capability_matrix`: 7 `ALIVE`, 4 `PARTIAL_ALIVE`, 3 `UNSUPPORTED`, 1
  `BUILD_BROKEN`, 1 `UNKNOWN`.
- **21** — every `amp:GeneratorCapability` individual in the pack ontology, which
  also covers five Igniter tasks off the manufacture path: 7 `ALIVE`, 5
  `PARTIAL_ALIVE`, 4 `UNSUPPORTED`, 1 `BUILD_BROKEN`, 4 `UNKNOWN`; 12 admitted, 9
  refused. This is the set ticket 02's matrix grades.

The `UNSUPPORTED`/`BUILD_BROKEN` rows are typed refusals that reach the OCEL log
as `capability_refused` events — never silent skips.

| Ticket | Status | Evidence |
|---|---|---|
| 01 fixture | SUPERSEDED by 07's day-zero protocol | `bin/day_zero.sh` now defines the subject deterministically |
| 02 matrix | REWRITTEN against real dep source | [02-ASH-TASK-VALIDATION-MATRIX.md](02-ASH-TASK-VALIDATION-MATRIX.md) |
| 03 harness | SUPERSEDED — `sh_after`/`--allow-sh` not used | 07 §"What changed and why" |
| 04 idempotency | EXECUTED via Igniter `--check` + tree diff | receipt `idempotency` block |
| 05 deferral | UNCHANGED — xaas stays deferred | no change |
| 06 OCEL | EXECUTED | `GgenIgniter.Telemetry.Ocel2Export` + real beam4pm import |
| 07 manufacture path | EXECUTED / QUALIFIED | [evidence/](evidence/) |
| 08 review | COMPLETE — 4 blockers repaired, gaps recorded | [08-REVIEW-MANUFACTURE-PATH.md](08-REVIEW-MANUFACTURE-PATH.md) |

## The pivot

`xaas`'s Next Read case study (`~/xaas/docs/case-studies/next-read/README.md`,
`ILS-AND-EXPLANATION-SUBSTITUTION.md`, `DEFINITION-OF-DONE.md`,
`RCA-ggen-tool-confusion.md`, `FMEA-ggen-tool-selection.md`, all written this
session) is **paused, not cancelled**, until `xaas` itself is ready to go live. The
RCA and FMEA in that case study identified real tool-selection confusion when
driving `ggen_igniter` against a live, non-fixture consumer app; validating the Ash
task-driving story does not require `xaas` readiness as a precondition, and blocking
on it stalls this repo's own capability work for no benefit.

Instead, `ggen_igniter` gets its own real "book" library-domain Ash fixture, now on
disk (untracked) at `test/fixtures/book_library/`, as a genuine separate `mix.exs` project declaring
real `{:ash, "~> 3.0"}` and `{:ash_postgres, "~> 2.0"}` deps. This is a deliberate
contrast with the existing `test/fixtures/ash-lifecycle-pack/` fixture, which has
**no `mix.exs`** and is confirmed (this session) never compiled against a real `ash`
dependency — its `templates/domain.ex.eex` hand-renders Elixir source text that
merely resembles what a real Igniter generator produces, without ever exercising one.
`test/fixtures/book_library/` closes that gap: it is the vehicle for proving whether
`ggen_igniter` can drive real Ash Igniter tasks executably and idempotently, detailed
in ticket 01.

## Idempotency definition (stated once; other tickets reference this section)

Still current. Running the **same** invocation twice against a repo already in the
post-first-run state must produce:

- (a) zero new files on run 2;
- (b) zero changed lines in any previously-generated file (real `git diff`, not
  message text);
- (c) the underlying `mix` task's own `--ignore-if-exists`/`--conflicts=ignore` (or
  equivalent natural idempotency, e.g. Ecto's applied-migration tracking for
  `ash_postgres.migrate`) actually exercised;
- (d) exit code 0 both runs;
- (e) no duplicate `config.exs` entries or duplicate migration files.

Ticket 04 specified the methodology for proving this. What actually proved it is
07's rung G, with two independent oracles — Igniter's own `--check` and a byte-level
T1/T2 tree digest — and the standing it establishes is `IDEMPOTENCY_ALIVE` **for the
generated tree only**. Database idempotency remains unproven; 08 records that gap.

---

# Pre-execution history (superseded — retained for provenance)

Everything below this line was written **before** the manufacture path was executed,
against the `sh_after:` + `--allow-sh` shell-out design that 07 replaced. It is kept
because its dependency-verified findings are real and were the input to the redesign.

**On any conflict, the status table above governs.** Statuses below — `PLANNED / NOT
STARTED`, `DRY-RUN VERIFIED`, "not yet met", "no claim that any ticket is done" —
describe the state of this set before the qualification run, not its state now.
Ticket 02 was rewritten against real deps; tickets 04 and 06 were executed. The
harness this section's reproduction commands invoke,
`test/fixtures/ash_tier_matrix_pack/`, has since been **deleted** from the repo, so
those commands no longer run at all.

## Two real EEx actuation modes, and why mode (2) was chosen (pre-execution)

Verified before the manufacture path existed, `ggen_igniter` has two real template
actuation modes:

1. **`mode: file`** — a template hand-renders a full Elixir module (e.g.
   `test/fixtures/ash-lifecycle-pack/templates/domain.ex.eex`), duplicating what a
   real Igniter generator does and skipping `config.exs` wiring entirely.
2. **`sh_before:`/`sh_after:` frontmatter** — shells a real command via
   `System.cmd`, verified in `test/ggen_igniter_sync_sh_hooks_test.exs:71`, gated
   behind an explicit `--allow-sh` flag
   (`lib/mix/tasks/ggen_igniter.sync.ex:236` schema, `:709` help text,
   `check_allow_sh!/3` around `:1161`).

Decision made at the time: **mode (2) is correct for Ash tasks specifically**.
*Superseded by 07:* the premise — that a real Igniter task should drive the work
rather than a template re-rendering it — was right, but shelling out was the wrong
way to reach it. `Igniter.compose_task/4` calls the same real tasks in one
`%Igniter{}` with one diff and one write, and exposes Igniter's own `--check`
oracle, which a subprocess exit code cannot. The reasoning that follows is kept
because it is the reasoning that produced that premise.

The original argument: `mix ash.gen.domain`/`mix ash.gen.resource` are themselves
real Igniter tasks doing correct AST-aware work (`config.exs` `ash_domains:` list editing, domain
resource-reference registration) that re-implementing in an EEx template would
duplicate worse. Confirmed by direct read of `deps/ash/lib/mix/tasks/gen/
ash.gen.domain.ex` (91 lines: creates the domain module, auto-edits `config.exs`
`ash_domains:`, only flag `--ignore-if-exists`) and `deps/ash/lib/mix/tasks/gen/
ash.gen.resource.ex` (804 lines: `--attribute`/`-a`, `--relationship`/`-r`,
`--default-actions`, `--uuid-primary-key`/`-u`, `--uuid-v7-primary-key`,
`--integer-primary-key`/`-i`, `--domain`/`-d`, `--extend`/`-e`, `--base`/`-b`,
`--timestamps`/`-t`, `--ignore-if-exists`, `--conflicts` (`ignore`\|`replace`)).
Ticket 03 builds the `--allow-sh` harness this pivot depends on.

## Tier 1 / Tier 2 split (pre-execution scope record)

**Tier 1 (in scope, ticket 02's validation matrix)** — core/cross-cutting Ash tasks,
per a real `mix help` in `~/xaas`: `ash.gen.domain`, `ash.gen.resource`,
`ash.gen.base_resource`, `ash.gen.enum`, `ash.gen.change`, `ash.gen.preparation`,
`ash.gen.validation`, `ash.gen.custom_expression`, `ash.extend`, `ash.patch.extend`,
`ash.codegen`, `ash.setup`, `ash.migrate`, `ash.rollback`, `ash.reset`,
`ash.tear_down`, `ash.set.domains`, `ash.manifest.dump`,
`ash.generate_resource_diagrams`, `ash.generate_policy_charts`,
`ash.generate_livebook`, `ash_postgres.install`, `ash_postgres.create`,
`ash_postgres.drop`, `ash_postgres.generate_migrations`, `ash_postgres.migrate`,
`ash_postgres.rollback`, `ash_postgres.squash_snapshots`.

That prose list is 28 names; ticket 02's matrix and the pack ontology carry **26 rows**.
`ash.migrate` and `ash.rollback` have no row of their own (ticket 02 carries only the
`ash_postgres.migrate`/`ash_postgres.rollback` rows), and two names differ from ticket
02's literal because of what exists in `deps/`: row 20 is `ash.generate_policy_chart`
(singular) and row 23 is `ash.reset` (there is no `ash_postgres.reset`). Ticket 03's
"SPARQL query shape" section and `alp:specDeviation` in the ontology record each one.

**Tier 2 (explicitly deferred, not silently dropped — ticket 05)** — every
extension-specific `*.install`/feature task: `ash_admin`, `ash_authentication`
(`_phoenix`), `ash_double_entry`, `ash_events`, `ash_graphql`, `ash_json_api`,
`ash_money`, `ash_oban`, `ash_onetime`, `ash_phoenix.gen.*`, `ash_rate_limiter`,
`ash_state_machine`, `ash_typescript`, `ash_postgres.setup_vector` (pgvector, not
needed), `ash_postgres.gen.resources` (reverse-generation, different direction).

## OCEL/beam4pm observability requirement (pre-execution)

Every validation run in this ticket set should be observable as real OCEL v2 events
via the existing `GgenIgniter.Telemetry.OcelEmitter`
(`lib/ggen_igniter/telemetry/ocel_emitter.ex`; real public API: `telemetry_event/0`,
`new_sink/0`, `drain_sink/1`, `peek_sink/1`, `emit/4`, `file_object/1`,
`run_object/1`, `find_last/2`, `any?/2`) — this is new observability wiring, not new
OCEL infrastructure. `ggen_igniter` already has real OCEL2/EKG support: tests at
`test/ggen_igniter_ocel_emitter_test.exs`, `test/ggen_igniter_sync_ocel2_ekg_pack_test.exs`,
`test/ggen_igniter_sync_beam4pm_bench_pack_test.exs`, a real pack at
`priv/ggen/ocel2-ekg-pack/templates/ocel2.ex.eex`, and docs at `doc/ocel.md`,
`docs/reference/evidence/ocel.md`. `~/beam4pm` (with worktrees `~/beam4pm-wt-ferroplan`,
`~/beam4pm_ws2`) is the separate, real process-mining/OCEL2 event-knowledge-graph repo
this projection ultimately feeds. Ticket 06 details wiring each Tier 1 task
invocation and each idempotency-verification run (ticket 04) to emit real `emit/4`
calls (activity = the mix task name, objects = file/run objects, attributes =
exit code and idempotency-check result) rather than leaving these runs unobserved.

## Tickets, as scoped pre-execution (statuses below are superseded)

1. [01-BOOK-CASE-STUDY-FIXTURE](01-BOOK-CASE-STUDY-FIXTURE.md) — **DRY-RUN
   VERIFIED (not executed).** `test/fixtures/book_library/` exists (untracked) as a
   real, separate `mix.exs` project with real `ash 3.33.1`/`ash_postgres 2.13.1`
   deps and compiles clean at day zero, contrasted explicitly with
   `ash-lifecycle-pack`'s no-`mix.exs` gap. No `ash.gen.*` task has been run in it.
2. [02-ASH-TASK-VALIDATION-MATRIX](02-ASH-TASK-VALIDATION-MATRIX.md) — **PLANNED /
   NOT STARTED.** The full Tier 1 task-by-task validation matrix: which
   `ggen_igniter` sync mode drives each task, what real evidence closes it. The 26
   rows are encoded in `test/fixtures/ash_tier_matrix_pack/ontology.ttl` and appear
   in the dry-run plan; zero rows have been executed.
3. [03-SH-AFTER-ALLOW-SH-HARNESS](03-SH-AFTER-ALLOW-SH-HARNESS.md) — **DRY-RUN
   VERIFIED (not executed).** The `sh_after:` + `--allow-sh` harness exists at
   `test/fixtures/ash_tier_matrix_pack/`; the exact invocation plans 26 receipts
   under `--dry-run` and is refused without `--allow-sh`. No shell hook has fired
   for real.
4. [04-IDEMPOTENCY-VERIFICATION-METHODOLOGY](04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md)
   — **PLANNED / NOT STARTED.** The real double-run-and-diff methodology proving
   the five-part idempotency definition above, per Tier 1 task. Its dry-run
   precondition is satisfied; the two-run protocol itself has not been performed.
5. [05-TIER2-DEFERRAL-AND-XAAS-CUTOVER](05-TIER2-DEFERRAL-AND-XAAS-CUTOVER.md) —
   **PLANNED / NOT STARTED.** Named deferral of the Tier 2 task list, and the
   readiness bar for resuming the paused `xaas` Next Read case study once the book
   fixture's Tier 1 validation is closed.
6. [06-OCEL-BEAM4PM-PROJECTION](06-OCEL-BEAM4PM-PROJECTION.md) — **PLANNED / NOT
   STARTED.** Wiring `GgenIgniter.Telemetry.OcelEmitter` into every validation run
   from tickets 02 and 04, and the real projection path toward `beam4pm`.

## Definition of done as originally stated (pre-execution forward statement)

- **Ticket 01**: `test/fixtures/book_library/mix.exs` exists, declares real
  `{:ash, "~> 3.0"}`/`{:ash_postgres, "~> 2.0"}`, and `mix deps.get && mix compile`
  succeeds inside that fixture directory for real, pasted as evidence. *(Met at
  the dry-run level — see receipt Step 1 — but uncommitted, and with one disclosed
  extra dep, `{:ggen_igniter, path: "../../.."}`; ticket 01 records it.)*
- **Ticket 02**: every Tier 1 task has a named row stating its driving `ggen_igniter`
  sync mode and its closing evidence command; no task is silently skipped or
  reclassified into Tier 2 without ticket 05's explicit deferral note.
- **Ticket 03**: a real `--allow-sh` sync run against the book fixture actually
  invokes `mix ash.gen.domain`/`mix ash.gen.resource` via `System.cmd`, proven by
  real post-run file content (a real domain module, a real `config.exs` edit) —
  never a canned string. *(Not met: only `--dry-run` has been executed; no
  `System.cmd` shell hook has fired against the fixture.)*
- **Ticket 04**: for each Tier 1 task exercised, a real second-run `git diff`
  against the fixture shows zero changed lines and the five-part idempotency
  definition above holds, evidenced by real command output.
- **Ticket 05**: the Tier 2 list and the `xaas` resumption bar are both stated as
  named, dated deferrals — not silent gaps.
- **Ticket 06**: every ticket-02/04 run's OCEL sink (`OcelEmitter.peek_sink/1`) is
  asserted non-empty with real `emit/4` calls naming the actual mix task run, per a
  real test — never inferred from log text.
- **Across the set**: every acceptance bullet in every ticket is bound to Chicago-
  school testing discipline (`~/.claude/rules/testing-chicago-style.md`) — real
  collaborators, state-based assertions, zero `Mock`/`mock(`/`patch(`/`monkeypatch`
  verified by a fresh `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native`
  — and real command output pasted as evidence, never a narrated summary.

## Non-goals as originally stated (pre-execution)

- No claim that any ticket in this set is done. The strongest status any ticket
  holds is DRY-RUN VERIFIED (not executed) — tickets 01 and 03 — meaning the
  artifacts exist and the plan renders, not that any Ash task ran. All other
  tickets are PLANNED / NOT STARTED.
- No execution against `xaas` or the Next Read case study in this ticket set; that
  work remains explicitly paused per ticket 05.
- No Tier 2 (extension-specific `*.install`) task work.
- No `ash_postgres.setup_vector`/pgvector work — not needed for the book fixture's
  domain shape.
- No `ash_postgres.gen.resources` reverse-generation work — different direction
  from this set's forward-generation validation goal.
- No new OCEL2/EKG infrastructure — ticket 06 wires into `GgenIgniter.Telemetry.
  OcelEmitter` and the existing packs, it does not build new observability plumbing.
- No git tag or version-boundary claim beyond the `v26.9.8` directory name matching
  this repo's `mix.exs` version `"26.9.3"` loosely, the same coincidental-timing
  caveat `v26.9.1`'s overview states for its own two work streams.

## Reproducing the dry run (pre-execution; no longer runnable — harness deleted)

Everything marked DRY-RUN VERIFIED in the history block above reduced, at the time,
to two commands run from inside the fixture. Prerequisites a fresh clone does not carry:

- Elixir 1.19 / OTP 28 on `PATH` (the receipt's toolchain block), and Hex network
  access — `test/fixtures/book_library/deps/` is gitignored by the fixture's own
  `.gitignore`, so it must be fetched.
- A working Rust/`cargo` toolchain. The default `oxigraph` query engine is a Rustler
  NIF (`lib/ggen_igniter/native/graph_nif.ex`, `use Rustler`; crate at
  `native/ggen_graph_nif/`), and the compiled `priv/native/*.so` is gitignored at the
  repo root, so the fixture's path dep on `ggen_igniter` builds it on first compile.
  The repo README states the same requirement for the engine generally.
- **No Postgres** is needed for either command below: at day zero the fixture has no
  `Repo`/`ecto_repos:` config, and `--dry-run` executes no `mix ash.*` task. Postgres
  (and a `book_library_dev` database) becomes a requirement only for ticket 04's real
  run, at matrix row 11 onward.

```bash
cd test/fixtures/book_library
mix deps.get && mix compile --force --warnings-as-errors
# dry run: exit 0, 26 "planned: write .ash-validation-receipts/NN-..." lines, 01..26
ELIXIR_ERL_OPTIONS="+S 1" mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack \
  --for-each ash_tier_task_query --allow-sh --dry-run
# negative path: exit 1, zero "planned:" lines, ArgumentError from check_allow_sh!/3
mix ggen_igniter.sync --pack-dir ../ash_tier_matrix_pack \
  --for-each ash_tier_task_query --dry-run
```

Equivalent driver form, from the repo root:
`sh test/fixtures/ash_tier_matrix_pack/bin/matrix_run.sh --dry-run`. Both forms leave an
empty `.ggen_igniter/` directory in the fixture (gitignored there; `rmdir` it if you want
the tree byte-identical). Expected outputs are the receipt's Steps 2 and 4; a third,
independent reproduction on the same HEAD is appended to the receipt.

## See Also

This section covers the whole file, current path first.

**Current (post-execution):**

- [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md) — the executed
  architecture and the A-K acceptance ladder. Read first.
- [08-REVIEW-MANUFACTURE-PATH.md](08-REVIEW-MANUFACTURE-PATH.md) — its adversarial
  review: 4 blockers repaired, remaining gaps recorded as scope.
- [02-ASH-TASK-VALIDATION-MATRIX.md](02-ASH-TASK-VALIDATION-MATRIX.md) — per-task
  standing, rewritten against real dependency source.
- [evidence/](evidence/) and `test/fixtures/.qualification/book_library/` — the
  receipt, conformance, drift and OCEL artifacts behind every standing above.
- `test/fixtures/ash_manufacture_pack/` and `test/fixtures/book_library/` — the pack
  and the day-zero fixture the qualification runs against.
- `bin/check_doc_citations.sh` — resolves every artifact citation in this directory.
- [../../../AGENTS.md](../../../AGENTS.md) — the hand-write refusal doctrine.

**Pre-execution history:**

- [DRY-RUN-RECEIPT.md](DRY-RUN-RECEIPT.md) — the real command transcript (compile,
  `--allow-sh --dry-run`, negative path, hygiene grep) that backs the pre-execution
  dry-run statuses recorded in the history block above.
- [REVIEW-ASH-MAINTAINER-LENS.md](REVIEW-ASH-MAINTAINER-LENS.md) — adversarial
  Ash/Igniter-maintainer review of the superseded design (5 blockers / 11 majors /
  9 minors, 4 refuted), verified against the vendored ash 3.33.1 / ash_postgres
  2.13.1 / igniter 0.8.4 source.
- `test/fixtures/ash_tier_matrix_pack/` (ticket 03) — **deleted from the repo.** The
  `--allow-sh` harness the history block's reproduction commands invoke no longer
  exists; those commands cannot be run.
- `~/xaas/docs/case-studies/next-read/README.md`,
  `ILS-AND-EXPLANATION-SUBSTITUTION.md`, `DEFINITION-OF-DONE.md`,
  `RCA-ggen-tool-confusion.md`, `FMEA-ggen-tool-selection.md` — the paused case
  study this set's pivot is deliberately stepping around, not replacing.
- `docs/jira/v26.9.1/00-OVERVIEW.md` and
  `docs/jira/v26.9.1/04-SYNC-SHELLOUT-AND-VERIFY.md` — the ticket-set convention this
  directory matches: index+charter overview, numbered topic files, `GGEN-####`
  numbering, real evidence citations, never a bare status claim.
- `test/fixtures/ash-lifecycle-pack/` — the existing no-`mix.exs`
  fixture this set's book fixture deliberately contrasts with.
- `lib/mix/tasks/ggen_igniter.sync.ex` — `--allow-sh` schema (`:236`),
  help text (`:709`), `check_allow_sh!/3` (`:1161`, raise at `:1166`).
- `lib/ggen_igniter/telemetry/ocel_emitter.ex` — the existing OCEL v2
  emitter ticket 06 wires into.
- `deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex`,
  `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex` — the real Ash Igniter task
  source read this session, grounding the mode-(2)-over-mode-(1) decision above.
