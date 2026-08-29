# Gaps to fill for v26.9.1

Real, confirmed gaps found while integrating `ggen_igniter` v26.8.28-30 into `~/xaas` as a
consumer, verified by direct grep/read of this repo's own `lib/`+`test/` -- not inferred from
docs. Each gap below is disclosed the same way this repo's own CHANGELOG discloses one (see
v26.8.30's "`:run_queries` concurrency: investigated, NOT changed" entry): named honestly,
not silently worked around downstream.

**Update (adversarial Zach-Daniel-style ERRC/RCA/FMEA review, 10/12 findings survived 3-vote
refutation)**: this file's original gap #1 undersold how much real Reactor compensation
machinery already exists -- `Mix.Tasks.GgenIgniter.Sync`'s default path (`run_via_reactor/3`)
now DOES route ordinary file/inject-mode targets through `ReconcileReactor`'s real
`compensate/4`+`undo/4` LIFO revert. The gap is narrower and more precise than originally
written: see items 4-8 below, added by that review, for exactly which paths still have none of
that safety net and where the architecture itself has drifted (`Controller` defaulting to the
wrong pipeline).

## 1. `sh_after` frontmatter field is parsed but never executed (highest priority)

`GgenIgniter.Frontmatter` parses a `sh_after: "..."` field (`lib/ggen_igniter/frontmatter.ex:35,96,124,191`)
into every real `%GgenIgniter.Frontmatter{}` struct returned by `GgenIgniter.Frontmatter.parse/1`.
Confirmed via a full-repo grep (`grep -rn "sh_after" lib/ test/`) that **no code anywhere reads
`.sh_after` off a parsed frontmatter struct to actually run it** -- `Mix.Tasks.GgenIgniter.Sync`
(`lib/mix/tasks/ggen_igniter.sync.ex`) writes the rendered file/injects content per-row via
`Actuate.write_file!/3`/`Actuate.inject_content!/5`, but the `sh_after` shell command a
template's own frontmatter declares (e.g. `mix ash.gen.resource ...`, `mix compile`,
`terraform validate`) is a documented-but-inert field.

This mirrors the real Rust `ggen`'s own `Frontmatter.sh_after` (see `~/xaas/templates-hooks/*.tmpl`,
all four of which declare a real `sh_after:` used by the Rust CLI's `ggen sync run` today) --
the Elixir port has 1:1 frontmatter *parsing* parity but not *actuation* parity for this one
field. A consumer project cannot fully replace the external Rust `ggen` CLI with
`mix ggen_igniter.sync` until this closes.

**Suggested shape** (not prescriptive -- name only, don't force a specific implementation):
a real `System.cmd/3` invocation (or `Mix.Task.run/2` dispatch when `sh_after` is itself a
`mix ...` command, to stay in-BEAM rather than shelling out for same-VM tasks) after a
successful `write_file!/3`/`inject_content!/5` outcome for that row, with real stdout/stderr
capture surfaced the same way `Mix.Tasks.GgenIgniter.Doctor`'s checks report real command output
today. Needs a real decision on failure semantics: does a nonzero `sh_after` exit fail the whole
`sync` run (refuse), or only that row (partial success + a printed warning, mirroring
`--for-each`'s existing per-row outcome tracking)?

## 2. Render is EEx-only; real consumer templates use Tera syntax

`GgenIgniter.Render.render/2` (`lib/ggen_igniter/render.ex`) is explicitly "Stdlib EEx, not a
Tera/Liquid port" (its own moduledoc). This is a disclosed, deliberate scope decision, not an
oversight -- but it means a real consumer's existing Tera-templated body content (e.g.
`~/xaas/templates-hooks/*.tmpl`'s `{{ results | length }}`, `{{ moduleName }}`,
`{{ mixArgs | default(value="") }}`) cannot be rendered as-is; every such template's *body* (not
its frontmatter, which already round-trips 1:1) needs manual conversion to EEx (`<%= %>`) syntax
before `mix ggen_igniter.sync` can replace an external Rust `ggen sync run` for that template.

Not proposing this be un-decided -- noting it as the real, concrete migration cost a consumer
pays per template when adopting `sync.ex` in place of the Rust CLI, so it's visible in one place
rather than rediscovered per-consumer.

## 3. `GgenIgniter.Query.Qlever.load_store!/2`'s dead-code branch (pre-existing, low priority)

`lib/mix/tasks/ggen_igniter.doctor.ex:648`, `check_qlever_reachable/2`: a Dialyzer-style compiler
typing warning ("the following pattern will never match... because the right-hand side has type
`none()`") has appeared consistently across v26.8.28/29/30 builds in a consumer's
`mix compile --warnings-as-errors`. It doesn't fail a consumer's own build (the warning is
attributed to `(ggen_igniter 26.8.x) lib/mix/tasks/ggen_igniter.doctor.ex:648`, inside this repo's
own compiled output, not the consumer's), but it's real, reproducible, and low-effort to clear.

## 4. `GgenIgniter.Controller` defaults to the deliberately-narrower `Reconcile.run/1`, not `Sync`'s real `ReconcileReactor.run/1` path

`Controller.run_pipeline/1` calls `Reconcile.run(reconcile_opts)` unless
`Application.get_env(:ggen_igniter, :use_reactor, false)` is true (default `false`) --
opt-in, backwards from `Mix.Tasks.GgenIgniter.Sync`'s own `run_sync/3`, which now unconditionally
tries `run_via_reactor/3` FIRST. `Reconcile.run/1` is a real, hand-maintained duplicate of a
strict subset of `ReconcileReactor`'s own `:render`/`:admit`/`:actuate` steps (both ultimately
call the same `Actuate.write_file!/3`/`Actuate.eval_code!/2`), and its only remaining
justification -- a plain, Igniter-free function usable outside a Reactor context -- is not
actually exercised anywhere except `Controller`'s now-default branch. Concrete fix: flip
`Controller`'s default to `use_reactor: true` (or remove the flag entirely and always call
`ReconcileReactor.run/1`; `receipt_to_legacy_result/2` already exists to reshape the output to
`Controller`'s expected return shape) and retire `Reconcile.run/1` once `Controller` no longer
needs it.

## 5. `--for-each` and `mode: eval` get zero Reactor/compensation coverage even after the AR-9/AR-10 corrections

`run_via_reactor/3` (`lib/mix/tasks/ggen_igniter.sync.ex`) explicitly returns
`{:not_delegatable, ...}` for `for_each not in [nil, ""]`, and separately falls back to the
non-Reactor path for `mode: eval` (the `ReconcileReactor`'s own `:render` step has a real,
disclosed `FunctionClauseError` crash on eval targets). Both fallback classes call
`Actuate.write_file!/3`/`Actuate.eval_code!/2` directly from `run_pipeline!/3`, a plain function
chain with no Reactor step and therefore no `undo/4` target at all. These are exactly the two
feature classes most likely to need reverting -- fan-out touches multiple files per run, and
`eval` runs arbitrary evaluated code -- and they inherited none of the compensation machinery
the v26.8.30 CHANGELOG's "seven-workstream integration pass" otherwise closed for the ordinary
single-file case.

## 6. `GgenIgniter.Lock`'s stale-lock recovery has no liveness heartbeat -- a legitimately slow run can have its own lock stolen mid-run

`stale_lock?/1` computes age purely from the lock file's original creation `mtime`; nothing
re-touches that mtime while the lock is genuinely still held by a live process. A real `sync`
invocation that legitimately runs past `@stale_after_ms` (5 minutes -- plausible for a large
`--for-each` fan-out or a slow Qlever-backed query set) is indistinguishable from a crashed
holder to a second invocation, which will `File.rm/1` the "stale" lock and proceed to mutate the
same project's filesystem concurrently -- the exact two-genuinely-concurrent-writers scenario
this module exists to prevent, now caused by its own recovery mechanism. The existing property
test (`test/ggen_igniter_lock_staleness_properties_test.exs`) covers the boundary at a fixed
elapsed-time threshold, not a live-holder-past-the-window scenario. Needs either a periodic
mtime refresh from the live holder, or a PID-liveness check (`Process.alive?`/OS-level) before
treating an old mtime as proof of a crashed holder.

## 7. `CompensationTelemetryMiddleware`'s counters have no run-scoping and can double-count one failure

`error/2` independently checks `find_compensation_failure/1` (bumps `:compensation_failed`) and
`find_step_error/2` for `{:compile_failed, _}` (bumps `:build_broken`) against the same error
term with no mutual exclusion -- both can fire for one real failing run. More significantly, the
backing table is a single global, unscoped ETS table: `counters/0` answers "how many times has
this ever compensated/undone across every run since this BEAM node booted," not "how many times
did THIS run compensate," despite the moduledoc framing the question in the singular. A
long-lived `GgenIgniter.Controller` looping `Reconcile.run/1` (or, post-item-4's fix,
`ReconcileReactor.run/1`) repeatedly would accumulate all runs into one indistinguishable total.
Needs a `{run_id, counter}` key shape and either an exposed reset or a per-run snapshot API.

## 8. `DoctorFixes`'s `--fix` dep-only rewrite crashes on a valid 2-tuple dependency shape

`rewrite_dep_only/2` unconditionally calls `Igniter.Code.Tuple.tuple_elem(tuple_zipper, 2)` to
reach a dependency's options, which only exists on a 3-element `{name, version, opts}` tuple.
The check-side predicate (`dep_only_predicate/2`, a generic regex match) has no notion of tuple
arity, so it reports `:fixable` for an equally common, idiomatic 2-tuple form with no version
requirement -- e.g. `{:some_dep, github: "org/repo", only: :test}` or
`{:some_dep, path: "../local", only: :dev}` -- and the AST transform then raises a
`RuntimeError` on that shape instead of degrading gracefully. `test/ggen_igniter_doctor_fixes_test.exs`
has no 2-tuple-with-opts fixture (confirmed via grep), so this tuple-arity mismatch is untested
despite the CHANGELOG's "7 new tests... a regression test proves it" claim, which covers only
the regex-vs-comment bug the migration was written to fix, not this one.

## Not a gap (confirmed, for completeness)

- `Mix.Tasks.GgenIgniter.Sync` already has full frontmatter parsing, `--for-each` multi-row
  fan-out, and `inject`/`before`/`after`/`at_line` splicing (`lib/mix/tasks/ggen_igniter.sync.ex`,
  `GgenIgniter.Frontmatter`) -- these were previously (incorrectly) assessed as missing by
  reading only `GgenIgniter.Reconcile`'s deliberately-bounded proof-of-concept moduledoc, which
  disclaims all three features for *itself* specifically, not for the real CLI task. `sync.ex` is
  the correct integration point for a consumer wanting frontmatter/for-each/inject parity with
  the Rust `ggen` CLI; `Reconcile`/`Controller` remain the narrower, stateless/supervised-process
  variants for a consumer that doesn't need those three features.
