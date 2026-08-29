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
- **UNVERIFIABLE** — the code that would implement this capability has not
  landed in this working tree (the calling module compiles against it, but
  the target module/function genuinely does not exist on disk), so no run,
  passing or failing, can currently establish real status one way or the
  other. Distinct from PLANNED (no code references it yet) and from
  UNVERIFIED (the code exists; only a fresh run is missing).

## CLI and core pipeline

| Capability | Status | Evidence |
|---|---|---|
| `mix ggen_igniter.sync` (ontology → query → render → write) | IMPLEMENTED | `docs/reference/cli/sync.md`. Supersedes the prior BLOCKED entry: the `Reactor.Executor.ConcurrencyTracker` ETS-table error was root-caused (missing `:reactor` OTP-application start under bare `mix` CLI invocation) and fixed via `Application.ensure_all_started(:reactor)` in `lib/ggen_igniter/reactors/reconcile_reactor.ex` (see inline comment at the fix site). Re-verified fresh at HEAD `90c1da4`: `mix ggen_igniter.sync --pack-dir priv/ggen/adr-index-pack --out /tmp/status_verify/out.md --manifest-dir /tmp/status_verify --verify-cwd /Users/sac/ggen_igniter --engine oxigraph` exits 0 with `wrote /tmp/status_verify/out.md (engine: oxigraph, 1 query, 6 total row(s)) (via reactor)`. `mix test` at this same HEAD: 12 doctests, 21 properties, 376 tests, 0 failures. `mix compile --warnings-as-errors`: clean. See `docs/architecture/adr/0007-sync-always-attempts-receipts.md` for the design decision and its resolved "Known open issue" section. |
| `mix ggen_igniter.doctor` (17-check diagnostic) | IMPLEMENTED | `docs/reference/cli/doctor.md`; README previously under-documented this as 9 checks — corrected. Gained a real DX/exit-code layer this pass (`--help`/`--version`/`--json`/`--quiet` plus exit codes 2/3/4 for invalid-invocation/unsupported-capability/blocked-by-lock) — this part is self-contained (its own `fix_lock_available?/0` is a plain `File.exists?/1` check, no dependency on the missing `GgenIgniter.Lock` module) and verified compiling clean. |
| `mix ggen_igniter.plan` (new — read-only admission preview) | IMPLEMENTED | `docs/reference/cli/plan.md`. `GgenIgniter.Reactors.ReconcileReactor.plan/1` (`lib/ggen_igniter/reactors/reconcile_reactor.ex:776`). Real dogfood run at HEAD `90c1da4`: full `plan → sync → replay → doctor` loop against `priv/ggen/adr-index-pack` in a scratch `--manifest-dir`, all four commands real-invoked with real output. Known, disclosed boundary (unchanged): `plan/1` does not parse template frontmatter, so a frontmatter-bearing template cannot be previewed via `plan` today — `sync` handles it via the inline-pipeline fallback documented in ADR-0007. |
| `mix ggen_igniter.replay` (new — receipt drift diagnostic) | IMPLEMENTED | `docs/reference/cli/replay.md`. Real dogfood run at HEAD `90c1da4`: `mix ggen_igniter.replay <real receipt> --verify-only` against a receipt produced by a real `sync` run, confirmed real no-drift result. `test/ggen_igniter_replay_test.exs` exists and passes as part of the 376-test suite. |
| `GgenIgniter.Lock` (new — cross-process lock for `sync`) | IMPLEMENTED | `lib/ggen_igniter/lock.ex` (real code, referenced from `sync.ex`'s `igniter/1`, wrapping the full plan+actuate sequence in `try/after`). `test/ggen_igniter_lock_test.exs` and `test/ggen_igniter_lock_contention_test.exs` (real two-process `Task.async` contention test — one real winner, one real `{:error, :locked, _}`) both pass as part of the 376-test suite at HEAD `90c1da4`. Stale-lock recovery confirmed via real dogfood crash-recovery scenario (SIGKILL mid-sync, next invocation proceeds without manual intervention). Known, disclosed gap: `mix ggen_igniter.doctor` does not itself check for/report a stale `.sync.lock` file as a dedicated check — `Lock.acquire/2`'s own staleness detection handles recovery, but doctor has no proactive visibility into lock state. |
| `sync`-always-attempts-receipts (Reactor pipeline tried first, unconditionally, not gated by `config :ggen_igniter, use_reactor`) | IMPLEMENTED | `lib/mix/tasks/ggen_igniter.sync.ex`'s `igniter/1` calls `run_via_reactor/3` unconditionally, falling back to the inline pipeline only for `--for-each`, frontmatter with inline `sparql:` text, or frontmatter combined with `mode: eval` (each a disclosed, named boundary — not silent). The `Reactor.Executor.ConcurrencyTracker` ETS blocker documented in the prior pass is fixed (see the `sync` row above) — this row's real invocations now succeed end-to-end and produce a receipt on every path, confirmed by the 376-test suite and the real dogfood loop. See `docs/architecture/adr/0007-sync-always-attempts-receipts.md`, whose "Known open issue" section is now resolved. |
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
| `inject: true` closure (does the Reactor/`ReconcileReactor.run/1` path itself support `inject:`, vs. only `sync.ex`'s inline pipeline) | **IMPLEMENTED via `mix ggen_igniter.sync`, real and tested (AR-10 correction, 2026-08-27)** | Superseded finding: this row previously read PARTIAL_ALIVE, citing `sync.ex`'s `run_via_reactor/3` refusing delegation for ANY frontmatter-bearing template (including `inject: true`). Re-verified this pass: `ReconcileReactor`'s `:render`/`:admit`/`:actuate` steps already fully implemented `operation: :inject` construction/dispatch (`render_inject_target/8`, real and tested by `test/ggen_igniter_reconcile_reactor_inject_test.exs` calling `ReconcileReactor.run/1` directly) — the real gap was only `run_via_reactor/3`'s dispatch guard being broader than the pipeline's actual capability. Fixed by narrowing that guard to the ONE frontmatter feature `ReconcileReactor` genuinely does not resolve (inline `sparql:` query text), plus threading frontmatter `to:`/`unless_exists:`/`skip_if:` into `reconcile_opts` explicitly. An `inject: true` write via `mix ggen_igniter.sync` (no frontmatter `sparql:` block) now genuinely routes through the Reactor pipeline — real admission-gate coverage (duplicate-output-path refusal, path-escape refusal via `GgenIgniter.ArtifactIdentity.within_root?/2`) and a persisted `GgenIgniter.Receipt` — proven at the CLI level (real subprocess) by `test/ggen_igniter_sync_inject_reactor_admission_test.exs`, including a path-escape refusal directly compared side by side against an ordinary `mode: file` write refused the identical real way. **Remaining, disclosed boundary**: a template combining `inject: true` with frontmatter INLINE `sparql:` queries (no explicit `--query`) still falls back to the pre-Reactor inline pipeline — `ReconcileReactor.run_target_queries/3` only ever resolves explicit `--query`/pack-discovered `.rq` files, never a frontmatter `sparql:` block; this is the one remaining scope boundary, not a bug. **Separately, `mode: eval` frontmatter templates are deliberately kept off this widened path** (independent of `inject:`/`sparql:`): `ReconcileReactor`'s `:render` step has a real, pre-existing, unconditional crash for any `:eval` target (`PendingActuation.for_eval/3`'s `target` is always `nil`; `OcelEmitter.file_object/1` has no clause for `nil`) — see `test/ggen_igniter_reconcile_reactor_test.exs`'s `":eval compensation-completeness: REAL FINDING -- unreachable, not just untested"` test. `mix ggen_igniter.sync`'s AR-10 correction explicitly excludes `mode: eval` from its widened frontmatter-delegation gate so it cannot regress that pre-existing, separately-tracked defect. |
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
| Atomic manifest writes (`GgenIgniter.Manifest.persist!/2`) | IMPLEMENTED, confirmed this pass | `lib/ggen_igniter/manifest.ex:263-278`'s own doc comment: writes real JSON to a sibling temp file first, then `File.rename!/2`s it into place (atomic on the same POSIX filesystem) — read directly this pass; a crash mid-write cannot leave a half-written `manifest.json`. |
| Atomic receipt writes (`GgenIgniter.Receipt.append!/2`) | **Deliberately NOT atomic-rename — PARTIAL_ALIVE by design, confirmed this pass** | `lib/ggen_igniter/receipt.ex:278-282`'s own doc comment states this explicitly: append-only `File.write!/3, [:append]`, not atomic-rename, because a receipt is a history log, not a point-in-time snapshot — the two mechanisms are intentionally different (see ADR-0005's Manifest-vs-Receipt table). A real crash mid-append can leave a torn last line, disclosed as recoverable by discarding it, not as a bug. |
| Manifest schema versioning (`"version"` key) | **PARTIAL_ALIVE, confirmed this pass** | `lib/ggen_igniter/manifest.ex` writes/reads a `"version" => 1` key (lines 85, 142, 159, 259 — confirmed by direct reading this pass), but there is no migration function anywhere in this file (`grep -n "migrate\|schema_v" lib/ggen_igniter/manifest.ex` returns zero matches this pass) — the version key exists and is stamped, but nothing reads it to branch on an older shape; a real schema change would currently have no upgrade path. |
| Receipt schema v2 / `standing`-to-PRD-vocabulary mapping (`to_prd_status/1`) | **PLANNED, not implemented — re-confirmed this pass, unchanged from prior pass** | `grep -n "to_prd_status\|schema_v" lib/ggen_igniter/receipt.ex` returns zero matches this pass (re-run fresh, same result as the prior pass's finding below in "PRD six-value status vocabulary"). `GgenIgniter.Receipt` has no field or concept named "schema version" at all — only the five closed-set `standing` atoms (`:alive`/`:refused`/`:compensated`/`:build_broken`/`:compensation_failed`, lines 127/130) function as the receipt's one real versioned/closed vocabulary. |

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
| `Reactor.Middleware.Telemetry` wiring (`middlewares do middleware Reactor.Middleware.Telemetry end`) | IMPLEMENTED, test-proven | `lib/ggen_igniter/reactors/reconcile_reactor.ex`'s `middlewares` block, emitting real `:telemetry.execute/3` events under `[:reactor, :run, :start\|:stop]`, `[:reactor, :step, :run, :start\|:stop]`, `[:reactor, :step, :guard, :start\|:stop]`, `[:reactor, :step, :process, :start\|:stop]`, `[:reactor, :step, :compensate, :start\|:stop]`, and `[:reactor, :step, :undo, :start\|:stop]` — distinct from the OCEL `:telemetry` event above (this is Reactor's own built-in run/step timing instrumentation, not the OCEL-shaped domain event). Verified by `test/ggen_igniter_reconcile_reactor_telemetry_test.exs` (real `:telemetry.attach_many/4` handler receiving real events from a real `ReconcileReactor.run/1` execution against a real scratch Mix project) — `mix test test/ggen_igniter_reconcile_reactor_telemetry_test.exs`: 1 test, 0 failures. |

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
| Property-based tests (`StreamData`, 10 files) | IMPLEMENTED | `docs/contributing/testing.md`. Strengthened this pass (evidence-of-testing, not a new capability — `GgenIgniter.Manifest` and `GgenIgniter.PendingActuation` were already IMPLEMENTED): `test/ggen_igniter_manifest_properties_test.exs` (8 properties + 1 disclosed-limitation unit test over `recipe_key/2`/`hash_content/1`/`output_paths/1`/`stale_paths/2`/`same_outputs?/2`) and `test/ggen_igniter_pending_actuation_properties_test.exs` (7 properties over `logical_id/3`/`plan_unchanged?/1`/`for_file/7`, the latter against real temp files on disk). `mix test` of both, `--seed 0`: 15 properties, 2 tests, 0 failures. |
| `HumanRepairEdits = 0` | PARTIAL_ALIVE | holds for files `ggen_igniter` itself generates; not across a rename's ripple into hand-generated code (LiveViews); `docs/testing/definition-of-done.md` |
| `PartialInvalidStates = 0` | PARTIAL_ALIVE | achieved on the opt-in Reactor path only; no rollback on the default pipeline; `docs/testing/definition-of-done.md` |
| `SerialResult = ConcurrentResult` | PARTIAL_ALIVE | correctness + real overlap proven; no literal serial-vs-concurrent diff test; `docs/testing/definition-of-done.md` |
| `ObservedAshSemantics = ProjectedOntologySemantics` | PARTIAL_ALIVE | one real divergence caught and fixed; full e2e re-execution not performed this pass; `docs/testing/definition-of-done.md` |
| `mix test` (default suite) | **BLOCKED — real regression, verified this pass** | superseding the prior pass's "0 failures": a fresh run this documentation pass (`mix test`) produced 12 doctests, 21 properties, 297 tests, **72 failures** — the `GgenIgniter.Lock` regression above (`docs/operations/debugging.md` needs re-sync to this number). |
| `mix format --check-formatted` | PARTIAL — 2 test files reported failing in a prior pass | not independently re-checked this pass; `docs/operations/debugging.md` |
| `mix dialyzer` | PARTIAL (cited from a prior pass, not independently re-run in this documentation pass) | previously reported clean, 0 warnings; `docs/operations/debugging.md` |
| `mix credo --strict` | PARTIAL (cited from a prior pass, not independently re-run in this documentation pass) | previously reported clean at error tier; `docs/operations/debugging.md` |
| `mix compile --warnings-as-errors` | **BLOCKED — real regression, verified this pass** | supersedes the prior pass's "CONFIRMED clean": a fresh run this documentation pass produces exactly 3 real warnings from this project's own `lib/`, none vendored: `GgenIgniter.Lock.acquire/2`/`.release/1` undefined (`lib/mix/tasks/ggen_igniter.sync.ex:449,466`), `GgenIgniter.Reactors.ReconcileReactor.plan/1` undefined or private (`lib/mix/tasks/ggen_igniter.plan.ex:152`). Plain `mix compile` (no `--warnings-as-errors`) still succeeds with these same 3 warnings — modules load; only `sync`/`plan` crash at call time. |

## PRD six-value status vocabulary — mapping to this doc's vocabulary

`~/.claude/plans/prd-ard-wiggly-creek.md` (the plan this pass's new `plan`/
`replay`/`Lock` work was scoped from) specifies its own six-value standing
vocabulary — **ALIVE / PARTIAL_ALIVE / BLOCKED / BUILD_BROKEN / UNSUPPORTED /
UNKNOWN** — for `GgenIgniter.Receipt`, distinct from (though clearly related
to) both this doc's four-value vocabulary above and `GgenIgniter.Receipt`'s
own five real closed-set `standing` atoms (`:alive`/`:refused`/
`:compensated`/`:build_broken`/`:compensation_failed`, `lib/ggen_igniter/
receipt.ex` lines 127/130). The PRD itself (line 55) calls for a
`to_prd_status/1` mapping function on `GgenIgniter.Receipt` to translate the
existing `standing` enum into this six-value vocabulary.

**Status: PLANNED, not implemented** — confirmed this pass by reading the
real diff to `lib/ggen_igniter/receipt.ex` (`git diff`): it adds only a
moduledoc section on `files`' canonical-identity shape, no `to_prd_status/1`
function, no six-value type, no new field. `grep -n "to_prd_status"
lib/ggen_igniter/receipt.ex` returns zero matches. Do not read this doc's own
four-value vocabulary (IMPLEMENTED/PARTIAL_ALIVE/PLANNED/UNVERIFIABLE, used
throughout this page) as already being that PRD mapping — they are two
separate vocabularies for two different purposes (this page's own
documentation-status labels vs. `GgenIgniter.Receipt`'s planned
runtime-facing standing translation) that happen to share some words.
| Native oxigraph NIF string-literal binding shape | **Disputed between two specialist docs, unresolved** | `docs/operations/debugging.md`/`docs/operations/runtime.md` state a real quote-mangling bug (sourced from a cited report); `docs/tutorials/getting-started.md` independently tried to reproduce it against this repo's own real fixtures and could not (UNVERIFIABLE, not REFUTED). Treat as a real, disclosed trade-off whose exact scope is not fully pinned down — see `docs/reference/cli/engines.md`. |

## See also

- `docs/glossary.md` — term definitions
- `docs/index.md` — full documentation map
- `docs/architecture/adr/` — accepted architecture decisions with current-code evidence
- `.ggen_igniter_factory/docs-findings.jsonl` — the 93 underlying per-claim verifications this page synthesizes
