# Gaps to fill for v26.9.1

> ARCHIVED 2026-09-01: all 8 gaps closed (#1/#3/#6/#7/#8) or explicitly deferred
> (#2/#4/#5-mode:eval-half) as of v26.9.3. See docs/status.md and CHANGELOG.md's
> v26.9.3 entry for current status.

> **STATUS PASS (2026-09-01)**: cross-checked against current `docs/status.md` and
> `docs/v26.9.1-requirements.md`. Not archived — 1 of 8 gaps (#8) remains real, unaddressed
> open work with no closure and no explicit deferral recorded anywhere in either doc (#6 fixed
> for real this pass; #7 already resolved). Per-gap disposition:
>
> - **#1** `sh_after`/`sh_before` execution — **CLOSED**. `docs/status.md` L54.
> - **#2** EEx-only render vs. Tera consumer templates — **DEFERRED (deliberate scope,
>   unchanged)**. `docs/status.md` L105 confirms `GgenIgniter.Render.Tera` exists only as
>   a standalone parser with automated `*.tmpl` pipeline dispatch still "planned for
>   future integration" — this was never claimed closed, and remains a disclosed,
>   intentional scope boundary rather than silent neglect.
> - **#3** `check_qlever_reachable/2` dialyzer dead branch — **CLOSED**. `docs/status.md`
>   references the fix via CHANGELOG's v26.9.1 entry; `docs/v26.9.1-requirements.md` does
>   not list it as open.
> - **#4** `Controller` defaults to `Reconcile.run/1` not `ReconcileReactor` —
>   **DEFERRED, explicitly**. `docs/status.md` L80-81 confirms `ReconcileReactor` is
>   still `PARTIAL_ALIVE (not the default)` and `Reconcile.run/1` "is the default today";
>   `docs/v26.9.1-requirements.md` Open Question 2 names this exact question
>   ("Is the Reactor pipeline going default in v26.9.1, or does `use_reactor: true`
>   remain opt-in?") as explicitly unresolved/deferred past this release, and Open
>   Question 3 defers full pipeline consolidation (`Reconcile.run/1` /
>   `ReconcileReactor` / `Sync`'s inline path) the same way.
> - **#5** `--for-each`/`mode: eval` Reactor coverage — **HALF-CLOSED, remainder
>   DEFERRED, explicitly**. `--for-each` closed per `docs/status.md` L55. `mode: eval`
>   remains routed around `ReconcileReactor`'s `:render`-step crash by design —
>   `docs/status.md` L52 states this is unchanged and deliberate ("`mode: eval`
>   frontmatter templates remain deliberately kept off this widened path"), consistent
>   with `docs/v26.9.1-requirements.md` Open Question 6 (`to_prd_status/1` and related
>   eval-path questions deferred past v26.9.1). Note: HEAD commit `52164d6` ("Thread a
>   real `%Igniter{}` through `mode:eval` targets in `ReconcileReactor`'s `:actuate`
>   step") postdates this file's last edit and touches `mode:eval` handling in
>   `:actuate`, but does not remove the `:render`-step crash `docs/status.md` L52 and
>   `test/ggen_igniter_reconcile_reactor_test.exs`'s eval-compensation test still
>   document as live — the disclosed boundary stands as stated.
> - **#6** `GgenIgniter.Lock` stale-lock recovery has no liveness heartbeat —
>   **RESOLVED (v26.9.3)**. `stale_lock?/1` (`lib/ggen_igniter/lock.ex:151-180`) now consults a
>   real `Process.alive?/1` PID-liveness check (`holder_pid_status/1`,
>   `lib/ggen_igniter/lock.ex:189-200`) as the primary staleness signal, with mtime-age as
>   fallback only for the cross-node/unparseable-marker case. See `docs/status.md`'s
>   `GgenIgniter.Lock` row and gap #6 below for the real test citations
>   (`test/ggen_igniter_lock_heartbeat_test.exs`, real `mix test` output).
> - **#7** `CompensationTelemetryMiddleware` counters are unscoped/global and can
>   double-count — **RESOLVED (v26.9.3, commit TBD)**. `{run_id, counter}` ETS key
>   shape + `counters/1` per-run API + `error/2` mutual-exclusion precedence fix, see
>   `docs/status.md`'s `CompensationTelemetryMiddleware` row and gap #7 below.
> - **#8** `DoctorFixes.rewrite_dep_only/2` crashes on a valid 2-tuple dep shape —
>   **OPEN, unaddressed**. `lib/ggen_igniter/doctor_fixes.ex:359` still calls
>   `Igniter.Code.Tuple.tuple_elem(tuple_zipper, 2)` unconditionally; no 2-tuple fixture
>   exists in `test/ggen_igniter_doctor_fixes_test.exs`. Not named in
>   `docs/v26.9.1-requirements.md`.
>
> **Conclusion: not archived.** Gap #8 is real open work with no recorded closure or
> deferral decision — archiving would silently drop it from view, which this file's own
> stated discipline (name gaps honestly, don't silently work around them) forbids.
> Re-run this check after #8 is either fixed or given an explicit deferral decision in
> `docs/v26.9.1-requirements.md`.

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

## 1. `sh_after` frontmatter field is parsed but never executed (highest priority) — RESOLVED (v26.9.1, commit `d601983`)

Closed in full: `GgenIgniter.ShellHook.run/3` (`lib/ggen_igniter/shell_hook.ex`)
executes a template's `sh_before:`/`sh_after:` frontmatter field for real via
`System.cmd("sh", ["-c", cmd], ...)`, gated by `--allow-sh`, wired into both
`sync.ex`'s inline pipeline and `ReconcileReactor`'s `actuate_one/2` — see
`CHANGELOG.md`'s v26.9.1 entry and `docs/status.md`'s `sh_before:`/`sh_after:`
row for the full, independently-re-verified disclosure (three real manual
`mix ggen_igniter.sync` invocations, not just the new test suite). The
failure-semantics question this gap's own "Suggested shape" section left
open (does a nonzero exit fail the whole run or only that row?) was answered
per-pipeline, disclosed as an intentional difference: the inline pipeline's
`sh_before:`/`sh_after:` failure is a per-row outcome that does not abort the
run; the Reactor pipeline treats it as an ordinary actuation failure with
real `undo/4` compensation. **v26.9.2 update**: now that `--for-each` also
routes through the Reactor pipeline (see gap #5 below), a `sh_before:`/
`sh_after:` failure can no longer reach the inline pipeline's per-row
semantics at all in practice — `test/ggen_igniter_sync_sh_hooks_test.exs`'s
two failure-mode tests were updated to assert the Reactor's all-or-nothing
outcome instead, a real, disclosed contract change (see `CHANGELOG.md`'s
v26.9.2 entry), not a regression of this gap's original fix.

## 1 (original text, kept for the historical record below)

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

## 3. `GgenIgniter.Query.Qlever.load_store!/2`'s dead-code branch (pre-existing, low priority) — RESOLVED (v26.9.1, commit `d601983`)

Closed: the pointless `case ... do rows when is_list(rows) -> ... end` wrapping
a stub-typed `no_return()` call was removed from `check_qlever_reachable/2` —
the existing `rescue` clause a few lines below already handled both the
stub's raise and any real network/query failure. See `CHANGELOG.md`'s v26.9.1
entry ("`mix ggen_igniter.doctor`'s `check_qlever_reachable/2` dialyzer
fix"). Original gap text kept below for the historical record.

## 3 (original text)

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

## 5. `--for-each` and `mode: eval` get zero Reactor/compensation coverage even after the AR-9/AR-10 corrections — HALF RESOLVED (v26.9.2)

`--for-each` half of this gap is closed: `--for-each` now routes through
`GgenIgniter.Reactors.ReconcileReactor.run/1` (`Mix.Tasks.GgenIgniter.Sync.
run_for_each_via_reactor!/7`), with real `undo/3` compensation coverage —
see `CHANGELOG.md`'s v26.9.2 entry and `docs/status.md`'s "`--for-each NAME`
real compensation coverage" row for the full disclosure, including the
real, intentional all-or-nothing behavior-change trade-off this brings.
`mode: eval` remains OUT of scope, unchanged: `ReconcileReactor`'s `:render`
step still has the real, pre-existing, unconditional crash on `:eval`
targets this gap's original text and `test/ggen_igniter_reconcile_reactor_test.exs`'s
":eval compensation-completeness" test both already named — v26.9.2 did not
touch this. Original gap text kept below for the historical record.

## 5 (original text)

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

## 6. `GgenIgniter.Lock`'s stale-lock recovery has no liveness heartbeat -- a legitimately slow run can have its own lock stolen mid-run — RESOLVED (v26.9.3)

Closed in full: `stale_lock?/1` (`lib/ggen_igniter/lock.ex:151-180`) no longer decides staleness
from mtime-age alone. `holder_marker/0` (`lib/ggen_igniter/lock.ex:146-148`) now records the
acquiring process's real `erlang_pid=` (its own `self()`, `inspect/1`-formatted) alongside the
existing `node=`. On contention, `stale_lock?/1` consults `holder_pid_status/1`
(`lib/ggen_igniter/lock.ex:189-200`) as the PRIMARY signal: it parses the recorded `erlang_pid=`
back into a real pid via `:erlang.list_to_pid/1` and checks `Process.alive?/1` for real, on
demand, at contention time -- no periodic background heartbeat/refresher process is needed. A
same-node holder confirmed genuinely alive is never preempted, however old its lock file's mtime
is; a same-node holder confirmed genuinely dead (crashed, killed, never reached `release/1`) is
immediately reclaimable, however fresh its lock file's mtime is. mtime-age remains the fallback
signal only when PID-liveness is `:unknown` -- a disclosed, real cross-node limitation (an Erlang
pid from another node's local process table cannot be resolved locally), a missing/unparseable
marker, or a reused OS pid.

Real test evidence, no `Mock`/`patch`/`monkeypatch` anywhere in the chain
(`grep -rn "Mock\|mock(\|patch(\|monkeypatch" test/ggen_igniter_lock_heartbeat_test.exs
test/ggen_igniter_lock_staleness_properties_test.exs lib/ggen_igniter/lock.ex` → zero matches):

- `test/ggen_igniter_lock_heartbeat_test.exs` (new) --
  `"a live same-node holder's lock is NOT stolen even once its file's mtime is well past
  @stale_after_ms"`: a real spawned Elixir process genuinely holds the lock past
  `@stale_after_ms` while alive (its file's mtime is force-set into the past via a real
  `File.touch!/2`); a second real `acquire/2` call correctly keeps blocking and raises the
  documented `RuntimeError`, never stealing the lock.
- `test/ggen_igniter_lock_heartbeat_test.exs` -- `"a holder whose real process has genuinely died
  is immediately reclaimable, even with a fresh mtime"`: a real spawned process acquires and
  exits without releasing; `Process.monitor/1`'s real `:DOWN` message confirms it is genuinely
  dead; a real `acquire/2` call immediately succeeds despite the file's mtime being seconds-fresh.
- Real run: `mix test test/ggen_igniter_lock_staleness_properties_test.exs
  test/ggen_igniter_lock_heartbeat_test.exs` → `2 properties, 3 tests, 0 failures`.
- The pre-existing `test/ggen_igniter_lock_contention_test.exs` needed a real fix to match the
  corrected semantics: its winning task previously let its process exit the instant `acquire/2`
  returned (without ever calling `release/1`), which is now correctly, immediately reclaimable
  under the PID-liveness check -- updated to genuinely hold the lock (`Process.sleep/1`) before
  returning, matching real-world usage where the holding process stays alive for the run's
  duration. Re-run 5x after the fix: `1 test, 0 failures` every time.

Disclosed, real remaining scope boundary: the cross-node case (two distinct BEAM nodes, not two
OS processes/subprocesses on the same node -- the `mix run -e` subprocess scenario in
`test/ggen_igniter_lock_staleness_properties_test.exs`'s integration test IS same-node and IS
covered) still falls back to mtime-age only, since an Erlang pid from a remote node's local
process table cannot be resolved via `:erlang.list_to_pid/1` locally without `:rpc`/distribution
machinery this module does not use.

## 7. `CompensationTelemetryMiddleware`'s counters have no run-scoping and can double-count one failure — RESOLVED (v26.9.3, commit TBD)

Closed in full: `lib/ggen_igniter/reactors/compensation_telemetry_middleware.ex`'s
`error/2` now checks `find_step_error/2`'s `{:compile_failed, _}` match FIRST
and only falls through to `find_compensation_failure/1` when that didn't
already match -- one real error term bumps at most one of
`:build_broken`/`:compensation_failed`, matching
`ReconcileReactor.standing_for_failure/2`'s own real either/or classification
those two counters are meant to mirror. The ETS table's key shape is now
`{run_id, counter_atom}`, not a bare `counter_atom` -- `run_id` is minted in
`init/1` (`{self(), System.unique_integer/1}`; `Reactor.context()` provides no
run identifier of its own, confirmed absent from
`deps/reactor/lib/reactor.ex`'s `@type context :: %{optional(atom) => any}`)
and stored into the real context map `init/1` returns, which
`deps/reactor/lib/reactor/executor.ex`'s `run/4` threads unchanged into every
subsequent `event/3`/`error/2` call for that one run (traced directly, not
guessed). A new `counters/1` reads back exactly one run's counts; `counters/0`
is kept for backward compatibility, now documented as a cross-run aggregate
(sums every `run_id`'s counts) rather than a per-run answer.
`ReconcileReactor.run/1` gained an optional `:telemetry_run_id` opt, threaded
into the `Reactor.run/4` context, so a caller/test can supply its own id and
read it back via `counters/1` without needing Reactor to expose one itself.
`test/ggen_igniter_reconcile_reactor_compensation_telemetry_test.exs`: 5 tests
(the two original real `ReconcileReactor.run/1` scenarios, now scoped via
`counters/1`; a new test proving two real sequential `ReconcileReactor.run/1`
calls with distinct `telemetry_run_id`s are independently readable and never
summed; two new tests calling `error/2` directly against real constructed
error terms shaped exactly like `find_compensation_failure/1`/
`find_step_error/2`'s own pattern-match clauses, proving the mutual-exclusion
precedence fires correctly in both directions), 0 failures
(`mix test test/ggen_igniter_reconcile_reactor_compensation_telemetry_test.exs`
-> `5 tests, 0 failures`). `mix compile --warnings-as-errors` clean.
`grep -rn "Mock\|mock(\|patch(\|monkeypatch" test/ggen_igniter_reconcile_reactor_compensation_telemetry_test.exs
lib/ggen_igniter/reactors/compensation_telemetry_middleware.ex` -> zero
matches. Original gap text kept below for the historical record.

## 7 (original text)

`error/2` independently checks `find_compensation_failure/1` (bumps `:compensation_failed`) and
`find_step_error/2` for `{:compile_failed, _}` (bumps `:build_broken`) against the same error
term with no mutual exclusion -- both can fire for one real failing run. More significantly, the
backing table is a single global, unscoped ETS table: `counters/0` answers "how many times has
this ever compensated/undone across every run since this BEAM node booted," not "how many times
did THIS run compensate," despite the moduledoc framing the question in the singular. A
long-lived `GgenIgniter.Controller` looping `Reconcile.run/1` (or, post-item-4's fix,
`ReconcileReactor.run/1`) repeatedly would accumulate all runs into one indistinguishable total.
Needs a `{run_id, counter}` key shape and either an exposed reset or a per-run snapshot API.

## 8. `DoctorFixes`'s `--fix` dep-only rewrite crashes on a valid 2-tuple dependency shape — RESOLVED (v26.9.3, commit TBD)

`rewrite_dep_only/2` unconditionally called `Igniter.Code.Tuple.tuple_elem(tuple_zipper, 2)` to
reach a dependency's options, which only exists on a 3-element `{name, version, opts}` tuple.
The check-side predicate (`dep_only_predicate/2`, a generic regex match) has no notion of tuple
arity, so it reported `:fixable` for an equally common, idiomatic 2-tuple form with no version
requirement -- e.g. `{:some_dep, github: "org/repo", only: :test}` or
`{:some_dep, path: "../local", only: :dev}` -- and the AST transform then raised a
`RuntimeError` on that shape instead of degrading gracefully. `test/ggen_igniter_doctor_fixes_test.exs`
had no 2-tuple-with-opts fixture (confirmed via grep), so this tuple-arity mismatch was untested
despite the CHANGELOG's "7 new tests... a regression test proves it" claim, which covered only
the regex-vs-comment bug the migration was written to fix, not this one.

**Fix**: added `dep_opts_elem/1` (`lib/ggen_igniter/doctor_fixes.ex:399-407`), which determines
the dependency tuple's real arity via `Igniter.Code.Common.maybe_move_to_single_child_block/1` +
`Sourceror.Zipper.node/1` (a raw `Sourceror`-parsed literal 2-tuple is wrapped in a `:__block__`
node until unwrapped this way -- confirmed via a real `mix run` debug script inspecting the
zipper node) before picking element 2 (3-tuple `{name, version, opts}`) or element 1 (2-tuple
`{name, opts}`); any other shape returns `:error` and falls through to the pre-existing
"refusing to guess" `RuntimeError` path rather than crashing on an out-of-bounds index (which
`Igniter.Code.Tuple.tuple_elem/2` itself already handles gracefully, returning `:error`, never
raising). `rewrite_dep_only/2` now only runs `collapse_empty_dep_opts/1` (3-tuple -> 2-tuple
degeneration) for the 3-tuple case; an emptied 2-tuple's opts list is left as `{name, []}`,
still syntactically valid mix.exs. Two real fixtures added to
`test/ggen_igniter_doctor_fixes_test.exs` -- `{:some_dep, github: "org/repo", only: :test}` and
`{:local_dep, path: "../local", only: :dev}` -- both asserting the real rewritten `mix.exs`
content via the same real `Sourceror`/`Igniter.Code` machinery the existing tests use (no
mocks; `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test/ggen_igniter_doctor_fixes_test.exs
lib/ggen_igniter/doctor_fixes.ex` -> zero matches). `mix test test/ggen_igniter_doctor_fixes_test.exs`
-> `27 tests, 0 failures` (up from 25), `mix compile --warnings-as-errors` clean.

## Not a gap (confirmed, for completeness)

- `Mix.Tasks.GgenIgniter.Sync` already has full frontmatter parsing, `--for-each` multi-row
  fan-out, and `inject`/`before`/`after`/`at_line` splicing (`lib/mix/tasks/ggen_igniter.sync.ex`,
  `GgenIgniter.Frontmatter`) -- these were previously (incorrectly) assessed as missing by
  reading only `GgenIgniter.Reconcile`'s deliberately-bounded proof-of-concept moduledoc, which
  disclaims all three features for *itself* specifically, not for the real CLI task. `sync.ex` is
  the correct integration point for a consumer wanting frontmatter/for-each/inject parity with
  the Rust `ggen` CLI; `Reconcile`/`Controller` remain the narrower, stateless/supervised-process
  variants for a consumer that doesn't need those three features.
