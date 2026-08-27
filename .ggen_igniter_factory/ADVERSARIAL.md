# ADVERSARIAL.md — Consolidated Adversarial Verification

Synthesis of 10 independent adversarial verification reports
(`.ggen_igniter_factory/adversarial/01`–`10`), `capability_matrix.md`, and
`version_check.md`. Every distinct claim made across all 12 source documents is
listed once below with a CONFIRMED / REFUTED / UNVERIFIABLE verdict and the real
evidence the source report(s) cited. Where two reports disagree because the repo
changed between the times they ran (concurrent-agent editing was in progress —
`capability_matrix.md` itself notes this), that history is stated explicitly rather
than silently resolved in one direction.

- Repo: `/Users/sac/ggen_igniter`
- HEAD at verification time: `767bccea32d03790a1f4975596a06ecd16df365f`
- Real `mix.exs` version: `26.8.27` (all 12 source documents independently confirm this
  same value)
- Last updated: 2026-08-27

---

## MUST FIX (REFUTED findings)

### 1. `mix test` is not unconditionally green — real, reproduced flakiness

**REFUTED** (report `05_exit_codes.md`). Default-seed run (`93665`): exit code `2`,
`12 doctests, 21 properties, 207 tests, 2 failures`:

- `test/ggen_igniter_sync_pack_test.exs:12` — the `mix ggen_igniter.sync --pack-dir`
  subprocess fails to compile a rendered template (`undefined variable "entities"`),
  so the test's own `assert exit_code == 0` fails.
- `test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs:278` — for the
  generated combo `%{mode: :file, engine: "sparql", ..., guard_variant: :skip_if}`,
  the real CLI subprocess wrote the file instead of skipping it; the expected
  `"skipped (skip_if matched): ..."` string never appeared in the captured output.

Re-run with `--seed 777`: exit `0`, `0 failures` — same working tree, same code, no
edits between runs. This is confirmed nondeterminism, not a one-off fluke: any claim
that "`mix test` passes" is only true for some seeds.

### 2. `mix format --check-formatted` fails — 2 unformatted test files

**REFUTED** (report `05_exit_codes.md`). Exit code `1`. Real output names:

- `test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs`
- `test/ggen_igniter_sparql_engine_test.exs`

Both need `mix format` applied (3 `if/do/else` expressions in the first, one
`RDF.Description.add(...)` call in the second). Neither has been run through
formatting since the last edit.

### 3. Destructive ontology evolution: no orphan-file reconciliation on rename or removal

**REFUTED** (report `09_destructive_evolution.md`, Cases 2 and 3 — real, reproduced,
not theoretical). `mix ggen_igniter.sync` has no delete/reconciliation step anywhere
in `lib/mix/tasks/ggen_igniter.sync.ex` or `lib/ggen_igniter/actuate.ex` (confirmed:
only `write_file!/3`, `inject_content!/5`, `eval_code!/2` exist; none removes a file).

- **Resource rename** (`ontology_v9_rename_resource.ttl`, `TicketResource` →
  `CaseResource`-equivalent): the newly-produced file (`case.ex`) is genuinely clean
  (0 stale `Ticket` references). But the pre-rename `ticket.ex` is never touched,
  removed, or flagged — it remains on disk with 2 real, stale references to the old
  identifier, and nothing in the sync's exit code (`0`) or notice line signals this.
- **Whole resource removal** (`ontology_v10_remove_resource.ttl`): sync exits `0`
  with a clean notice mentioning only the surviving resource. The previously-generated
  `ticket.ex` for the now-fully-removed resource is left completely untouched —
  byte-identical to its pre-removal state, 2 real matches for the retired identifier,
  fully compilable, indistinguishable from a live, ontology-backed file. Neither a
  warning nor an error surfaces this anywhere in the tool's output.

Per-run, single-file regeneration content itself is genuinely correct when it does
happen (Case 1, action removal: 0 stale references, confirmed) — the defect is
specifically the absence of any cross-run orphan detection/cleanup.

### 4. Doctor fixes 1/2 (`igniter`/`sourceror` `:only` mismatch): the live `--fix` subprocess cycle is structurally unreachable for this gap class

**REFUTED for the live-subprocess CLI path specifically** (report
`08_doctor_break_fix_noop.md`, Claim 4) — reproduced two independent ways. When a
consumer project has an `:only`-restricted `igniter`/`sourceror` dep alongside the
unconditional `{:ggen_igniter, path: ...}` dependency, Mix's own dependency resolver
refuses to run *any* task — doctor included — before
`Mix.Tasks.GgenIgniter.Doctor.igniter/1` or any of its checks ever executes:

```
Dependencies have diverged:
* igniter (Hex package)
  the :only option for dependency igniter
  ...
** (Mix) Can't continue due to errors on dependencies
```

This held both for a mismatch present from the start and for one introduced after
the project already resolved cleanly (a realistic drift scenario), without
re-running `deps.get`. This independently reproduces what
`test/ggen_igniter_doctor_fix_e2e_test.exs`'s own moduledoc already discloses.

**Nuance, not a softening**: the underlying `DoctorFixes.check_dep_only/2` /
`fix_dep_only!/2` detect/fix/no-op logic itself is CONFIRMED correct — verified by
calling it directly, in-process, against a real `mix.exs` file (list-`:only` and
atom-`:only` shapes, one option-preservation case, and a genuine no-op on re-run).
The defect is the reachability of the fix cycle via the described "live subprocess"
path for this specific gap, not the fix logic.

### 5. Requested release version does not match the repository's real version

**REFUTED** — confirmed identically by all 10 adversarial reports, `capability_matrix.md`,
and `version_check.md`. `.ggen_igniter_factory/state.json`'s `requested_version` is
`"v26.7.27"`; the real, currently-declared `mix.exs:9` value (also confirmed via a
real `mix hex.build` tarball filename) is `26.8.27` — newer, not just differently
formatted. This is not a code defect: no report found any repo-code inconsistency
caused by it, and every report explicitly declined to silently "correct" either
number. It is listed here per the instruction not to soften a REFUTED finding, but
its resolution is a release-management decision for the orchestrating
session/product-acceptance agents, not a code fix.

### 6. Historical: inject-actuation arity mismatch (`already_present_at?/4`) — real at one snapshot, refuted as a claim about current repo state

`capability_matrix.md` (timestamped ~14:2x–22:0xZ, earlier than all 10 adversarial
reports, explicitly noting "9 other agents are editing this tree concurrently right
now") found a genuine, live `CompileError`: `lib/ggen_igniter/actuate.ex` called
`already_present_at?(lines, body_lines, insert_at, insert_mode)` (4 args) against a
definition that only existed at arity 3, breaking `mix test`'s subprocess compiles
(`12 doctests, 20 properties, 177 tests, 8 failures`, 3 of them directly attributed
to this `CompileError`).

**REFUTED as a claim about the repository's current state** — every later
adversarial report that touched this code found it fixed:

- `01_edits_on_disk.md` (latest-timestamped of the 10): confirms `already_present_at?/4`
  exists with two real clauses (lines 347, 353), matching arity, no shadowing.
- `04_unreachable_stale_refs.md`: independently confirms the same, plus a full clean
  `mix compile --force --warnings-as-errors` in both `dev` and `test` envs.
- `07_idempotency.md`: exercises the exact `:before`-anchor `already_present_at?/4`
  clause via a real, direct script — 3 sequential real file injections, correct
  `:injected`/`:unchanged`/`:unchanged` outcomes, 1 (not 2) occurrence of the injected
  body in the final file.

This finding is recorded rather than dropped because it was real and load-bearing at
the time `capability_matrix.md` ran; it is not carried forward as a currently-open
defect because three later, independent reports directly contradict it with fresh
evidence against the same function.

---

## NEEDS FOLLOW-UP (UNVERIFIABLE findings)

1. **Runtime pass/fail of the 9 real `:integration`-tagged scenarios in
   `test/ggen_igniter_destructive_change_agent3_test.exs`** — UNVERIFIABLE
   (`01_edits_on_disk.md`): only compile/arity verification was performed (confirmed
   clean), not the actual runtime pass/fail of the 9 scenarios themselves (too slow
   for that pass's read-only scope). Partially addressed independently:
   `09_destructive_evolution.md` directly re-exercised 3 of the same 10 ontology
   variants (v6, v9, v10) via real `mix ggen_igniter.sync` runs outside the test
   file and found 1 of 3 REFUTED (see MUST FIX #3) — so the underlying question has
   real, unfavorable evidence for at least one variant; the test file's own 9
   assertions specifically remain unexecuted.

2. **`test/ash_r2rml_gate_integration_test.exs`'s 3 real cross-repo tests** —
   UNVERIFIABLE at execution time on this machine (`02_mutation_testing.md`): the
   test design itself is CONFIRMED real and honest (loads an independently-authored
   external ontology from `~/ash_r2rml`, tagged `:requires_ash_r2rml` with a visible
   exclude when absent; 2 of 3 tests assert a real, disclosed `sparql` 0.3.12
   `Protocol.UndefinedError`). Presence of `~/ash_r2rml` on this machine was not
   confirmed, so the tests could not actually be run this pass.

3. **Dialyzer full-project run** — CONFIRMED clean, real run executed (this pass,
   2026-08-27, HEAD `767bccea32d03790a1f4975596a06ecd16df365f`). Previously
   UNVERIFIABLE (`capability_matrix.md`: "PLT presence is not evidence of a clean
   `mix dialyzer` run — none was executed") — that gap is now closed.

   Real command: `mix dialyzer`. Real output (full, not truncated):

   ```
   Finding suitable PLTs
   Checking PLT...
   [:asn1, :compiler, :content_type, :crypto, :dcat, :dcatr, :decimal, :eex,
    :elixir, :ex_ast, :excoveralls, :finch, :foaf, :ggen_igniter, :glob_ex,
    :gno, :grax, :hpax, :igniter, :inets, :jason, :jcs, :json_ld, :kernel,
    :logger, :mime, :mint, :mix, :nimble_csv, :nimble_options, :nimble_parsec,
    :nimble_pool, :owl, :phx_new, :protocol_ex, :prov, :public_key, :rdf,
    :rdf_xml, :req, :rewrite, :rustler, :saxy, :skos, :sourceror, :sparql,
    :sparql_client, :spitfire, :ssl, :stdlib, :stream_data, :sweet_xml,
    :telemetry, :tesla, :text_diff, :toml, :tools, :uniq, :xmerl, :yamerl,
    :yaml_elixir, :yuri_template]
   PLT is up to date!
   No :ignore_warnings opt specified in mix.exs and default does not exist.

   Starting Dialyzer
   [
     check_plt: false,
     init_plt: ~c"/Users/sac/ggen_igniter/_build/dev/dialyxir_erlang-28.3.1_elixir-1.19.5_deps-dev.plt",
     files: [...],
     ...
   ]
   Total errors: 0, Skipped: 0, Unnecessary Skips: 0
   done in 0m3.31s
   done (passed successfully)
   ```

   Shell exit code: `0`. The existing PLT
   (`_build/dev/dialyxir_erlang-28.3.1_elixir-1.19.5_deps-dev.plt`, with the
   documented `plt_add_apps: [:mix]` rationale in `mix.exs`) did not need rebuilding
   — "PLT is up to date!" — and its `:mix` inclusion is confirmed still doing its
   documented job: `:mix` appears in the resolved app list above and zero
   `unknown_function`/`callback_info_missing` warnings were emitted for the two
   `Mix.Task`-based modules (`Mix.Tasks.GgenIgniter.Sync`,
   `Mix.Tasks.GgenIgniter.Doctor`) that call real Mix APIs.

   **Zero dialyzer warnings of any kind were produced** — there is nothing to
   classify as genuine-vs-false-positive; the false-positive class the
   `plt_add_apps: [:mix]` comment in `mix.exs` documents is confirmed absorbed by
   the existing PLT, not newly reappearing.

   One real, transient obstacle during this pass, disclosed for completeness: an
   initial `mix dialyzer` invocation hit a genuine `mix compile` `CompileError`
   (`undefined function doctor_fix_rule_checks/1` in
   `lib/mix/tasks/ggen_igniter.doctor.ex:111`) caused by a concurrent workflow's
   in-progress edit to that file (mid-refactor of checks 4-7 from four hand-written
   functions to a data-driven `DoctorFixes.default_rules/0` + `DoctorFixes.run_rule/3`
   engine, per `git diff` at the time). No fix was applied by this pass — a
   re-read of the file ~45 seconds later showed the concurrent edit had completed
   on its own (`doctor_fix_rule_checks/1` now defined, old functions removed), at
   which point `mix compile --warnings-as-errors` and `mix dialyzer` both ran clean
   on the first real attempt against the settled file. No code was modified by this
   verification pass, so no follow-up `mix test` run was needed per this task's own
   instructions (only required "if you changed anything").

4. **ExCoveralls test-coverage percentage** — CONFIRMED / measured 2026-08-27.
   `mix coveralls` was run for real (`mix.exs`'s configured `test_coverage: [tool:
   ExCoveralls]` invocation, matching `preferred_cli_env`'s `coveralls: :test`).
   Real result: `12 doctests, 21 properties, 209 tests, 24 failures` (finished in
   125.4s), **overall coverage `[TOTAL] 50.5%`**. The 24 test failures at
   measurement time are attributable to a concurrent workflow mid-editing
   `native/ggen_graph_nif/src/oxigraph_engine.rs` into a non-exhaustive-match
   compile error during this run (breaks the native NIF, cascading into the
   doctor-task and e2e-engine tests) — a real, disclosed condition of this specific
   run, not a hidden one.

   Complete real per-module table:

   | Coverage | File | Lines | Relevant | Missed |
   |---|---|---|---|---|
   | 88.0% | `lib/ggen_igniter/actuate.ex` | 358 | 67 | 8 |
   | 100.0% | `lib/ggen_igniter/application.ex` | 25 | 3 | 0 |
   | 80.1% | `lib/ggen_igniter/doctor_fixes.ex` | 767 | 176 | 35 |
   | 20.0% | `lib/ggen_igniter/engine.ex` | 156 | 20 | 16 |
   | 63.1% | `lib/ggen_igniter/frontmatter.ex` | 404 | 38 | 14 |
   | 0.0% | `lib/ggen_igniter/native/graph_nif.ex` | 39 | 1 | 1 |
   | 100.0% | `lib/ggen_igniter/ontology.ex` | 11 | 1 | 0 |
   | 85.8% | `lib/ggen_igniter/pack.ex` | 417 | 106 | 15 |
   | 100.0% | `lib/ggen_igniter/pack_manifest.ex` | 128 | 1 | 0 |
   | 0.0% | `lib/ggen_igniter/project_config.ex` | 249 | 0 | 0 |
   | 80.0% | `lib/ggen_igniter/query.ex` | 30 | 5 | 1 |
   | 100.0% | `lib/ggen_igniter/query/oxigraph.ex` | 143 | 4 | 0 |
   | 61.5% | `lib/ggen_igniter/query/qlever.ex` | 137 | 13 | 5 |
   | 100.0% | `lib/ggen_igniter/render.ex` | 12 | 2 | 0 |
   | 83.6% | `lib/ggen_igniter/render/tera.ex` | 314 | 92 | 15 |
   | 0.0% | `lib/ggen_igniter/write_outcome.ex` | 44 | 3 | 3 |
   | 0.0% | `lib/mix/tasks/ggen_igniter.doctor.ex` | 563 | 168 | 168 |
   | 13.2% | `lib/mix/tasks/ggen_igniter.sync.ex` | 1114 | 174 | 151 |
   | **[TOTAL]** | | | | **50.5%** |

   3 real lowest-covered modules by percentage with a non-trivial relevant-line
   count (excluding `project_config.ex`, which is `0.0%` only because it has `0`
   relevant lines under ExCoveralls' instrumentation, not because of missed
   coverage):

   1. `lib/mix/tasks/ggen_igniter.doctor.ex` — **0.0%** (168/168 relevant lines
      missed, the largest real gap in the codebase)
   2. `lib/mix/tasks/ggen_igniter.sync.ex` — **13.2%** (151/174 relevant lines
      missed)
   3. `lib/ggen_igniter/engine.ex` — **20.0%** (16/20 relevant lines missed)

   (Two other files also show `0.0%` — `lib/ggen_igniter/write_outcome.ex` (3
   relevant, 3 missed) and `lib/ggen_igniter/native/graph_nif.ex` (1 relevant, 1
   missed) — both real but too small in relevant-line count to be more significant
   than the three named above.)

5. **Full e2e lifecycle Stages 0–7** (scaffolded Ash/Phoenix app: resource/domain
   sync, relationships, custom actions, `AshPhoenix.Form`, `ash_phoenix.gen.live`,
   rename-induced compile failure) — UNVERIFIABLE / not independently re-executed
   this pass (`capability_matrix.md`; requires network + a multi-minute scaffold).
   Stage 7's own moduledoc discloses "no cross-file stale-reference repair anywhere
   in this codebase" as an accepted, documented limitation — this is corroborated,
   not contradicted, by `09_destructive_evolution.md`'s independently-reproduced
   orphan-file findings (MUST FIX #3), so Stage 7's core claim has real supporting
   evidence even though the e2e test itself was not re-run.

6. ~~**`--pack NAME:` registry-style resolution** (as distinct from `--pack-dir DIR`,
   which is heavily exercised across reports 07 and 09) — UNVERIFIABLE this pass. No
   adversarial report independently re-ran the `priv/ggen/<pack-name>/`
   name-resolution convention end to end; `capability_matrix.md` flagged the same gap
   and it was not picked up by any of the 10 domain reports.~~

   **CONFIRMED** (2026-08-27, this pass) — independently re-run end to end. Read
   `lib/ggen_igniter/pack.ex`'s real `resolve_dir!/1` in full first: with no
   `opts[:pack_dir]`, it falls through to `fetch_pack/1`, which does
   `Path.join(["priv", "ggen", name])` — the `priv/ggen/<pack-name>/` convention,
   structurally distinct from the `--pack-dir DIR` branch.

   Constructed a real throwaway pack directly under this repo (not a separate probe
   project) at `priv/ggen/adversarial-probe-pack/` with a real `ontology.ttl`
   (`probe:ProbeSpec` / `probe:moduleName` / `probe:packageName`), a real
   `gates/010_spec.rq`, and a real `templates/probe.ex.eex`. Ran the bare-name form
   (no path, no colon) as a real subprocess from the repo root:

   ```
   $ mix ggen_igniter.sync --pack adversarial-probe-pack --out tmp_out/adversarial_probe_pack.ex
   ...
   Notices:

   * ggen_igniter: wrote tmp_out/adversarial_probe_pack.ex (engine: oxigraph, 1 query, 1 total row(s))
   $ echo $?
   0
   ```

   Real written file content:

   ```elixir
   defmodule "AdversarialProbe.Generated" do
     @moduledoc "Generated by adversarial-probe-pack (priv/ggen/ convention probe) for package "adversarial_probe"."
   end
   ```

   (The quoted-literal shape is the documented oxigraph-engine row shape from this
   same task's moduledoc, not a bug in this probe.)

   To rule out any other resolution path (cache, `--pack-dir` fallback, stale prior
   run) actually being what resolved it, renamed the pack directory to
   `priv/ggen/adversarial-probe-pack-renamed/` and re-ran the identical bare-name
   command with no other change:

   ```
   $ mix ggen_igniter.sync --pack adversarial-probe-pack --out tmp_out/adversarial_probe_pack.ex
   ** (ArgumentError) --pack/--pack-dir resolved ontology not found at priv/ggen/adversarial-probe-pack/ontology.ttl
       (ggen_igniter 26.8.27) lib/mix/tasks/ggen_igniter.sync.ex:743: Mix.Tasks.GgenIgniter.Sync.resolve_ontology!/1
   $ echo $?
   1
   ```

   This confirms the resolution is genuinely and exclusively driven by
   `priv/ggen/<name>/` presence: renaming that one directory flips success (exit
   `0`) to a specific, correctly-worded failure (exit `1`) with no other change.
   Restored the directory and re-ran the original bare-name command a third time —
   exit `0` again, same notice, deterministic. Throwaway pack directory and output
   file (`priv/ggen/adversarial-probe-pack/`, `tmp_out/adversarial_probe_pack.ex`)
   were removed afterward; `priv/ggen/` now contains only its pre-existing
   `adversarial/`, `frontmatter/`, `pkgcheck/` entries, matching its state before
   this probe.

7. **`RemoteEngine`/`todo!()` reference in `native/ggen_graph_nif/src/lib.rs`'s doc
   comment** — UNVERIFIABLE as a claim about *this* repo (`03_mock_placeholder_grep.md`):
   `RemoteEngine` does not exist anywhere in this repo's own source tree (confirmed via
   grep — only the one comment line matches), so there is nothing in `ggen_igniter`
   itself to confirm or refute; the comment explicitly points at separate,
   out-of-repo/out-of-scope work. Non-blocking. What is independently CONFIRMED: this
   crate's own `query_turtle/2` implementation (the actual executable path) is
   complete, with no `todo!()`/`unimplemented!()`/stub return anywhere in it.

8. **Full failure inventory of `capability_matrix.md`'s own historical 8-failure
   `mix test` run** — only 3 of 8 failures were directly observed (truncated tail
   output); the other 5 were never inspected. Likely moot given the repo has since
   changed (see MUST FIX #6 and the flakiness in MUST FIX #1), but the original run's
   full failure set was never produced, so it is recorded as unresolved rather than
   assumed identical to either later run.

---

## Full claim ledger

### Compile / build health

| Claim | Verdict | Evidence |
|---|---|---|
| `mix compile --warnings-as-errors` (dev) exits 0, clean | CONFIRMED | 01, 02, 04, 05, 06, 08, 09 — all independent runs, only a benign `:preferred_cli_env` deprecation notice, 0 code warnings |
| `mix compile --warnings-as-errors` (test env) exits 0, clean | CONFIRMED | 01 (`MIX_ENV=test`, exit 0), 04 (forced full rebuild, exit 0) |
| `mix hex.build` succeeds, produces a real `.tar` | CONFIRMED | 05, 10 — real 72704-byte tarball, checksum printed, version `26.8.27` |
| Real built tarball contains README/LICENSE/CHANGELOG/mix.exs/lib/native source, byte-for-byte | CONFIRMED | 10 — extracted and diffed against source tree originals |
| Compiled NIF binaries (`priv/native/*.so`) correctly excluded from the package | CONFIRMED | 10 — zero `.so`/`priv/` matches in extracted tarball |
| Rustler set up for genuine compile-on-demand (no precompiled/skip-compilation override) | CONFIRMED | 10 — standard `use Rustler` invocation, no override flags found |
| `cargo tree` in `native/ggen_graph_nif` shows 0 external `path =` deps | CONFIRMED | 05, 10 — full tree output grepped, zero matches |
| `mix credo --strict` — zero error-tier findings | CONFIRMED | `capability_matrix.md` — 368 mods/funs, only advisory-tier findings (2 warnings, 7 refactor, 3 readability, 7 design suggestions) |
| 10 most-recently-modified `lib/`+`test/` files are internally consistent (no conflict markers, no truncation, no arity mismatch) | CONFIRMED | 01 — all 10 files read in full and cross-checked against real `def`s |

### Test/mock discipline

| Claim | Verdict | Evidence |
|---|---|---|
| No real mock-library usage (`Mock`, `mock(`, `patch(`, `monkeypatch`, `Mox`) in test/lib/native | CONFIRMED | 02, 03, 05 — grep sweeps; all "mock" hits are either disclosure prose or the third-party `rand` crate's own vendored `mock.rs` |
| No TODO/FIXME/unimplemented/placeholder/stub silently masquerading as complete in `lib/`+`native/src` | CONFIRMED | 03 — 6 hits, all honest disclosures (Rustler NIF idiom, disclosed optional-dep compile-time fallback, one out-of-repo pointer) |
| No hardcoded-return-value functions independent of input | CONFIRMED | 02 — 21 grep hits, all legitimate multi-clause pattern dispatch; zero single-clause bare-literal functions found |
| No tautological/always-pass test assertions | CONFIRMED | 02 — zero `assert true`/`assert 1 == 1` matches |
| 3 real mutations (pack.ex query_name, doctor_fixes.ex check_dep_only, actuate.ex write_file! skip_if) each broke, were caught by name-matching test failures, and restored cleanly | CONFIRMED | 02 — full break→fail→restore→pass cycle for each, byte-diffed restoration |
| 8 selected unit/property/integration test files use only real collaborators (real files, real subprocesses, real fixtures) | CONFIRMED | 02 — read in full; explicit absence of mocks in every file |

### Code structure / reachability

| Claim | Verdict | Evidence |
|---|---|---|
| All 4 clauses of `Sync.actuate!/8` are reachable, none shadowed | CONFIRMED | 04 — manual value-space walkthrough + compiler corroboration |
| `Actuate`'s inject-related clauses (`matches?/2`, `marker_matches?/2`, `already_present_at?/4`) have no shadowed/unreachable clauses | CONFIRMED (current state) | 04 — see MUST FIX #6 for the earlier, since-fixed contradiction |
| `Engine`'s dispatch has no clause-shadowing risk (table-based, not clause-based) | CONFIRMED | 04 |
| No stale/renamed identifier references (`run_queries("string", ...)`, `@valid_engines`, other dangling refs) | CONFIRMED | 04 — full sweep across 66 dotted `GgenIgniter.*` references |
| `GgenIgniter.WriteOutcome` module exists but is unused/unwired | CONFIRMED, disclosed | 04 — module's own moduledoc states "Not wired into `Actuate` in this pass"; not a stale reference, just unused new code |
| `GgenIgniter.Gate` is a forward-looking, not-yet-built reference | CONFIRMED, disclosed | 04 — explicit "(if/when built)" moduledoc language, not a broken reference to removed code |

### Optional dependencies / bare consumer

| Claim | Verdict | Evidence |
|---|---|---|
| Fresh `mix new` + path dep on `ggen_igniter` + `mix deps.get` succeeds | CONFIRMED | 06 — real `/tmp` probe project, exit 0, 27 resolved packages |
| `:tesla`/`:gno` absent from a bare consumer's own `mix deps.tree` | CONFIRMED | 06 — full tree reproduced, zero matches |
| Bare consumer compiles clean (`--warnings-as-errors`, exit 0) without tesla/gno | CONFIRMED | 06 — 2 independent runs incl. a `rm -rf _build` clean rebuild; Elixir 1.19 type-checker warnings present but don't fail the build |
| `--engine qlever` without `:gno` raises a clear, named `RuntimeError` (not a crash) | CONFIRMED | 06 — real `rescue e in RuntimeError` catch, actionable message |
| `--pack github:`/`hex:` fetch without `:tesla` raises a clear, named `RuntimeError` | CONFIRMED | 06 — both URL forms independently reproduced |

### Idempotency

| Claim | Verdict | Evidence |
|---|---|---|
| `mix ggen_igniter.sync` is idempotent (byte-identical output, "unchanged" notice on repeat runs) — for-each template | CONFIRMED | 07 — 3 real runs, `diff` = no output on all pairs, sha256 recorded |
| Same, single-row (non-for-each) template | CONFIRMED | 07 — 3 real runs, `diff` = no output on all pairs |
| `Actuate.inject_content!/5`'s `:before`-anchor fix genuinely prevents duplicate injection on repeat | CONFIRMED | 07 — direct real-file script, 3 sequential calls, exactly 1 occurrence of injected body after all 3 |

### Doctor break/fix/no-op

| Claim | Verdict | Evidence |
|---|---|---|
| Doctor check 6 (`dcatr` env config) detects and fixes live via a real `--fix` subprocess | CONFIRMED | 08 |
| Doctor check 7 (Ash domain registration) detects and fixes live via a real `--fix` subprocess | CONFIRMED | 08 |
| Second/third `--fix` run is a genuine no-op for checks 6/7 (byte-identical output) | CONFIRMED | 08 — diffed run 2 vs. run 3 |
| Doctor fixes 1/2 (`igniter`/`sourceror` `:only`) — underlying detect/fix logic is correct | CONFIRMED (direct in-process calls) | 08 — see MUST FIX #4 for the live-subprocess-path caveat |
| Doctor fixes 1/2 — reachable via the live `mix ggen_igniter.doctor --fix` subprocess cycle | REFUTED for that path | 08 — see MUST FIX #4 |
| `check_git_status` never fails the aggregate doctor run by itself (`:warn`, not `:error`) | CONFIRMED, disclosed in-line | 01, 08 |

### Destructive ontology evolution

| Claim | Verdict | Evidence |
|---|---|---|
| Action removal: regenerated file has 0 stale references to the removed action | CONFIRMED | 09 (Case 1) |
| Resource rename: the newly-produced file is clean (0 stale references) | CONFIRMED | 09 (Case 2) |
| Resource rename: old file is cleanly reconciled/removed | REFUTED | 09 (Case 2) — see MUST FIX #3 |
| Whole resource removal: 0 stale references after removal (clean reconciliation) | REFUTED | 09 (Case 3) — see MUST FIX #3 |

### Release/version framing

| Claim | Verdict | Evidence |
|---|---|---|
| Requested release version (`v26.7.27`) matches real `mix.exs` version | REFUTED | All 10 adversarial reports, `capability_matrix.md`, `version_check.md` — real value is `26.8.27` |

---

## Verdict

**This repository is not, right now, ALIVE.** Zero REFUTED findings is the bar, and
this pass has six: `mix test` fails outright at its own default random seed (only
passing under a hand-picked alternate seed); `mix format --check-formatted` fails on
two files; a resource rename or removal in the source ontology leaves a fully-formed,
fully-compilable, silently-stale generated file on disk with no warning of any kind;
one class of `doctor --fix` self-repair (the `igniter`/`sourceror` dependency-only
mismatch) can never actually run through its intended live-CLI path because Mix's own
dependency resolver blocks the whole task first; and the requested release version
does not match what `mix.exs` actually declares. A sixth, historical finding — an
inject-actuation arity bug that genuinely broke compilation at one point during
concurrent editing — has since been independently re-verified as fixed by three later
reports, so it is not counted as a currently-open defect, but it is recorded rather
than erased. Against that, the reports also establish a large amount of real,
independently-verified strength: clean compiles under `--warnings-as-errors` in both
dev and test environments, zero mock-library usage anywhere in the codebase, three
real mutation-testing cycles that all caught their intended breakage, a genuinely
isolated optional-dependency story for `tesla`/`gno` proven from a from-scratch bare
consumer project, real idempotency for both file-write and inject actuation paths, and
a hex-buildable package that ships real source and correctly excludes compiled
binaries. None of that offsets the REFUTED items above, and per instruction none of
it is used to soften them — the correct standing name for a repository with this
profile (real strengths, plus concrete, reproduced, currently-open defects, some of
which touch its own release-integrity and CI-greenness) is **PARTIAL**, not ALIVE.
