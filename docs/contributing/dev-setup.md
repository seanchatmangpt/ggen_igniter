# Developer Setup

This page is for a newcomer building and testing `ggen_igniter` from a fresh clone: which
toolchain to install, why the first build is slow, which test lane to run, and how to
triage a broken build. Measured numbers come from
`docs/jira/v26.9.28/ci-runtime-errc.md`; they are from a 16-core dev machine under
variable load, not a hosted runner.

## Toolchain

- Elixir 1.18.4 (OTP 27), from `.tool-versions`.
- Erlang/OTP 27.2.4, from `.tool-versions`.
- Rust `cargo`, needed to compile `native/ggen_graph_nif`; the repo pins no Rust version.

`.tool-versions` also lists `postgres 15.2`; the fast lane does not need it for the
library itself. `mix.exs` accepts Elixir `~> 1.17` and OTP 25 or newer, and CI installs the
pinned versions. A test asserts the running VM matches the pin, so running on a different
Elixir/OTP shows a failure in that one test (environmental, not a regression).

## First build

```bash
git clone https://github.com/seanchatmangpt/ggen_igniter.git
cd ggen_igniter
mix deps.get
mix compile
mix ggen_igniter.doctor
```

Compiling this library builds the Rustler NIF `native/ggen_graph_nif` (the default
`--engine oxigraph`) whatever engine you later use. A cold compile is the slow step: CI
measured about 14 minutes cold before tests start; a warm incremental build is far
faster. `mix ggen_igniter.doctor` check 14 confirms the NIF is compiled and check 15 runs a
real SELECT against it.

## Test lanes

- **Fast (default):** `mix test` (alias `mix test.fast`). Runs everything except
  `:integration`. Measured 83 to 104 s.
- **Full:** `mix test.full`, or `GGEN_TEST_FULL=1 mix test`. Fast lane plus `:integration`.
- **Shard:** `MIX_TEST_PARTITION=2 mix test.shard --partitions 8`. One partition of the
  full suite; CI shards measured 55 to 329 s each.

Why the full suite is slow: about 480 tests are `:integration` (real `mix` and `ggen`
subprocesses, real git repos). A serial run summed to 2668 s (44.5 min), and one file,
`test/ggen_igniter_semantic_jira_pack_test.exs`, was 59% of it. `test/test_helper.exs`
excludes `:integration` unless `GGEN_TEST_FULL` is set. `--include integration` beats
any `--exclude` on a test carrying both tags, which is why CI uses `GGEN_TEST_FULL=1`
with `--exclude heavy` and `--partitions 6` (see `.github/workflows/ci.yml`).

Fast-lane counts recorded in that measurement: 20 doctests, 41 properties, 1298 tests, 5
skipped, 480 excluded. Run a single file with `mix test test/<file>_test.exs`; add
`--include integration` if that file carries the tag.

## Other tiers

- `mix e2e` runs the real downstream-consumer lifecycle
  (`test/e2e/run_e2e.exs`); it needs network and is not part of `mix test` or CI.
- The same suite in a container: see [Docker e2e](../reference/docker-e2e.md).
- Test conventions: [testing](testing.md) and `test/CLAUDE.md`.

## Before you push

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

CI also runs `mix credo` and
`mix ggen_igniter.verify --pack test/fixtures/ash_manufacture_pack --json`.

## Common failures

Start with `mix ggen_igniter.doctor` (17 checks; see
[debugging](../operations/debugging.md)). Then:

- **`GgenIgniter.Native.GraphNif.query_turtle/2 is undefined`**: the NIF `.so` is missing
  from a cached `_build`. Delete `_build/dev/lib/ggen_igniter` and
  `_build/test/lib/ggen_igniter`, then `mix compile`.
- **doctor check 14 fails**: `cargo` is missing or the NIF is stale. Install Rust; doctor
  falls back to a real `cargo build --quiet`.
- **A test fails on one seed and passes on another**: known seed-dependent flakiness.
  Re-run with `mix test --seed 777`; a failure that reproduces across seeds is real.
- **`--engine oxigraph` output has stray quote characters**: known string-binding quoting
  issue. Use `--engine sparql`.
- **Stale generated file after an ontology rename**: no cross-run orphan reconciliation
  yet, so this is expected today. See `docs/operations/failure-recovery.md`.
- **`Can't continue due to errors on dependencies`**: a consumer `mix.exs` restricts
  `igniter` or `sourceror` with `:only`. Relax it by hand, run `mix deps.get`, then
  `mix ggen_igniter.doctor --fix`.
- **`.tool-versions` or version-vs-CHANGELOG tests fail**: you run a different
  Elixir/OTP than the pin, or `mix.exs` `version:` differs from the topmost
  `CHANGELOG.md` heading. Use the pinned toolchain and keep the two equal.

## See Also

- [Contributing](../../CONTRIBUTING.md)
- [Architecture rules](architecture-rules.md)
- [Debugging](../operations/debugging.md)
- [CI runtime measurements](../jira/v26.9.28/ci-runtime-errc.md)
