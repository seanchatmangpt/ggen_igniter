# RECEIPT — ggen_igniter finish slice (2026-11-18)

Standing: PASS

## What “finish” meant after inventory

Adopted targets (evidence-backed; marketplace ash-a2a G1–G8 left as
consumer/pack work, not this repo’s finish criterion):

1. Red / flake gate: `ChicagoFaultInjectionPackTest` vs async
   `Application.put_env(:graphlaw_wasm_path, …)` pollution.
2. Documented atom-mint hardening from
   `docs/jira/v26.11.12/TODO-FIX-AND-FINISH.md` (MatchRule enums,
   descriptor render keys, SPARQL binding keys).
3. Sync-spine unification: close the documented three-spine gap
   (Sync inline / `Reconcile.run` / `ReconcileReactor`) to preferred
   `ReconcileReactor` + bounded `Reconcile.run` residual; correct docs
   that still claimed Sync inline / `mode: eval` fallback.
4. `to_prd_status/1` contradiction: mark REMOVED/superseded by
   `RProjection` (do not restore without operator decision).

## Sync-spine consolidation choice

**Chosen:** preferred path = `ReconcileReactor`; do **not** flip Controller
`use_reactor` default.

| Surface | Pipeline today |
|---|---|
| `mix ggen_igniter.sync` | **always** `ReconcileReactor` (incl. `mode: eval`); Sync inline coordinator deleted |
| `GgenIgniter.Controller` | `Reconcile.run/1` unless `use_reactor: true` |
| `GgenIgniter.Reconcile.run/1` | bounded programmatic / Controller-default residual |

Flipping Controller default is an operator product decision (in-process
consumers would suddenly get receipts/compensation/verify).

## Changes

- `test/ggen_igniter_graphlaw_engine_test.exs` — `async: false`
- `lib/ggen_igniter/binding_keys.ex` + test — identifier-bounded atomize
- `lib/ggen_igniter/{frontmatter,reconcile,reactors/reconcile_reactor}.ex`,
  `lib/mix/tasks/ggen_igniter.sync.ex`,
  `lib/ggen_igniter/semantic_jira/descriptor.ex` — use bounded admission
- Sync `build_bindings/2` delegates list/flatten to `Reconcile.build_bindings/1`
- docs: `runtime.md`, `architecture-rules.md`, `adding-a-reactor-step.md`,
  `status.md`, Sync/Reconcile/CLAUDE moduledocs — three-spine → preferred
  Reactor + bounded residual (no Sync inline / no `mode: eval` fallback claim)

## Operator decisions still required

Canonical short list (docs lane re-derived): `docs/jira/v26.11.18/FINISH.md`.

- Flip `use_reactor` Controller default to `true`?
- Marketplace ash-a2a pack G1–G8 (lives under ggen-marketplace, not here)?
- Hex publish of v26.11.18 (runbook exists; not executed this slice)?
- Wire `[ontology.aggregate]` into sync?
- Remaining open `String.to_atom` sites (install otp_app, DoctorFixes,
  refusals schema load, tera filter ops, review_eval kind, rename_options)?
- Lock TOCTOU (`pack_lock` / `lock`) — still OPEN in TODO-FIX-AND-FINISH.
## Gate evidence (this slice)

| Command | Exit | Result |
|---|---|---|
| `mix compile --warnings-as-errors` | 0 | clean |
| `mix test` (full default suite) | 0 | **1994 passed**, 5 skipped, 0 failed (22 doctests, 41 properties, 1931 tests) |
| focused atom/graphlaw/frontmatter/descriptor | 0 | 35 passed |

## See Also

- `docs/jira/v26.11.18/FINISH.md`
- `docs/contributing/architecture-rules.md`
- `docs/operations/runtime.md`
- `docs/jira/v26.11.12/TODO-FIX-AND-FINISH.md`
