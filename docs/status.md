# Status

Real, current IMPLEMENTED / PARTIAL_ALIVE / PLANNED status of every major
capability in this repo, sourced from `.ggen_igniter_factory/docs-findings.jsonl`
(93 individually-verified claims from 10 concurrent verification agents,
2026-08-27) and the specialist docs each claim backs. See `docs/glossary.md`
for term definitions and each linked doc for full evidence (file:line
citations, real command output).

Status vocabulary used below (matching the vocabulary used consistently
across every specialist doc in this tree — not a separate scheme invented
for this page):

- **IMPLEMENTED** — real, currently working code, verified by direct reading
  and/or a real passing test run.
- **PARTIAL_ALIVE** — real and working, but with a disclosed, real gap or
  scope limit (not a stub).
- **PLANNED** — described in source (a moduledoc, a comment) as future work,
  not present in `lib/` today.
- **UNVERIFIED (this pass)** — the mechanism is real by inspection, but a
  full end-to-end run was not freshly executed and observed passing in this
  documentation pass (distinct from PLANNED — the code exists).

## CLI and core pipeline

| Capability | Status | Evidence |
|---|---|---|
| `mix ggen_igniter.sync` (ontology → query → render → write) | IMPLEMENTED | `docs/reference/cli/sync.md`; every flag verified against `info/2`'s real schema |
| `mix ggen_igniter.doctor` (17-check diagnostic) | IMPLEMENTED | `docs/reference/cli/doctor.md`; README previously under-documented this as 9 checks — corrected |
| `--engine oxigraph` (default since v26.8.27) | IMPLEMENTED | `docs/reference/cli/engines.md` — default changed to fix a real `sparql` hex 0.3.12 `ORDER BY` row-reversal bug |
| `--engine sparql` | IMPLEMENTED | pure-Elixir fallback; `docs/reference/cli/engines.md` |
| `--engine qlever` | IMPLEMENTED | real remote HTTP SPARQL endpoint; `docs/reference/cli/engines.md` |
| `--pack` / `--pack-dir` / `--pack NAME:TEMPLATE` | IMPLEMENTED | `docs/reference/cli/packs.md` |
| Marketplace pack fetch (`GgenIgniter.Pack.fetch_pack!/2`) | PARTIAL_ALIVE | real, tested function; no CLI flag/task wired to it (`docs/reference/cli/packs.md`) |
| `--for-each NAME` (multi-row fan-out) | IMPLEMENTED | `docs/reference/cli/sync.md` |
| Template frontmatter (`to:`/`sparql:`/`for_each:`/`unless_exists:`/`skip_if:`/`mode:`) | IMPLEMENTED | `docs/reference/cli/sync.md`, `docs/tutorials/first-reconciliation.md` |
| `mode: file` (default) | IMPLEMENTED | `docs/integrations/igniter/safety.md` |
| `mode: eval` (disclosed arbitrary-code-execution capability) | IMPLEMENTED | `docs/integrations/igniter/safety.md` |
| `inject: true` frontmatter splice (`Actuate.inject_content!/5`) | IMPLEMENTED, wired into `sync.ex` | **README correction**: previously stated as unwired ("no call to `inject_content!`"); a real grep found the call site (line 852) and a real 9-test, 0-failure suite proves it works end to end — see `docs/tutorials/getting-started.md` |
| `--unless-exists` / `--skip-if` write-safety guards | IMPLEMENTED | `docs/integrations/igniter/safety.md` |
| `--dry-run` | IMPLEMENTED | previews every actuation/reconciliation decision, zero writes; `docs/reference/cli/sync.md` |

## Reconciliation (manifest and stale artifacts)

| Capability | Status | Evidence |
|---|---|---|
| `GgenIgniter.Manifest` (current-state cache) | IMPLEMENTED | `docs/reference/reconciliation/manifest.md` |
| `--on-stale refuse` (default) | IMPLEMENTED | fail-closed, nothing written; `docs/reference/reconciliation/stale-artifacts.md` |
| `--on-stale prune` (real deletion) | IMPLEMENTED | `docs/reference/reconciliation/stale-artifacts.md` |
| `--on-stale preserve` (warn + release tracking) | IMPLEMENTED | `docs/reference/reconciliation/stale-artifacts.md` |
| Idempotent no-op re-runs (manifest untouched) | IMPLEMENTED | `docs/reference/reconciliation/idempotency.md` |
| Cross-run orphan-file cleanup on resource rename/removal | IMPLEMENTED (via `--on-stale prune`) | **Historical gap now CLOSED** for the explicit-`prune` case — was ADVERSARIAL.md's "MUST FIX #3"; 10/10 destructive-evolution tests pass. Default (`refuse`) still fails closed rather than silently orphaning. `docs/reference/reconciliation/destructive-evolution.md` |
| `GgenIgniter.Manifest` awareness in `GgenIgniter.Reconcile.run/1` | **UNSUPPORTED** (by design) | that pipeline has zero manifest/receipt involvement — a disclosed, bounded-scope gap, not an oversight; `docs/reference/reconciliation/manifest.md` |
| Concurrent-writer safety on `manifest.json` (two racing `sync` processes) | UNVERIFIABLE | no locking mechanism found, no test exercises it; `docs/reference/reconciliation/idempotency.md` |
| Cross-file stale-reference repair (e.g. a renamed attribute breaking a separately hand-generated LiveView) | **PLANNED / not implemented** | disclosed, deliberate limit — "no cross-file stale-reference repair anywhere in this codebase"; `docs/integrations/ash/resources.md`, `docs/testing/definition-of-done.md` |

## Reactor coordination (opt-in target pipeline)

| Capability | Status | Evidence |
|---|---|---|
| `GgenIgniter.Reactors.ReconcileReactor` (9-step Reactor pipeline) | PARTIAL_ALIVE (real, tested, **not the default**) | opt-in via `config :ggen_igniter, use_reactor: true` (default `false`); `docs/reference/reactor/overview.md` |
| `GgenIgniter.Reconcile.run/1` (plain function pipeline) | IMPLEMENTED, **is the default today** | bounded scope: no frontmatter, no `--for-each`, no `inject:`, no manifest, no receipt; `docs/architecture/component-boundaries.md` |
| Step-level concurrency (`observe_prior_manifest`/`load_ontology`/`resolve_pack`) | IMPLEMENTED (Reactor DSL default, not independently timed) | `docs/reference/reactor/concurrency.md` |
| Per-target concurrency inside `:actuate` (`Task.async_stream/3`) | IMPLEMENTED, test-proven (real overlap timing) | `docs/reference/reactor/concurrency.md` |
| Same-output-path collision refusal (never last-writer-wins) | IMPLEMENTED | `docs/reference/reactor/overview.md` |
| `compensate/4` (self-heal, no-op by design) | IMPLEMENTED | `docs/reference/reactor/compensation.md` |
| `undo/4` (real revert on a later step's failure) | IMPLEMENTED, test-proven | `docs/reference/reactor/compensation.md` |
| Four closed-set receipt standings (`:alive`/`:refused`/`:compensated`/`:build_broken`) | IMPLEMENTED | `docs/reference/evidence/standing.md` |
| Receipt-before-manifest evidence ordering | IMPLEMENTED, test-proven | `docs/reference/reactor/steps.md`, `docs/reference/evidence/recovery.md` |
| `:finalize_evidence` retry safety (no `max_retries 0` override) | **Known, disclosed gap** | a transient retry could theoretically double-append a receipt line; not exercised by any test; `docs/reference/reactor/failure-semantics.md` |
| Generic `:compensated` (non-`build_broken`) branch, `:actuate`'s own self-heal path, `:finalize_evidence`'s append-raises branch | UNVERIFIABLE by an executed test this pass | real, reachable code, not directly test-proven; `docs/reference/evidence/standing.md` |
| `ActuationOccurred => ReceiptExists` invariant | PARTIAL_ALIVE — real on the Reactor path only | the default pipeline writes no receipt on any outcome; `docs/reference/evidence/standing.md` |
| `GgenIgniter.Controller` (persistent GenServer) | PARTIAL_ALIVE, opt-in | `config :ggen_igniter, start_controller: true` (default `false`); `docs/operations/controller.md` |
| OCEL-shaped event log (`GgenIgniter.Telemetry.OcelEmitter`) | PARTIAL_ALIVE relative to full OCEL2.0 | real event/object shape for this pipeline's needs; no object-type registry, no e2o/o2o relation types; `docs/reference/evidence/ocel.md` |
| Real `:telemetry` event (`[:ggen_igniter, :reconcile, :ocel]`) | IMPLEMENTED | `docs/reference/evidence/telemetry.md` |

## ggen / Igniter integration

| Capability | Status | Evidence |
|---|---|---|
| Own Elixir ontology/query/render/write pipeline (no shell-out to real `ggen` binary) | IMPLEMENTED | `docs/integrations/ggen/semantic-compilation.md` |
| Embedded Rust oxigraph query engine (Rustler NIF over `ggen`'s `ggen-graph-wasm`) | IMPLEMENTED | `docs/integrations/ggen/semantic-compilation.md` |
| `GgenIgniter.Render.render/2` (Elixir stdlib `EEx`) & `GgenIgniter.Render.Tera` (auxiliary standalone Jinja2/Tera subset parser) | IMPLEMENTED | `GgenIgniter.Render.render/2` runs `EEx.eval_string/2` for sync rendering; `GgenIgniter.Render.Tera` (`lib/ggen_igniter/render/tera.ex`) provides standalone Jinja2/Tera parsing, with automated pipeline dispatch for `*.tmpl` planned for future integration. |
| `GgenIgniter.Frontmatter` (hand-maintained 1:1 mirror of Rust `ggen::Frontmatter`) | IMPLEMENTED | `docs/integrations/ggen/semantic-compilation.md` |
| `Igniter.Mix.Task` / `add_notice/2` usage | IMPLEMENTED | `docs/integrations/igniter/project-actuation.md` |
| Igniter AST-mutation (`Igniter.Project.Module`/`Igniter.Code`/`Sourceror.Zipper`) | **PLANNED, not implemented** | zero real code matches by grep; `docs/integrations/igniter/project-actuation.md`, `docs/integrations/igniter/ast-mutation.md` |
| Marker-based line-anchored injection (`inject_content!/5`) standing in for AST patch | IMPLEMENTED | `docs/integrations/igniter/ast-mutation.md` |

## Ash / Phoenix (optional, consumer-side)

| Capability | Status | Evidence |
|---|---|---|
| Ash as a core `ggen_igniter` dependency | **Not present — by design** | zero `:ash`/`:ash_phoenix` in `mix.exs` `deps/0`; `docs/integrations/ash/overview.md` |
| `ash-lifecycle-pack` fixture (Ash.Resource/Ash.Domain generation) | IMPLEMENTED (template mechanics) | `docs/integrations/ash/resources.md`, `docs/integrations/ash/domains.md` |
| Multi-domain fan-out (`domain.ex.eex`) | PARTIAL_ALIVE | correct by inspection; only exercised in the degenerate single-domain case, no 2+-domain fixture; `docs/integrations/ash/domains.md` |
| belongs_to/has_many relationship attribute selection | IMPLEMENTED (real bug found and fixed) | `docs/integrations/ash/resources.md` |
| Custom vs. default CRUD action rendering | IMPLEMENTED | `docs/integrations/ash/actions.md` |
| Orphan-file cleanup on resource rename/removal (independent of `--on-stale`) | **REFUTED / UNSUPPORTED** | no delete/orphan-detection actuation path exists at all outside `--on-stale prune`; `docs/integrations/ash/resources.md` |
| Full 8-stage Ash+Phoenix e2e lifecycle test (`mix e2e`) | UNVERIFIED (this pass) | mechanism real and sound by inspection (no mocking); full scaffold-through-LiveView run not re-executed (needs network + minutes); `docs/integrations/ash/overview.md`, `docs/testing/e2e-lifecycle.md` |
| `AshPhoenix.Form` round-trip (Stage 5) | UNVERIFIED (this pass) | real test file exists; not freshly re-run; `docs/integrations/phoenix/liveview.md` |
| `mix ash_phoenix.gen.live` + LiveView test (Stage 6) | UNVERIFIED (this pass) | same caveat — do **not** read this as "verified"; `docs/integrations/phoenix/liveview.md`'s own "Honest status" section states this explicitly |
| Ash domain compile-time registration (`config :OTP_APP, ash_domains: [...]`) | Consumer's own responsibility, not `ggen_igniter`'s | `docs/integrations/ash/domains.md` |

## Testing and verification

| Capability | Status | Evidence |
|---|---|---|
| Chicago-style, no-mock test discipline | IMPLEMENTED (verified fresh) | zero matches on `grep "Mock\|mock(\|patch(\|monkeypatch" test lib native`; `docs/testing/chicago.md` |
| Property-based tests (`StreamData`, 8 files) | IMPLEMENTED | `docs/contributing/testing.md` |
| `HumanRepairEdits = 0` | PARTIAL_ALIVE | holds for files `ggen_igniter` itself generates; not across a rename's ripple into hand-generated code (LiveViews); `docs/testing/definition-of-done.md` |
| `PartialInvalidStates = 0` | PARTIAL_ALIVE | achieved on the opt-in Reactor path only; no rollback on the default pipeline; `docs/testing/definition-of-done.md` |
| `SerialResult = ConcurrentResult` | PARTIAL_ALIVE | correctness + real overlap proven; no literal serial-vs-concurrent diff test; `docs/testing/definition-of-done.md` |
| `ObservedAshSemantics = ProjectedOntologySemantics` | PARTIAL_ALIVE | one real divergence caught and fixed; full e2e re-execution not performed this pass; `docs/testing/definition-of-done.md` |
| `mix test` (default suite) | PARTIAL — real, seed-dependent flakiness reported previously | 2 files affected per a prior, cited verification pass, unrelated to core reconciliation/reactor tests; a fresh run this documentation pass (`mix test`, seed 727847) produced 12 doctests, 21 properties, 257 tests, 0 failures — re-run with a different `--seed` if a failure appears; `docs/operations/debugging.md` |
| `mix format --check-formatted` | PARTIAL — 2 test files reported failing in a prior pass | not independently re-checked this pass; `docs/operations/debugging.md` |
| `mix dialyzer` | PARTIAL (cited from a prior pass, not independently re-run in this documentation pass) | previously reported clean, 0 warnings; `docs/operations/debugging.md` |
| `mix credo --strict` | PARTIAL (cited from a prior pass, not independently re-run in this documentation pass) | previously reported clean at error tier; `docs/operations/debugging.md` |
| `mix compile --warnings-as-errors` | CONFIRMED clean, this pass | real, fresh run this documentation pass: 0 errors (only pre-existing warnings from vendored dependencies, none from this project's own `lib/`) |
| Native oxigraph NIF string-literal binding shape | **Disputed between two specialist docs, unresolved** | `docs/operations/debugging.md`/`docs/operations/runtime.md` state a real quote-mangling bug (sourced from a cited report); `docs/tutorials/getting-started.md` independently tried to reproduce it against this repo's own real fixtures and could not (UNVERIFIABLE, not REFUTED). Treat as a real, disclosed trade-off whose exact scope is not fully pinned down — see `docs/reference/cli/engines.md`. |

## See also

- `docs/glossary.md` — term definitions
- `docs/index.md` — full documentation map
- `docs/architecture/adr/` — accepted architecture decisions with current-code evidence
- `.ggen_igniter_factory/docs-findings.jsonl` — the 93 underlying per-claim verifications this page synthesizes
