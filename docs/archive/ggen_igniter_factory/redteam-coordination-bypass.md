# Red-team finding: competing coordinators for production reconciliation

**Verdict: CONFIRMED** — three independently-coded implementations of the
ontology-load -> query -> render -> actuate spine exist in this repo, each with
its own direct call site into `GgenIgniter.Actuate.write_file!/3` (and/or
`eval_code!/2`), reachable through real, non-test code paths. None of the
three is a thin adapter over one authoritative implementation.

## The three real actuators

1. **`Mix.Tasks.GgenIgniter.Sync.run_pipeline!/3`**
   `/Users/sac/ggen_igniter/lib/mix/tasks/ggen_igniter.sync.ex:563-723`
   Fully independent pipeline body: `resolve_ontology!` ->
   `Ontology.load!/1` -> `Frontmatter.split_template/1` ->
   `resolve_named_queries!/2` -> `run_queries/4` -> `build_bindings/2` ->
   `Render.render/2` -> `actuate!/8`, plus its own reconciliation-manifest
   (`Manifest`) stale-path logic. Calls `Actuate.write_file!/3` directly at
   line 837, `Actuate.inject_content!/5` at line 852, `Actuate.eval_code!/2`
   at line 890. **This is the default path**: reached whenever
   `Application.get_env(:ggen_igniter, :use_reactor, false)` is `false` (the
   default, `sync.ex:446`) and no `GgenIgniter.Controller` process is
   registered (`sync.ex:451-462`, `dispatch_pipeline/3`) — i.e., out of the
   box, with zero config changes.

2. **`GgenIgniter.Reconcile.run/1`**
   `/Users/sac/ggen_igniter/lib/ggen_igniter/reconcile.ex:92-125`
   A second, separately written implementation of the same spine
   (`resolve_ontology!` -> `Ontology.load!/1` -> `resolve_named_queries!` ->
   `run_queries/4` -> `build_bindings/1` -> `Render.render/2` ->
   `actuate!/4`), calling `Actuate.write_file!/3` directly at line 140 and
   `Actuate.eval_code!/2` at line 145. This module's own moduledoc
   (`reconcile.ex:14-19`) states explicitly: *"`Mix.Tasks.GgenIgniter.Sync`
   itself is left unchanged in this pass ... so for now this is a second
   entry point into the same real query engines/render/actuate modules
   `sync.ex` already uses, not yet the CLI's own call path."* — i.e. the
   module's own author-facing documentation confirms `sync.ex` does **not**
   call this function; `sync.ex`'s `alias` list
   (`sync.ex:174`) does not even import `GgenIgniter.Reconcile`.
   Reached by `GgenIgniter.Controller.reconcile/3` ->
   `handle_call/3` -> private `run_pipeline/1`
   (`controller.ex:169-179`), whenever `Application.get_env(:ggen_igniter,
   :use_reactor, false)` is `false` (the default, checked independently of
   Sync's own copy of the same flag) — i.e. Controller's default behavior,
   when a Controller process is running, is to call *this* third writer, not
   `sync.ex`'s pipeline.

3. **`GgenIgniter.Reactors.ReconcileReactor.run/1`**
   `/Users/sac/ggen_igniter/lib/ggen_igniter/reactors/reconcile_reactor.ex`
   A third, wholly separate implementation built as a `Reactor` pipeline
   (`observe_prior_manifest` -> `load_ontology` -> `resolve_pack` ->
   `run_queries` -> `render` -> `admit` -> `actuate` -> `verify` ->
   `finalize_evidence`, steps at lines 326-570). Its `:actuate` step calls
   `Actuate.write_file!/3` directly at line 1289 and `Actuate.eval_code!/2`
   at line 1276 (helper `actuate_one/2`). It reuses exactly one pure helper
   from module 2 (`Reconcile.build_bindings/1`, called at line 886) but does
   **not** call `Reconcile.run/1` or `Sync.run_pipeline!/3` for its actual
   actuation — it re-derives ontology/query/render/admit/actuate/verify
   logic itself. Reachable two ways, both gated by the *same* app-env flag
   `Application.get_env(:ggen_igniter, :use_reactor, false)`, checked
   independently in each caller:
     * from `Mix.Tasks.GgenIgniter.Sync.igniter/1` ->
       `run_via_reactor/3` (`sync.ex:436-444, 473-493`)
     * from `GgenIgniter.Controller`'s private `run_pipeline/1` ->
       `run_via_reactor/1` (`controller.ex:169-198`)
   and is also a public `run/1` any other caller could invoke directly
   (nothing prevents a fourth call site from appearing).

## Why this is "competing," not "thin adapter"

For "exactly one authoritative coordinator with thin adapters" to hold, at
most one of the three modules above should contain real
ontology-load/query/render/write logic, with the other two being pure
pass-throughs that marshal arguments and forward to it. That is not what the
code shows:

- `sync.ex`'s default fallback (`run_pipeline!/3`) and `Controller`'s default
  path (`Reconcile.run/1`) are two **separately maintained** copies of
  essentially the same spine (compare `sync.ex:563-723` clause-by-clause
  against `reconcile.ex:92-262` — same shape, duplicated code, acknowledged
  as duplicated by `reconcile.ex`'s own moduledoc, and NOT yet unified as of
  this read).
- `ReconcileReactor` is a third, richer reimplementation (with its own
  admit/verify/compensate machinery) that does not route through either of
  the other two for its actual disk writes.
- The flag gating Reactor dispatch (`:use_reactor`) is read **independently**
  in `sync.ex:446` and `controller.ex:170` — there is no single switchboard;
  each of the two upstream entry points makes its own routing decision, and
  each can independently reach `ReconcileReactor` OR its own legacy pipeline
  OR (`sync.ex` only) `Controller`.

## Real call graph (as read, not as documented)

```
Mix.Tasks.GgenIgniter.Sync.igniter/1
├─ use_reactor?() == true  -> ReconcileReactor.run/1        [real actuate]
└─ use_reactor?() == false (default)
   ├─ Controller registered -> Controller.reconcile/3
   │     └─ Controller's own use_reactor flag
   │         ├─ true  -> ReconcileReactor.run/1              [real actuate]
   │         └─ false (default) -> Reconcile.run/1           [real actuate]
   └─ Controller not registered (default) -> Sync.run_pipeline!/3  [real actuate]
```

Three distinct leaves reach real disk mutation
(`Actuate.write_file!/3`/`eval_code!/2`): `Sync.run_pipeline!/3`
(sync.ex:837/852/890), `Reconcile.run/1` (reconcile.ex:140/145), and
`ReconcileReactor.run/1` (reconcile_reactor.ex:1289/1276). None is reached by
100% of production configurations, and none is a pure forwarding shim over
another.

## Scope note

This finding is about **code structure and reachability**, not about which
path a given deployment actually exercises today (both `use_reactor` and
`start_controller` default to `false`, so a fresh `mix ggen_igniter.sync`
invocation with default config only ever reaches `Sync.run_pipeline!/3`).
The claim under test — "does more than one real coordinator exist... rather
than exactly one being authoritative with the others as thin adapters" — is
about the code as written, and on that question the answer is CONFIRMED:
three independently-implemented, independently-reachable actuators exist,
each gated by its own opt-in flag checked in its own module, not funneled
through one shared implementation.
