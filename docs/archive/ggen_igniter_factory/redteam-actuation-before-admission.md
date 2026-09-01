# Red-team: mutation before admission/manifest-stale-check?

Independent adversarial review. Question: is there a real code path where a
real filesystem mutation (write/inject/delete/eval) can occur BEFORE the real
admission/manifest-stale-check step runs, for `mode:file`, `mode:eval`, or
`inject:true`?

Files read in full: `lib/ggen_igniter/reactors/reconcile_reactor.ex` (1576
lines), `lib/mix/tasks/ggen_igniter.sync.ex` (1317 lines),
`deps/reactor/lib/reactor/planner.ex`, `deps/reactor/lib/reactor/executor.ex`,
`deps/reactor/lib/reactor/executor/async.ex`, `lib/ggen_igniter/actuate.ex`
(inject/eval/write clauses), `lib/ggen_igniter/pending_actuation.ex`.

## Verdict summary

| Path | mode:file | mode:eval | inject:true |
|---|---|---|---|
| `GgenIgniter.Reactors.ReconcileReactor` | REFUTED | REFUTED | N/A — operation not implemented |
| `Mix.Tasks.GgenIgniter.Sync.run_pipeline!/3` (inline, default) | REFUTED | **CONFIRMED** | **CONFIRMED** |

The inline pipeline is not a rare fallback: `use_reactor?/0`
(`lib/mix/tasks/ggen_igniter.sync.ex:446`) defaults to `false`
(`Application.get_env(:ggen_igniter, :use_reactor, false)`), and `inject:true`
can *never* reach the Reactor path regardless of that flag (see below) — so
the confirmed gap sits on the actual default execution path for these two
modes, not a theoretical corner.

## 1. ReconcileReactor: REFUTED for mode:file / mode:eval, real Reactor DAG evidence

`:actuate` (`reconcile_reactor.ex:438`) declares
`argument :admitted, result(:admit)`. Whether that dependency edge actually
blocks execution — not just declares intent — was checked against the real
`deps/reactor` executor, not assumed:

- `Reactor.Planner.add_regular_dependencies/4`
  (`deps/reactor/lib/reactor/planner.ex:95-127`) adds a directed graph edge
  `dependency -> current_step` for every `result(:x)` argument — here,
  `:admit -> :actuate`.
- `Reactor.Executor.find_ready_steps/2`
  (`deps/reactor/lib/reactor/executor.ex:298-317`) selects **only** vertices
  with `Multigraph.in_degree(reactor.plan, step) == 0` as runnable. `:actuate`
  has in-degree 1 (the edge from `:admit`) until that edge is removed.
- A step's vertex (and thus its dependents' in-edges) is only removed on
  **successful** completion:
  `deps/reactor/lib/reactor/executor/async.ex:134-146` (`{:ok, value,
  new_steps}` -> `drop_from_plan`). On failure,
  `deps/reactor/lib/reactor/executor/async.ex:173-184` (`{:error, error}` ->
  `drop_from_plan(task) |> drop_from_plan(step)` then **`{:undo, reactor,
  state}`**) — the reactor transitions to the undo/halt path, it does not
  continue scheduling `:actuate`.

So real Reactor semantics structurally guarantee `:actuate` cannot start
until `:admit` has returned `{:ok, ...}`; an `:admit` refusal
(`{:error, {:refused_duplicate_output_path, _}}` etc., `reconcile_reactor.ex:1146-1152`)
halts the run before any write. `mode:file` (`:create`/`:replace`) and
`mode:eval` targets are both admitted-then-actuated through this same single
`:actuate` step (`actuate_pending/2`, `reconcile_reactor.ex:1189-1272`;
`actuate_one/2` for `:eval`, `reconcile_reactor.ex:1274-1282`) — REFUTED for
both.

One adjacent, narrower gap worth flagging (not the ordering question asked,
but related): `admit_pending/2` (`reconcile_reactor.ex:1127-1164`) filters
`write_pending` to `operation in [:create, :replace]` and `delete_pending` to
`operation == :delete` for its three substantive checks (duplicate-target,
unowned-delete, stale-refuse). An `operation: :eval` item matches neither
filter, so none of those three checks ever examine it — it is admitted by
construction, unexamined, but still strictly *after* `:admit` completes. This
is a coverage gap in what `:admit` checks, not an ordering violation.

**`inject:true` cannot reach `ReconcileReactor` at all**, by any call path:

- `PendingActuation.for_file/6` (`pending_actuation.ex:146-172`, the only
  builder `render_target/2` calls for `mode: :file`) derives `operation` from
  real file existence alone (`:create`/`:replace`) — it never produces
  `operation: :inject`, even though `:inject` is a declared member of the
  `operation()` type (`pending_actuation.ex:87`).
- `reconcile_reactor.ex` never calls `GgenIgniter.Frontmatter.split_template/1`
  anywhere (confirmed: zero matches for `"inject"` in the whole file) — so
  even a caller who invokes `ReconcileReactor.run/1` **directly** (bypassing
  `sync.ex`'s own frontmatter gate entirely) with a template file containing
  a `---\ninject: true\n...\n---` header would have that header treated as
  literal, un-parsed template body text, not as an injection instruction.
  There is no code path in this module that ever calls
  `Actuate.inject_content!/5`.
- The CLI's own gate (`run_via_reactor/3`, `sync.ex:473-493`;
  `delegate_to_controller/4`, `sync.ex:512-539`) additionally refuses
  delegation whenever the resolved template has any frontmatter at all
  (`inject:true` requires frontmatter to express the flag), falling back to
  `dispatch_pipeline/3` -> `run_pipeline!/3`.

## 2. `run_pipeline!/3` (inline pipeline): CONFIRMED for mode:eval and inject:true

This is the sole real implementation of `mode:eval` (when frontmatter is
present, or `use_reactor?()` is false — the default) and the sole real
implementation of `inject:true` (always, per above; ReconcileReactor cannot
run this operation).

Real ordering, `lib/mix/tasks/ggen_igniter.sync.ex`:

- `sync.ex:607-610` — `inject_spec = resolve_injection!(frontmatter)` when
  `mode == :file and inject: true`.
- `sync.ex:648` — `reconcile? = mode == :file and inject_spec == nil`.
  **This is false for both `mode: :eval` (any `mode`, `!= :file`) and for any
  `inject: true` template (any `mode: :file` with `inject_spec != nil`).**
- `sync.ex:650-667` — the entire admission block (`manifest_dir`, `on_stale`,
  `recipe_key`, `manifest = Manifest.load(manifest_dir)`, `old_entry`,
  `new_paths`, `stale = Manifest.stale_paths(...)`, and the refuse-raise
  `if reconcile? and on_stale == :refuse and MapSet.size(stale) > 0 ->
  raise ArgumentError`) is gated behind `reconcile?`. When `reconcile?` is
  `false`, `stale` is hard-set to `MapSet.new()` (`sync.ex:663`, the `else`
  branch) and the refuse-check is a no-op by construction — **this code does
  not run at all for these two modes in that call**, not merely "runs but
  finds nothing stale."
- `sync.ex:669-685` — `render_results = Enum.map(renders, fn {...} ->
  actuate!(mode, content, bindings, out_path, template_path, write_opts,
  dry_run, inject_spec) end)` — the real mutation call, unconditionally
  reached right after the (skipped, for these modes) admission block.
- `actuate!/8` clauses that actually mutate:
  - `mode: :eval`, `dry_run: false` (`sync.ex:880-892`) ->
    `Actuate.eval_code!(content, bindings)` ->
    `Code.eval_string(code, bindings)` (`actuate.ex:302-304`) — real,
    unrestricted Elixir code execution.
  - `mode: :file`, `inject_spec != nil` (`sync.ex:841-866`) ->
    `Actuate.inject_content!(out_path, marker, ..., inject_opts)` ->
    real `File.write!(path, new_content)` (`actuate.ex:214-218`).

Neither `Actuate.eval_code!/2` nor `Actuate.inject_content!/5` (read in full,
`actuate.ex:184-220`, `302-310`) references `GgenIgniter.Manifest` anywhere.
`inject_content!/5`'s own internal checks (`File.exists?` at `actuate.ex:188`,
anchor-uniqueness via `unique_marker_line!/3`, an idempotency compare at
`actuate.ex:207-209`) are real, but they are existence/anchor validity checks,
not the manifest-based ownership/staleness admission the task is asking
about — and none of them consult `on_stale`/the recipe manifest.

The only real gate standing between "rendered content" and "bytes on disk /
code executed" for `mode:eval` and `inject:true` in this pipeline is the
`dry_run` boolean threaded into `actuate!/8`'s own dry-run clauses
(`sync.ex:875-878` for eval; the `dry_run: true` early-return inside
`inject_content!/5` for inject, `actuate.ex:211-212`).

This is disclosed, not hidden: the moduledoc says so explicitly —
`sync.ex:639-647` ("Reconciliation applies ONLY to the actuation path where
this pack fully OWNS the target file: `mode: file` writes... It deliberately
excludes `mode: eval`... and `inject: true` targets... treating a splice
target as 'manufactured by this pack' would let `--on-stale prune` delete a
file this pack never created.") The design rationale for excluding these two
from *manifest ownership* is sound (an injected/evaluated target isn't
something this tool safely owns for later stale-pruning). But the code as
written doesn't just exclude them from ownership bookkeeping — it removes
*all* pre-mutation gating for them, including any refusal check, since
`reconcile?` is the single switch controlling both.

## 3. mode:file, no inject (the one case where reconcile? is true): REFUTED

`sync.ex:665-667`'s refuse-raise runs strictly before `sync.ex:669-685`'s
write loop; `Actuate.write_file!/3` (`actuate.ex:75-101`) is the only mutator
reached, and it is only ever called after the stale-refuse check has already
either passed or raised. No ordering bug in this sub-case.

## Net finding

**CONFIRMED**, for the inline pipeline only (`Mix.Tasks.GgenIgniter.Sync.run_pipeline!/3`,
the real, default, sole implementation of both `mode: eval` and `inject: true`):
real filesystem mutation (arbitrary Elixir code evaluation for `mode: eval`;
a real spliced `File.write!/2` for `inject: true`) executes with the
manifest-based admission/stale-check block structurally un-reached — not
delayed, not raced, simply never invoked in that call — because both modes
force `reconcile? = false` (`sync.ex:648`), which is the single switch gating
that entire block (`sync.ex:650-667`). The only gate left is `dry_run`.

**REFUTED** for `GgenIgniter.Reactors.ReconcileReactor`, for both `mode:file`
and `mode:eval` (the only two operations it can produce/actuate) — backed by
reading the real `deps/reactor` planner/executor source, not by trusting this
module's own moduledoc claims about Reactor semantics. `inject:true` cannot
reach this reactor by any call path (direct or CLI), so the question is moot
for that mode in this pipeline specifically.
