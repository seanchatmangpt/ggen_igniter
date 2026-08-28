# Debugging `ggen_igniter`

## Start here: `mix ggen_igniter.doctor`

**IMPLEMENTED.** `lib/mix/tasks/ggen_igniter.doctor.ex` runs a fixed
checklist of 17 real checks — no fabricated pass output. Run it bare first:

```
mix ggen_igniter.doctor
```

Add `--pack NAME` (or `--pack-dir DIR`) to also run the four pack-scoped
checks (9–12 below); add `--engine qlever --store-id ID` to also check a live
QLever endpoint; add `--hex-check` to also run the (slow) hex-publish
readiness check; add `--fix` to have checks 4–7 and 17 apply their real,
recognized fixes to the **current** project instead of only reporting them.

| # | Check | Runs when | `--fix`? |
|---|---|---|---|
| 1 | Elixir/OTP version satisfies `mix.exs`'s `~> 1.17` / OTP ≥ 25 | always | no |
| 2 | Required deps (`rdf`, `sparql`, `igniter`, `gno` if qlever) loaded, resolvable `:vsn` | always | no |
| 3 | Advisory: known `sparql` ≤ 0.3.12 `FILTER NOT EXISTS` + `BIND`-in-`UNION` bug | always | no |
| 4 | Current project's own `mix.exs` doesn't `:only`-restrict its `igniter` dep | always | **yes** |
| 5 | Same, for `sourceror` | always | **yes** |
| 6 | `config :dcatr, env: ...` present when `:gno`/`:dcatr` are in the dep tree | always | **yes** |
| 7 | Every `use Ash.Domain` module registered in `config :OTP_APP, ash_domains: [...]` | always | **yes** |
| 8 | QLever endpoint really reachable via a real `ASK` query | `--engine qlever` given | no |
| 9 | Pack `ontology.ttl` exists and parses as valid Turtle | `--pack`/`--pack-dir` given | no |
| 10 | At least one gate query (`gates/*.rq`) present | `--pack`/`--pack-dir` given | no |
| 11 | At least one template (`templates/*.{eex,tmpl}`) present | `--pack`/`--pack-dir` given | no |
| 12 | Every gate query is syntactically valid SPARQL (parse-only) | `--pack`/`--pack-dir` given | no |
| 13 | Target (cwd) git status — clean vs. dirty, advisory only | always | no |
| 14 | `native/ggen_graph_nif` compiled and up to date (falls back to real `cargo build --quiet`) | always | no |
| 15 | `GgenIgniter.Query.Oxigraph` functional smoke test (real SELECT against a real tiny graph) | always | no |
| 16 | Hex-publish readiness (`mix hex.build` + `package[:description]`/`package[:licenses]`) | `--hex-check` given | no |
| 17 | `mix.exs`'s `version:` matches `CHANGELOG.md`'s topmost `## vX` heading | always | **yes** |

Only checks 4–7 and 17 come back `:error` and fail the whole run (exit 1);
check 13 is deliberately `:warn`-only even when it can't reach git at all
(see the in-source note at `lib/mix/tasks/ggen_igniter.doctor.ex` near
`check_git_status/0` — a git-free fixture project must not fail doctor
solely for lacking a `.git` directory).

### Running `doctor` against a consumer app, not this repo

Check 14/15 resolve the `native/ggen_graph_nif` crate's real location via
`ggen_igniter_root/0`: when the current Mix project **is** `:ggen_igniter`
itself, it uses `File.cwd!()`; when running as a dependency, it resolves
`Mix.Project.deps_paths()[:ggen_igniter]` instead. This matters because a
consumer's own project root never contains `native/ggen_graph_nif` — before
this resolution existed, doctor unconditionally failed for every consumer
app on check 14.

## Known, currently-open gaps (verified 2026-08-27, not carried forward from an older claim)

These come from a real, dated adversarial verification pass
(`.ggen_igniter_factory/ADVERSARIAL.md`) that re-ran the actual commands
listed below against this repo's real disk state. Re-check before assuming
any of these are stale.

- **`mix test` is not unconditionally green — real, seed-dependent
  flakiness.** Default-seed run (seed `93665`): exit 2, 2 real failures
  (`test/ggen_igniter_sync_pack_test.exs:12` — a rendered template fails to
  compile with `undefined variable "entities"`; a `guard_variant: :skip_if`
  property case in `ggen_igniter_actuation_dispatch_matrix_properties_test.exs:278`
  where the CLI subprocess wrote instead of skipping). Re-run with `--seed
  777`: exit 0. Same working tree, no edits between runs — this is
  confirmed nondeterminism, not a one-off fluke. If you hit a failing `mix
  test`, re-run with a different `--seed` before assuming you broke
  something.
- **`mix format --check-formatted` fails on two test files** as of the same
  pass: `test/ggen_igniter_actuation_dispatch_matrix_properties_test.exs`
  and `test/ggen_igniter_sparql_engine_test.exs`. Run `mix format` before
  committing if you touch either.
- **`--engine oxigraph` (the CLI's own default) mangles string bindings** —
  literal quote characters are embedded in bound template variables
  (confirmed via a real `--dry-run` probe cited in `test/e2e/lifecycle_test.ex`'s
  own inline comment, and independently in
  `.ggen_igniter_factory/capability_matrix.md`). The project's own e2e suite
  works around this by pinning `--engine sparql` explicitly. If generated
  output has stray quote characters where a plain string was expected, this
  is the known cause — switch engines rather than debug the template.
- **No cross-run orphan-file reconciliation on ontology rename/removal** —
  see `docs/operations/failure-recovery.md`'s "Known, disclosed limitation"
  section. A stale generated file after a rename is expected today, not a
  regression you introduced.
- **`igniter`/`sourceror` `:only`-relaxation doctor fixes (checks 4/5) can be
  structurally unreachable via the live `--fix` subprocess** when a
  consumer's `mix.exs` already has a diverged `:only` restriction — Mix's
  own dependency resolver refuses to run *any* task, doctor included,
  before `mix ggen_igniter.doctor`'s own code ever executes
  (`** (Mix) Can't continue due to errors on dependencies`). The underlying
  `GgenIgniter.DoctorFixes.check_dep_only/2`/`fix_dep_only!/2` logic itself
  is correct when called directly/in-process — the defect is reachability
  through that one specific live-CLI path, not the fix logic. If you hit
  this, relax the `:only` restriction in the consumer's `mix.exs` by hand
  first, run `mix deps.get`, *then* run `mix ggen_igniter.doctor --fix` for
  the remaining checks.

## Static analysis status (last real run: 2026-08-27, HEAD `767bccea`)

- **`mix dialyzer`** — CONFIRMED clean, 0 warnings, real run (`_build/dev/dialyxir_*.plt`
  up to date). `plt_add_apps: [:mix]` in `mix.exs` is required and load-bearing:
  without it, dialyzer reports 12 false-positive `unknown_function`/
  `callback_info_missing` warnings on `Mix.Tasks.GgenIgniter.Sync`/`.Doctor`
  (both call real Mix APIs; `:mix` is excluded from the PLT by default).
- **`mix credo --strict`** — CONFIRMED clean at error-tier: 368 mods/funs, 0
  `[C]` findings; only advisory-tier (2 warnings, 7 refactor, 3 readability,
  7 design suggestions).
- **`mix coveralls`** — last measured overall: 50.5%. Lowest-covered
  non-trivial modules: `lib/mix/tasks/ggen_igniter.doctor.ex` (0.0%, the
  largest real gap), `lib/mix/tasks/ggen_igniter.sync.ex` (13.2%),
  `lib/ggen_igniter/engine.ex` (20.0%). These are real coverage gaps in the
  Mix-task layer, not evidence those tasks are untested — most of their
  exercising happens via subprocess-driven integration tests
  (`System.cmd("mix", ["ggen_igniter.sync", ...])`), which ExCoveralls does
  not attribute back to the parent process's own coverage instrumentation.

## Practical triage order for a broken build

1. `mix ggen_igniter.doctor` (bare, then with `--pack`/`--engine` as
   relevant) — catches the largest class of environment/wiring problems in
   one command, including native NIF staleness (check 14) and dependency
   `:only` conflicts (checks 4/5).
2. `mix compile --warnings-as-errors` directly — isolates whether the
   problem is this project's own code vs. a doctor-scope issue.
3. If `mix test` fails, re-run with an explicit `--seed` before assuming a
   regression (see the seed-dependent flakiness above); if a *specific*
   named test fails reproducibly across seeds, that is real.
4. If a `mix ggen_igniter.sync` run produced unexpected content, check
   which `--engine` was used — the oxigraph quote-mangling bug above is the
   most common cause of stray-quote output.
5. If a generated file looks stale after an ontology rename/removal, that
   is the disclosed orphan-file gap, not a bug to chase — see
   `docs/operations/failure-recovery.md`.
6. For a Reactor-path failure specifically, read the newest receipt line in
   `.ggen_igniter/receipts/<date>.jsonl` before re-running anything — see
   `docs/operations/failure-recovery.md`.

## See Also

- `docs/operations/runtime.md` — what actually starts and which pipeline runs
- `docs/operations/failure-recovery.md` — receipts, standings, and the orphan-file gap in full
- `docs/contributing/testing.md` — how the test suite itself is organized and run
- `lib/mix/tasks/ggen_igniter.doctor.ex`, `lib/ggen_igniter/doctor_fixes.ex` — source of record for every check/fix above
