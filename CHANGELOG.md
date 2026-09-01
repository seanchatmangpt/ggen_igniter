# Changelog

## v26.9.1

Process-mining/OCEL manufacturing-pack expansion release, layered on the
already-committed engine-registry and Reactor-pipeline hardening pass
(ADR-0008, the `mode:eval` `:render`-step crash fix). Seven new
ggen-marketplace packs ship for the first time, plus two disclosed
documentation/build fixes closed out in the same pass.

- **Seven new `priv/ggen/*` process-mining packs ship**, each ported from
  ex4pm's reference implementations into reusable, namespace-parameterized
  templates with real Chicago-school (no-mock) test coverage:
  - `incremental-discovery-pack` -- streaming DFG discovery
    (`update/2` O(1) amortized, `from_events/1` batch oracle, proven
    equivalent by construction). `test/ggen_igniter_incremental_dfg_test.exs`.
  - `sensor-sink-pack` -- threshold-crossing sensor-to-event discretization,
    Broadway-shaped, forwarding emitted events through a real supplied
    callback (`assert_received`, no mocking framework).
    `test/ggen_igniter_sensor_sink_test.exs`.
  - `process-discovery-pack` -- inductive-miner DFG cut discovery +
    token-replay conformance, two sub-templates, namespace-parameterized
    (default `Ex4pm.Engine`), including a real mine-then-replay
    integration round-trip and a `mix ggen_igniter.doctor` subprocess
    check. `test/process_discovery_pack_test.exs`.
  - `ocel2-ekg-pack` -- OCEL 2.0/EKG-style IR derivation (object trace,
    attribute-change history, O2O relationships), fully
    namespace-parameterized, ships a worked `ekg:example_ir` individual.
    `test/ggen_igniter_sync_ocel2_ekg_pack_test.exs`.
  - `olap-pack` -- slice/dice/roll_up/drill_down over OCEL-shaped IR;
    only `moduleName`/`logModule`/`eventModule` are ontology knobs, the
    algebra itself is fixed in the template. Verified via a real
    `Code.string_to_quoted!/1` parse of generated output.
    `test/ggen_igniter_olap_pack_test.exs`.
  - `chicago-fault-injection-pack` -- real BEAM network-partition +
    process-kill Chicago fault-injection test-suite generator, ships a
    worked `beam4pm_fault_injection_suite` individual, re-parameterization
    proven with a second render against different bindings.
    `test/ggen_igniter_chicago_fault_injection_pack_test.exs`.
  - `beam4pm-bench-pack` -- distributed-topology + virtual-cost +
    Wasmtime benchmark modules; `virtual_cost`/`topology` are real and
    tested, `wasm_bench` requires a consumer-supplied `adapter` binding
    that fails fast (nonzero exit, no output file) when omitted --
    `test/ggen_igniter_sync_beam4pm_bench_pack_test.exs` plus
    `test/fixtures/beam4pm-bench-pack-wasm-adapter/` prove the
    load-bearing-binding contract; no real downstream consumer has wired
    the adapter yet, disclosed as a release-surface caveat rather than a
    defect in this pack.

  All seven render through the existing pipeline
  (`Ontology.load!/1` -> `Query.run/2` -> `Frontmatter.split_template/1`
  -> `Render.render/2`) with no pipeline changes required, and
  `olap-pack`/`ocel2-ekg-pack`/`beam4pm-bench-pack` are proven to work via
  `--engine sparql` real subprocess invocation with no dependency on the
  oxigraph NIF for their CI-viable path.

- **ADR-0001 oxigraph row-shape dispute resolved** -- the previously
  unreconciled disagreement between the ADR text and `docs/status.md`'s
  independently-probed real behavior (raw N-Triples-style term strings vs.
  bare Elixir values returned by the oxigraph NIF) is closed; ADR text and
  `docs/status.md` now agree on the real, observed row shape, removing the
  correctness-adjacent documentation contradiction flagged as a release
  blocker.

- **ADR-0007 ETS crash resolved and closed** -- the `Reactor.Executor.
  ConcurrencyTracker.allocate_pool/1` "table identifier does not refer to
  an existing ETS table" crash on `mix ggen_igniter.sync`'s unconditional
  Reactor-path attempt is fixed; the ADR's "Known open issue" section is
  updated to reflect resolution and the ADR is flipped to Accepted/closed.

- **`mix dialyzer` `guard_fail` fix in `lib/mix/tasks/ggen_igniter.sync.ex`**
  -- a guard clause dialyzer could prove would never succeed against the
  narrowed type it now infers for the value in question is corrected so
  the PLT run is clean again.

- **Two `mix credo --strict` warnings fixed** -- both flagged findings in
  the sync/install task modules addressed directly, no behavior change.

## v26.9.2

Two-workstream integration pass (isolated in a `git worktree`, independently
re-verified before merge -- not trusted on the workstream's own say-so,
including re-running its own headline regression test and separately
hand-reproducing both correctness claims against real files/manifest
content before merging).

- **Template frontmatter inline `sparql:` query text now resolves through
  `GgenIgniter.Reactors.ReconcileReactor.run/1`** -- `resolve_named_queries!/1`
  widened to `/2`, delegating directly to
  `Mix.Tasks.GgenIgniter.Sync.resolve_named_queries!/2` (reused verbatim, not
  re-derived) so a target's own frontmatter `sparql:` block is consulted the
  same real merge-by-priority way `sync.ex`'s inline pipeline already does.
  `run_via_reactor/3`'s `{:not_delegatable, "template frontmatter's inline
  \"sparql:\" ..."}` guard is removed. `mode: eval` combined with frontmatter
  stays excluded from Reactor delegation, unchanged and independent of this
  fix -- a real, pre-existing `ReconcileReactor` `:render`-step crash on
  `:eval` targets (see `docs/status.md`'s existing "`inject: true` closure"
  row), out of this pass's scope to fix.
- **`--for-each NAME` fan-out now also routes through
  `GgenIgniter.Reactors.ReconcileReactor.run/1`** -- new
  `Mix.Tasks.GgenIgniter.Sync.run_for_each_via_reactor!/7` runs the driver
  query via the exact same call path `run_pipeline!/3` already uses
  (`Engine.fetch!/1` -> `Ontology.load!/1` -> `resolve_named_queries!/2` ->
  `run_queries/4` -> `fetch_driver_rows!/2`) and expands each row into a
  `[for_each_row: row]` per-target override consumed by `ReconcileReactor`'s
  existing `:targets` mechanism -- no second, parallel fan-out path added.
  `run_via_reactor/3`'s `{:not_delegatable, "--for-each ..."}` guard is
  removed.
- **Real correctness fix, found and closed in the same pass**: stale-prune
  detection for a `--for-each` recipe routed through the reactor is now
  computed ONCE per `(template, out_template)` recipe, against the UNION of
  every row's own canonical output path (new `compute_stale_deletes/2`),
  instead of the prior per-target diff in `render_file_target/7`, which
  independently compared each row's own single output path against the
  recipe's FULL prior manifest entry -- wrongly flagging every OTHER row's
  own still-produced sibling path as stale on that row's own diff. The
  matching manifest-write bug is fixed alongside it: `commit_recipe_group/5`
  now unions every row's real output into ONE manifest entry per
  `recipe_key` before a single `Manifest.put/3` call, instead of each row's
  own `commit_recipe/5` call independently overwriting the same key.
  Independently re-verified this pass with a real, by-hand repro (not just
  the new automated regression test): ran a real 3-row `--for-each` sync,
  read the real `manifest.json` (all 3 paths present under one recipe
  entry), then re-ran with a real 2-row ontology and `--on-stale prune` --
  only the genuinely-removed row's file was pruned, the other two rows
  reported `unchanged` and were left byte-identical on disk, and the
  resulting `manifest.json` correctly lists only the two surviving paths.
  New `test/ggen_igniter_sync_for_each_reactor_test.exs` proves the same
  fact through the actual CLI path (real subprocess, real files, no mocks).
- **DISCLOSED, INTENTIONAL BEHAVIOR CHANGE**: because every row of a
  `--for-each` recipe now runs inside ONE `ReconcileReactor.run/1`
  invocation, `:actuate` is all-or-nothing -- a genuine mid-run failure on
  one row (independently re-verified with a real invalid-Elixir-identifier
  row that fails a real `mix compile --warnings-as-errors`) now triggers
  Reactor's real `undo/3`, reverting EVERY row's writes in that run, not
  just the failing row's. Before this pass, `--for-each` always ran via the
  inline `run_pipeline!/3` pipeline, which allowed genuine per-row partial
  success (a failed row did not abort or revert its siblings) and had no
  compensation machinery at all for this path. A second, related, disclosed
  strictness increase: every `--for-each` row now passes through
  `ReconcileReactor`'s own `:admit` gate, including its real
  duplicate-canonical-output-path refusal and its real
  authorized-project-root escape refusal
  (`GgenIgniter.ArtifactIdentity.within_root?/2`) -- both previously
  silently permitted under the inline pipeline's sequential, uncoordinated
  writes. This is the same disclosure discipline this file's own
  `sh_before:`/`sh_after:` entry (v26.9.1, above) and
  `docs/architecture/adr/0006-marker-based-injection-not-ast-patch.md` both
  already use for a deliberate scope trade-off: named as a real, intentional
  behavior change with its own regression test, not silently absorbed.
  `test/ggen_igniter_sync_sh_hooks_test.exs`'s two failure-mode tests now
  assert the OPPOSITE outcome from before this pass for exactly this
  reason: a failing `sh_before:`/`sh_after:` (a frontmatter-only field, with
  no CLI equivalent, so it can no longer reach the inline pipeline at all
  once `--for-each` and inline `sparql:` both route through the reactor)
  now fails the whole run via real compensation instead of the inline
  pipeline's old per-row outcome.
- **UX parity ported into the reactor pipeline** so routing `--for-each`/
  inline `sparql:` through it does not regress `sync.ex`'s existing
  notice-text features: `--on-stale prune`/`preserve` real notice text
  (`finalize_evidence/1`'s `prune_lines`/`preserve_warning` receipt
  metadata) and the `outcome_summary_suffix` "`-- summary: wrote N, skipped
  M`" convention (new `reactor_summary_suffix/1`), both mirroring `sync.ex`'s
  own exact conventions.
- **Second real correctness fix, found independently during this pass's own
  post-merge verification** (not part of the original workstream report,
  which never reproduced it — its own isolated `git worktree` had no
  pre-existing manifest state to expose it): `compute_stale_deletes/2`'s
  diff against a recipe's PRIOR manifest entry compared raw path strings,
  not real path identity. `Mix.Tasks.GgenIgniter.Sync.run_pipeline!/3`'s own
  inline pipeline has always recorded a manifest entry's `outputs` keys as
  the RAW, uncanonicalized rendered path (self-consistent as long as a
  recipe stays on the inline pipeline forever); the Reactor pipeline records
  and compares `ArtifactIdentity.canonicalize/2`'s canonical form instead.
  Before this pass, no frontmatter-bearing/`--for-each` recipe could ever
  reach the Reactor at all, so this raw-vs-canonical mismatch was completely
  dormant. Once workstream A/B widened Reactor routing, ANY recipe with a
  pre-existing inline-pipeline manifest entry hit this mismatch on its first
  post-upgrade run and was wrongly refused as "stale" even though it was
  about to write the identical real file again — caught by a genuine `mix
  test` failure on `main`'s own real, already-accumulated
  `.ggen_igniter/manifest.json` (a local, gitignored dev artifact, not
  committed state) in `test/ggen_igniter_sync_frontmatter_test.exs`, not by
  the new automated suite. Fixed the same way this codebase's own
  duplicate-path/case-fold guards already treat this exact class of problem
  (`ArtifactIdentity.canonicalize/2`, never a raw string compare):
  `compute_stale_deletes/2` now canonicalizes every one of a recipe's prior
  manifest output-path keys against `base_dir` before diffing against this
  run's own (already-canonical) paths.
- **`--replay` file-path-dependency risk, investigated and confirmed a
  non-issue** (not just asserted): read `lib/mix/tasks/ggen_igniter.replay.ex`
  and `lib/ggen_igniter/receipt.ex` in full this pass. `replay`'s
  ontology-drift/template-drift detection keys entirely off `recipe_key`
  (`template_path=>out_template`), `metadata["graph_hash"]`, and the
  template's own current hash -- the word "query" appears nowhere in
  `receipt.ex`, and `replay` never reads query text or a query path. This
  pass's inline-`sparql:` routing change has no effect on `--replay`'s real
  dependency surface; confirmed by direct read, no fix needed.
- **Test migration, wider than originally scoped**: 12 existing test files
  needed `--manifest-dir`/`--verify-cwd` added now that they genuinely reach
  `ReconcileReactor`'s real `:admit`/`:verify` steps. Several of these
  (`ggen_igniter_sync_inject_test.exs`, the inject case in
  `ggen_igniter_sync_inprocess_dispatch_test.exs`,
  `ggen_igniter_sync_sh_hooks_test.exs`) are a real, confirmed finding: their
  own fixture templates carry an inline `sparql:` frontmatter block, so
  before this pass's inline-`sparql:` fix they were silently exercising the
  inline `run_pipeline!/3` pipeline the whole time, never the reactor path
  their own names/moduledocs claimed to test.
  `ggen_igniter_sync_inprocess_reconcile_test.exs`'s stale-refusal test now
  expects `RuntimeError` instead of `ArgumentError`, since
  `dispatch_reactor_reconcile/2` wraps every reactor reconciliation failure
  in a plain `raise`.
- **Version**: `mix.exs` bumped `26.9.1` -> `26.9.2` (`version:`/`source_ref:`
  kept in sync per this file's own versioning convention -- see
  `test/ws5_contracts/16_version_contract_test.exs` and
  `test/ggen_igniter_doctor_task_test.exs`'s `check_version_policy` tests).
- **Verification (this release)**: `mix format --check-formatted` -- clean.
  `mix compile --warnings-as-errors` -- clean (only the pre-existing,
  unrelated `:preferred_cli_env` deprecation warning). Full `mix test`, run
  four times total across this integration pass -- honestly reported, not
  just the clean ones: once in the isolated `git worktree` before merge (0
  failures); once on `main` immediately after merge (1 failure -- the
  second real correctness fix above, caught here for the first time); once
  more on `main` after that fix (1 unrelated failure, a self-inflicted
  transient: `test/ws5_contracts/16_version_contract_test.exs` was mid-edit
  when that run started, so it briefly asserted the OLD `26.9.1` literal
  against the already-bumped `mix.exs`); and a final, true "everything
  settled" run: **15 doctests, 42 properties, 495 tests, 0 failures** (up
  from 493 in v26.9.1 -- the 2 new tests are
  `test/ggen_igniter_sync_for_each_reactor_test.exs`'s own real-subprocess
  regression proofs). No flaky failure observed in
  `test/ggen_igniter_lock_staleness_properties_test.exs` (the real
  subprocess/wall-clock timing property v26.8.30/v26.9.1 both already
  disclosed as occasionally flaky under full-suite concurrent load) in any
  of the four runs this pass. `grep -rn "Mock\|mock(\|patch(\|monkeypatch"
  test lib native` -- zero real matches. HEAD at merge: `8eb27cc`.

## v26.9.1

Seven-workstream integration pass (one isolated in a `git worktree`, six run
directly against `main`'s working tree), independently re-verified before
merge/commit -- not trusted on any workstream's own say-so.

- **`sh_before:`/`sh_after:` frontmatter shell hooks, gated by `--allow-sh`**
  -- new `GgenIgniter.ShellHook.run/3` (`lib/ggen_igniter/shell_hook.ex`)
  executes a template's `sh_before:`/`sh_after:` frontmatter field for real
  via `System.cmd("sh", ["-c", cmd], cd:, stderr_to_stdout: true)`, wrapped
  in a real `Task.async/1` + `Task.yield/2`/`Task.shutdown/2` timeout
  (default 60s). Wired into both `sync.ex`'s inline pipeline
  (`actuate_row!/11`) and `ReconcileReactor`'s `actuate_one/2`. `--allow-sh`
  (default `false`) is required whenever any resolved template declares
  either field -- absent it, the WHOLE run refuses before any actuation,
  checked in both pipelines' every real call path
  (`check_allow_sh!/3`/`check_allow_sh!/2`). Failure semantics deliberately
  differ by pipeline (disclosed in both moduledocs): the inline pipeline
  gets new `:sh_before_failed`/`:sh_after_failed` per-row outcomes that do
  not abort the run; the Reactor pipeline treats a hook failure as an
  ordinary actuation failure, flowing through its existing self-heal/
  `undo/4` machinery. `GgenIgniter.Receipt.commands` is populated by a real
  call site for the first time. **DISCLOSED, INTENTIONAL LIMITATION**
  (matching this changelog's own "`:run_queries` concurrency: investigated,
  NOT changed" disclosure style from v26.8.30): a `sh_before:`/`sh_after:`
  command's real side effects are NOT integrated into
  `GgenIgniter.PendingActuation`'s `operation()` type, NOT inspected by
  `:admit`'s guards (duplicate-path/path-escape/unowned-delete refusal), and
  NOT tracked by `undo/4`'s compensation/revert machinery -- a template
  author declaring `sh_before:`/`sh_after:` is trusted the same way this
  repo already trusts a frontmatter `to:` path; `--allow-sh` is the one new,
  deliberately small admission-adjacent mitigation, not a full admission-gate
  integration. Independently re-verified this integration pass with three
  real manual `mix ggen_igniter.sync` invocations (not just the new test
  suite): without `--allow-sh` a template with `sh_after:` set refuses
  before any file is written; with `--allow-sh` the real `touch` command
  genuinely ran and `GgenIgniter.Receipt.commands` was populated on disk
  with a real `status: "ok"` entry; with `--allow-sh --dry-run` the real
  command never ran at all. Two real bugs found and fixed along the way: an
  `inject: true` target's real outcome was previously discarded (hardcoded
  `nil`), making `sh_after:` un-triggerable for it; and a failing
  `sh_after:` after a successful Reactor-pipeline write bypassed the
  self-heal revert list entirely, leaving a real file un-reverted despite
  the run reporting `:compensated` -- both fixed, both covered by new
  regression tests. `docs/reference/cli/sync.md`'s "`sh_before:`/`sh_after:`
  shell hooks" section; `docs/glossary.md`'s "shell hook" term.
- **`GgenIgniter.ArtifactIdentity.canonicalize/2` case-fold fix** -- a real,
  confirmed defect in `walk_real_path/3`: on a case-insensitive/
  case-preserving filesystem (macOS default APFS/HFS+), an existing,
  non-symlink path segment's raw caller-supplied spelling was preserved
  verbatim rather than resolved to its real on-disk directory-entry casing,
  so two differently-cased spellings of the SAME real file could
  canonicalize to two DIFFERENT strings -- defeating `:admit`'s
  duplicate-canonical-target dedup guard. Fixed via new
  `real_case_segment/2` (a real `File.ls/1`-backed case-insensitive lookup,
  falling back to the raw spelling verbatim when unlistable or no match
  exists). On a genuinely case-sensitive filesystem this is a structural
  no-op. Independently re-verified this pass, not just trusted from the new
  property test: confirmed this machine's filesystem is genuinely
  case-insensitive via a real probe, then ran `canonicalize/2` directly
  against two real case-variant spellings of the same file -- both returned
  the byte-identical canonical string.
- **`inject_content!/5`'s `:before` negative-index fix** -- `already_present_at?/4`'s
  `:before` clause could compute a negative `Enum.slice/2` start
  (`insert_at - length(body_lines)`) whenever an anchor sits near the top of
  the file and the injected body is longer than the anchor's own line
  offset; `Enum.slice/2` counts a negative start from the END of the list
  rather than clamping to 0, silently slicing the wrong lines. Fixed to
  return `false` (not-yet-injected) directly whenever the computed start is
  negative, never reaching `Enum.slice/2` with it. New regression test in
  `test/actuate_inject_test.exs` proves correct `:injected`-then-`:unchanged`
  behavior for exactly this anchor-near-top-of-file scenario.
- **`mix ggen_igniter.doctor`'s `check_qlever_reachable/2` dialyzer fix** --
  a `case ... do rows when is_list(rows) -> ... end` wrapping a call whose
  stub implementation (`:gno` not loaded) has a `no_return()` spec made
  Elixir's compiler infer the case subject as `none()`, flagging the single
  clause "will never match." Fixed by removing the pointless `case`/binding
  entirely -- the existing `rescue` clause a few lines below already
  handles both the stub's raise and any real network/query failure.
- **`lib/mix/tasks/CLAUDE.md`**: new "Known `Igniter.Mix.Task` base-class
  quirks" section documenting the `--help`/`-h` split (`help_requested?/1`
  matches only the literal `"--help"`, never `-h`) and the `--json`
  success-path `System.halt(0)` requirement (an Igniter-runner footer would
  otherwise corrupt a single-JSON-document contract), both already fixed in
  commits `6c2f109`/`b184d907` -- this section exists so a future change
  doesn't silently reintroduce either one. New parametrized regression
  coverage in `test/ggen_igniter_cli_tasks_quirks_test.exs` (real
  subprocesses only) across every real CLI task.
- **New test coverage on two previously-untested pure-data modules** (not a
  status change): `test/ggen_igniter_write_outcome_test.exs` (10 tests over
  `GgenIgniter.WriteOutcome`'s `FM-WRITE-NNN` formatting) and
  `test/ggen_igniter_project_config_test.exs` (22 tests over
  `GgenIgniter.ProjectConfig` and its nested submodules' real struct
  construction, `@enforce_keys` enforcement, and defaults). No bug found in
  either module; one intentional, documented behavior captured as an
  explicit test case: `GgenIgniter.ProjectConfig` itself declares no
  `@enforce_keys`, unlike every one of its nested submodules, so `%ProjectConfig{}`
  silently succeeds with `nil` fields rather than raising.
- **`docs/status.md` staleness fix**: two rows (`mix test`, `mix compile
  --warnings-as-errors`) previously read BLOCKED, citing `GgenIgniter.Lock.acquire/2`/
  `.release/1` and `GgenIgniter.Reactors.ReconcileReactor.plan/1` as
  undefined/private. Both are real, public, currently-defined functions --
  the BLOCKED finding was itself stale. Corrected to IMPLEMENTED with a
  fresh re-verification citation.
- **Version**: `mix.exs` bumped `26.8.30` -> `26.9.1` (`version:`/`source_ref:`
  kept in sync per this file's own versioning convention -- see
  `test/ws5_contracts/16_version_contract_test.exs` and
  `test/ggen_igniter_doctor_task_test.exs`'s `check_version_policy` tests,
  both of which read `mix.exs`/`CHANGELOG.md` fresh off disk rather than
  hardcoding an expected version).
- **Verification (this release)**: `mix format --check-formatted` -- clean
  (2 new test files needed one `mix format` pass, applied). `mix compile
  --warnings-as-errors` -- clean (only the pre-existing, unrelated
  `:preferred_cli_env` deprecation warning). Full `mix test`, run three
  times: **15 doctests, 42 properties, 493 tests** -- two runs showed 1
  failure under full-suite concurrent load in
  `test/ggen_igniter_lock_staleness_properties_test.exs` (the same real
  subprocess/wall-clock timing property v26.8.30 already disclosed as
  flaky under load), a third full run and three isolated re-runs of that
  same file were all clean (0 failures) -- not a regression introduced by
  this release. `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib
  native` -- zero real matches (the same two pre-existing prose mentions of
  the banned-word list itself, untouched). Three real manual end-to-end
  `mix ggen_igniter.sync` invocations independently re-confirmed the
  `sh_before:`/`sh_after:` refuse/execute/dry-run contract (see above). The
  `ArtifactIdentity` case-fold fix was independently re-verified against
  this machine's real filesystem (confirmed case-insensitive), not just the
  new property test.

## v26.8.30

Seven-workstream integration pass (two isolated in `git worktree`s, five run
directly against `main`'s working tree), independently re-verified before
merge/commit -- not trusted on any workstream's own say-so.

- **`GgenIgniter.DoctorFixes` `--fix` transforms migrated from regex/text splices to
  structural `Sourceror.Zipper` rewrites** -- all 4 named targets (dep `:only`
  relaxation, `ash_domains:` registration, `package/0` description/licenses
  insertion, `version:` literal rewrite) now use Igniter's own pure-zipper codemod
  primitives (`Igniter.Code.Module`/`Function`/`List`/`Tuple`/`Keyword`,
  `Igniter.Project.Config.modify_config_code/4`) over a
  `Sourceror.parse_string!/1`-built `Sourceror.Zipper.t()` -- no `%Igniter{}`/
  `Rewrite` project needed. Fixes a latent bug: the old whole-file `version:`
  regex could rewrite a look-alike `version: "..."` string in a comment instead of
  the real `project/0` key; the structural rewrite is scoped to the real AST node
  and a regression test proves it. 7 new tests in
  `test/ggen_igniter_doctor_fixes_test.exs`. `docs/status.md`'s "Igniter
  AST-mutation ... PLANNED" row is corrected to IMPLEMENTED.
- **`GgenIgniter.Reactors.CompensationTelemetryMiddleware`** -- new real
  `Reactor.Middleware` (`lib/ggen_igniter/reactors/compensation_telemetry_middleware.ex`)
  wired alongside `Reactor.Middleware.Telemetry` in `ReconcileReactor`'s
  `middlewares` block, counting `{:compensate_start, _}`/`{:compensate_error, _}`/
  `:undo_start` events plus `error/2`-derived `:compensation_failed`/
  `:build_broken` standings (reusing `ReconcileReactor`'s own real
  `find_compensation_failure/1`/`find_step_error/2` helpers) into a real, public,
  named ETS table (`counters/0`). New
  `test/ggen_igniter_reconcile_reactor_compensation_telemetry_test.exs`: 2 tests
  against the real `:verify`-fails/`undo/4` path and the real `:actuate`-self-heal
  path, 0 failures.
- **`:run_queries` concurrency: investigated, NOT changed.** A real hazard was
  found and disclosed rather than fixed: `GgenIgniter.Engine.Qlever.prepare!/2`
  has a check-then-act race on a named process
  (`Process.whereis(GgenIgniter.Finch)` then `Finch.start_link/1`) that
  `Task.async_stream/3` concurrency would make reachable whenever two `:targets`
  in one run both specify `engine: "qlever"`. `:run_queries` is byte-for-byte
  unchanged.
- **`GgenIgniter.Ontology.load!/1` multi-format dispatch** -- now dispatches on
  file extension: `.nt` -> `RDF.NTriples.read_file!/1`, `.nq` ->
  `RDF.NQuads.read_file!/1` (returns `RDF.Dataset.t()`, not `RDF.Graph.t()` --
  `@spec` widened accordingly), everything else (including `.ttl`) falls back to
  the pre-existing `RDF.Turtle.read_file!/1`. New
  `test/ggen_igniter_ontology_multiformat_test.exs`: 4 tests, 0 failures, real
  fixture files (`test/fixtures/sample.nt`/`sample.nq`/`sample.unknownext`).
- **New property-test coverage** on already-IMPLEMENTED modules (not a status
  change): `test/ggen_igniter_artifact_identity_properties_test.exs` (3
  properties over `GgenIgniter.ArtifactIdentity.within_root?/2`/`canonicalize/2`,
  including a real `File.ln_s!/2` symlink-escape adversarial sweep) and
  `test/ggen_igniter_lock_staleness_properties_test.exs` (2 properties over
  `GgenIgniter.Lock.acquire/2`'s stale-vs-live boundary at `@stale_after_ms`,
  plus one real two-OS-subprocess contention test).
- **`mix ggen_igniter.plan --help`/`-h` regression coverage** -- new
  `test/ggen_igniter_plan_task_test.exs` closes a real coverage gap (`sync`/
  `doctor` already had a dedicated subprocess test for this class of AR-11
  regression; `plan` did not). Independently re-verified: `plan`'s `--help`/`-h`
  were already byte-identical and already routed through the concise
  `print_help/0` block (the AR-11 fix pattern from commit `b184d907` already
  covers `plan.ex`) -- no bug found, no fix needed; this closes the test-coverage
  gap only.
- **`mix.exs`**: added `docs:` key + `{:ex_doc, "~> 0.34", only: :dev,
  runtime: false}` (real `mix docs` run confirmed `doc/index.html`/`doc/llms.txt`/
  `doc/ggen_igniter.epub` generated); added explicit `{:jason, "~> 1.4"}` (was
  only present transitively; `lib/ggen_igniter/receipt.ex` calls
  `Jason.encode!/1`/`decode!/1` directly in production code).
- **`lib/ggen_igniter/pack.ex`**: added `{Tesla.Middleware.Retry, max_retries: 3}`
  to the one `Tesla.client/1` call site (github:/hex: pack fetch), scoped to
  transient connection failures only -- HTTP-level error statuses (404/500) are
  not retried, per `Tesla.Middleware.Retry`'s own `should_retry` default.
- **Verification (this release)**: `mix format --check-formatted` -- clean.
  `mix compile --warnings-as-errors` -- clean (only the pre-existing, unrelated
  `:preferred_cli_env` deprecation warning). Full `mix test`: **12 doctests, 41
  properties, 440 tests** -- one run showed 1 failure under full-suite
  concurrent load, a second full run and three isolated re-runs of the suspect
  file (`test/ggen_igniter_lock_staleness_properties_test.exs`) were all clean
  (0 failures) -- real subprocess/wall-clock timing flakiness under load,
  disclosed rather than hidden, not a regression introduced by this release.
  `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native` -- zero real
  matches (the same two pre-existing doc-string mentions as v26.8.29, untouched).
  `mix ggen_igniter.doctor --fix` re-run against a real fixture consumer project
  confirmed the migrated Igniter-based codemods perform the same real fixes as
  before the AST-mutation migration.

## v26.8.29

Testing/observability strengthening pass (three parallel agents reconciled onto a
shared working tree) -- no new user-facing CLI capability; `GgenIgniter.Manifest` and
`GgenIgniter.PendingActuation` were already IMPLEMENTED (see `docs/status.md`), this
pass adds real test coverage and real Reactor instrumentation for them.

- **`Reactor.Middleware.Telemetry` wired onto `GgenIgniter.Reactors.ReconcileReactor`**
  -- a new `middlewares do middleware Reactor.Middleware.Telemetry end` block
  (`lib/ggen_igniter/reactors/reconcile_reactor.ex`), emitting real
  `:telemetry.execute/3` events for this reactor's run/step/compensate/undo timing
  under `[:reactor, :run, :start|:stop]`, `[:reactor, :step, :run, :start|:stop]`,
  `[:reactor, :step, :guard, :start|:stop]`, `[:reactor, :step, :process,
  :start|:stop]`, `[:reactor, :step, :compensate, :start|:stop]`, and `[:reactor,
  :step, :undo, :start|:stop]`. Verified DSL shape directly against
  `deps/reactor/documentation/explanation/architecture.md` and
  `deps/reactor/lib/reactor/dsl/middleware.ex` before writing. New
  `test/ggen_igniter_reconcile_reactor_telemetry_test.exs`: a real
  `:telemetry.attach_many/4` handler receives real `[:reactor, :run, :start]`/`:stop`
  events from a real `ReconcileReactor.run/1` execution against a real scratch Mix
  project (`mix test test/ggen_igniter_reconcile_reactor_telemetry_test.exs`: 1 test,
  0 failures).
- **Two new StreamData property-test files**, strengthening already-IMPLEMENTED
  modules (not a status change):
  - `test/ggen_igniter_manifest_properties_test.exs` -- real generator-driven
    properties over `GgenIgniter.Manifest`'s pure functions: `hash_content/1`
    determinism and its `sha256:<64 hex>` output shape; `recipe_key/2` injectivity
    over distinct `(template, out_template)` pairs (plus one disclosed unit test
    documenting the known `"=>"`-embedded-string collision, not asserted as a
    universal property); `output_paths/1` round-tripping the exact generated path
    set; `stale_paths/2` as real `MapSet.difference/2` equivalence; `same_outputs?/2`
    reflexivity and single-key-change detection.
  - `test/ggen_igniter_pending_actuation_properties_test.exs` -- real
    generator-driven properties over `GgenIgniter.PendingActuation`: `logical_id/3`
    determinism and its sensitivity to a changed `target`; `plan_unchanged?/1`'s
    exact iff-both-non-nil-and-equal semantics; `for_file/7` against real temp files
    on disk (real `File.write!/2`/`File.exists?/1`), proving `:create` vs `:replace`
    dispatch and the real `previous_hash`/`compensation_data` derivation from actual
    prior file content.
  - Both run clean: `mix test test/ggen_igniter_manifest_properties_test.exs
    test/ggen_igniter_pending_actuation_properties_test.exs --seed 0` twice in a
    row -- `15 properties, 2 tests, 0 failures` both times, no flakiness.
- **Verification (this release)**: `mix format --check-formatted` -- clean (fixed
  three real formatting deltas the three source agents left behind: the
  `middleware` DSL call's parens and two `check all(...)` generator-list wraps).
  `mix compile --warnings-as-errors` -- clean (only the pre-existing, unrelated
  `:preferred_cli_env` deprecation warning from `mix.exs` itself). Full `mix test`:
  **12 doctests, 36 properties, 424 tests, 0 failures** (174.1s). `grep -rn
  "Mock\|mock(\|patch(\|monkeypatch" test lib native` -- zero matches (the two hits
  the raw grep returns are pre-existing doc-string mentions of the banned pattern
  names in `test/ggen_igniter_reactor_concurrency_test.exs` and `test/CLAUDE.md`
  itself, not actual mock usage, and neither file was touched this release).

## v26.8.28

DX/QoL swarm (16 parallel agents reconciled onto a shared working tree, commit
`6c2f109`) plus a follow-up correctness pass on the two real gaps that swarm's own
verification missed (`--help` output split, `doctor --json` footer corruption).

- **`mix ggen_igniter.doctor --strict`** -- a new flag: WARN-level findings (not just
  ERROR-level) now also fail the run (exit 1), and every WARN line printed under
  `--strict` is suffixed `[STRICT]` so it's visible why a run that would otherwise
  pass is failing. Plain (non-`--strict`) behavior is unchanged -- WARN findings still
  print but don't affect the exit code.
- **`check_id` tagging on all 17 doctor checks** -- both the human-readable and
  `--json` output now carry a stable `check_id` per check, so a CI script or a
  human diffing two runs can identify which specific check changed status without
  parsing free-text messages.
- **Fixed a real `--hex-check`/`--fix` staleness bug (check 16)** -- the check read
  the once-loaded `Mix.Project.config()` for the package version instead of
  `mix.exs`'s current-on-disk text, so a `--fix` applied earlier in the same
  `doctor` invocation wasn't reflected by check 16's own re-evaluation later in
  that same run.
- **`mix ggen_igniter.sync --help`/`-h` and `--version`/`-v`** -- new flags on the
  sync task itself.
- **`--for-each` summary line** -- a `--for-each` run with more than one row now
  appends a real, counted-from-actual-outcomes summary (e.g.
  `-- summary: wrote 8` / `wrote 2, skipped 6`) after the existing per-file notice
  lines, rather than only printing per-file notices with no aggregate.
- **Five rewritten error messages** -- `GgenIgniter.Reactors.ReconcileReactor`
  (a `:verify` failure caused by `--manifest-dir` pointing outside a Mix project
  without `--verify-cwd` now prepends a concrete pointer at `--verify-cwd` to the
  raw Mix crash text) and `GgenIgniter.Pack`/`GgenIgniter.Query.Qlever`
  (pack-fetch 404/network failures and QLever query/store-load failures now raise
  actionable messages naming the spec/URL, likely cause, and a concrete next step,
  instead of a bare HTTP status or an `inspect()`'d raw error).
- **`mix.exs` cleanup** -- removed a duplicate `description: description()` at the
  project-level (only `package/0`'s copy was meaningful).
- **AR-11: `--help` output split fixed on `sync`, `plan`, and `doctor`** --
  `Igniter.Mix.Task`'s generated `run/1` intercepts literal `"--help"` in `argv`
  before this project's own `igniter/1` ever runs (`Igniter.Mix.Task.
  help_requested?/1` checks `"--help" in argv` but never matches `-h`), dispatching
  to `Mix.Task.run("help", [task_name])` -- Mix's own generic renderer of the
  module's full `@moduledoc` -- instead of each task's own concise
  `print_help`/`print_help_and_halt`. `-h` was unaffected (it already reached the
  concise help via `igniter/1`'s own `opts[:help]` branch), so this was a real,
  confirmed `--help`-vs-`-h` output split. Fixed by overriding `run/1` on all
  three tasks (`Mix.Tasks.GgenIgniter.Sync`, `.Plan`, `.Doctor`) to catch literal
  `"--help"` before Igniter's own check runs and dispatch to the same concise help
  path `-h` already used; every other `argv`, including `-h` itself, is untouched
  and still flows through the unchanged `super/1` path.
- **`mix ggen_igniter.doctor --json` footer corruption fixed** -- the
  all-checks-passed path returned `igniter` (with zero proposed changes, since
  `doctor` never mutates the target project) back to `Igniter.Mix.Task`'s
  generated runner, which then printed its own "No proposed content changes!"
  footer to stdout AFTER `print_json/3` had already written a validly-closed JSON
  document -- corrupting `--json` output with trailing non-JSON bytes a strict
  single-document JSON parser rejects. Fixed by halting directly with
  `System.halt(0)` on that path (mirroring `mix ggen_igniter.plan`'s existing
  identical fix for the same Igniter-runner behavior) instead of returning to the
  runner. See `test/ggen_igniter_doctor_task_test.exs`'s three new subprocess-level
  regression tests, including one that round-trips real `--json` output through an
  external `python3 -m json.tool` process to prove it parses as exactly one
  document.

## v26.8.27

Template frontmatter execution modes, a new opt-in end-to-end tier, and three
new read-only/lock-safe CLI verbs (`plan`, `replay`) plus a real cross-process
mutation lock (`GgenIgniter.Lock`).

- **`mix ggen_igniter.plan`** (`lib/mix/tasks/ggen_igniter.plan.ex`,
  `GgenIgniter.Reactors.ReconcileReactor.plan/1`) -- a read-only admission
  preview: runs the SAME observe -> load ontology -> resolve pack -> run
  queries -> render -> admit sequence a real `mix ggen_igniter.sync` (with
  `use_reactor: true`) runs, but stops before `:actuate`. Reports every
  `%GgenIgniter.PendingActuation{}` the admitted plan would write (operation,
  target, `plan_unchanged?/1`, previous/desired hash) in human-readable or
  `--json` form; nothing is ever written to disk. Per the PRD's FR-5, `plan`
  does NOT acquire `GgenIgniter.Lock` -- it may run concurrently with an
  in-flight `sync`/lock holder. A run that hits a capability outside
  `GgenIgniter.Reconcile.run/1`'s bounded reactor scope (`inject: true`,
  `--for-each`) exits 3 (`:unsupported_capability`) rather than silently
  downgrading to a partial plan. See `test/ggen_igniter_plan_schema_test.exs`
  and `docs/reference/cli/plan.md`.
- **`mix ggen_igniter.replay <receipt_file>`** (`lib/mix/tasks/ggen_igniter.replay.ex`)
  -- a diagnostic task that loads one real `GgenIgniter.Receipt` (either a
  date-partitioned `.jsonl` partition's last line, or a single-object JSON
  file) and recomputes real, current hashes of the same inputs the receipt
  recorded, to answer "has anything this receipt depended on drifted since it
  was written?" It reports two independently-checked categories: "output
  state changed" (`GgenIgniter.Receipt.hash_files/1` re-run over the
  receipt's own `files`, compared to the recorded `post_run_hash`) and
  "ontology changed" (only when the receipt's `recipe_key` resolves to a
  `GgenIgniter.Manifest` entry with a `pack_dir` AND the receipt recorded
  `metadata["graph_hash"]` -- `<pack_dir>/ontology.ttl` is re-hashed with the
  same `"sha256:" <> hex` algorithm and compared). Exits 2 on a missing/
  unparseable receipt file rather than guessing at its content. See
  `test/ggen_igniter_replay_test.exs` and `docs/reference/cli/replay.md`.
- **`GgenIgniter.Lock`** (`lib/ggen_igniter/lock.ex`) -- a real, file-based
  cross-process lock (`.ggen_igniter/.sync.lock`, `File.open/2`'s
  `:exclusive` mode, so two separate `mix` invocations genuinely cannot both
  win the race -- not an in-memory/`:global`/`GenServer` lock, which would
  only serialize callers inside the same BEAM node) now serializes concurrent
  mutating invocations of `mix ggen_igniter.sync`/`mix ggen_igniter.replay`
  against the same target project (AR-9). A lock file older than 5 minutes is
  treated as abandoned (crashed holder, killed process, machine restart) and
  is removed automatically by the next `acquire/2` caller rather than
  permanently wedging future runs. `mix ggen_igniter.doctor` and
  `mix ggen_igniter.plan` remain read-only and never acquire this lock. See
  `test/ggen_igniter_lock_contention_test.exs` and `docs/reference/cli/lock.md`.

- **AR-10: `inject: true` now gets real Reactor admission-gate coverage via
  `mix ggen_igniter.sync`** -- `Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3`
  used to refuse delegating ANY frontmatter-bearing template to
  `GgenIgniter.Reactors.ReconcileReactor.run/1`, falling back to the
  pre-Reactor inline pipeline -- which has no duplicate-output-path or
  path-escape admission checks at all. Since `inject: true` can only be
  expressed via frontmatter, every `inject: true` write was silently
  exempt from those real checks. `ReconcileReactor` itself already fully
  implements `operation: :inject` construction/dispatch (real, tested by
  `test/ggen_igniter_reconcile_reactor_inject_test.exs`); the gap was only
  the CLI's own dispatch guard being broader than the pipeline's real
  capability. Fixed by narrowing that guard to the one frontmatter feature
  `ReconcileReactor` genuinely does not resolve (inline `sparql:` query
  text) and threading frontmatter `to:`/`unless_exists:`/`skip_if:` into
  the resolved reconcile options explicitly. `mode: eval` frontmatter
  templates are deliberately excluded from this widening (a real,
  separately-tracked `ReconcileReactor` `:render` crash for `:eval`
  targets, independent of this change -- see `docs/status.md`). See
  `test/ggen_igniter_sync_inject_reactor_admission_test.exs` for the real,
  CLI-subprocess proof: an `inject: true` write now genuinely routes
  `"(via reactor)"`, and an `inject: true` write escaping the authorized
  project root is refused the exact same real way an ordinary `mode: file`
  write already was.

- **`mode: eval` frontmatter execution mode** (`GgenIgniter.Frontmatter.split_template/1`,
  `GgenIgniter.Actuate.eval_code!/2`) -- a template's `---`-fenced YAML header
  can now carry `mode: eval` (or `--mode eval` on the CLI, which always wins
  over the frontmatter value) alongside the existing `mode: file` default.
  Under `mode: eval`, the rendered template body is never written to disk at
  all: instead it is real Elixir source, evaluated in-process via
  `Code.eval_string/2` using the exact same `bindings` keyword list the
  template body renders with, so eval'd code can reference `module_name`, a
  single-row query's flattened columns, or a `--for-each` row's columns just
  like the template body itself can. `eval_code!/2` returns `{:ok, value}`
  (the real, unwrapped return value of the evaluated code) and turns any
  `CompileError`/`SyntaxError`/`TokenMissingError` into a clear `RuntimeError`
  naming the real failure rather than letting the raw exception struct
  surface. `--out`/`to:` is not required in this mode, and
  `--unless-exists`/`--skip-if` do not apply. This is a deliberate, disclosed
  arbitrary-code-execution capability -- ontology/RDF-driven data becomes
  literally-executed Elixir code under `mode: eval` -- at the same trust
  boundary an EEx template body already is (an EEx template can already run
  arbitrary Elixir inside `<%= %>` during rendering).
- **Template frontmatter parsing (hygen/ggen parity)** -- `mix ggen_igniter.sync`
  now recognizes a `---\n...\n---\n` YAML header on the first line of a
  `--template` file, mirroring real hygen and the real Rust ggen's own
  `ggen-engine/src/template.rs` `Frontmatter` convention. The header supplies
  defaults for `to:` (equivalent to `--out`), `sparql:` (named inline query
  text, not file paths), `for_each:`, `skip_if:` (literal-string form),
  `unless_exists:`, and the new `mode:` field, so a self-contained template
  can be rendered with just `--template`/`--ontology` and no repeated
  `--out`/`--for-each`/`--query` flags -- exactly like `hygen generate <name>`
  needs no routing flags because the template's own header carries them. Any
  explicit CLI flag always overrides the same-named frontmatter field, and a
  template with no `---` header behaves exactly as before this feature
  existed.
- **`mix e2e` task** (aliased in `mix.exs` to `run test/e2e/run_e2e.exs`,
  separate from and not run by plain `mix test`) -- a real, sequential,
  multi-stage lifecycle test (`test/e2e/lifecycle_test.ex`) that scaffolds a
  fresh, throwaway Ash+Phoenix application (via real `mix archive.install` +
  `mix igniter.new`, no mocking) and drives it through resource creation,
  attribute addition, a relationship, a custom action, a real
  `AshPhoenix.Form`, a real `mix ash_phoenix.gen.live`-generated LiveView, and
  a rename -- all via real `mix ggen_igniter.sync` subprocess runs against the
  `test/fixtures/ash-lifecycle-pack/` fixture pack -- to prove
  ggen_igniter-generated code stays consistent across real Ash, AshPhoenix,
  and Phoenix APIs as an application evolves. This tier requires network
  access (archive installs, dependency fetches) and takes several minutes to
  run; it is intentionally not part of `mix test` and must be invoked
  explicitly with `mix e2e`.

## v26.8.26

Packaging pass: real hex.pm package metadata (`package:` entry in `mix.exs`),
MIT `LICENSE`, `.formatter.exs`, and this changelog/README pass. No source
changes to `lib/` or `native/` in this release beyond what v0.1.0's six
commits already established below.

## v0.1.0 (pre-release history, commits `d94cedc`..`f70d7ec`)

- **`d94cedc`** — Bootstrapped `ggen_igniter`: a pure-Elixir
  ontology -> SPARQL -> EEx -> Igniter pipeline (`GgenIgniter.Ontology`,
  `GgenIgniter.Query`, `GgenIgniter.Render`, `GgenIgniter.Actuate`, and the
  `mix ggen_igniter.sync` task), with write-safety guards
  (`unless_exists`/`skip_if`/idempotent no-op) mirroring the real Rust
  ggen's `ggen-engine/src/write.rs` decision table.
- **`312ac08`** — Added a cross-repo composition test proving the pipeline
  against a real external pack (`ash_r2rml`), not just in-repo fixtures.
- **`549cec2`** — Added a real QLever-backed alternate SPARQL engine
  (`GgenIgniter.Query.Qlever`), demonstrating that a known `sparql` hex
  package 0.3.12 bug (`FILTER NOT EXISTS` + `BIND` inside `UNION`) is
  engine-specific rather than a query-shape limitation.
- **`279dab7`** — Fixed manifest graph splitting for Gno's Manifest Graph
  Expansion (MGE).
- **`46a4d11`** — Wired `GgenIgniter.Query.Qlever` into
  `mix ggen_igniter.sync` as `--engine qlever` (real HTTP against an
  already-running QLever endpoint, `--store-id` required).
- **`f70d7ec`** — Added the `--pack` convention
  (`priv/ggen/<pack-name>/{ontology.ttl,gates/*.rq,templates/*.eex}`,
  `GgenIgniter.Pack`) and the `mix ggen_igniter.doctor` diagnostic task
  (fixed checklist of real environment/dep/pack-shape/SPARQL-syntax checks).

### Also present in this working tree (uncommitted-history features exercised
by the current test suite and moduledocs, folded into this release)

- **`--engine oxigraph`** — a real native [oxigraph](https://github.com/oxigraph/oxigraph)
  query engine via a Rustler NIF (`native/ggen_graph_nif`,
  `GgenIgniter.Native.GraphNif`, `GgenIgniter.Query.Oxigraph`) over ggen's
  `ggen-graph-wasm` `OxigraphEngine`, as a third alternative to `sparql` and
  `qlever` for queries that trip the pure-Elixir `sparql` package's
  `FILTER NOT EXISTS`/`UNION` limitation.
- **`--for-each NAME`** — multi-row fan-out mirroring the real Rust ggen's
  `for_each:` frontmatter field: renders the template once per row of a
  named query result and writes each rendering to its own output path
  (`--out` itself rendered as an EEx template per row).
- **`--dry-run`** — previews planned writes/skips without touching disk.
- **Marketplace pack fetch** (`GgenIgniter.Pack.fetch_pack!/2`) — resolves
  `github:owner/repo[@ref]` (print-only checksum, no verification available
  from GitHub's archive endpoint) and `hex:name[@version]` (fail-closed
  SHA-256 verification against hex.pm's published checksum) pack sources.
- **`GgenIgniter.Frontmatter`** — an Elixir struct mirroring the real Rust
  `ggen::Frontmatter` field-for-field (`to`, `sparql`, `for_each`,
  `construct`, `inject`, `before`/`after`, `at_line`, `skip_if`,
  `unless_exists`, `unattended_write_eligible`, `force`), and
  `GgenIgniter.PackManifest` mirroring `pack.toml` shape, so the Elixir and
  Rust/WASM sides of the templating engine describe the identical field set.
