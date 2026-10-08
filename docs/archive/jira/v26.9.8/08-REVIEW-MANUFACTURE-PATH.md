# Adversarial Review — the Ash Manufacturing Path (v26.9.8)

Second adversarial review of the v26.9.8 work, taken from an Ash-maintainer
lens: hostile to reimplementing what Ash owns, and unimpressed by green
output that does not establish the claim it is presented as establishing.
It reviews the architecture described in
[07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md), not the superseded
`sh_after`/`--allow-sh` design that
[REVIEW-ASH-MAINTAINER-LENS.md](REVIEW-ASH-MAINTAINER-LENS.md) attacked.

Five lenses ran in parallel, each finding independently verified by a second
agent instructed to refute it. 27 findings survived verification: **4 blockers**
(B1-B4 below — B4 came from the coverage lens), 17 majors, 6 minors. Every
blocker is repaired below with an observed execution, not an argument. Several
majors are repaired; the rest are recorded as scope, because a gap that is
written down as a gap is a different object from a gap that is hidden.

## Blockers, and what closed them

### B1 — OCEL evidence was written before Igniter applied anything

`maybe_write_ocel/3` ran inside `igniter/1`, which executes before
`Igniter.do_or_dry_run/2` (`deps/igniter/lib/mix/task.ex:112` then `:119`).
A run declined at the confirmation prompt therefore left a log full of
`task_composed` events for files that never reached disk. The reviewer
reproduced this: killing a `--phase core` run at the prompt left no
`sort_by_title.ex` on disk and a 14 KB log asserting its composition.

The decision data only exists inside `igniter/1` — guard outcomes depend on
module existence *before* the run — so moving the emission later is not
possible. The log stopped being self-certifying instead. `mix
ggen_igniter.ocel.seal` appends the outcome the caller observed, and
`bin/conformance.py` treats an unsealed log as a violation. Falsified:
stripping the seal from a real log flips conformance to
`conformant: false` naming the unsealed file.

### B2 — the guard failed open under the real hook protocol

`refuse-handwritten-ash.sh` read `$CLAUDE_TOOL_INPUT`/`$CLAUDE_FILE_PATH`.
A `PreToolUse` hook receives the tool call as JSON on **stdin**, so in
production the guard saw an empty string and exited 0. Its passing
qualification cases were passing against a code path that never runs. A
standing produced by testing the wrong interface is worse than no standing.

The hook now parses stdin JSON (`tool_input.file_path` plus
`content`/`new_string`), keeps the environment variables as a fallback, and
**fails closed on an unparseable payload** — it scans the raw bytes rather
than assuming innocence. The qualification harness drives it through the
real JSON protocol. A separator bug found while fixing this is worth
recording: bash strips NUL bytes out of command substitution, so a
`\0`-delimited path/body pair silently merged and mis-classified; the
delimiter is now `\x1f`.

### B3 — beam4pm compatibility was asserted, never tested

The OCEL 2.0 shape was matched against a fixture the same author had read.
That is a closed loop. Both logs are now fed to the real importer:

```text
IMPORTED book_library.manufacture.base.ocel.json -> ocel_handle 1
IMPORTED book_library.manufacture.core.ocel.json -> ocel_handle 2
```

`BeamPM.Rust4PM.import_ocel_json/2`, backed by `process_mining` 0.6.2,
returns `{:ok, %{"ocel_handle" => n}}` for both. This runs as rung H of
`bin/qualify.sh`, and is **skipped loudly** — with the reason recorded in
`steps.jsonl` — when beam4pm's wasm artifact is absent, never silently.

### B4 (from the coverage lens) — the support modules were structural orphans

`ash.gen.validation` / `.change` / `.preparation` create a module and stop.
Nothing referenced the three manufactured modules; `grep` across the
fixture's `lib/` found zero references outside their own definition files.
Presenting them as manufactured domain semantics was an overclaim.

No admitted generator can close this: `ash.gen.resource` has no
`--validation`/`--change`/`--preparation` flag at ash 3.33.1, and
`ash.extend` adds extensions, not DSL entries inside `actions`. So it is
exactly the `UNSUPPORTED(generator capability)` case the doctrine specifies.
`amp:AttachSupportModuleCapability` now names the unmanufacturable element
(the `validations do validate X end` entry), and `amp:servesResource`
records the intent that could not be actuated — turning a silent orphan
into a typed refusal that reaches the OCEL log as a `capability_refused`
event.

## Majors repaired

| Finding | Repair |
|---|---|
| `ash.install` evidence cited a nonexistent path and attributed `add_dep` to a file that lacks it | Triple corrected; `bin/evidence_check.py` now resolves every `deps/` citation and line range, and runs as rung C3 |
| The rendered moduledoc claimed a `module_exists` guard on `ash.gen.domain` that the `@plan` does not apply | Ontology text corrected to state that Ash's own `--ignore-if-exists` does the work and ggen_igniter adds no guard |
| `amp:SupportModule` had no link to what it serves | `amp:servesResource` added (see B4) |
| Leftover database from a previous run broke `ash.setup` with `relation "books" already exists` | Database is now run-scoped (`book_library_qual_<utc>`); isolation by naming, never by dropping someone else's data |

## Majors recorded as scope, not repaired

These are real and are not claimed to be fixed.

- **Database idempotency is unproven.** Neither oracle covers DB state, and
  `ash.setup` is not re-run. `IDEMPOTENCY_ALIVE` covers the generated
  **tree**, not the database.
- **A third run is never attempted**, and `--check` is never run against the
  final `T2` state.
- **The tree hash excludes** `mix.lock`, `_build` and `.ggen_igniter`. The
  first two are defensible; excluding `.ggen_igniter` means the evidence
  directory's own churn is invisible to the diff.
- **`OCEL_PROCESS_ALIVE` remains partly a closed authorial loop** — the
  checker, the emitter and the ontology share an author. B3 breaks the
  loop for the *format*; the *semantics* of the check are still
  self-authored.
- **Ontology modelling gaps.** The attribute→enum dependency is a bare
  string rather than an IRI, so the ordering the pack requires is not
  expressible in the graph. Actions regress from `ash-lifecycle-pack`'s
  3-property `alp:Action` class to a bare `amp:defaultAction` literal. The
  capability envelope asserts version-scoped facts with no version triples.
  All 11 gates are conjunctive `SELECT`s that **fail open**: one missing
  triple silently drops a resource from the plan rather than erroring.
- **Guard granularity.** `guard: BookLibrary.Repo` gates roughly twenty
  independent add-if-absent repairs inside `ash_postgres.install` in order
  to suppress the one queued `ash.codegen initialize` task that would fail
  `--check`. That is a disclosed trade, not a free win.
- **Semantic coverage.** Policies, calculations, aggregates, identities,
  code interfaces, multitenancy and custom actions have no vocabulary at
  all — unrepresentable, not partially covered. Only `belongs_to` is
  instantiated, so no inverse relationship side exists.
- **Conformance cannot see any of the above**, so a green conformance
  result carries less information than its name suggests.

## Refuted findings, kept

- *"A second `ash.codegen --name X` would emit a duplicate migration."*
  Refuted: codegen is snapshot-diffed, and `--name` is not the mechanism
  that prevents it.
- *"`Ash.Igniter.codegen/2` queues unconditionally."* Partly refuted: it
  merges into an existing queued task when one exists
  (`deps/ash/lib/ash/igniter.ex:10-32`). In this run none exists, so it does
  reach `add_task` — the consequence stands, the stated mechanism did not.

## Standing after this review

Five standings, each from an observed execution recorded in
[evidence/receipt.json](evidence/receipt.json):
`ONTOLOGY_ALIVE`, `ASH_MANUFACTURE_ALIVE`, `IDEMPOTENCY_ALIVE` (tree only),
`OCEL_PROCESS_ALIVE`, `AGENT_HANDWRITE_REFUSAL_ALIVE`. 29 commands, 0
failures. The scope bound in the receipt is load-bearing: this is a claim
about the `book_library` fixture at ash 3.33.1 / ash_postgres 2.13.1 /
igniter 0.8.4 on this machine, and about nothing else.

## See Also

- [07-ASH-MANUFACTURE-PATH.md](07-ASH-MANUFACTURE-PATH.md) — the architecture reviewed here
- [REVIEW-ASH-MAINTAINER-LENS.md](REVIEW-ASH-MAINTAINER-LENS.md) — the first review, of the superseded design
- [02-ASH-TASK-VALIDATION-MATRIX.md](02-ASH-TASK-VALIDATION-MATRIX.md) — per-task standing
- [../../../AGENTS.md](../../../AGENTS.md) — the hand-write refusal doctrine
- [../../../test/fixtures/ash_manufacture_pack/README.md](../../../test/fixtures/ash_manufacture_pack/README.md) — the pack
