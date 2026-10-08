# Install E2E Report (lane w5)

Milestone v26.9.28, measured 2026-09-28. Subject: a real `mix new` consumer with
`{:ggen_igniter, path: "/Users/sac/ggen_igniter"}` plus `{:igniter, "~> 0.8"}`; Elixir 1.19.5 /
OTP 28. Test: `test/e2e/igniter_install_path_dep_test.exs` (`:integration`, `:e2e`).

## Result

Path-dep install sequence: ALIVE (offline, no network needed). `mix igniter.install ggen_igniter`
against a path dep: PARTIAL, see Finding 1.

## Commands, exit codes, elapsed (test run, HEX_OFFLINE=1 throughout)

| step | command | exit | elapsed |
|---|---|---|---|
| resolve | `mix deps.get` | 0 | 13.2 s (offline resolution succeeded; online retry not needed) |
| build | `mix compile` (whole dep tree) | 0 | 192.0 s |
| stage 1 | `mix ggen_igniter.install --yes` | 0 | 19.1 s |
| stage 2 | `mix ggen_igniter.install --yes` (rerun) | 0 | 16.5 s |
| stage 3 | `mix ggen_igniter.install --with-ash-domain --yes` | 0 | 20.8 s |

Full test: `1 test, 0 failures`, 267.1 s.

Assertions on real output files: `.formatter.exs` gains `import_deps: [... :ggen_igniter]` after
stage 1; stage 2 leaves `.formatter.exs` and `mix.exs` byte-identical and writes no
`ash_domains`; stage 3 adds `{:ash, "~> 3.0"}` to `mix.exs`, `ash_domains` with `Demo.Ash.Domain`
to `config/config.exs`, and `Demo.Ash.Domain` to `lib/demo/application.ex`.

## Finding 1: `mix igniter.install ggen_igniter` rewrites a path dep to a Hex requirement

Manual run (HEX_OFFLINE=1, exit 0, 5 m 50 s) on a consumer that already listed the path dep:

- `mix.exs` deps became `{:ash, "~> 3.0"}, {:igniter, "~> 0.8"}, {:ggen_igniter, "~> 26.0"}`;
  the path dep was replaced by an unpublished Hex requirement and `ash` was added.
- `.formatter.exs` was NOT changed (the installer's own guard skipped `import_dep` because
  `ggen_igniter` was no longer resolvable as the declared dep at install time).
- A following `mix ggen_igniter.install --yes` failed: `Unchecked dependencies ... ash ...
  run "mix deps.get"`.

Consequence: until ggen_igniter is on Hex, the supported local sequence is path dep +
`mix ggen_igniter.install`, which is what the test exercises. Once published,
`mix igniter.install ggen_igniter` should be re-measured (dry-run publish lane).

## Falsifier

Mutated the stage-1 `import_deps` assertion to require `:ggen_igniter_MUTANT`: test FAILED
(`Assertion with =~ failed`, `1 test, 1 failure`) after the real install ran; file restored,
mutant count 0, test passed before and after.

## Skip and block behaviour

Compile-time named skips: `SKIP(toolchain)` no `mix`; `SKIP(hex-cache)` no `~/.hex/packages`;
`SKIP(repo-deps)` no `deps/igniter`. If `deps.get` fails offline and again online the test fails
with `BLOCKED: <both errors>` (ExUnit cannot skip at run time).

## Cleanup

Test tmp dirs are removed in `on_exit`; the manual scratch project was under the session
scratchpad only (`w5run1`); no repo files other than the two owned paths were touched. Build
root used: `_build-w5` (untracked build output).

## Coordinator edits needed

None required. Optional: add `:e2e` to the CI exclude list if that tag is ever excluded.
