# Redteam Doc-vs-Source Contradiction Review

Scope: `docs/architecture/**` and `docs/reference/reactor/**` vs.
`lib/ggen_igniter/reactors/reconcile_reactor.ex` (1575 lines), read directly
by this reviewer, independent of the docs' own cited line numbers.

`docs/` exists and is populated (14 files/dirs under `docs/`, including both
target directories). Five claims independently re-verified below.

## Claim 1 (REFUTED on citation, substance holds)

**Doc claim** (`docs/reference/reactor/steps.md` line 178-179, repeated in
`compensation.md` line 168-169): "`:actuate`... **Retry policy:** `max_retries
0` -- **explicit**, line 378."

**Real source:** `step :actuate do` opens at line 438; `max_retries 0` for
that step is at **line 505**, not 378 (`reconcile_reactor.ex:505`). The
mechanism claim (explicit `max_retries 0` override on `:actuate`) is
substantively true, but the cited line is wrong by 127 lines.

**Verdict: REFUTED** (as a file:line citation) / substance CONFIRMED. The
whole module has shifted down by a large, non-uniform offset since the docs
were written (a large moduledoc addition dated 2026-08-27 at the top of the
file, `reconcile_reactor.ex:9-95`+), so every absolute line number cited
throughout `steps.md`, `compensation.md`, and `concurrency.md` is stale.

## Claim 2 (REFUTED on citation, substance holds)

**Doc claim** (`steps.md` lines 208-210): "`:verify`... a real subprocess,
`System.cmd(\"mix\", [\"compile\", \"--warnings-as-errors\"], cd: project_dir,
stderr_to_stdout: true)` (line 389)."

**Real source:** `System.cmd("mix", ["compile", "--warnings-as-errors"], cd:
project_dir, stderr_to_stdout: true)` is real and verbatim, but at
**`reconcile_reactor.ex:523-526`**, not 389. `step :verify do` itself opens
at line 515, not 381 as `steps.md`'s header table claims.

**Verdict: REFUTED** (citation) / substance CONFIRMED (the exact command,
arguments, and `"reason_type" => "build_broken"` behavior on failure, line
533, all match).

## Claim 3 (REFUTED — the doc's description of the mechanism is now incomplete/stale, not just mis-cited)

**Doc claim** (`compensation.md` lines 78-100): "`:actuate`'s `undo/4`... the
real, tested revert path" is presented as: call `revert_all(tracked)`
unconditionally, then compute `post_hash`, emit `"FILES_RESTORED"`, and
`:ok` — no error branch shown or mentioned anywhere in the doc.

**Real source** (`reconcile_reactor.ex:457-503`): `undo fn %{tracked:
tracked}, ...` now wraps the revert in `case revert_all(tracked) do {:ok,
_restored} -> ... :ok ; {:error, %{restored:, failed:} = details} -> ...
{:error, {:compensation_failed, details}} end`. `revert_all/1` itself
(`reconcile_reactor.ex:1358`) returns `{:ok, _} | {:error, _}`, not a bare
`:ok`. There is a whole additional standing, `:compensation_failed`
("CATASTROPHIC" per the moduledoc, `reconcile_reactor.ex:272`,
`find_compensation_failure/1` at line 730, `"COMPENSATION_FAILED"` /
`"COMPENSATION_COMPLETED"` OCEL events at lines 462-501), that
`compensation.md` never mentions at all.

**Verdict: REFUTED.** This is not a line-drift artifact — the doc's
behavioral description (revert always succeeds, returns `:ok`, no failure
path) omits a real, currently-implemented failure/standing branch in the
source. A reader of `compensation.md` alone would not know
`:compensation_failed` exists.

## Claim 4 (REFUTED on citation, substance holds)

**Doc claim** (`concurrency.md` lines 52-65): "`actuate_pending/2`
(`reconcile_reactor.ex:890-948`)... `max_concurrency =
max(System.schedulers_online(), 1)` ... `Task.async_stream(&actuate_one(&1,
...), max_concurrency: max_concurrency, timeout: :infinity)`."

**Real source:** `defp actuate_pending(%{pending: pending, exec: exec},
event_sink)` is at **line 1189**; `max_concurrency = max(System.schedulers_
online(), 1)` is at **line 1192**; the `Task.async_stream` call is at
**lines 1198-1203**. None of these fall in the cited 890-948 range (off by
~300+ lines).

**Verdict: REFUTED** (citation) / substance CONFIRMED (the code shown in the
doc is a verbatim, currently-accurate excerpt of the real function body,
just at the wrong line numbers).

## Claim 5 (REFUTED on citation, substance holds)

**Doc claim** (`steps.md` lines 246-256): "`Receipt.append!(manifest_dir,
receipt)` (line 1102)... `Manifest.persist!(new_manifest, manifest_dir)`
(line 1113), but wrapped in `try/rescue`."

**Real source:** `:ok = Receipt.append!(manifest_dir, receipt)` is at
**line 1492**; the `try do Manifest.persist!(new_manifest, manifest_dir) ...
rescue exception -> {:pending, Exception.message(exception)} end` block is
at **lines 1502-1507**. Both are ~390 lines below the doc's citations. The
behavioral claim (receipt written first and durably, manifest promotion
wrapped in try/rescue so a failure there does not undo the already-durable
receipt) matches the real code exactly.

**Verdict: REFUTED** (citation) / substance CONFIRMED.

## Summary

| # | Claim (doc) | Mechanism/substance | Line citation |
|---|---|---|---|
| 1 | `:actuate` `max_retries 0` | CONFIRMED | REFUTED (378 vs 505) |
| 2 | `:verify`'s `System.cmd` | CONFIRMED | REFUTED (389 vs 523) |
| 3 | `undo/4` always returns `:ok`, no failure path | REFUTED (source has a real `{:error, ...}` / `:compensation_failed` branch the doc never describes) | n/a |
| 4 | `actuate_pending/2` concurrency shape | CONFIRMED | REFUTED (890-948 vs 1189-1203) |
| 5 | `finalize_evidence` receipt-then-manifest ordering | CONFIRMED | REFUTED (1102/1113 vs 1492/1503) |

**Root cause (verified in-session):** the module's moduledoc gained a large
"Corrections applied (2026-08-27)" section near the top of the file
(`reconcile_reactor.ex:9` onward) and the `:actuate` `undo/4` callback grew a
real `:compensation_failed` error branch — both post-dating whatever revision
of the source the three reactor docs (`steps.md`, `compensation.md`,
`concurrency.md`) were written against. Every absolute-line-number citation
across all three files checked is stale by a large, non-uniform offset (the
offset itself grows through the file, from ~59 lines near the top to ~390
lines near the bottom — evidence of at least two separate insertions, not one
uniform shift). Claim 3 additionally shows the docs did not just drift in
line number but in *behavioral completeness*: a real standing
(`:compensation_failed`) exists in source with no documentation coverage in
`compensation.md` or `failure-semantics.md` (not independently checked here,
but implicated by the same gap).
