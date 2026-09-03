# mix ggen_igniter.fortune5_ready — assembled task and Chicago-style end-to-end test

## Status update (round 3 — bundle-serializer comment/order-preservation fix)

**MERGED** — `story/GI-07-bundle-serialize-preserve-comments`, commit `a89fcf1`, now
merged to `ggen_igniter` `main` at `c7d3d64`. Full detail lives in
`~/ggen_igniter/docs/jira/v26.9.1/03-BUNDLE-MANIFEST-AND-MERGE.md`'s own "Status
update (round 3 ...)" section — cross-referenced here because it directly concerns
this ticket's own `serialize_step`.

Summary: `GgenIgniter.Bundle`'s merge-then-serialize path is fixed via a new
`GgenIgniter.GgenToml.IO.splice_added_packs!/2` — a textual splice over the raw
original file text (not a full lossy re-render) — proven addition-only against
beam4pm's real `ggen.toml` (2 new tests, 11/11 total passing), with the
`gh-terraform-pack` decline comment surviving byte-for-byte and non-alphabetical
original pack order preserved.

**Disclosed remaining gap directly affecting this ticket**: this ticket's own
`serialize_step` (`lib/mix/tasks/ggen_igniter.fortune5_ready.ex:179-185`) still
calls the old lossy `GgenIgniter.GgenToml.IO.serialize!/1` on a live run — it has
**not** been rewired to the new `splice_added_packs!/2` path as part of GI-07.
Rewiring `serialize_step` to call the splice-based serializer instead is a natural
GI-08 follow-on, not performed by GI-07 and not yet performed here.

## Status (updated after real implementation)

**DONE** per gi05 evidence in `/tmp/full_results.json`.

- Branch `story/GI-05-fortune5-ready-mix-task` (based on GI-04's
  `story/GI-04-sync-shellout-and-verify`, commit `c542eea`), new commit `6486cb5`. Committed only —
  not merged to main, not pushed.
- Worktree: `/private/tmp/GI-04-worktree`. Note — this is a real fact, not a typo: GI-05's agent
  reused GI-04's worktree directory rather than creating a new one, and just switched branches
  inside it (`git checkout -b story/GI-05-fortune5-ready-mix-task` on top of GI-04's commit, in
  the same checkout at `/tmp/GI-04-worktree`).
- New `lib/mix/tasks/ggen_igniter.fortune5_ready.ex` — `Mix.Tasks.GgenIgniter.Fortune5Ready`,
  `use Igniter.Mix.Task`, real pipeline: `dispatch_probe/1` (ticket 01's `SchemaDispatch.load/1`)
  → `parse_step` → `merge_bundle_step` (ticket 03's `Bundle.merge/2`) → `serialize_step` (ticket
  02's `GgenToml.IO.serialize!/1`) → `sync_step` (ticket 04's `SyncVerify.run/3` when `--pack-dir`
  given, else `SyncShellout.run/2` alone) → `report_step` (fail-loud via `Igniter.add_issue/2`).
- Real defect found and fixed forward during this ticket's own e2e test: `SchemaDispatch.
  build_project_config/1` (tickets 01/02, already closed) hardcoded `generation: %GenerationConfig{
  rules: []}`, silently discarding every real `[[generation.rules]]` entry — fixed in
  `lib/ggen_igniter/schema_dispatch.ex` (`build_generation_config/1` et al.) and
  `lib/ggen_igniter/ggen_toml_io.ex` (`generation_section/1` now emits real
  `[[generation.rules]]` array-of-tables blocks).
- New `test/ggen_igniter_fortune5_ready_task_test.exs`: Test 1 (Frontmatter schema e2e, real
  `ggen sync run`, real idempotency proof), Test 2 (DeclarativeRules schema e2e, proves genuine
  dispatch branching), Test 3 (negative case — gate failure reported via a real `Igniter` issue,
  never a success notice), Test 4 (`--help` real subprocess, exit 0).
- Command output: `mix compile --warnings-as-errors` → clean. `mix ggen_igniter.fortune5_ready
  --help` → real usage text, exit 0. `mix test test/ggen_igniter_fortune5_ready_task_test.exs
  test/ggen_igniter_ggen_toml_io_test.exs test/ggen_igniter_schema_dispatch_test.exs
  test/ggen_igniter_bundle_test.exs test/ggen_igniter_sync_shellout_test.exs` → "34 tests, 0
  failures" (this ticket's 4 new tests plus zero regressions across tickets 01–04). `mix
  ggen_igniter.doctor` → "all checks passed". `grep -rn "Mock\|mock(\|patch(\|monkeypatch" test
  lib native` → only doc-comment mentions of the discipline plus pre-existing `assert_has_patch`
  calls (igniter's real API, not mocking) — zero real mock usage anywhere.

**Same full-suite-unconfirmed caveat as the other stages**: a background full-repo `mix test` (log
at `/tmp/gi05_fulltest.log`) was still running against this repo's full 2500+-test suite
(unrelated pre-existing suites — OCEL, telemetry, native NIF, redteam collision reproducers, etc.)
when the task's time budget was reached; not confirmed to completion. The scoped run above is the
load-bearing evidence for this ticket's own acceptance bullets.

**Cross-reference**: this same worktree/branch (`/tmp/GI-04-worktree`,
`story/GI-05-fortune5-ready-mix-task`) is also where `docs/jira/v26.9.1/PARITY-VALIDATION.md` was
later written and committed (commit `ebf507c`) during the follow-on parity-validation stage — see
that file for the real-`ggen`-binary parity checks run against beam4pm's actual `ggen.toml`.

Non-goals explicitly out of scope and not attempted: the real `~/beam4pm` trial (ticket 06), and
the two upstream `fortune5-required-capabilities`/`fortune5-testing-bblock` pack portability
fixes (source epic's own blocking dependency, not this ticket's).

---

Capstone story for this milestone's fortune5-ready bundle-installer work stream — maps to
`GGEN-1807` in the source epic, `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md`.
This is a **different work stream** from `~/ggen_igniter/docs/v26.9.1-requirements.md` (the
process-mining/OCEL manufacturing-pack expansion release — incremental DFG discovery,
sensor-to-event streaming, inductive-miner discovery, token-replay conformance, OCEL2/EKG
derivation, OLAP slice/dice, Chicago-style OTP fault-injection packs) that happens to share the
same `v26.9.1` version number. See "See Also" below for both.

Ticket 05 assumes tickets 01–04 in this same `docs/jira/v26.9.1/` set exist and are closed:

- **01** — the shared classifier + dispatch point (`GgenIgniter.SchemaDispatch`, mirroring
  ggen core's `ggen-engine/src/schema_dispatch.rs` + `ggen_config::classify_ggen_toml`):
  reads a target project's `ggen.toml` once and classifies it as `:frontmatter` (empty
  `[[generation.rules]]`) or `:declarative_rules` (non-empty).
- **02** — the two concrete typed parse/serialize structs: `GgenIgniter.ProjectConfig`
  (Frontmatter/`GgenConfig` mirror — `[packs]` as a table-of-tables,
  `%{String.t() => PackRef.t()}`) and the existing `GgenIgniter.PackManifest`/`PackRef`
  (DeclarativeRules/`GgenManifest` mirror — `[[packs]]` as an array-of-tables), each with a
  round-trip-safe serializer back to real TOML text.
- **03** — the bundle-merge step: given a parsed config (either schema) and the fortune5 pack
  bundle (the four fortune5-adjacent packs from the source epic, portability fixes assumed
  closed per that epic's own dependency note), produces a new parsed config with the bundle's
  packs merged in, idempotently (re-running the merge against an already-merged config is a
  no-op, not a duplicate entry).
- **04** — the sync-and-gate step: shells out to `ggen sync run` against the target project's
  real `ggen.toml` on disk, then runs the milestone's gate checks and reports pass/fail per
  gate.

This ticket assembles 01–04 into one real, runnable `mix ggen_igniter.fortune5_ready` task and
proves the assembled pipeline end-to-end against a real scratch fixture project. It does **not**
cover the beam4pm trial itself — that is `~/ggen/docs/jira/v26.9.1/06-BEAM4PM-TRIAL-AND-GATE-M2-PREREQUISITE.md`,
a downstream ticket scoped to the real `~/beam4pm` repo. This ticket's acceptance is scoped
entirely to a scratch fixture project created for the test.

## Story: assemble the pipeline as a real `Igniter.Mix.Task`

Model the task directly on `lib/mix/tasks/ggen_igniter.install.ex`'s real structure — read
before writing this task, not re-derived from scratch:

- **`use Igniter.Mix.Task`**, `@impl Igniter.Mix.Task def info/2` declaring
  `group: :ggen_igniter` and a `schema` (at minimum `path: :string` — the target project
  directory, defaulting to `File.cwd!/0` — and `yes: :boolean` with `aliases: [y: :yes]`,
  matching `install.ex`'s existing `--yes`/`-y` convention).
- **`@impl Mix.Task def run(argv)`** with the same `"--help" in argv` early-exit precedent
  `install.ex` already uses, calling `super(argv)` otherwise.
- **`@impl Igniter.Mix.Task def igniter(igniter)`** as the real pipeline body:

  ```elixir
  def igniter(igniter) do
    case dispatch_probe(igniter) do
      {:ok, path} ->
        igniter
        |> parse_step(path)
        |> merge_bundle_step()
        |> serialize_step(path)
        |> sync_step(path)
        |> verify_gates_step()
        |> report_step()

      {:error, reason} ->
        Igniter.add_issue(igniter, fortune5_ready_issue_text(reason))
    end
  end
  ```

  Each `_step/1,2` function is a thin call into ticket 01's `SchemaDispatch`, ticket 02's
  `ProjectConfig`/`PackManifest` parse+serialize pair, ticket 03's merge, and ticket 04's
  sync+gate runner — this ticket's own new code is the glue, not a reimplementation of any of
  the four.

- **Defensive-probe pattern, reused from `install.ex`'s `deps_probe/1`.** `install.ex`'s
  `deps_probe/1` runs the exact same `Igniter.Code.Module.move_to_module_using/2` +
  `Igniter.Code.Function.move_to_defp/3` probe that `Igniter.Project.Deps.add_dep/2,3`
  internally runs, *before* calling `add_dep/2`, specifically to fail closed (an
  `Igniter.add_issue/2` diagnostic, no partial write) instead of hitting the known
  `CaseClauseError` documented in that file's moduledoc. This task applies the same
  discipline at its own known-risk seam: `dispatch_probe/1` runs ticket 01's classifier
  against the target `ggen.toml` *before* attempting to parse it, and returns `{:error,
  reason}` — routed to `Igniter.add_issue/2`, never a raised exception — for every failure
  mode ticket 01 can name (file missing, unreadable, malformed TOML, a classification ggen
  core itself would reject). Nothing downstream of `dispatch_probe/1` runs on an `:error`
  result; this mirrors `install.ex`'s `case deps_probe(igniter) do :ok -> ... ; :error ->
  Igniter.add_issue(...) end` shape exactly, generalized from a boolean probe result to a
  `{:ok, classification}` / `{:error, reason}` result because ticket 01's classifier, unlike
  `install.ex`'s probe, needs to hand its classification forward to the parse step.

- **Default schema per this milestone's resolved schema-dispatch decision.** Per the
  now-firm requirement in tickets 01–02 (ggen core's `Frontmatter`/`GgenConfig`
  table-of-tables `[packs]` shape is what real consumers like beam4pm actually use, and is
  exercised first and by default — `DeclarativeRules`/`GgenManifest` stays supported for
  projects that use it, but is not the assumed-default path), this task's own dispatch does
  not special-case either branch: it calls ticket 01's shared classifier exactly once, exactly
  as ggen core's `schema_dispatch.rs` does for every real call site, and follows whichever
  branch the classifier returns. No new bespoke schema-guessing logic is written in this
  ticket — that would reopen the ad hoc six-call-site inconsistency ggen core's own
  `schema_dispatch.rs` doc comment cites (`BUG-005`) as the reason the shared dispatch point
  exists at all.

- **Fail-loud gate reporting.** `verify_gates_step/1` and `report_step/1` refuse to report
  partial success as success: if ticket 04's gate runner reports any gate as failed, the task
  emits `Igniter.add_issue/2` (or `Mix.raise/1` outside the `%Igniter{}` composition, per
  whichever of the two `install.ex` itself demonstrates is idiomatic for a hard stop) naming
  every failed gate by name, and does not proceed to claim the bundle install succeeded. A run
  where sync succeeds but one gate fails is reported as a failed `fortune5_ready` run, full
  stop — this is the same "no partial-success-as-success" discipline this milestone's
  originating plan and beam4pm's own `docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md`
  acceptance format both hold every story to (compilation or file existence alone is not a
  crown; the acceptance behavior must be the real, checked outcome).

- **Structured summary output.** `report_step/1` prints (via `Igniter.add_notice/2`, matching
  `install.ex`'s own notice/issue vocabulary) a summary naming: which packs were newly added by
  the merge (from ticket 03's merge result, not re-derived by diffing files after the fact),
  which gates passed, which gates failed (empty list on success), and the final `ggen.toml`
  classification the run dispatched against.

## Acceptance

- `lib/mix/tasks/ggen_igniter.fortune5_ready.ex` exists, `use Igniter.Mix.Task`, and its
  `@impl Igniter.Mix.Task def igniter/1` calls into ticket 01's `SchemaDispatch`, ticket 02's
  parse/serialize pair, ticket 03's merge, and ticket 04's sync+gate runner as named modules —
  evidence: `grep -n "SchemaDispatch\|ProjectConfig\|PackManifest\|sync_step\|verify_gates"
  lib/mix/tasks/ggen_igniter.fortune5_ready.ex` shows real calls into each, not inlined
  reimplementations.
- A real Chicago-style ExUnit test,
  `test/ggen_igniter_fortune5_ready_task_test.exs`, runs the **entire assembled task** —
  `Mix.Tasks.GgenIgniter.FortuneFiveReady.igniter/1` (or the task invoked as a real subprocess
  `mix` call, whichever this ticket's own implementation settles on — either is acceptable,
  a mocked task invocation is not) — against a **real scratch Elixir project fixture** created
  fresh under a temp directory for the test (a minimal `mix.exs` + a real `ggen.toml` on disk
  using the Frontmatter/`GgenConfig` table-of-tables `[packs]` shape, matching real
  `~/beam4pm/ggen.toml`'s shape per this milestone's resolved schema-dispatch finding — not a
  hand-typed string asserted against in memory).
- The test asserts on **real post-run state on disk**, not on interaction/call-count
  assertions: the actual `ggen.toml` content read back from the scratch fixture after the run
  (containing the fortune5 bundle's packs merged into `[packs]`, still valid, re-parseable
  TOML, idempotent — a second run of the task against the same fixture produces byte-identical
  `ggen.toml` content, proving the merge step is actually idempotent rather than merely
  documented as such) and the actual files `ggen sync run` produced in the fixture's `src`/
  equivalent output directory (real files present on disk, not merely a claimed exit code).
- A **second real scratch-fixture case** exercises the `DeclarativeRules`/`GgenManifest`
  array-of-tables `[[packs]]` shape (a `ggen.toml` with a non-empty `[[generation.rules]]`),
  proving the task's dispatch genuinely branches on ticket 01's classifier rather than
  hard-coding the Frontmatter default — asserted the same way, on real post-run `ggen.toml`
  content and real generated files, not on which internal function was called.
- A **negative case**: a scratch fixture whose `ggen sync run` (or a gate ticket 04 checks)
  is made to fail for real (e.g. an intentionally malformed pack reference in the bundle
  merge, or a real gate script exit-code failure) asserts the task reports failure — via
  `Igniter.add_issue/2`'s real issue text, or a non-zero exit if invoked as a subprocess —
  and that it does **not** write a `ggen.toml` claiming the bundle was successfully installed;
  this is the acceptance evidence for the fail-loud requirement above, not merely a
  code-review claim that the logic looks fail-closed.
- **Chicago-style testing discipline, per this repo's own `~/ggen_igniter/CLAUDE.md`
  (Chicago-school only: real collaborators — real files, real subprocesses, real SPARQL —
  never `Mock`/`mock(`/`patch(`/`monkeypatch`) and per the shared
  `~/.claude/rules/testing-chicago-style.md`** discipline both this repo and beam4pm follow:
  the new test file(s) added by this ticket use zero test doubles for any collaborator this
  repo owns or that is realistically runnable in-process/locally (the scratch fixture's
  `ggen.toml`, the real `SchemaDispatch`/`ProjectConfig`/`PackManifest` modules, and the real
  `ggen sync run` subprocess invocation via ticket 04's runner are all real). Definition of
  done for this ticket explicitly includes running:

  ```sh
  grep -rn "Mock\|mock(\|patch(\|monkeypatch" test/ggen_igniter_fortune5_ready_task_test.exs
  ```

  and confirming **zero matches**. If any future maintainer believes a specific collaborator
  in this test genuinely cannot be run for real (the only candidate under discussion at
  ticket-authoring time is `ggen sync run` itself when the real `ggen` binary is unavailable
  in a given CI environment — not a reason to mock it outright, but a reason for a named,
  visible `@tag :skip`/`ExUnit.Case`-level skip guarded by a real binary-availability probe,
  the same degrade-to-named-skip pattern `~/.claude/rules/testing-chicago-style.md`'s worked
  example uses for an unavailable local model server), that exception must be named explicitly
  in the test module's own `@moduledoc`/comment per that rule's "one legitimate use" criteria
  — a silent mock substitution is not an acceptable resolution and does not close this ticket.
- `mix test test/ggen_igniter_fortune5_ready_task_test.exs` is run for real and its actual
  output (not a remembered prior run) is pasted into the PR/commit closing this ticket, per
  this repo's own `CLAUDE.md` Commands section precedent (`mix test`, and `mix
  ggen_igniter.doctor` re-run afterward if the task touches doctor-relevant config surface).
- `mix ggen_igniter.fortune5_ready --help` prints real usage text (matching
  `install.ex`'s `print_help_and_halt/0` precedent) and exits zero, run for real as evidence,
  not asserted from the source alone.

## Explicitly out of scope for this ticket

- The real `~/beam4pm` trial — `~/ggen/docs/jira/v26.9.1/06-BEAM4PM-TRIAL-AND-GATE-M2-PREREQUISITE.md`
  owns running this task against the actual beam4pm repo and its real `ggen.toml`/gate suite
  (`scripts/gate_m2_check.sh` et al.). This ticket's fixture is a scratch project deliberately
  shaped like beam4pm's `ggen.toml` (per the resolved schema-dispatch finding) — it is not
  beam4pm itself, and passing this ticket's acceptance does not close ticket 06.
- The two upstream pack-portability fixes (`fortune5-required-capabilities-pack`'s hardcoded
  `../../../../crates/ggen-marketplace` path; `fortune5-testing-bblock-pack`'s
  `crates/ggen-cli`/`target/debug/ggen` self-detection), tracked in the source epic
  (`~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md`) as blocking dependencies
  of the whole epic, not as work this ticket performs.

## See Also

- `~/ggen_igniter/docs/v26.9.1-requirements.md` — the **other**, unrelated v26.9.1 work
  stream in this same repo (process-mining/OCEL manufacturing-pack expansion: incremental DFG
  discovery, sensor-to-event streaming, inductive-miner discovery, token-replay conformance,
  OCEL2/EKG derivation, OLAP slice/dice, Chicago-style OTP fault injection). Shares this
  milestone's version number only by coincidence of timing — not the same epic, not the same
  code paths.
- `~/ggen/docs/jira/v26.9.1/05-FORTUNE5-READY-BUNDLE-INSTALLER.md` — the source epic
  (`GGEN-1801`–`GGEN-1807`) this ticket's story numbering maps 1:1 against; this ticket is
  `GGEN-1807`'s ggen_igniter-side implementation detail.
- `~/ggen/docs/jira/v26.9.1/06-BEAM4PM-TRIAL-AND-GATE-M2-PREREQUISITE.md` — the downstream
  ticket that runs this task against the real beam4pm repo; explicitly out of scope here.
- `~/ggen_igniter/lib/mix/tasks/ggen_igniter.install.ex` — the real precedent this task's
  pipeline shape and defensive-probe pattern are modeled on.
- `~/ggen_igniter/CLAUDE.md` — this repo's pipeline shape (`Ontology.load!/1` ->
  `Engine.run/2` -> `Render.render/2` -> `Actuate.write_file!/3`), reconciliation-manifest
  discipline, and Chicago-school testing discipline cited above.
- `~/.claude/rules/testing-chicago-style.md` — the shared (beam4pm + ggen_igniter) testing
  discipline this ticket's Definition of Done is scoped against.
- `~/beam4pm/docs/jira/v26.8.31/04-jira-epics-stories-acceptance.md` — the epic/story/
  acceptance-bullet format this document follows (exact subject, acceptance behavior,
  evidence; compilation or existence alone is not a crown).
