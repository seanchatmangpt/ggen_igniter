# Ash Task Validation Matrix — v26.9.8

## Status

**REWRITTEN AGAINST REAL DEPS.** This document replaces the earlier planning matrix,
which named tasks that do not exist and recorded standings that were never observed.
Every task name below was read out of the actual dependency tree at
`test/fixtures/book_library/deps/`, and every non-`UNKNOWN` standing is copied from an
`amp:GeneratorCapability` individual in
`test/fixtures/ash_manufacture_pack/ontology.ttl`, each of which carries its own
`amp:evidence`.

Superseded approach: the old matrix drove tasks through `ggen_igniter`'s
`sh_before:`/`sh_after:` `--allow-sh` shellout. That is no longer the mechanism. The
ontology now renders one composed `Igniter.Mix.Task` at
`lib/mix/tasks/book_library.manufacture.ex`, which calls upstream generators via
`Igniter.compose_task/4`. No `ggen_igniter` template renders Ash resource source.

## Corrections to the previous version of this file

| Old name | Real name | Evidence |
|----------|-----------|----------|
| `ash_postgres.reset` | `ash.reset` | `deps/ash/lib/mix/tasks/ash.reset.ex:5` defines `Mix.Tasks.Ash.Reset`; no `reset` task exists under `deps/ash_postgres/lib/mix/tasks/` |
| `ash.generate_policy_chart` | `ash.generate_policy_charts` | `deps/ash/lib/mix/tasks/ash.generate_policy_chart.ex:5` defines `Mix.Tasks.Ash.GeneratePolicyCharts` — the filename is singular, the invoked task name is plural |
| `ash_postgres.rollback` used as the only rollback | both `ash.rollback` and `ash_postgres.rollback` exist | `deps/ash/lib/mix/tasks/ash.rollback.ex:5`, `deps/ash_postgres/lib/mix/tasks/ash_postgres.rollback.ex:5` |
| `ash.patch.extend` listed as top-level | it lives under `patch/` | `deps/ash/lib/mix/tasks/patch/ash.patch.extend.ex:6` |
| `ash.install` listed as absent | it exists | `deps/ash/lib/mix/tasks/install/ash.install.ex:6` |

Tasks the old matrix omitted entirely: `ash`, `ash.migrate`, `ash.gettext.extract`,
`ash.gen.gettext`, `ash.install`, `ash_postgres.gen.resources`.

## What "standing" means here, and what UNKNOWN means

Standing is scoped to exactly one dependency set: **ash 3.33.1, ash_postgres 2.13.1,
igniter 0.8.4, spark 2.7.2, Elixir 1.19.5 / OTP 28**, as resolved in
`test/fixtures/book_library/mix.lock`. A standing recorded here is a claim about
those versions in that fixture, not about the task in general and not about any other
version.

`UNKNOWN` means **not exercised** in the qualification run. It is not a defect claim,
not a deprecation, and not evidence of absence. The task exists (its file is cited);
nothing was observed about whether it is idempotent, admissible, or correct, so
nothing is asserted. Upgrading an `UNKNOWN` row requires running the task and
recording evidence in the ontology, not inferring from its source.

Vocabulary used in the standing column:

- `ALIVE` — exercised, works, idempotency mechanism observed to hold.
- `PARTIAL_ALIVE` — exercised and usable, but with a named, evidenced limitation.
- `BUILD_BROKEN` — exercised; its output does not compile at these versions.
- `UNSUPPORTED` — exists and works, but deliberately not admitted into the
  manufacture path (destructive / cannot share database identity with the subject).
- `UNKNOWN` — not exercised.
- `BLOCKED` — reserved; no row currently carries it.

The `phase` column uses the ontology's `amp:phase` values: `base` (first Igniter run),
`core` (second Igniter run), `lifecycle` (post-manufacture mix invocation, outside any
Igniter run), or `n/a` for tasks not in the manufacture path.

## Validation matrix — all real tasks in `ash` 3.33.1

| Task | Standing | Admitted? | Phase | Idempotency mechanism | Evidence (file:line) |
|------|----------|-----------|-------|------------------------|----------------------|
| `ash.install` | ALIVE | yes | base | `Igniter.Project.Deps.add_dep` + `Igniter.Project.Formatter.import_dep` are add-if-absent | `deps/ash/lib/mix/tasks/install/ash.install.ex:6` |
| `ash.gen.domain` | PARTIAL_ALIVE | yes | core | Its `--ignore-if-exists` branch is unreachable from the CLI (no `schema:` in `Info`, so `OptionParser` strict rejects the flag); reachable only via `Igniter.compose_task`. Ash's OWN branch does the work, so `ggen_igniter` composes with that flag and applies NO guard of its own — the rendered plan sets `guard: nil`. CORRECTED after review: an earlier version of this row claimed a `module_exists/2` guard here, contradicting the plan | `deps/ash/lib/mix/tasks/gen/ash.gen.domain.ex:26-30` (no `schema:`), flag branch at `:36` |
| `ash.gen.resource` | ALIVE | yes | core | `ensure_resource_exists/5` skips creation when the module is found; `--conflicts ignore` (the default) skips already-present attributes/relationships/actions. Composed **unguarded** so the upstream property is exercised, not masked | `deps/ash/lib/mix/tasks/gen/ash.gen.resource.ex:254-267`, `:74` |
| `ash.gen.base_resource` | PARTIAL_ALIVE | yes | base | Module creation guarded by `module_exists/2`; config write is `prepend_new_to_list`. Run in its own Igniter run so no earlier `find_module` full scan has latched `included_all_elixir_files?` | `deps/ash/lib/mix/tasks/gen/ash.gen.base_resource.ex:59` (retrofit leg), `deps/igniter/lib/igniter/project/module.ex:475` (`try_full_scan/3` sets the assign) |
| `ash.gen.enum` | ALIVE | yes | core | `ggen_igniter` `module_exists/2` admission guard | `deps/ash/lib/mix/tasks/gen/ash.gen.enum.ex:6` |
| `ash.gen.change` | ALIVE | yes | core | `ggen_igniter` `module_exists/2` admission guard | `deps/ash/lib/mix/tasks/gen/ash.gen.change.ex:6` |
| `ash.gen.validation` | ALIVE | yes | core | `ggen_igniter` `module_exists/2` admission guard | `deps/ash/lib/mix/tasks/gen/ash.gen.validation.ex:6` |
| `ash.gen.preparation` | ALIVE | yes | core | `ggen_igniter` `module_exists/2` admission guard | `deps/ash/lib/mix/tasks/gen/ash.gen.preparation.ex:6` |
| `ash.gen.custom_expression` | BUILD_BROKEN | **no** | core | N/A — not admitted | GENERATOR `deps/ash/lib/mix/tasks/gen/ash.gen.custom_expression.ex:46` emits `args: [...]`; CONSUMER `deps/ash/lib/ash/custom_expression.ex:113-115` raises `ArgumentError` when `opts[:arguments]` is nil |
| `ash.codegen` | PARTIAL_ALIVE | yes | lifecycle | Snapshot-diffed: a second run against an unchanged resource set generates no new migration. Not composed inside the Igniter run — it must observe compiled resources | `deps/ash/lib/mix/tasks/ash.codegen.ex:5` |
| `ash.setup` | PARTIAL_ALIVE | yes | lifecycle | Delegates to `ash_postgres.create` (create-if-absent) + `ash_postgres.migrate` (version-tracked) | `deps/ash/lib/mix/tasks/ash.setup.ex:5` |
| `ash.tear_down` | UNSUPPORTED | **no** | n/a | N/A — destructive; drops the database. Run 2 has nothing to drop, and it cannot share database identity with the qualification subject | `deps/ash/lib/mix/tasks/ash.tear_down.ex:5` |
| `ash.reset` | UNSUPPORTED | **no** | n/a | N/A — destructive (`tear_down` + `setup`); same isolation requirement as `ash.tear_down` | `deps/ash/lib/mix/tasks/ash.reset.ex:5` |
| `ash` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.ex:5` |
| `ash.extend` | PARTIAL_ALIVE | yes | core | Exercised TRANSITIVELY only — the manufacture path reaches it through `ash.gen.resource --extend`, never by composing it directly, which is why this is not `ALIVE`. Non-singleton extension keys go through `Igniter.Code.List.prepend_new_to_list`, so re-adding a present extension is a no-op; the singleton `:data_layer` key is replaced in place. It also runs `Mix.Task.run("compile")` unconditionally | `deps/ash/lib/mix/tasks/ash.extend.ex:40-52` (Info), `:57`, `:264-277`; `deps/spark/lib/spark/igniter.ex:332-337` |
| `ash.patch.extend` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/patch/ash.patch.extend.ex:6` |
| `ash.migrate` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.migrate.ex:5` |
| `ash.rollback` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.rollback.ex:5` |
| `ash.set.domains` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.set.domains.ex:6` |
| `ash.manifest.dump` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.manifest.dump.ex:5` |
| `ash.generate_resource_diagrams` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.generate_resource_diagrams.ex:5` |
| `ash.generate_policy_charts` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.generate_policy_chart.ex:5` (module `Mix.Tasks.Ash.GeneratePolicyCharts`) |
| `ash.generate_livebook` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.generate_livebook.ex:5` |
| `ash.gettext.extract` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/ash.gettext.extract.ex:5` |
| `ash.gen.gettext` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash/lib/mix/tasks/gen/ash.gen.gettext.ex:5` |

## Validation matrix — all real tasks in `ash_postgres` 2.13.1

| Task | Standing | Admitted? | Phase | Idempotency mechanism | Evidence (file:line) |
|------|----------|-----------|-------|------------------------|----------------------|
| `ash_postgres.install` | ALIVE | yes | base | Creates Repo/Application only when absent; config writes are `prepend_new_to_list`. `ggen_igniter` additionally guards on `BookLibrary.Repo` existence because this task unconditionally queues `ash.codegen initialize`, and a queued task fails `--check` even with zero file changes | `deps/ash_postgres/lib/mix/tasks/ash_postgres.install.ex:6`; queueing at `deps/ash/lib/ash/igniter.ex:31` |
| `ash_postgres.create` | UNKNOWN | not exercised directly | n/a | Reached only transitively via `ash.setup`; not exercised as its own row | `deps/ash_postgres/lib/mix/tasks/ash_postgres.create.ex:5` |
| `ash_postgres.migrate` | UNKNOWN | not exercised directly | n/a | Reached only transitively via `ash.setup`; not exercised as its own row | `deps/ash_postgres/lib/mix/tasks/ash_postgres.migrate.ex:5` |
| `ash_postgres.generate_migrations` | UNKNOWN | not exercised directly | n/a | Reached only transitively via `ash.codegen`; not exercised as its own row | `deps/ash_postgres/lib/mix/tasks/ash_postgres.generate_migrations.ex:5` |
| `ash_postgres.drop` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash_postgres/lib/mix/tasks/ash_postgres.drop.ex:5` |
| `ash_postgres.rollback` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash_postgres/lib/mix/tasks/ash_postgres.rollback.ex:5` |
| `ash_postgres.squash_snapshots` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash_postgres/lib/mix/tasks/ash_postgres.squash_snapshots.ex:5` |
| `ash_postgres.setup_vector` | UNKNOWN | not exercised | n/a | Not observed | `deps/ash_postgres/lib/mix/tasks/ash_postgres.setup_vector.ex:30` |
| `ash_postgres.gen.resources` | UNSUPPORTED | **no** | n/a | N/A — refused by design, not unobserved. DIRECTION INVERSION: it generates Ash resources FROM an existing database schema, the opposite of this pack's direction (ontology to resources to migrations); admitting it would create a second, competing source of truth for the same resources | `deps/ash_postgres/lib/mix/tasks/ash_postgres.gen.resources.ex:185` (queues `ash_postgres.generate_migrations` via `Igniter.add_task`) |

## Modelled refusals that are not mix tasks

These two rows exist in `ontology.ttl` but name no file under `deps/`, because the thing
being refused is a capability the toolchain does not provide at all. They are in the
matrix so the gap is a row rather than an absence.

| Pseudo-task | Standing | Admitted? | Why |
|---|---|---|---|
| `ash.attach.support_module` | UNSUPPORTED | no | No upstream task attaches a manufactured validation/change/preparation module to a resource. `ash.gen.validation|change|preparation` create the module and stop; `ash.gen.resource` has no matching flag; `ash.extend` adds extensions, not DSL entries inside `actions`. The unmanufacturable element is the `validations do validate X end` entry. Consequence: the three modules this pack manufactures are REAL but ORPHANED |
| `ash.extend:policies` | UNKNOWN | no | `mix ash.extend <resource> Ash.Policy.Authorizer` is a real supported path, but this case study never ran it. UNKNOWN means not exercised, not broken; upgrading it needs an observed run |

## Coverage

34 real tasks exist across both deps (25 in `ash`, 9 in `ash_postgres`). **19** of
them carry an `amp:GeneratorCapability` individual in
`test/fixtures/ash_manufacture_pack/ontology.ttl:365-512`. The remaining 15 carry no
individual at all and are `UNKNOWN` by absence, not by grading.

The ontology also carries **2** individuals that name no mix task — the two
pseudo-tasks in the section above — so it holds **21** `amp:GeneratorCapability`
individuals in total. Across all 21:

| Standing | Count |
|---|---|
| `ALIVE` | 7 |
| `PARTIAL_ALIVE` | 5 |
| `UNSUPPORTED` | 4 |
| `UNKNOWN` | 4 |
| `BUILD_BROKEN` | 1 |
| **Total** | **21** |

12 are `amp:admitted true`, 9 are refused.

Do not compare this 21 against the **16** rows in `receipt.json`
`capability_matrix` without noting the denominators differ: the receipt carries only
the tasks on the manufacture path, so `ash.extend`, `ash.patch.extend`,
`ash.set.domains`, `ash_postgres.gen.resources` and `ash_postgres.setup_vector` are
in the ontology's 21 and not in the receipt's 16. Both counts are correct for their
own scope; `00-OVERVIEW.md` states the same split.

## Why exit code is not the idempotency oracle

`Igniter.do_or_dry_run/2` returns `:issues` without halting
(`deps/igniter/lib/igniter.ex:1279-1281`), so a nonzero-work run can still exit 0. The
qualification harness instead uses Igniter's own `--check`, which calls
`System.halt/1` on any change, warning, issue, queued task, move, or removal
(`halt_if_fails_check!/3`, `deps/igniter/lib/igniter.ex:1293-1330`), and independently
compares byte-level tree digests between run 1 and run 2.

## Known upstream defect outside the matrix rows

`mix ash.codegen --yes` fails at these versions. `ash.codegen` is a plain `Mix.Task`
(`deps/ash/lib/mix/tasks/ash.codegen.ex:36`) that forwards argv verbatim; AshPostgres
routes it to `ash_postgres.generate_migrations`, an Igniter task with no `yes` switch,
so strict validation errors with `--yes : Unknown option`. Reproduced in the harness.

## See Also

- `test/fixtures/ash_manufacture_pack/ontology.ttl:365-512` — the 21
  `amp:GeneratorCapability` individuals that are the source of truth for every
  standing above that is not `UNKNOWN`-by-absence.
- `test/fixtures/.qualification/book_library/` — `steps.jsonl`, `receipt.json`,
  `conformance.json`, and the run-1/run-2 tree digests behind the standings.
- [04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md](04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md)
  — the two-run protocol.
