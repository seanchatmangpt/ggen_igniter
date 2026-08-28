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
| `mix ggen_igniter.sync` (ontology → query → render → write) | **BLOCKED — different real regression, re-verified this pass (2026-08-27, later same day)** | `docs/reference/cli/sync.md`. Supersedes this row's own prior entry: `GgenIgniter.Lock` now exists (`lib/ggen_igniter/lock.ex`, real code — see `docs/reference/cli/lock.md`) and `mix compile --warnings-as-errors` now succeeds with zero real warnings from this repo's `lib/` (confirmed by a fresh run this pass; only a pre-existing, unrelated `:preferred_cli_env` deprecation notice from `mix.exs` prints). But a fresh real invocation of the exact same repro command still fails, now with a **different** error: `** (ArgumentError) ... the table identifier does not refer to an existing ETS table`, raised from `Reactor.Executor.ConcurrencyTracker.allocate_pool/1` inside `GgenIgniter.Reactors.ReconcileReactor.run/1` (called from `sync.ex:530`'s `run_via_reactor/3`) — reproduced fresh this pass. `mix test`'s full-suite result was **not independently re-confirmed this pass**: this repo's working tree had multiple concurrent `mix test` invocations running from other agents at the same time (`ps aux` showed 4+ separate `mix test` processes against this same tree during this pass), so a fresh run started and stopped by this pass without a clean, attributable result — mark the full-suite number **UNVERIFIABLE-pending-integration** rather than repeat the stale 72-failure figure or claim a fresh clean number that was not actually observed. See `docs/architecture/adr/0007-sync-always-attempts-receipts.md` for the design decision this blocker sits downstream of. |
| `mix ggen_igniter.doctor` (17-check diagnostic) | IMPLEMENTED | `docs/reference/cli/doctor.md`; README previously under-documented this as 9 checks — corrected. Gained a real DX/exit-code layer this pass (`--help`/`--version`/`--json`/`--quiet` plus exit codes 2/3/4 for invalid-invocation/unsupported-capability/blocked-by-lock) — this part is self-contained (its own `fix_lock_available?/0` is a plain `File.exists?/1` check, no dependency on the missing `GgenIgniter.Lock` module) and verified compiling clean. |
| `mix ggen_igniter.plan` (new — read-only admission preview) | **UNVERIFIABLE-pending-integration — real code now present, not independently re-run this pass** | `docs/reference/cli/plan.md`. Supersedes the prior finding: `GgenIgniter.Reactors.ReconcileReactor.plan/1` now exists (`def plan(reconcile_opts) when is_list(reconcile_opts)`, `lib/ggen_igniter/reactors/reconcile_reactor.ex:776`, confirmed by a real grep this pass — the prior pass's "zero matches" is superseded). This pass did not re-run `mix ggen_igniter.plan` against a real fixture (time/priority went to re-confirming the `sync`/`Lock`/ETS chain instead — see above) and other agents are concurrently editing `reconcile_reactor.ex` in this same working tree, so a fresh invocation's real output could not be attributed with confidence to a stable state. Mark UNVERIFIABLE-pending-integration, not IMPLEMENTED, until a real `mix ggen_igniter.plan` invocation is re-run and its output inspected post-merge. |
| `mix ggen_igniter.replay` (new — receipt drift diagnostic) | IMPLEMENTED for the task's basic load/parse/exit-code contract, UNVERIFIED (this pass) for drift categories — status unchanged from prior pass | `docs/reference/cli/replay.md`. Not independently re-run this pass (no new evidence found or contradicting the prior pass's real invocation and its recorded exit-2 behavior); a real end-to-end run against a genuinely-produced receipt remains blocked on the same `sync`/`Reactor.Executor` chain documented above. `test/ggen_igniter_replay_test.exs` now exists in this working tree (new, untracked) — not executed independently this pass (see the `mix test` contention note above). |
| `GgenIgniter.Lock` (new — cross-process lock for `sync`) | **UNVERIFIABLE-pending-integration — module now exists, real code, not end-to-end proven** | Supersedes the prior "module does not exist" finding: `lib/ggen_igniter/lock.ex` (142 lines) is real, present, and referenced correctly from `sync.ex:449,466` — confirmed by direct reading and `mix compile --warnings-as-errors` succeeding with zero warnings from this module or its caller. `find test -iname "*lock*"` returns zero matches — no dedicated unit test exists for `acquire/2`/`release/1`/stale-lock recovery. A real `sync` invocation now gets past the point `GgenIgniter.Lock.acquire/2` would need to run, but fails downstream inside `Reactor.Executor.ConcurrencyTracker` before this pass could directly observe whether `acquire/2` succeeded and `release/1`'s `after`-block cleanup actually ran on that crash path. Full detail: `docs/reference/cli/lock.md`. |
| `sync`-always-attempts-receipts (Reactor pipeline tried first, unconditionally, not gated by `config :ggen_igniter, use_reactor`) | **Implemented as intended in code; still not runnable end-to-end for a new, different reason this pass** | `lib/mix/tasks/ggen_igniter.sync.ex`'s `igniter/1` still calls `run_via_reactor/3` unconditionally with the same `{:not_delegatable, reason}` fallback shape described in the prior pass (re-confirmed by `grep -n "run_via_reactor\|use_reactor\|migration_notice" lib/mix/tasks/ggen_igniter.sync.ex` this pass — no `use_reactor?/0` reintroduced). The `GgenIgniter.Lock` blocker from the prior pass is resolved (module exists — see above), but the same real invocation now dies one step further in, inside `Reactor.Executor.ConcurrencyTracker.allocate_pool/1` (a missing ETS table, likely a `:reactor` OTP-application supervision-tree start issue specific to bare `mix` CLI invocation) — see `docs/architecture/adr/0007-sync-always-attempts-receipts.md`'s "Known open issue" for the exact reproduced stack trace. Re-verify this row once that ETS issue is root-caused and fixed — this row's own code does not need further changes to become IMPLEMENTED, only for its downstream Reactor-execution environment to work. |
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
| `inject: true` closure (does the Reactor/`GgenIgniter.Reconcile.run/1` path itself support `inject:`, vs. only `sync.ex`'s inline pipeline) | **PARTIAL_ALIVE — real, confirmed this pass** | The root `CLAUDE.md`'s own "Two parallel pipelines" table already discloses this: `GgenIgniter.Reconcile.run/1` "does **not** yet implement frontmatter parsing or `--for-each`" — `inject: true` is a frontmatter field, so it falls inside that same disclosed gap. Confirmed by this pass's ADR-0007 finding: `sync.ex`'s `run_via_reactor/3` returns `{:not_delegatable, reason}` for any frontmatter-bearing template (including `inject: true` ones), falling back to the pre-Reactor `dispatch_pipeline/3` — the same inline path `inject_content!/5` was always wired into (line 852, see the `inject:` row above). So `inject: true` closure is real and IMPLEMENTED on the inline pipeline specifically, and genuinely absent (not a bug, a disclosed scope boundary) on the Reactor/receipt-producing path — meaning an `inject: true` run today produces no `GgenIgniter.Receipt`, same as any other frontmatter template. |
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
