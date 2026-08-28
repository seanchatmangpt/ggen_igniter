export const meta = {
  name: 'ggen-igniter-v26-8-27-release-closure',
  description: 'Full release-closure swarm for ggen_igniter v26.8.27: builders, dogfood consumers, DX red-team, falsifiers, crown gate',
  phases: [
    { title: 'Wave1-Builders', detail: '14 orthogonal builder agents, disjoint file ownership, worktree-isolated' },
    { title: 'Wave2-Dogfood', detail: 'Fresh-consumer and lifecycle dogfood agents against merged state' },
    { title: 'Wave3-RedTeam', detail: 'DX/CLI/doctor/pack adversaries, read-mostly' },
    { title: 'Wave4-Falsifiers', detail: 'Architectural invariant falsifiers' },
    { title: 'Crown', detail: 'Integration gate + final release census + receipt synthesis' },
  ],
}

const REPO = '/Users/sac/ggen_igniter'
const PRE = `cd ${REPO} && pwd && git remote -v && git rev-parse --abbrev-ref HEAD (echo verbatim first). `

phase('Wave1-Builders')
const builders = await parallel([
  () => agent(PRE +
    `Own lib/ggen_igniter/lock.ex + test/ggen_igniter_lock_test.exs (new files, no conflict risk). ` +
    `Implement GgenIgniter.Lock: acquire/2(base_dir, opts:[operation, owner]) -> {:ok, lock}|{:error,:locked,meta}|{:error,:stale,meta}, ` +
    `release/1, force_unlock!/1. Lock file "<base_dir>/.ggen-igniter/locks/sync.lock", JSON: {repository, project_root, branch, pid, owner, ` +
    `operation, started_at, tool_version}. Stale = recorded pid not alive (real liveness check, e.g. System.cmd("kill",["-0",pid]) on unix). ` +
    `Atomic-ish acquire via tmp+rename to avoid two callers both winning. Real Chicago tests: real tmp dirs, real contention, real stale pid. ` +
    `No mocks. mix format the new files. Run mix test test/ggen_igniter_lock_test.exs and report real output.`,
    { label: 'lock', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Read lib/ggen_igniter/reactors/reconcile_reactor.ex fully. Add a new public function ` +
    `GgenIgniter.Reactors.ReconcileReactor.plan/1(opts) that runs observe_prior_manifest->load_ontology->resolve_pack->run_queries->render->admit ` +
    `and returns {:ok, %{pending: [PendingActuation.t()], engine: map(), queries: [map()], inputs: [map()]}} WITHOUT calling :actuate — purely ` +
    `additive, do not change run/1's existing behavior/tests. If the step functions are private, expose thin public wrappers rather than rewriting ` +
    `the reactor graph. Re-run test/ggen_igniter_reconcile_reactor_test.exs after and confirm zero regression; report real output and the diff.`,
    { label: 'reactor-plan-fn', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Read lib/ggen_igniter/receipt.ex fully. Extend GgenIgniter.Receipt additively (never break existing fields/functions/tests) with PRD v2 ` +
    `fields: schema_version("1"), tool_version(Mix.Project.config()[:version]), operation, inputs, queries, engine, outputs, skipped_outputs, ` +
    `commands, source_hash, plan_hash, pre_state_hash, result_hash, parent_hash, receipt_hash, started_at, completed_at. Preserve chain integrity ` +
    `(receipt_hash should cover the receipt's own content; parent_hash links to prior receipt in the same recipe_key chain, reusing the existing ` +
    `reconstruct_standing/2 chain-walk convention). Add to_prd_status/1 mapping standing -> ALIVE/PARTIAL_ALIVE/BLOCKED/BUILD_BROKEN/UNSUPPORTED/UNKNOWN ` +
    `(:alive->ALIVE, :build_broken->BUILD_BROKEN, :refused->BLOCKED, :compensated->PARTIAL_ALIVE, :compensation_failed->PARTIAL_ALIVE). ` +
    `Find and re-run the real existing receipt test file (grep for it) to confirm zero regression, then add real new tests for the v2 fields and ` +
    `to_prd_status/1. No mocks. Report diff and real test output.`,
    { label: 'receipt-v2', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Own priv/schema/receipt.schema.json + test/ggen_igniter_receipt_schema_test.exs (new files). Write a real JSON Schema (draft 2020-12) ` +
    `describing the GgenIgniter.Receipt v2 shape: schema_version, tool_version, operation, standing (enum of the 5 real standings + PRD 6-value ` +
    `mapping), inputs, queries, engine, outputs, skipped_outputs, commands, source_hash, plan_hash, pre_state_hash, result_hash, parent_hash, ` +
    `receipt_hash, started_at, completed_at as required/optional per what receipt.ex actually emits (read lib/ggen_igniter/receipt.ex first — do not ` +
    `invent fields that don't exist). Write a real test that validates fixture receipts (valid, missing-required, bad-standing-enum, bad-hash-format) ` +
    `against the schema using a real JSON-schema validator available in this project's deps (check mix.exs; if none exists, write a minimal ` +
    `structural validator in Elixir rather than adding a new heavy dependency, and say so). Report real test output.`,
    { label: 'receipt-schema', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Own priv/schema/plan.schema.json + test/ggen_igniter_plan_schema_test.exs (new files). Write a real JSON Schema for the PRD's plan output ` +
    `shape: inputs+hashes, query names+sources, engine selection, bindings discovered, output paths, existing-file decisions, skip conditions, ` +
    `unsupported features, intended mutations. Write a real fixture-based test (valid + invalid cases) using the same validation approach the ` +
    `receipt-schema agent used if it's landed, otherwise a minimal Elixir structural validator. Report real test output and the schema file.`,
    { label: 'plan-schema', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Read lib/ggen_igniter/actuate.ex fully. Determine real feasible atomic-write guarantees for write_file!/3 (whole-file writes only — inject ` +
    `and eval are out of scope for this agent). Implement: write to a temp file in the same directory (so rename stays same-filesystem), ` +
    `File.write! + explicit :file.sync if available via :file module, then File.rename!/2 to the final path, only for the :written outcome path ` +
    `(unchanged/skipped outcomes need no write). Preserve existing outcome semantics (:written/:unchanged/:skipped_exists/:skipped_match) and all ` +
    `existing callers (dry_run must still do zero I/O). Document in the moduledoc EXACTLY what guarantee is provided (same-filesystem atomic rename ` +
    `on POSIX; note Windows/NFS caveats honestly, do not overclaim universal atomicity). Add real tests: kill-mid-write is hard to simulate safely, ` +
    `so instead assert the temp file never appears at the final path in a partial state by checking write_file! either fully succeeds or raises ` +
    `before any rename, and that a pre-existing file is never observed truncated (read + assert full expected content in one File.read! after). ` +
    `Re-run existing actuate tests for zero regression. No mocks. Report diff and real output.`,
    { label: 'atomic-actuate', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Read lib/ggen_igniter/pending_actuation.ex, lib/ggen_igniter/frontmatter.ex, and lib/ggen_igniter/actuate.ex fully. The PRD/redteam notes ` +
    `state PendingActuation's :inject operation is declared but never constructed. Close this: add a real constructor (e.g. for_inject/8 mirroring ` +
    `for_file/7's shape but carrying marker/anchor/before-after-at_line info) and wire it so the Reactor's :render step can produce :inject-typed ` +
    `PendingActuation entries when frontmatter has inject:true, and the :actuate step calls GgenIgniter.Actuate.inject_content!/5 for those entries ` +
    `(reuse the existing match_spec_to_marker!/2-equivalent logic from sync.ex if it's the right conversion — read it first, don't reinvent). ` +
    `Cover idempotency (re-run doesn't duplicate), missing-anchor (raises, fail-closed), multiple-anchor-matches (raises), and add compensation ` +
    `support (revert_one_safe/2 must handle :inject entries by restoring prior full file content, which the reactor already tracks for other ops — ` +
    `verify it captures pre-content for inject targets too). Real tests only, no mocks. Report diff and real test output. If reconcile_reactor.ex ` +
    `is being edited by another agent concurrently, work in your own worktree and report clearly what you touched so it can be merged.`,
    { label: 'inject-closure', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Read lib/ggen_igniter/manifest.ex fully. Add a schema_version field to the persisted manifest.json (e.g. "1"), a corruption-detection check ` +
    `on load (invalid JSON, missing required keys -> a clear {:error, :corrupt_manifest, detail} rather than a crash), and explicit refusal of an ` +
    `unsupported future schema_version (e.g. "2" when this code only understands "1") rather than silently misreading it. Document a minimal ` +
    `migration strategy (e.g. absent schema_version field on an old manifest.json is treated as version "1" for backward compat per AR-9 — no ` +
    `silent reinterpretation). Add real tests: real manifest.json fixtures (valid current, valid legacy-no-version, corrupt-json, unknown-future-version) ` +
    `exercised via real File.write!+load/1 calls. No mocks. Re-run existing manifest tests for zero regression. Report diff and real output.`,
    { label: 'manifest-versioning', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Read lib/mix/tasks/ggen_igniter.doctor.ex fully as style template. Own new files lib/mix/tasks/ggen_igniter.plan.ex + ` +
    `test/ggen_igniter_plan_task_test.exs. Implement mix ggen_igniter.plan: flags --template, --pack, --pack-dir, --query name=path.rq (repeatable), ` +
    `--engine, --store-id, --json, --help, --version, --quiet, --verbose, --no-color. This task must call ` +
    `GgenIgniter.Reactors.ReconcileReactor.plan/1 (another agent is adding this function in parallel — if it isn't present when you compile-check, ` +
    `write against the documented signature {:ok, %{pending:, engine:, queries:, inputs:}} and clearly report the dependency). Print human-readable ` +
    `plan output (inputs+hashes, query names/sources, engine, bindings, output paths, existing-file decisions, skip conditions, unsupported features, ` +
    `intended mutations) or --json of the same shape. Read-only — never acquires the lock, never mutates disk. Exit 0 normal, 2 invalid invocation, ` +
    `3 unsupported capability. Add a real test asserting running plan twice on unchanged input produces byte-identical JSON output (determinism). ` +
    `No mocks. Report file contents and real test output (or clear compile-blocked-on-dependency status).`,
    { label: 'plan-task', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Own new files lib/mix/tasks/ggen_igniter.replay.ex + test/ggen_igniter_replay_task_test.exs. Read lib/ggen_igniter/receipt.ex and ` +
    `lib/ggen_igniter/manifest.ex fully first. Implement mix ggen_igniter.replay <receipt.json> [--verify-only] [--json]: load the receipt, extract ` +
    `recorded input hashes (template/query/pack/ontology/engine-version/config/output-state), recompute real current hashes of those same inputs ` +
    `(reuse Manifest.hash_content/1 and Receipt's own hash_files/1, do not re-derive hashing), report drift per category or "no drift detected". ` +
    `--verify-only skips any re-actuation. Exit 0 no-drift, 1 drift-found, 2 invalid invocation (bad/missing receipt file). Real Chicago test: write ` +
    `a real receipt via Receipt.append!/2 in a real tmp dir with real file content, assert real no-drift case, then mutate a real file and assert ` +
    `real drift-detected case with the correct category name. No mocks. Report file contents and real test output.`,
    { label: 'replay-task', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Read lib/mix/tasks/ggen_igniter.doctor.ex fully. Normalize exit codes/flags: 0=all pass, 1=diagnostic failures (keep existing halt(1)), ` +
    `2=invalid invocation/config (find any place bad args currently crash raw instead of a clean halt(2) and fix), 3=unsupported capability ` +
    `requested, 4=blocked by lock/environment (only if --fix genuinely needs exclusivity — read current --fix code to decide; if not applicable, ` +
    `document why 4 is unused for doctor rather than forcing it in). Confirm/add --help --version --quiet --verbose --no-color alongside the ` +
    `existing --json (verify --json still works after your change with a real test run). Do not change the 17 checks' semantics. Also generalize ` +
    `at least 3 of the most repetitive checks toward a %DoctorRule{id, check, fix, verify} data shape if doing so doesn't risk breaking the other ` +
    `14 — if risky, skip and clearly say why rather than destabilizing a working file. Find/run existing doctor tests (or note none exist) and ` +
    `report real output.`,
    { label: 'doctor-normalize', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Read lib/ggen_igniter/engine.ex and its three adapters (Sparql/Oxigraph/Qlever) fully. Build a real contract-matrix test suite at ` +
    `test/ggen_igniter_engine_parity_test.exs running the SAME set of queries (SELECT, ASK, CONSTRUCT if supported, empty-result, FILTER, ` +
    `FILTER NOT EXISTS, a typed-literal query, a unicode-literal query, a deliberately malformed query) against Sparql and Oxigraph engines for ` +
    `real (skip Qlever with a clear, named skip if no live endpoint is configured — do not fake it). Assert either matching normalized results or, ` +
    `where one engine has a real known limitation (e.g. sparql-hex's FILTER NOT EXISTS gap already documented), assert the documented divergent ` +
    `behavior explicitly rather than silently ignoring it. No mocks — real oxigraph NIF, real sparql-hex execution. Report real test output ` +
    `including any genuine divergences found, each classified as already-documented vs newly-discovered.`,
    { label: 'engine-parity', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Own lib/mix/tasks/ggen_igniter.sync.ex modification (this is the one file multiple things converge on — do it carefully and read everything ` +
    `first). Read the full current sync.ex, lib/ggen_igniter/reactors/reconcile_reactor.ex's run/1 (its real, already-existing signature and option ` +
    `handling — read the actual code, do not guess), and lib/ggen_igniter/reconcile.ex (Reconcile.run/1). Modify sync.ex so every invocation, ` +
    `regardless of the use_reactor config flag: (1) acquires GgenIgniter.Lock.acquire/2 before doing anything mutating (another agent is building ` +
    `lock.ex in parallel — write against acquire/2(base_dir, opts) -> {:ok, lock}|{:error, reason, meta} and release/1(lock), report clearly if ` +
    `lock.ex isn't present yet when you try to compile), (2) routes actuation through ReconcileReactor.run/1 instead of the plain inline ` +
    `Ontology->Query->Render->Actuate pipeline so every sync always writes a receipt, (3) wraps the whole plan+actuate sequence in try/after so the ` +
    `lock always releases even on error, (4) preserves existing CLI flags (--for-each, --dry-run, --on-stale, --manifest-dir) by mapping them onto ` +
    `whatever options ReconcileReactor.run/1 actually accepts today — for any flag with no real Reactor-pipeline equivalent yet (e.g. --for-each ` +
    `fan-out), keep the existing plain-pipeline behavior for THAT flag only and emit a one-time clear migration/limitation notice rather than ` +
    `silently reinterpreting it (never fake support). Re-run test/ggen_igniter_pending_actuation_test.exs and any other currently-passing ` +
    `sync-related tests; report real pass/fail output. This is the highest-integration-risk file in the whole swarm — be conservative and explicit ` +
    `about anything you could not verify compiling.`,
    { label: 'sync-convergence', phase: 'Wave1-Builders', isolation: 'worktree' }),
  () => agent(PRE +
    `Own docs only: docs/status.md, docs/reference/cli/plan.md (new), docs/reference/cli/replay.md (new), docs/reference/cli/lock.md (new), and a ` +
    `docs/architecture/adr/ entry documenting the sync-always-receipts convergence decision (follow existing ADR numbering/format — read one existing ` +
    `ADR first as a template). Read docs/status.md fully first. For each of: mix ggen_igniter.plan, mix ggen_igniter.replay, GgenIgniter.Lock, ` +
    `sync-always-receipts, inject: closure, atomic writes, manifest schema versioning, receipt schema v2 — write the REAL current status using this ` +
    `repo's existing IMPLEMENTED/PARTIAL_ALIVE/PLANNED/UNVERIFIABLE vocabulary. Since these are being built concurrently by other agents you cannot ` +
    `see, mark anything you cannot personally verify as UNVERIFIABLE-pending-integration rather than IMPLEMENTED — a later crown-gate pass will ` +
    `correct these once everything is merged and tested together. Do not overclaim. Report the diffs.`,
    { label: 'docs-sweep', phase: 'Wave1-Builders' }),
])

log(`Wave1-Builders complete: ${builders.filter(Boolean).length}/14 agents returned`)

phase('Wave3-RedTeam')
// Read-mostly adversarial agents can run concurrently with dogfood since they mostly probe CLI/docs/errors independently
const redteamP = parallel([
  () => agent(PRE +
    `Act as a first-time user with zero prior knowledge of this repo's internals. Read ONLY README.md and docs/ (not lib/ source) to try to ` +
    `understand how to run doctor/plan/sync/replay. Every point where you had to fall back to reading source code to understand basic usage is a ` +
    `DX defect — list each one with the exact doc gap. Then actually run "mix ggen_igniter.doctor" for real in this repo and report the real output, ` +
    `noting anything confusing or unclear about it as a real user would. Report a list of concrete DX defects, not vague impressions.`,
    { label: 'redteam-firsttime', phase: 'Wave3-RedTeam' }),
  () => agent(PRE +
    `CLI adversary. Try to run mix ggen_igniter.sync and mix ggen_igniter.doctor with malformed/missing/conflicting flag combinations (e.g. ` +
    `--engine bogus_engine, --query with no "=", --pack pointing nowhere, both --pack and --pack-dir given, --on-stale invalidvalue) for real and ` +
    `report each command's exact real output and exit code. Flag any raw Elixir exception/stacktrace leaking to the user instead of a clean error — ` +
    `that is a real defect per FR-9 (errors must state what/why/affected-file/correctable/next-command). List every real defect found with the exact ` +
    `command and output.`,
    { label: 'redteam-cli', phase: 'Wave3-RedTeam' }),
  () => agent(PRE +
    `Doctor adversary. Deliberately break the local environment in safe, reversible ways within a throwaway tmp copy of this repo (e.g. rename/hide ` +
    `the compiled NIF artifact, point PATH away from cargo temporarily in a subshell, use a broken --pack-dir) and run mix ggen_igniter.doctor for ` +
    `real against each broken state, reporting whether doctor correctly diagnoses each real failure with an actionable message vs. crashing or ` +
    `giving a misleading result. Do not leave the real repo in a broken state — work in a copy under /private/tmp. Report real command output for ` +
    `each scenario.`,
    { label: 'redteam-doctor', phase: 'Wave3-RedTeam' }),
  () => agent(PRE +
    `Error-message adversary. Read lib/ggen_igniter/actuate.ex, lib/ggen_igniter/frontmatter.ex, lib/ggen_igniter/pending_actuation.ex, and every ` +
    `raise/RuntimeError call site across lib/. For each distinct error message, check whether it states: what failed, why, the affected file/query/ ` +
    `output, whether it's user-correctable, and a next valid command (FR-9). List every error message that fails this bar, with its exact file:line ` +
    `and current text, and a proposed improved text.`,
    { label: 'redteam-errors', phase: 'Wave3-RedTeam' }),
  () => agent(PRE +
    `Repeated-use adversary. Run "mix ggen_igniter.doctor" three times in a row for real in this repo and diff the outputs — flag any nondeterministic ` +
    `noise (timestamps changing format, ordering flapping, spurious warnings appearing/disappearing) that isn't a genuine state change. Also run ` +
    `mix test twice in a row and report whether results are stable. Report real diffs, not assumptions.`,
    { label: 'redteam-repeated', phase: 'Wave3-RedTeam' }),
  () => agent(PRE +
    `Pack-author adversary. Read ONLY docs/ (priv/ggen/CLAUDE.md and any pack docs, not lib/ source) to try to build a minimal new pack from scratch ` +
    `following documented convention (priv/ggen/<pack-name>/{ontology.ttl,gates/*.rq,templates/*.eex}) in a throwaway tmp location, then try to ` +
    `invoke it via --pack for real. Report every point where the docs were insufficient to succeed without reading source, and whether the final ` +
    `real command worked.`,
    { label: 'redteam-pack', phase: 'Wave3-RedTeam' }),
])

phase('Wave2-Dogfood')
const dogfoodP = parallel([
  () => agent(PRE +
    `Dogfood: fresh throwaway Mix project (mix new, real subprocess, in /private/tmp), add ggen_igniter as a path: dependency to THIS repo, run ` +
    `mix deps.get for real, then run mix ggen_igniter.doctor and (if a suitable pack/template is available) mix ggen_igniter.sync against it for ` +
    `real. Report the real, complete command output including any failures. This validates the package genuinely works for a brand-new consumer ` +
    `with no sibling-repo assumptions.`,
    { label: 'dogfood-fresh-mix', phase: 'Wave2-Dogfood' }),
  () => agent(PRE +
    `Dogfood: real GgenIgniter.Manifest lifecycle test simulating destructive evolution — write a real manifest.json via Manifest.put/3+persist!/2 ` +
    `in a real tmp dir, then simulate add/rename/remove of tracked outputs across three sequential "runs" (real function calls, real files on disk), ` +
    `asserting Manifest.stale_paths/2 correctly identifies removed/renamed entries at each step and that a final --on-stale prune-equivalent call ` +
    `leaves zero orphaned tracked paths. Real assertions on real state, no mocks. Report real test output (write this as a real ExUnit test file ` +
    `at test/ggen_igniter_manifest_destructive_evolution_test.exs if one doesn't already exist covering this).`,
    { label: 'dogfood-destructive-evolution', phase: 'Wave2-Dogfood' }),
  () => agent(PRE +
    `Dogfood: real lock contention test. Write a real ExUnit test at test/ggen_igniter_lock_contention_test.exs that spawns two real concurrent ` +
    `Elixir processes (Task.async) both calling GgenIgniter.Lock.acquire/2 against the SAME base_dir at nearly the same time, asserting exactly one ` +
    `succeeds and the other gets {:error, :locked, _}. If GgenIgniter.Lock isn't present yet in this working tree (built by a parallel agent), write ` +
    `the test against its documented acquire/2 signature and report clearly that it's pending integration. No mocks — real processes, real file. ` +
    `Report real or pending-dependency status honestly.`,
    { label: 'dogfood-lock-contention', phase: 'Wave2-Dogfood' }),
  () => agent(PRE +
    `Dogfood: self-dogfood. Use this repo's OWN priv/ggen/ packs (list them first) to run a real mix ggen_igniter.sync (or .plan if available) ` +
    `invocation against one of them for real, inspecting whether the generated output is sane and whether a manifest/receipt is produced as ` +
    `expected. This is "ggen_igniter generating something inside ggen_igniter" — report the real command and its real output.`,
    { label: 'dogfood-self', phase: 'Wave2-Dogfood' }),
])

const [redteam, dogfood] = await Promise.all([redteamP, dogfoodP])
log(`Wave3-RedTeam complete: ${redteam.filter(Boolean).length}/6, Wave2-Dogfood complete: ${dogfood.filter(Boolean).length}/4`)

phase('Wave4-Falsifiers')
const falsifiers = await parallel([
  () => agent(PRE +
    `Falsifier: duplicate-coordinator detector. Grep and read every call site under lib/ that writes to disk (File.write!, File.rename!, ` +
    `Actuate.write_file!, Actuate.inject_content!, Actuate.eval_code!, Manifest.persist!). For each, trace whether it is reachable from BOTH the ` +
    `plain sync.ex pipeline AND the Reactor pipeline as two independent, un-unified code paths that could both claim to be "the" way sync happens. ` +
    `Report every real duplicate-coordinator instance found (file:line) or state DuplicateCoordinator=0 with the evidence (list of all call sites ` +
    `and which single pipeline owns each).`,
    { label: 'falsify-duplicate-coordinator', phase: 'Wave4-Falsifiers' }),
  () => agent(PRE +
    `Falsifier: unreceipted-actuation detector. For every disk-mutating call site found under lib/ (same grep as duplicate-coordinator detector — ` +
    `do your own independent pass), trace whether a GgenIgniter.Receipt.append!/2 call is guaranteed to happen on that path (success or failure). ` +
    `Report every real path where a real file mutation can occur with NO corresponding receipt write (file:line, and a concrete repro if possible), ` +
    `or state UnreceiptedActuation=0 with evidence.`,
    { label: 'falsify-unreceipted-actuation', phase: 'Wave4-Falsifiers' }),
  () => agent(PRE +
    `Falsifier: admission-bypass detector. Read lib/ggen_igniter/reactors/reconcile_reactor.ex's :admit step and lib/ggen_igniter/actuate.ex. Try to ` +
    `construct a real scenario (a real test, real function calls) where a file gets written WITHOUT first passing through the admission checks ` +
    `(duplicate output path, path-escapes-root, unowned-delete, stale-refuse). Report a real repro if one exists, or state ` +
    `AdmissionBypass=0 with the real test you wrote to try to prove otherwise and its real (failed-to-bypass) output.`,
    { label: 'falsify-admission-bypass', phase: 'Wave4-Falsifiers' }),
  () => agent(PRE +
    `Falsifier: compensation-incompleteness detector. Read lib/ggen_igniter/reactors/reconcile_reactor.ex's compensate/4, undo/4, and revert_all/1 ` +
    `fully. For each PendingActuation operation type (:create, :replace, :delete, :eval, and :inject if another agent has landed it), write a real ` +
    `test that forces a failure AFTER that operation type has actuated (e.g. make :verify fail) and assert the project's real file state is fully ` +
    `restored to pre-run content (real ProjectHash before == real ProjectHash after, computed via real sha256 of the relevant files). Report which ` +
    `operation types have real, test-proven compensation and which do not (name them explicitly) — do not claim compensation works for an operation ` +
    `type you didn't actually test.`,
    { label: 'falsify-compensation', phase: 'Wave4-Falsifiers' }),
  () => agent(PRE +
    `Falsifier: release-overclaim detector. Read README.md, docs/status.md, and CHANGELOG.md (if it exists) fully. For every claim of IMPLEMENTED ` +
    `or ALIVE status, try to find the actual executable evidence (a real passing test, a real command you can run right now) backing it. Report ` +
    `every claim you could NOT back with real evidence found in this working tree, each classified as: needs-a-real-test-added, actually-false-needs- ` +
    `correction, or verified-fine. Actually run at least 5 of the claimed capabilities for real (pick the ones that look riskiest) and report their ` +
    `real output.`,
    { label: 'falsify-overclaim', phase: 'Wave4-Falsifiers' }),
  () => agent(PRE +
    `Falsifier/census: mechanically grep across lib/, test/, docs/, README.md, CHANGELOG.md for: TODO, FIXME, XXX, HACK, UNVERIFIABLE, UNKNOWN, ` +
    `PARTIAL_ALIVE, "out of scope", "manual", "workaround", "delete manually", "use_reactor", "not implemented", "future work". For each hit, report ` +
    `file:line, the surrounding context, and classify it as: release-blocker, intentional-bounded-limitation (with the falsifiable boundary stated), ` +
    `stale-prose-should-be-removed, or false-positive. This is the final release census — be exhaustive and mechanical, not impressionistic.`,
    { label: 'falsify-census', phase: 'Wave4-Falsifiers' }),
])

log(`Wave4-Falsifiers complete: ${falsifiers.filter(Boolean).length}/6 agents returned`)

phase('Crown')
const crown = await agent(
  PRE +
  `You are the crown integration gate for the entire v26.8.27 release-closure swarm. Many agents worked in parallel, several in isolated git ` +
  `worktrees, on: lock.ex, reconcile_reactor.ex (plan/1 fn + inject closure), receipt.ex (v2 fields), receipt/plan JSON schemas, actuate.ex ` +
  `(atomic writes), manifest.ex (versioning), sync.ex (lock+reactor convergence), doctor.ex (exit codes), plan.ex/replay.ex (new tasks), engine ` +
  `parity tests, docs. Their changes may NOT all be merged into this exact working tree, and cross-file mismatches (wrong function name/arity ` +
  `assumed by one agent that another named differently) are likely, especially around lock.ex's real signature, ReconcileReactor.plan/1's real ` +
  `signature, and sync.ex's convergence onto both. Your job, in order: ` +
  `1) git status && git diff --stat — report exactly what exists in this working tree right now. ` +
  `2) mix format --check-formatted; run mix format to fix if needed. ` +
  `3) mix compile --warnings-as-errors — if it fails, read the REAL error output and fix forward (never delete another agent's work; reconcile ` +
  `naming/arity mismatches directly, e.g. align sync.ex's calls to lock.ex's actual acquire/release signature and to ReconcileReactor's actual ` +
  `plan/1 return shape). Iterate until it compiles or you hit a genuine architectural conflict you cannot resolve — if so, name it precisely. ` +
  `4) mix test — report real pass/fail counts and every real failure's output. Fix straightforward regressions forward; do not weaken assertions ` +
  `to make them pass. ` +
  `5) grep -rn "Mock\\|mock(\\|patch(\\|monkeypatch" test lib native — report real output, expect zero, name any real hit against the one-legitimate- ` +
  `use criteria. ` +
  `6) mix dialyzer if the PLT is already built (skip cleanly with a note if not, don't build a fresh PLT from scratch here). ` +
  `7) mix hex.build — inspect the real tarball contents for sanity (no missing priv/ files, no accidental inclusion of test/ or tmp artifacts). ` +
  `8) Re-read every file you personally edited to confirm changes actually landed on disk. ` +
  `Then write a consolidated v26.8.27 manufacturing receipt covering: version/HEAD, files changed, initial gaps vs closed gaps vs remaining ` +
  `limitations (cite the Wave4 falsifier findings and Wave3 redteam findings you were given — treat them as real input data, not your own guesses), ` +
  `standing per surface (doctor/plan/sync/replay/lock/reactor/atomicity/inject/manifest/receipt), and a final line: ` +
  `RELEASE_ALIVE or REFUSED:<exact remaining blocker>. Do not claim ALIVE for anything you did not personally verify compiling and testing in this ` +
  `exact working tree right now — that is the entire point of this gate.`,
  { label: 'crown-gate', phase: 'Crown', effort: 'high' }
)

return { builders, redteam, dogfood, falsifiers, crown }
