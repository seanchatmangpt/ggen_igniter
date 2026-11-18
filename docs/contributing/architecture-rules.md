# Architecture Rules

These are the layer-ownership rules this codebase is built to honor. They
are normative for new code, not merely descriptive of what happens to exist
today — a change that violates one of these needs a real justification in
its own right, not just "it was convenient here."

## Who owns what

- **Reactor owns coordination — preferred path.** `use Reactor` (plain
  `Reactor`, deliberately *not* `Ash.Reactor` — `ggen_igniter` must stay
  usable without Ash as a mandatory runtime dependency). The one
  coordination spine is `GgenIgniter.Reactors.ReconcileReactor`: observe →
  load → resolve → query → render → admit → actuate → verify → finalize
  evidence. `mix ggen_igniter.sync` is a CLI facade into that spine only
  (no separate inline Sync coordinator — `run_pipeline!/3` /
  `dispatch_pipeline/3` were deleted). The remaining non-Reactor path is
  the bounded plain function `GgenIgniter.Reconcile.run/1`, used by
  `GgenIgniter.Controller` when `use_reactor` is `false` (shipped default)
  and by programmatic callers that opt out of receipts/compensation —
  see `docs/operations/runtime.md`. Do not add a second, independent
  step-orchestration mechanism; extend `ReconcileReactor` (see
  `docs/contributing/adding-a-reactor-step.md`) or, for the bounded
  residual only, extend `GgenIgniter.Reconcile.run/1`'s linear sequence.

- **Igniter owns Elixir project mutation.** `mix ggen_igniter.sync` and
  `mix ggen_igniter.doctor` are both real `Igniter.Mix.Task` modules. Any
  code that needs to inspect or rewrite a *consumer's* `mix.exs`,
  `config/config.exs`, or other project-level Elixir source (dependency
  `:only` relaxation, `ash_domains:` registration, `config :dcatr, env:`
  insertion — see `GgenIgniter.DoctorFixes`) goes through Igniter's own
  conventions (real file reads/precise text replacement, never a full-file
  regex rewrite, never a guess where the shape is ambiguous — see that
  module's own "never silently no-op on a real problem" discipline). This
  is a distinct concern from ggen's own semantic compilation below: Igniter
  mutates the *host project's build/config surface*, not the *content* of
  what gets generated.

- **ggen owns semantic compilation.** The ontology → SPARQL → template
  pipeline itself (`GgenIgniter.Ontology`, `GgenIgniter.Engine`/`Query.*`,
  `GgenIgniter.Render`, `GgenIgniter.Actuate`) is a port of the real Rust
  `ggen`'s own semantics — the write-safety decision table
  (`unless_exists`/`skip_if`/idempotent no-op) deliberately mirrors
  `ggen-engine/src/write.rs`; the `PendingActuation` IR mirrors
  `ggen-engine/src/sync.rs`'s `PendingWrite`/`SyncReport`; the
  `GgenIgniter.Frontmatter` struct mirrors `ggen::Frontmatter` field-for-field.
  When in doubt about what a field or behavior should mean, check the real
  Rust `ggen` source first rather than inventing a new Elixir-only
  convention — divergence from the Rust semantics needs to be a disclosed,
  deliberate choice (see `ReconcileReactor`'s moduledoc "Prune timing"
  section for an example of exactly this: a deliberate, disclosed departure
  from `sync.ex`'s existing prune-timing behavior, not an oversight).

- **Ash owns application semantics — in Ash consumers only.** Nothing in
  `ggen_igniter`'s own `lib/` requires Ash to compile or run (`ash_domains`
  registration in `DoctorFixes` operates on a *consumer's* project by
  scanning for `use Ash.Domain` textually, never by requiring `Ash` itself
  to be a dependency of `ggen_igniter`). Templates that generate Ash
  resources (e.g. `test/fixtures/ash-lifecycle-pack/templates/resource.ex.eex`)
  are pack content, not core pipeline code — a pack author choosing to
  target Ash does not make Ash a core dependency of the generation engine.
  Do not add a hard `Ash` dependency to any module under `lib/ggen_igniter/`
  or `lib/mix/tasks/`.

- **GenServer (`Controller`) does not become a workflow engine.**
  `GgenIgniter.Controller` adds *only* in-process state bookkeeping around
  one existing pipeline call (`Reconcile.run/1` or, opt-in,
  `ReconcileReactor.run/1`) — see `docs/operations/controller.md`. It has
  no step graph, no dependency scheduling, no compensation/undo logic of
  its own. If a change to `Controller` starts adding any of those things,
  that logic belongs in `ReconcileReactor` instead, dispatched to via the
  existing `use_reactor` flag — not duplicated inline in the GenServer.

## Four hard invariants

- **No filesystem mutation before admission.** Every real create/replace/
  delete/eval intent for a run is built as a `%GgenIgniter.PendingActuation{}`
  *before* anything touches disk — the full planned delta is available for
  inspection and refusal (duplicate output-path collisions, unowned
  `:delete` candidates, `--on-stale refuse`'s stale-path policy) as one
  whole-plan decision, not scattered per-item checks interleaved with real
  writes. `:admit` is the one step allowed to refuse a run outright; once
  `:actuate` starts, every item it touches has already passed admission.
  New code that writes to disk without first producing a `PendingActuation`
  the admit step can see is a violation of this invariant, not a minor
  style issue — it reopens exactly the class of destructive-write risk this
  IR exists to close.

- **No hidden manual repair.** Every fix this codebase applies to a
  consumer project (the four `GgenIgniter.DoctorFixes` rules, plus the
  version-policy fix) is real, structured, and disclosed: a
  predicate/transform/verify triple that reports exactly what it changed
  (`FIXED: ...`) or exactly why it refuses to guess. There is no code path
  anywhere that silently patches a consumer's files as a side effect of an
  unrelated operation, and no fix that regex-rewrites a shape it hasn't
  precisely recognized — an unrecognized shape is reported as a real
  `:error`/`{:unrecognized, ...}`, never guessed at.

- **No duplicate coordinator.** There must be exactly one real
  coordination path per invocation shape: `ReconcileReactor.run/1` for
  `mix ggen_igniter.sync` (always), and exactly one of `Reconcile.run/1` /
  `ReconcileReactor.run/1` for the Controller (selected by the single
  `use_reactor` flag, never both at once for the same call). Do not add a
  third, competing orchestration mechanism (a revived Sync inline spine, a
  second GenServer with its own step logic, a second Reactor module
  duplicating `ReconcileReactor`) — extend `ReconcileReactor`, or the
  bounded `Reconcile.run/1` residual, instead.

- **Verification precedes advancement.** `:verify` (a real `mix compile
  --warnings-as-errors` subprocess against the actuated project) must run,
  and must pass, before the manifest is ever promoted or a `:delete`
  stale-prune candidate is actually removed — see `ReconcileReactor`'s
  "Prune timing" section: real prune deletions run only *after* `:verify`
  confirms the newly-actuated project compiles. The CLI inherits this
  ordering because it dispatches only through `ReconcileReactor`. The
  bounded `Reconcile.run/1` path has no manifest/prune/verify loop by
  design (no receipt either).

## Preferred path vs bounded residual (sync-spine unification)

The historical three-spine gap (Sync inline / `Reconcile.run/1` /
`ReconcileReactor`) is closed to the smallest lawful pair
(`docs/operations/runtime.md`, corrected 2026-11-18):

- **Preferred coordination path:** `GgenIgniter.Reactors.ReconcileReactor`
  — CLI happy path for every delegatable shape, including `mode: eval`
  (inline Sync coordinator deleted; no Sync→Controller fallback).
- **Bounded residual:** `GgenIgniter.Reconcile.run/1` — Controller default
  when `use_reactor` is `false`, plus programmatic callers that want the
  plain ontology→query→render→actuate spine without receipts.

This is PARTIAL_ALIVE only on the Controller default (`use_reactor: false`
is an operator product decision, not a missing CLI spine). New
coordination belongs in `ReconcileReactor`; do not grow a third spine.

## See Also

- `docs/operations/runtime.md` — the concrete, current default-vs-target split this file's rules describe the target for
- `docs/operations/failure-recovery.md` — the receipt/standing model `:verify`/`:admit` produce
- `docs/contributing/adding-a-reactor-step.md` — how to extend `ReconcileReactor` without violating the invariants above
- `docs/contributing/adding-a-pack.md` — where pack content (including Ash-targeting templates) fits relative to core pipeline code
