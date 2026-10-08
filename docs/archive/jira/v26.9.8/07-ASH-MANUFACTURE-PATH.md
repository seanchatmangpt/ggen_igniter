# Ash Manufacture Path — composed Igniter task supersedes the shell-out matrix

Standing: **ONTOLOGY_ALIVE**, **ASH_MANUFACTURE_ALIVE**, **IDEMPOTENCY_ALIVE**
(tree only — the database is not covered; see 08), **OCEL_PROCESS_ALIVE** and
**AGENT_HANDWRITE_REFUSAL_ALIVE** are all `true` for the `book_library` fixture at the
exact toolchain recorded in `test/fixtures/.qualification/book_library/receipt.json`
(ash 3.33.1, ash_postgres 2.13.1, igniter 0.8.4, spark 2.7.2, Elixir 1.19.5/OTP 28).
This ticket supersedes tickets 02/03/04's `sh_after:` + `--allow-sh` 26-shell-out
design with a single composed `Igniter.Mix.Task` rendered from the ontology by
`ggen_igniter.sync`. All 29 qualification commands hit their expected exit
(`receipt.json` `commands`, `failures: []`), the run-1 and run-2 fixture trees are
byte-identical (`tree_T1_sha256 == tree_T2_sha256 == 65c2ec4e…`), and the conformance
check reports `conformant: true` with zero violations. The receipt's own `scope` field
bounds this: it is a claim about this fixture at these dependency versions on this
machine, not about Ash projects generally, and not about the nine modelled
capabilities whose standing is not `ALIVE` — five of which are refused outright
(`receipt.json` `conformance.not_admitted`).

## What changed and why

```text
ontology.ttl                    semantic Book/Loan facts + GeneratorCapability
  |                             envelope (standing/admitted/phase/evidence)
  v
11 SPARQL gates                 010_project .. 085_refusals
  |
  v
ggen_igniter.sync               renders ONE composed Igniter.Mix.Task
  |                             -> lib/mix/tasks/book_library.manufacture.ex
  v
Igniter.compose_task/4          the REAL upstream ash.* / ash_postgres.* generators
  |
  v
project surfaces                lib/book_library/**, config/*.exs
  |
  v
mix compile                     manufactured surfaces compile
  |
  v
lifecycle                       mix ash.codegen --name ... ; mix ash.setup
  |
  v
OCEL 2.0 log                    .ggen_igniter/ocel/*.ocel.json
  |
  v
receipt.json                    machine-readable qualification receipt
```

The 26-shell-out design is superseded because every row spawned its own
`sh -> mix -> Igniter -> fresh BEAM`, so the exit code of a subprocess became the only
idempotency signal available, and that signal is not an oracle
(`igniter.ex:1279-1281` returns `:issues` without halting) — composition keeps all
rows in one `%Igniter{}`, one diff, one write, and exposes Igniter's own `--check`
oracle instead.

No `ggen_igniter` template renders Ash resource source. `templates/manufacture.ex.eex`
renders only the composed task; the resource bodies are produced by the upstream
generators.

## The five blockers, resolved

### B1 — `--ignore-if-exists` on `ash.gen.domain`

The review's blocker was real **at the CLI boundary** and a **non-defect through
composition**. Two parse paths exist:

- CLI: `run/1` -> `Igniter.Util.Info.validate!/3` parses `:strict`
  (`igniter/lib/igniter/util/info.ex:354-368`), so `ash.gen.domain` — which declares no
  schema — rejects the flag with `Unknown option`, exit 1.
- Composed: `compose_task -> configure_and_run -> parse_argv -> __options__!` uses
  non-strict `switches:` (`igniter/lib/mix/task.ex:237`), so the flag is tolerated. Ash
  itself depends on this at `ash.gen.resource.ex:185`.

**Resolution:** compose, never shell out. Independently, `ash.gen.resource` and
`ash.gen.enum` do declare `ignore_if_exists` in their own schemas, so those two rows
were never affected by either path.

### B2 — exit code is not an idempotency oracle

Confirmed: `do_or_dry_run` returns `:issues` without halting
(`igniter.ex:1279-1281`), so a generator that refused to write still exits 0.

**Resolution:** use Igniter's own `--check`, which `System.halt()`s on any change,
warning, issue, queued task, move or removal (`halt_if_fails_check!/3`,
`igniter.ex:1293-1330`). Both phases exit 0 under `--check` on run 2
(`20-idempotency-check-base.log`, `21-idempotency-check-core.log`), **and** the T1/T2
trees are byte-identical — two independent oracles, not one.

### B3 — `ash.gen.custom_expression` is broken upstream

Confirmed. The generator emits `args: [...]`
(`ash.gen.custom_expression.ex:46`) but `Ash.CustomExpression.__using__/1` raises
`ArgumentError` "You must provide arguments for the custom expression" when
`opts[:arguments]` is nil (`ash/lib/ash/custom_expression.ex:113-115`). Every module
this task produces fails to compile.

**Resolution:** standing `BUILD_BROKEN`, `admitted: false` in the ontology's capability
envelope, and a typed refusal emitted as an OCEL `capability_refused` event on both
runs (`conformance.json` `runs.run1.capability_refused`,
`runs.run2.capability_refused`). Not patched, not hand-written, not `sed`-ed after the
fact.

### B4 — database isolation

**Resolution:** `bin/qualify.sh` rewrites the manufactured repo config to a run-scoped
database (`book_library_qual`) before any DB-touching step; `book_library_dev` is left
untouched. Receipt `database_isolation.evidence` records the rewritten config line
(`7:  database: "book_library_qual",`); `db-isolation.txt` records that both databases
exist and that `books` + `loans` are present only in `book_library_qual`.

### B5 — `base_resource` ordering (mechanism differs from the review's diagnosis)

The review's direction was right; the mechanism is different and worse than an
ordering mistake. `ash.gen.base_resource`'s retrofit leg
(`ash.gen.base_resource.ex:59`, `Igniter.update_all_elixir_files`) short-circuits on
the `included_all_elixir_files?` assign (`igniter.ex:1112-1123`), and that same assign
is set as a side effect of **any** `find_module` full scan
(`igniter/project/module.ex:475`, `try_full_scan/3`). Both the `ggen_igniter` admission
guards and `ash.gen.resource`'s own `ensure_resource_exists/5` call `find_module`. In a
composed run the retrofit therefore silently does nothing — reproduced: a first composed
run with `base_resource` ordered last left `lib/book_library/catalog/book.ex` reading
`use Ash.Resource`.

**Resolution:** do not depend on the retrofit. Use the supported
`ash.gen.resource --base` flag, which requires `base_resources` config to be **loaded**,
which is what forces a two-phase (two mix invocation) manufacture. Both `Book` and
`Loan` now read `use BookLibrary.Resource`.

## Newly discovered defects

### The `update_all_elixir_files` latch

Any `find_module` full scan sets `included_all_elixir_files?`, which later causes
`Igniter.update_all_elixir_files` to become a no-op inside the same igniter.

Minimal reproduction: compose `ash.gen.resource` (which calls
`ensure_resource_exists/5` -> `find_module`) before `ash.gen.base_resource` in one
`Igniter.Mix.Task`, run it, then read `lib/book_library/catalog/book.ex` — the header is
still `use Ash.Resource`, with no error, no issue, and exit 0.

### `mix ash.codegen --yes` is rejected

`ash.codegen` is a plain `Mix.Task` (`ash.codegen.ex:36`) that forwards its argv
verbatim to each extension's codegen; AshPostgres routes to
`ash_postgres.generate_migrations`, an Igniter task whose `Info` declares no `yes`
switch, so strict validation errors with `--yes : Unknown option`.

Minimal reproduction, inside the fixture:

```bash
mix ash.codegen --name x --yes    # exit 1: --yes : Unknown option
mix ash.codegen --name x          # exit 0
```

Reproduced in run 1 of this harness before the flag was removed; `bin/qualify.sh`
carries the note inline and passes no `--yes` to `ash.codegen`.

## Phases

Two mix invocations are **forced by upstream**, not chosen:

`ash.gen.resource --base` validates its argument against the `:base_resources`
application config, and that config must be *loaded* — which happens at mix boot, not
mid-igniter. `ash.gen.base_resource` writes that config entry. So the base-resource
config write and its first consumer cannot share one BEAM. Combined with B5 (the
retrofit path is unusable in a composed run), the split is the only remaining
supported route:

- `--phase base` — `ash.install`, `ash_postgres.install`, `ash.gen.base_resource`.
- `--phase core` — `ash.gen.domain`, `ash.gen.enum`, `ash.gen.resource --base`,
  `ash.gen.change`, `ash.gen.preparation`, `ash.gen.validation`.

The guarded steps in `base`/`core` are the five that flip from `task_composed` on run 1
to `task_admission_refused` on run 2 (`conformance.json` `guard_flip_run1_to_run2`).

## How to run

```bash
cd /Users/sac/ggen_igniter
bash test/fixtures/ash_manufacture_pack/bin/qualify.sh
python3 test/fixtures/ash_manufacture_pack/bin/receipt.py \
  test/fixtures/book_library test/fixtures/.qualification/book_library
```

The 21 `mix` invocations, in execution order, run inside `test/fixtures/book_library`
(from `commands.log`). These are the `mix` subset of the ladder's 29 commands; the
remaining eight are two `python3` cross-checks, the tree diff, four guard cases and the
beam4pm import, all listed in the ladder below:

```bash
mix deps.get
mix compile
mix ggen_igniter.sync --pack-dir /Users/sac/ggen_igniter/test/fixtures/ash_manufacture_pack
mix compile
mix book_library.manufacture --phase base --yes
mix compile
mix book_library.manufacture --phase core --yes
mix compile
mix ggen_igniter.ocel.seal .ggen_igniter/ocel/book_library.manufacture.base.ocel.json \
  --exit 0 --observed "phase base applied; mix compile exit 0"
mix ggen_igniter.ocel.seal .ggen_igniter/ocel/book_library.manufacture.core.ocel.json \
  --exit 0 --observed "phase core applied; mix compile exit 0"
mix ash.codegen --name book_library_manufacture
mix ash.setup
mix compile
mix book_library.manufacture --phase base --check
mix book_library.manufacture --phase core --check
mix book_library.manufacture --phase base --yes
mix book_library.manufacture --phase core --yes
mix ash.codegen --name book_library_manufacture
mix compile
mix ggen_igniter.ocel.seal .ggen_igniter/ocel/book_library.manufacture.base.ocel.json \
  --exit 0 --observed "phase base re-applied; mix compile exit 0"
mix ggen_igniter.ocel.seal .ggen_igniter/ocel/book_library.manufacture.core.ocel.json \
  --exit 0 --observed "phase core re-applied; mix compile exit 0"
```

## Acceptance ladder A-K

Rungs A-H and K are executed commands; I and J are the artifacts that make the run
readable. Artifact paths are relative to `test/fixtures/.qualification/book_library/`.
One row per command, in execution order, matching `receipt.json` `commands` exactly —
all 29 hit their expected exit, and `failures` is empty.

Rung letters and log filenames are both liable to change as the harness grows.
`bin/check_doc_citations.sh` resolves every log name cited on this page against the
real qualification directory, so a renumbered rung fails a check instead of quietly
turning this table into fiction.

| Rung | Command | What it proves | Artifact |
|---|---|---|---|
| A | `deps-get` | Deps resolve at the pinned versions | `01-deps-get.log` |
| B | `baseline-compile` | Day-zero fixture compiles before manufacture | `02-baseline-compile.log` |
| C | `ggen-sync` | Ontology consumed, composed task rendered | `03-ggen-sync.log` |
| C | `compile-manufacture-task` | The rendered task itself compiles | `04-compile-manufacture-task.log` |
| C | `drift-check` | Rendered task still matches the ontology | `05-drift-check.log` |
| C | `evidence-citations` | Every `amp:evidence` citation resolves | `06-evidence-citations.log` |
| D | `manufacture-base-run1` | Real upstream tasks invoked, phase base | `07-manufacture-base-run1.log` |
| E | `compile-after-base` | Base-phase surfaces compile | `08-compile-after-base.log` |
| F | `isolate-databases` | Run-scoped qualification database assigned | `09-isolate-databases.log` |
| F | `manufacture-core-run1` | Book + Loan manufactured, phase core | `10-manufacture-core-run1.log` |
| F | `compile-after-core` | Core-phase surfaces compile | `11-compile-after-core.log` |
| F | `seal-ocel-base` | Base log sealed with the observed outcome | `12-seal-ocel-base.log` |
| F | `seal-ocel-core` | Core log sealed with the observed outcome | `13-seal-ocel-core.log` |
| F | `ash-codegen` | Migrations generated from real resources | `14-ash-codegen.log` |
| F | `ash-setup` | Database created and migrated | `15-ash-setup.log` |
| F | `db-nondegenerate` | Postgres schema contains manufactured tables | `16-db-nondegenerate.log` |
| F | `compile-after-lifecycle` | Post-lifecycle tree compiles | `17-compile-after-lifecycle.log` |
| M | `ash-setup-test-env` | Test database initialized and migrated | `18-ash-setup-test-env.log` |
| M | `manufactured-resources-execute` | Real Ash actions execute against Postgres | `19-manufactured-resources-execute.log` |
| G | `idempotency-check-base` | Base phase exits 0 under `--check` | `20-idempotency-check-base.log` |
| G | `idempotency-check-core` | Core phase exits 0 under `--check` | `21-idempotency-check-core.log` |
| G | `manufacture-base-run2` | Base phase re-applies without change | `22-manufacture-base-run2.log` |
| G | `manufacture-core-run2` | Core phase re-applies without change | `23-manufacture-core-run2.log` |
| G | `ash-codegen-run2` | No second migration is generated | `24-ash-codegen-run2.log` |
| G | `compile-after-run2` | Run-2 tree still compiles | `25-compile-after-run2.log` |
| G | `ash-setup-run2` | Database setup re-executes cleanly | `26-ash-setup-run2.log` |
| G | `seal-ocel-base-run2` | Run-2 base log sealed | `27-seal-ocel-base-run2.log` |
| G | `seal-ocel-core-run2` | Run-2 core log sealed | `28-seal-ocel-core-run2.log` |
| G | `tree-diff-T1-T2` | T1 and T2 trees byte-identical | empty `T1-vs-T2.diff` |
| G | `idempotency-check-base-at-T2` | Base phase `--check` clean at T2 | `29-idempotency-check-base-at-T2.log` |
| G | `idempotency-check-core-at-T2` | Core phase `--check` clean at T2 | `30-idempotency-check-core-at-T2.log` |
| L | `manufacture-base-run3` | Base phase re-applies on run 3 | `31-manufacture-base-run3.log` |
| L | `manufacture-core-run3` | Core phase re-applies on run 3 | `32-manufacture-core-run3.log` |
| L | `ash-codegen-run3` | No third migration is generated | `33-ash-codegen-run3.log` |
| L | `compile-after-run3` | Run-3 tree still compiles | `34-compile-after-run3.log` |
| L | `seal-ocel-base-run3` | Run-3 base log sealed | `35-seal-ocel-base-run3.log` |
| L | `seal-ocel-core-run3` | Run-3 core log sealed | `36-seal-ocel-core-run3.log` |
| L | `ash-migrate-run3` | Ash migrations run cleanly on run 3 | `37-ash-migrate-run3.log` |
| L | `tree-diff-T2-T3` | T2 and T3 trees byte-identical (fixpoint) | empty `T2-vs-T3.diff` |
| L | `idempotency-check-base-at-T3` | Base phase `--check` clean at T3 | `38-idempotency-check-base-at-T3.log` |
| L | `idempotency-check-core-at-T3` | Core phase `--check` clean at T3 | `39-idempotency-check-core-at-T3.log` |
| K | `guard-blocks-ash-resource` | Hand-written `use Ash.Resource` refused | `40-guard-blocks-ash-resource.log` |
| K | `guard-blocks-base-resource-header` | Hand-written base header refused | `41-guard-blocks-base-resource-header.log` |
| K | `guard-allows-plain-elixir` | Plain Elixir is not refused | `42-guard-allows-plain-elixir.log` |
| K | `guard-allows-manufactured-task` | The manufactured task is not refused | `43-guard-allows-manufactured-task.log` |
| H | `beam4pm-import` | Both OCEL logs import into real beam4pm | `44-beam4pm-import.log` |
| I | — | Execution followed the admitted process | `conformance.json` |
| J | — | Machine-readable receipt over every rung | `receipt.json`, `steps.jsonl` |

The two `K` block cases expect exit 2, the two `K` allow cases expect exit 0; every
other row expects 0. Expected exits are recorded per command in `receipt.json`.

Isolation rung (not lettered): `db-isolation.txt` and `db-name.txt` record the
run-scoped `book_library_qual` database from B4.

`conformance.json` states `spc: NOT_APPLICABLE` — n=2 runs is not a time series, so no
control limits are computed and none should be inferred.

## Changed after adversarial review

This ticket was written before [08-REVIEW-MANUFACTURE-PATH.md](08-REVIEW-MANUFACTURE-PATH.md)
ran. Three blockers it found changed the mechanism described above; read 08 for the
detail and the reproductions.

- **OCEL logs are sealed.** The manufacture task emits its decisions from inside
  `igniter/1`, which runs before Igniter applies anything, so an aborted run left a log
  asserting composition of files that never landed. `mix ggen_igniter.ocel.seal` now
  appends the outcome the caller observed, and `bin/conformance.py` treats an unsealed
  log as a violation.
- **The hand-write guard reads stdin.** It previously read `CLAUDE_TOOL_INPUT` only,
  which does not exist under the real `PreToolUse` protocol, so it failed open in
  production. It now parses the stdin JSON tool call, falls back to the environment, and
  fails closed on an unparseable payload.
- **beam4pm compatibility is tested, not asserted.** Both logs are fed to the real
  `BeamPM.Rust4PM.import_ocel_json/2` as rung H of `bin/qualify.sh`; both return
  `{:ok, %{"ocel_handle" => n}}`.

Two further mechanisms were added in the same pass:

- `bin/evidence_check.py` (rung C, `06-evidence-citations.log`) resolves every `deps/`
  citation and line range in `amp:evidence`. It was added because the review found a
  dangling citation that nothing caught. Its documentation counterpart is
  `bin/check_doc_citations.sh`, which does the same for this directory's own citations.
- The qualification database is **run-scoped** (`book_library_qual_<utc>`). A leftover
  database from a previous run broke `ash.setup` with `relation "books" already exists`:
  resetting the filesystem to day zero is not resetting the subject if the database
  survives. Isolation is by naming, never by dropping anyone else's data.

Also recorded in the ontology rather than fixed: the manufactured
validation/change/preparation modules are **structural orphans**, because no upstream
Ash task can attach them to a resource. `amp:AttachSupportModuleCapability` names the
unmanufacturable DSL entry and refuses it, so the gap reaches the OCEL log as a
`capability_refused` event instead of passing silently as manufactured semantics.

## See Also

- [00-OVERVIEW.md](00-OVERVIEW.md) — the ticket-set index this file joins.
- [02-ASH-TASK-VALIDATION-MATRIX.md](02-ASH-TASK-VALIDATION-MATRIX.md) — the 26-row
  matrix this ticket supersedes; its "why shellout" section is now obsolete.
- [03-SH-AFTER-ALLOW-SH-HARNESS.md](03-SH-AFTER-ALLOW-SH-HARNESS.md) — the
  `--allow-sh` harness superseded by composition.
- [04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md](04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md)
  — the five-part idempotency definition; rung G satisfies it with two oracles.
- [06-OCEL-BEAM4PM-PROJECTION.md](06-OCEL-BEAM4PM-PROJECTION.md) — the OCEL projection
  rung H feeds.
- [REVIEW-ASH-MAINTAINER-LENS.md](REVIEW-ASH-MAINTAINER-LENS.md) — the review whose
  five blockers this ticket closes.
- `test/fixtures/ash_manufacture_pack/` — ontology, 11 gates,
  `templates/manufacture.ex.eex`, `bin/qualify.sh`, `bin/conformance.py`,
  `bin/receipt.py`.
- `test/fixtures/.qualification/book_library/` — every artifact cited in the ladder.
- `lib/ggen_igniter/telemetry/ocel2_export.ex` and
  `test/ggen_igniter_ocel2_export_test.exs` — the OCEL 2.0 serializer and its
  Chicago-style test suite. No test count is quoted here: the suite is still
  growing, and a pinned number would be the next thing to go stale.
- `.claude/hooks/refuse-handwritten-ash.sh` and `.claude/settings.json` — the
  `PreToolUse` guard blocking hand-authored `use Ash.Resource`/`use Ash.Domain`
  outside the allowlist.
- [../../../AGENTS.md](../../../AGENTS.md) — the hand-write refusal doctrine this path
  is the executable half of; `CLAUDE.md` carries the repo's wider agent contract.
