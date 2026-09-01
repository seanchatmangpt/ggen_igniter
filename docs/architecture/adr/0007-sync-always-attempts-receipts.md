# ADR-0007: `mix ggen_igniter.sync` Always Attempts the Reactor Pipeline (Receipts on Every Run), Gated Only by Delegatability

## Status

**Accepted, and the "Known open issue" ETS crash below is no longer
reproducible** (re-verified 2026-09-01). The decision described below is
real and landed in `lib/mix/tasks/ggen_igniter.sync.ex`. Re-verification
this pass:

- Real repro attempt of the exact scenario the "Known open issue" section
  below describes (a bare `mix ggen_igniter.sync` CLI invocation, outside
  `mix test`'s already-running application tree): `cd /Users/sac/
  ggen_igniter && mix ggen_igniter.sync --ontology tmp_probe/mini.ttl
  --query spec=tmp_probe/mini.rq --template tmp_probe/mini.eex --out
  tmp_probe/probe_out.ex` completed successfully via the Reactor pipeline
  — actual output: `Notices: * ggen_igniter: wrote tmp_probe/probe_out.ex
  (engine: oxigraph, 1 query, 1 total row(s)) (via reactor)`, with the real
  templated file (`# generated: Foo`) written to disk. No
  `Reactor.Executor.ConcurrencyTracker.allocate_pool/1` `ArgumentError`, no
  ETS failure of any kind.
- `mix test test/ggen_igniter_reconcile_reactor_test.exs`: real output `8
  tests, 0 failures` — the module driving `ReconcileReactor` directly.
- Checked `git show --stat 0c0eb03 52164d6` (the two most recent commits
  touching `ReconcileReactor`/`mode: eval`) specifically for this ETS
  issue: neither commit's diff or message mentions
  `ConcurrencyTracker`/`allocate_pool`/ETS. `0c0eb03` ("Fix AR-9: mode:eval
  no longer crashes the Reactor's :render step") fixes an unrelated
  `OcelEmitter.file_object/1` `FunctionClauseError` on `mode: eval`'s nil
  target; `52164d6` ("Thread a real %Igniter{} through mode:eval targets in
  ReconcileReactor's :actuate step") threads an `%Igniter{}` accumulator
  through `:eval` actuation, also unrelated. So this ETS crash was not
  fixed *by* either commit specifically — it is simply not reproducible on
  current `main`, consistent with the original note's own hypothesis (a
  missing `:reactor` OTP-application-supervision-tree start on a bare CLI
  invocation, "rather than a defect in this ADR's own code") having since
  resolved as a non-issue in the current dependency/boot state.

The "Known open issue (this pass)" paragraph below is retained verbatim as
a historical record of the 2026-08-27 finding; it is superseded by this
Status section and is not a currently-standing blocker.

## Context

Prior to this decision, `mix ggen_igniter.sync` chose between two real,
independently-maintained pipelines at runtime based on
`Application.get_env(:ggen_igniter, :use_reactor, false)`:

- **Default (`false`)**: `dispatch_pipeline/3`, the bounded inline pipeline
  — no receipt, no `GgenIgniter.Manifest`-aware admission invariants beyond
  what `sync.ex` itself implements inline, no rollback on a downstream
  failure.
- **Opt-in (`true`)**: `GgenIgniter.Reactors.ReconcileReactor.run/1` — the
  full 9-step admission/actuate/verify/finalize-evidence pipeline (see
  `docs/reference/reactor/overview.md`), which is the only path that ever
  writes a `GgenIgniter.Receipt` (ADR-0005) or exercises `undo/4`
  compensation.

This meant the evidence guarantees ADR-0005 establishes — "if files were
actually changed, even temporarily, a receipt records it" — only held for
users who explicitly opted in. The overwhelming majority of real
`mix ggen_igniter.sync` invocations (the default config) produced **no
durable evidence at all** on failure, defeating the purpose of building the
Reactor pipeline's evidence subsystem in the first place.

## Decision

Delete `use_reactor?/0` and the `Application.get_env/3` branch entirely.
`mix ggen_igniter.sync`'s `igniter/1` now calls `run_via_reactor/3`
**unconditionally, on every invocation** — falling back to the pre-existing
`dispatch_pipeline/3` only when `run_via_reactor/3` itself returns
`{:not_delegatable, reason}` for a real, bounded-scope reason:
frontmatter-bearing templates, or `--for-each` fan-out — both real,
disclosed exclusions `GgenIgniter.Reconcile.run/1`'s Reactor path does not
yet implement (see the root `CLAUDE.md`'s "Two parallel pipelines" table).
A one-time migration notice is logged via a `:persistent_term`-tracked
`migration_notice_once/1` so a consumer who was relying on the old default
silently skipping receipt evidence is told, once, that behavior changed.

The reactor-path invocation is wrapped, for the first time on this
previously-default-off path, in a real cross-process
`GgenIgniter.Lock.acquire/2`/`.release/1` pair (`try/after`) — see
`docs/reference/cli/lock.md` — because making the Reactor pipeline the
default path for every invocation means concurrent `sync` invocations
against the same project are now a real, everyday scenario this pipeline
must serialize against, not an edge case only opt-in users hit.

## Consequences

- Every `mix ggen_igniter.sync` invocation now attempts to produce a real
  `GgenIgniter.Receipt` (ADR-0005's guarantee), not just opt-in ones — this
  is the intended, disclosed behavior change, not a regression.
- `dispatch_pipeline/3` (the old default) is not deleted — it remains the
  real fallback for frontmatter/`--for-each` cases the Reactor path cannot
  yet delegate to, and continues to write no receipt on that fallback path.
  This is a disclosed, bounded-scope gap (see `docs/status.md`'s "Two
  parallel pipelines" framing), not something this decision closes.
- `config :ggen_igniter, use_reactor: true/false` no longer has any effect
  on `mix ggen_igniter.sync`'s pipeline choice — that config key is now
  dead for this call site specifically. (`GgenIgniter.Controller`, a
  separate call site, is untouched by this ADR and was not re-verified for
  its own `use_reactor` dependency this pass.)
- **Known open issue (2026-08-27 pass; SUPERSEDED — see Status section
  above, re-verified 2026-09-01 not reproducible):** a real invocation of
  the now-default Reactor path raises `** (ArgumentError) ... the table
  identifier does not refer to an existing ETS table` from
  `Reactor.Executor.ConcurrencyTracker.allocate_pool/1`, reproduced fresh
  this pass via `mix ggen_igniter.sync --ontology
  test/fixtures/audit_trail_ontology.ttl --query
  spec=test/fixtures/spec.rq --template test/fixtures/extension.ex.eex
  --out /tmp/probe.ex`. This is a **different** failure than the
  `GgenIgniter.Lock` `UndefinedFunctionError` a prior pass recorded (that
  module now exists — see `docs/reference/cli/lock.md`) and appears to be a
  missing `:reactor` OTP-application-supervision-tree start when `sync` is
  invoked as a bare CLI task outside `mix test`'s already-running
  application tree, rather than a defect in this ADR's own code. Not
  independently root-caused or fixed this pass — flagged here as the
  concrete blocker standing between "the decision landed" and "the decision
  is runnable."

## Correction (AR-10, 2026-08-27): the frontmatter fallback was broader than the Reactor pipeline's real scope

This ADR's original "Decision" section named "frontmatter-bearing templates,
or `--for-each` fan-out" as the two real, bounded-scope exclusions from
Reactor delegation. Re-verified this pass: that framing was itself broader
than necessary. `GgenIgniter.Reactors.ReconcileReactor`'s `:render`/`:admit`/
`:actuate` steps already fully implement `operation: :inject`
`%PendingActuation{}` construction and dispatch (`render_inject_target/8`,
reusing `GgenIgniter.Frontmatter.split_template/1` + `GgenIgniter.Injection`)
-- proven by `test/ggen_igniter_reconcile_reactor_inject_test.exs`, which
calls `ReconcileReactor.run/1` directly. The real, narrower gap:
`run_via_reactor/3`'s own dispatch guard refused delegation for ANY
frontmatter at all, not just the one frontmatter feature the Reactor path
genuinely does not resolve (inline `sparql:` query text -- `ReconcileReactor.
run_target_queries/3` only ever resolves explicit `--query`/pack-discovered
`.rq` files). Since `inject: true` can only be expressed via frontmatter,
this meant no `inject: true` write via `mix ggen_igniter.sync` ever got this
pipeline's real admission-gate coverage (duplicate-output-path refusal,
path-escape refusal) or a persisted receipt.

Fixed: `run_via_reactor/3`'s guard now only refuses delegation for (a)
`--for-each` fan-out (unchanged), (b) frontmatter with a non-empty inline
`sparql:` block, and (c) frontmatter combined with `mode: eval` specifically
(a real, separate, pre-existing `ReconcileReactor` `:render`-step crash for
`:eval` targets, unrelated to this correction -- see `docs/status.md`'s
`inject: true` closure row and `test/ggen_igniter_reconcile_reactor_test.exs`'s
`":eval compensation-completeness"` finding). Frontmatter's `to:`/
`unless_exists:`/`skip_if:` fields are now resolved into concrete
`reconcile_opts` values before delegating, since `ReconcileReactor`'s own
target-resolution reads those ONLY from the flat opts/`:targets` list, never
re-reading the template's frontmatter directly (unlike its `:render` step's
own re-read for `inject`/`before`/`after`/`at_line`). See
`test/ggen_igniter_sync_inject_reactor_admission_test.exs` for the real,
CLI-subprocess proof, including a path-escape refusal compared side by side
against an ordinary `mode: file` write refused the identical real way.

## See also

- `docs/architecture/adr/0005-receipt-independent-of-manifest.md` — the
  evidence guarantee this decision extends to the default pipeline
- `docs/architecture/adr/0003-plain-reactor-for-coordination.md` — why the
  Reactor pipeline exists as a plain `Reactor` module in the first place
- `docs/reference/cli/lock.md` — the new cross-process lock this decision
  requires and wraps around every `sync` invocation
- `docs/status.md` — `sync`-always-attempts-receipts row, kept in sync with
  this ADR's status
