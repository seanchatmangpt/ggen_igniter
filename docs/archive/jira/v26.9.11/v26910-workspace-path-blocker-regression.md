# Ticket 05: workspace-path-blocker in-repo regression (v26.9.10)

## Summary

Investigated the `ash_a2a`-reported `/workspace` path-resolution blocker
(GGEN-05, `docs/jira/v26.9.10/05-GGEN-SYNC-TEMPLATE-PIPELINE-BLOCKER.md`)
against `ggen_igniter`'s own source. A `grep -rn '/workspace' lib/` found
zero hardcodes, so the blocker as literally described is not reproducible
from this repo's current source. Since the session was scoped to
`~/ggen_igniter` only (no permission to touch `~/ash_a2a`), the real
`ash_a2a`-reported blocker itself was not reproduced or refuted against
`ash_a2a`'s own material this pass -- that gap is disclosed explicitly in
the ticket's Status section rather than silently dropped. In its place, a
real, checked-in, passing Chicago-style regression test was manufactured
that reproduces the general shape of the disclosed scenario (a consumer
project's own `priv/ggen/<pack>/` tree, synced via `mix ggen_igniter.sync`
from that consumer's own working directory) using small, self-contained
fixture material.

## Status

Done -- already merged/committed.

## Commits

- `72950e1` merge: ticket 05 workspace-path-blocker in-repo regression (v26.9.10)
- `12472cb` fix(ggen-05): regression fixture for consumer-cwd path resolution; disclose ash_a2a scope gap

## Changes

- Updated `docs/jira/v26.9.10/05-GGEN-SYNC-TEMPLATE-PIPELINE-BLOCKER.md`
  Status section from "PLANNED / NOT STARTED" to "PARTIAL_ALIVE", recording:
  - the real `grep -rn '/workspace' lib/` result (zero matches) showing
    every path-construction site in `lib/` uses either the raw flag value
    verbatim or `opts[:manifest_dir] || File.cwd!()`, never a fixed
    `/workspace` string.
  - an explicit scope disclosure that the real `ash_a2a`-reported blocker
    was not reproduced-or-refuted against `ash_a2a`'s own material this
    pass, with a named follow-up: run `mix ggen_igniter.sync` (or the
    equivalent `ash_a2a` command) against `~/ash_a2a`'s real
    `priv/ggen/ash_a2a/` material from `~/ash_a2a`'s own working directory,
    in a session explicitly authorized to touch that repo.
- Added `test/fixtures/consumer_cwd_pack/` -- a minimal consumer-style
  `priv/ggen/<pack>/` tree: `ontology.ttl`, `gates/010_widget.rq`,
  `templates/widget.ex.eex`.
- Added `test/ggen_igniter_consumer_cwd_pack_test.exs` (148 lines, two
  tests, real collaborators throughout -- real `File.cd!/2` to a real tmp
  dir under `System.tmp_dir!()` outside this repo's own tree, the real
  `Igniter.Mix.Task.configure_and_run/3` plumbing `mix ggen_igniter.sync`
  itself uses, the real oxigraph NIF query engine, real file I/O):
  1. `mix ggen_igniter.sync --pack-dir ...` invoked with a deliberately
     relative `--out` and no `--manifest-dir` flag, from a consumer project
     root that is not `ggen_igniter`'s own repo root, resolves the
     generated file and reconciliation manifest against that consumer's
     own real `File.cwd!()` -- proven by real `File.exists?/1` checks
     against both the correct location and two wrong ones (`ggen_igniter`'s
     own root, and a literal `/workspace`).
  2. A second identical sync run against the same consumer root is a real
     no-op re-run (the manifest file's real mtime is unchanged).
- Real finding surfaced while building the fixture: this repo's own
  `config/test.exs` defaults `use_reactor: true`, so both new tests pass
  `--verify-cwd` pointing back at `ggen_igniter`'s own root for the
  Reactor pipeline's `:verify` step -- orthogonal to what the tests
  actually prove (default `--out`/`--manifest-dir` path resolution).

## Verification

Per commit `12472cb`'s message (this session, this worktree):

- `mix compile --warnings-as-errors`: clean.
- `mix test` (full suite): 20 doctests, 42 properties, 873 tests, 8
  failures, 1 skipped (9 excluded). All 8 failures are stated as
  pre-existing and unrelated to this diff (Igniter refactor/rename-blocker
  tests, AshManufacturePack guard-inertness tests, AshInstallAlignment
  tests) -- none touch `test/fixtures/consumer_cwd_pack/` or the new test
  file. The 2 new tests in this diff both pass.
- `mix format --check-formatted`: 2 pre-existing unformatted files
  (`lib/mix/tasks/ggen_igniter.doctor.ex`,
  `test/mix/tasks/ggen_igniter.frontier_release_plan_test.exs`), neither
  touched by this diff. This diff's own files are stated as clean.
- Mock-hygiene grep (Mox/Mimic/Patch/`:meck`/mockall/MagicMock/`Mock()`):
  zero matches across `test/lib/native`.

## Related

No PR numbers stated in the commit subjects. Merge commit `72950e1` merges
`12472cb` into the branch current at merge time (merge parents `16ab254`
and `12472cb`); no branch names are named in either commit subject.
