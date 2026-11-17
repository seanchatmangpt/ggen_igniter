# v26.11.17 — gate and publish dry-run receipt

Standing: PARTIAL

Coordinator-run evidence for the v26.11.17 sweep (`00-OVERVIEW.md`). The 20 lane findings
stay UNVERIFIED; this file records only what was executed.

## Environment

- Branch `claude/kind-ptolemy-imv2b6`, base `bc9117d`; host Ubuntu 24.04 x86_64, uid 0.
- Toolchain: prebuilt OTP 29.1.2 and Elixir 1.20.4-otp-29 from builds.hex.pm
  (Elixir zip sha256 checked against `builds.txt`), matching `.tool-versions`.

## Commands and results

| command | result |
|---|---|
| `mix compile --warnings-as-errors` | exit 0, NIF built in release mode (9m40s cold) |
| `mix test` | `Result: 1830/1839 passed (20/20 doctests, 41/41 properties, 1769/1778 tests), 11 skipped, 710 excluded`; exit 2, `Failed: 9 tests` |
| `mix hex.build --unpack` | version 26.11.10, 506 files, no `*.so` and no `target/` in the tarball |
| `mix hex.publish package --dry-run --yes` | built, printed "Publishing package...", exit 0, no key present |
| registry check | `hex.pm/api/packages/ggen_igniter` latest 26.10.5; `releases/26.11.10` is 404 |

## The 9 failing tests

Not baseline-compared: no prior green run exists in this container. Classification below
is a hypothesis, not a verified fact.

| # | test file | note |
|---|---|---|
| 2 | `ggen_igniter_manifest_prune_test.exs:44` | file sets read-only targets (5 chmod refs) |
| 4 | `ggen_igniter_lock_non_eexist_error_test.exs` | non-:eexist open failure; likely permission-based |
| 5 | `ggen_igniter_compensation_failure_test.exs` | real read-only target (14 refs) |
| 7 | `ggen_igniter_finalize_evidence_ordering_test.exs:123` | forced rename failure (8 refs) |
| 9 | `ggen_igniter_reconcile_reactor_test.exs:657` | expects real `File.rm` failure |
| 1 | `ggen_igniter_landing_pipeline_stages_test.exs` | RiskTier on real worktree diff; unclassified |
| 3 | `ggen_igniter_pack_lock_test.exs` | 8-writer concurrency; unclassified |
| 6 | `ggen_igniter_fortune5_ready_task_test.exs` | `--dry-run` ggen.toml check; unclassified |
| 8 | `ggen_igniter_security_gate_test.exs:64` | `Jason.DecodeError` on subprocess stdout; unclassified |

Tests 2, 4, 5, 7 and 9 are consistent with running as root (uid 0 ignores chmod); not
re-run as a non-root user, so UNVERIFIED.

## Residues

- No Hex credential exists in this container, so an authenticated dry run was not reached.
- Publishing was not performed and needs an operator grant.
- Version in `mix.exs` is still 26.11.10; this sweep did not bump it.

## See Also

- `docs/jira/v26.11.17/00-OVERVIEW.md`
- `docs/jira/v26.11.10/10-HEX-PACKAGING-AND-PUBLICATION-RUNBOOK.md`
