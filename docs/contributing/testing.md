# Testing

## Discipline: Chicago school (real collaborators), not London school (mocks)

This codebase's tests exercise real collaborators — real files on disk, real
subprocess `mix` invocations, real SPARQL engines, real HTTP calls (network-
tagged and skippable) — and assert on real resulting state, not on "was this
function called." This was independently, adversarially verified against
this repo's actual test/lib/native trees (`.ggen_igniter_factory/ADVERSARIAL.md`,
"Test/mock discipline" table, 2026-08-27):

- **Zero real mock-library usage** (`Mock`, `mock(`, `patch(`, `monkeypatch`,
  `Mox`) anywhere in `test/`/`lib/`/`native/` — grep-swept independently by
  three separate reports; every "mock" text hit was either disclosure prose
  or a third-party vendored crate's own file, never an actual test double
  standing in for a collaborator this codebase owns.
- **8 sampled unit/property/integration test files, read in full, use only
  real collaborators** — real files, real subprocesses, real fixtures.
- **3 real mutation-testing cycles** (breaking `pack.ex`'s `query_name/1`,
  `doctor_fixes.ex`'s `check_dep_only/2`, `actuate.ex`'s `write_file!/3`
  `skip_if` handling) each caused real, name-matching test failures, and
  each was cleanly restored — proof the assertions are actually
  state-based and actually catch real breakage, not tautological.

When you add a test, follow the same discipline: exercise the real
`Ontology`/`Engine`/`Render`/`Actuate` modules (or a real `System.cmd("mix",
["ggen_igniter.sync", ...])` subprocess for CLI-level behavior) against a
real fixture file under `test/fixtures/`, and assert on the real returned
value or the real file content written to a real temp directory — never on
an interaction count against a stubbed collaborator.

## Suite layout

```
test/
├── *_test.exs                    # unit + integration tests (one process per file, sequential mix subprocess calls where needed)
├── *_properties_test.exs         # StreamData property-based tests
├── fixtures/                     # real ontologies, queries, templates used by many tests
├── e2e/
│   ├── lifecycle_test.ex         # the mix e2e suite (see below) — NOT part of plain `mix test`
│   ├── run_e2e.exs               # entry point for `mix e2e`
│   └── support/e2e_case.ex
└── test_helper.exs               # ExUnit.start/0, boots :tesla and :ggen_igniter applications first
```

Run the default suite (excludes `mix e2e`):

```
mix test
```

`test_helper.exs` starts `:tesla` and `:ggen_igniter` for real before
`ExUnit.start()` — this is why `GgenIgniter.Application`'s Finch pool is
available even to tests that never explicitly start it themselves.

## Property-based tests (`stream_data`)

Eight files use `StreamData` to generate input combinations rather than
hand-enumerating cases: `ggen_igniter_pack_properties_test.exs`,
`ggen_igniter_cross_engine_equivalence_properties_test.exs`,
`ggen_igniter_sync_properties_test.exs`, `ggen_igniter_actuate_properties_test.exs`,
`ggen_igniter_frontmatter_properties_test.exs`,
`ggen_igniter_pack_discovery_matrix_test.exs`,
`ggen_igniter_full_pipeline_properties_test.exs`,
`ggen_igniter_render_properties_test.exs`. These run under the same `mix
test` invocation as everything else; ExUnit reports their count separately
(`N doctests, M properties, K tests`).

## Known, real flakiness: `mix test` is seed-dependent (verified 2026-08-27)

`mix test`'s default random seed can produce 2 real failures (a template
compile error in `ggen_igniter_sync_pack_test.exs`, and a property-test
counterexample in `ggen_igniter_actuation_dispatch_matrix_properties_test.exs`
around `:skip_if` guard behavior) that do **not** reproduce under a
different seed (`mix test --seed 777` passes clean on the identical working
tree). Before treating a `mix test` failure as a regression you introduced:
re-run with an explicit different `--seed` first. If the same named test
fails across multiple different seeds, that is real and worth chasing —
seed-dependence alone is not evidence of a hidden bug in the code under
test, but it is evidence the test itself has an ordering/timing dependency
worth investigating separately.

Two test files were also found unformatted at the same verification pass
(`ggen_igniter_actuation_dispatch_matrix_properties_test.exs`,
`ggen_igniter_sparql_engine_test.exs`) — run `mix format` before committing
test changes.

## Network-gated and cross-repo tests

Some tests require resources not guaranteed to exist on every machine, and
are tagged so they can be explicitly excluded (or explicitly run) rather
than silently failing:

- `:requires_network` — real HTTP calls (marketplace pack fetch from GitHub/
  Hex.pm). See `test/ggen_igniter_pack_fetch_test.exs`.
- `:requires_ash_r2rml` — requires an independently-authored external
  ontology checked out at `~/ash_r2rml` on the machine running the test;
  visibly excluded when absent. See `test/ash_r2rml_gate_integration_test.exs`.

## The `mix e2e` tier — separate, not part of `mix test`, not run by CI

`mix e2e` (aliased in `mix.exs` to `run test/e2e/run_e2e.exs`) is a real,
sequential, multi-stage lifecycle test that scaffolds a genuine, throwaway
Ash+Phoenix application in a temp directory via real `mix archive.install
hex phx_new`/`hex igniter_new` + `mix igniter.new` subprocess calls (real
hex/GitHub fetches, no mocking), adds `ggen_igniter` as a `path:`
dependency, and drives it through resource creation, attribute addition, a
relationship, a custom action, a real `AshPhoenix.Form` round-trip, a real
`mix ash_phoenix.gen.live`-generated LiveView, and a rename — running `mix
compile --warnings-as-errors`/`mix test` inside the scaffolded app after
each stage, against the `test/fixtures/ash-lifecycle-pack/` fixture pack.

Run it explicitly:

```
mix e2e
```

It requires network access, takes several minutes, and uses real temp disk
space (cleaned up via `on_exit`). There is no `.github/workflows` CI config
in this repo, so it is not run by CI either — run it manually before a
release, or when changing anything that touches the Ash/Phoenix-facing
templates or the sync pipeline's interaction with a real scaffolded
project.

**Disclosed, currently-accepted limitation this suite exists to surface,
not hide**: Stage 7 (a rename in the ontology) deliberately asserts that
`mix compile --warnings-as-errors` *raises* afterward, because Stage 6's
separately-generated LiveView files still reference the now-renamed
attribute and `ggen_igniter` has no cross-file stale-reference repair — see
`docs/operations/failure-recovery.md`'s orphan-file section for the same
underlying gap from the reconciliation-manifest angle.

## Adversarial verification as a standing practice

`.ggen_igniter_factory/ADVERSARIAL.md` (synthesizing 10 independent
adversarial reports plus a capability matrix) is this project's own
standing discipline for periodically re-verifying claims against real,
freshly-run commands rather than trusting a prior pass's memory — the same
"a run, not a survey" discipline this file's testing guidance follows. When
in doubt about whether a described behavior still holds, re-run the actual
command yourself rather than citing an old report as current truth; that
document itself states explicitly which findings were re-confirmed on a
later date and which were only true at an earlier snapshot.

## See Also

- `docs/operations/debugging.md` — the same seed-flakiness and format gaps, from a triage-order angle
- `docs/contributing/architecture-rules.md` — what a new test should treat as the boundary between layers
- `test/test_helper.exs`, `test/e2e/support/e2e_case.ex` — source of record for suite setup
