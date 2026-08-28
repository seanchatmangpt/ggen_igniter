# `mix ggen_igniter.plan`

Source: `lib/mix/tasks/ggen_igniter.plan.ex` (`Mix.Tasks.GgenIgniter.Plan`).
Status: **BLOCKED / UNVERIFIABLE — real, verified 2026-08-27**. The task
module itself is real (flag schema, validation, human/`--json` reporting are
all present and would work). It depends on
`GgenIgniter.Reactors.ReconcileReactor.plan/1`, a read-only admission-only
entry point that **does not exist yet** in this working tree — confirmed by
reading `lib/ggen_igniter/reactors/reconcile_reactor.ex` (no `def plan`) and
by a real invocation raising:

```
$ mix ggen_igniter.plan --template test/fixtures/extension.ex.eex --query spec=test/fixtures/spec.rq
** (UndefinedFunctionError) function GgenIgniter.Reactors.ReconcileReactor.plan/1 is undefined or private
    (ggen_igniter 26.8.27) GgenIgniter.Reactors.ReconcileReactor.plan(...)
    (ggen_igniter 26.8.27) lib/mix/tasks/ggen_igniter.plan.ex:152: Mix.Tasks.GgenIgniter.Plan.run_plan/2
```

The task's own moduledoc discloses this explicitly (see "Dependency on
`ReconcileReactor.plan/1`" below) — this is expected, not a bug in
`ggen_igniter.plan.ex` itself. Once `ReconcileReactor.plan/1` lands, this
reference doc's flag/output/exit-code contract should hold without further
changes, since the task was written against that intended signature; re-run
the example above and re-verify before upgrading this doc's status.

## Purpose

Read-only admission preview: computes the exact same
observe → load ontology → resolve pack → run queries → render → admit
sequence a real `mix ggen_igniter.sync` run would (via `use_reactor: true`),
through `GgenIgniter.Reactors.ReconcileReactor.plan/1`, but **stops before
`:actuate`**. Every `%GgenIgniter.PendingActuation{}` the admitted plan would
write is reported; nothing is ever written to disk, and no
compensation/rollback machinery is ever invoked (there is nothing an
already-applied actuation to compensate/roll back, since none was applied).

## Read-only, no lock (FR-5)

This task performs no filesystem mutation of the target project and
therefore does **not** acquire `GgenIgniter.Lock` (see
`docs/status.md`'s `GgenIgniter.Lock` row — that module itself does not yet
exist either). `mix ggen_igniter.doctor` and a read-only `mix
ggen_igniter.plan` inspection are designed to run concurrently with an
in-flight `mix ggen_igniter.sync` lock holder, per the PRD's FR-5. Only
`mix ggen_igniter.sync` and `mix ggen_igniter.replay`'s future re-actuation
mode (not yet implemented — see `replay.md`) are verbs that mutate and
therefore lock.

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--template PATH` | string | *(required unless `--pack`/`--pack-dir` resolves exactly one)* | Same resolution rule as `sync`'s `--template`. |
| `--pack NAME[:TEMPLATE]` | string | *(none)* | Same `priv/ggen/<NAME>/` convention as `sync`; see `packs.md`. |
| `--pack-dir DIR` | string | *(none)* | Same as `--pack` but uses `DIR` directly. |
| `--query NAME=PATH` | string, repeatable (`:keep`) | *(none unless `--pack` supplies gate queries)* | Same `NAME=PATH` parsing as `sync`. |
| `--engine NAME` | string | `"oxigraph"` | One of `oxigraph`, `sparql`, `qlever` — see `engines.md`. |
| `--store-id ID` | string | *(required only when `--engine qlever`)* | Same as `sync`'s `--store-id`. |
| `--json` | boolean | `false` | Emit the plan as a stable, script-parseable JSON object instead of human-readable text. |
| `--quiet` | boolean | `false` | Suppress non-essential human-readable output (no effect on `--json`). |
| `--verbose` | boolean | `false` | Human-readable form only: also prints each pending actuation's `semantic_source` and `logical_id`. |
| `--no-color` | boolean | `false` | Accepted for consistency with other `ggen_igniter.*` tasks; this task's output uses no ANSI color regardless. |
| `--help` | boolean | `false` | Print usage and exit 0 immediately, before any plan is computed. |
| `--version` | boolean | `false` | Print the tool version and exit 0 immediately. |

There is no `--out`/`--for-each`/`--on-stale`/`--dry-run`/`--mode`/
`--unless-exists`/`--skip-if`/`--manifest-dir` flag here — those are
`sync`-specific actuation controls that don't apply to a read-only preview;
`--out` and `--for-each` in particular are determined by the resolved
template/pack's own frontmatter and reported as part of each pending
actuation's `target`, not requested as separate flags on this task.

## Dependency on `ReconcileReactor.plan/1`

This task calls `GgenIgniter.Reactors.ReconcileReactor.plan/1`, a read-only
admission-only entry point (observe → load → resolve → run_queries → render
→ admit, returning the admitted `[%GgenIgniter.PendingActuation{}]` without
ever reaching `:actuate`) that this Mix task was written against by intended
signature but that does not yet exist in this working tree — see
`docs/architecture/adr/` and `~/.claude/plans/prd-ard-wiggly-creek.md`
("2. `mix ggen_igniter.plan`") for the extraction this depends on. Do not add
a compatibility shim here that re-derives a parallel plan-only pipeline out
of `sync.ex`'s own `run_pipeline!/3`-style logic — the whole point of this
task is to share the same admission logic `sync` uses, not to duplicate it.

## Output

Human-readable (default) or `--json` — a stable, script-parseable rendering
of the same real plan data (no field present in one is silently dropped from
the other):

- **inputs + hashes** — resolved `--ontology`/`--pack` root, every resolved
  `--query name=path` (or pack-discovered gate query), each pending
  actuation's `previous_hash`/`desired_hash`.
- **engine** — the resolved `--engine` (default `oxigraph`) and, for
  `qlever`, the resolved `--store-id`.
- **output paths** — each pending actuation's `target` (or `"(none -- mode:
  eval)"` in the human form / `null` in `--json`, for `operation: :eval`).
- **existing-file decisions** — `operation` (`:create`/`:replace`/`:delete`/
  `:eval`) plus `GgenIgniter.PendingActuation.plan_unchanged?/1` per item, so
  a plan run can distinguish "would create", "would replace with different
  bytes", "would replace with identical bytes (no-op)", and "would delete"
  without ever running `:actuate` to find out.
- **intended mutations** — one line per pending actuation in the
  human-readable form (`operation target (unchanged?) [previous_hash=...,
  desired_hash=..., ownership=...]`), or the full list under
  `pending_actuations` in `--json`.
- `--verbose` (human form only) additionally prints each item's
  `semantic_source` and `logical_id`.

```
mix ggen_igniter.plan --pack ash-lifecycle-pack:resource \
  --query resource=priv/ggen/ash-lifecycle-pack/gates/resource.rq

mix ggen_igniter.plan --template test/fixtures/extension.ex.eex \
  --query spec=test/fixtures/spec.rq --json
```

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Help/version printed, or plan computed successfully — admitted cleanly, whether or not any item would actually change anything (an all-unchanged plan is still exit 0). |
| `2` | Invalid invocation: no `--template` and no `--pack`/`--pack-dir` with a discoverable template; no queries resolvable; `--engine qlever` without `--store-id`; a bad `--pack`/`--pack-dir` name. Uses the same `ArgumentError` vocabulary `mix ggen_igniter.sync` already raises for these, caught here and turned into a clean exit instead of a raw stack trace. |
| `3` | Unsupported capability for the read-only plan path specifically — the resolved template/run needs `:actuate`-adjacent behavior `plan/1` cannot admit without executing it, or uses a feature outside `GgenIgniter.Reconcile.run/1`'s bounded reactor scope (frontmatter `inject: true`, `--for-each` fan-out). |

## Examples

```
mix ggen_igniter.plan --pack ash-lifecycle-pack --query resource=gates/resource.rq
mix ggen_igniter.plan --template test/fixtures/extension.ex.eex --query spec=test/fixtures/spec.rq --json
mix ggen_igniter.plan --template t.eex --query spec=s.rq --verbose
```
