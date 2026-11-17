# Lane 17: CI, e2e, and toolchain pin audit

Standing: UNVERIFIED

Read-only audit of `.github/workflows/*.yml`, the `mix e2e` alias, `.tool-versions`,
`Dockerfile.e2e`, `docker-compose.e2e.yml`, and `mix.exs` dep pins. Every finding below
was read from the file at the cited line; no workflow, container build, or `mix e2e` was
run. The main result is that the BEAM pin (Elixir 1.20.4 / OTP 29.1.2) is consistent
across `.tool-versions` and all four BEAM-using workflows, but `Dockerfile.e2e` runs a
different generation (Elixir 1.17 / OTP 25) and no workflow invokes `mix e2e`.

## Findings

| id | finding | standing | evidence |
|----|---------|----------|----------|
| F1 | `.tool-versions` pins elixir 1.20.4-otp-29, erlang 29.1.2, postgres 15.2 | UNVERIFIED | `.tool-versions:1-3` |
| F2 | `ci.yml` setup-beam pins match F1 in all 3 jobs | UNVERIFIED | `ci.yml:54-55,293-294,392-393` |
| F3 | Other BEAM workflows also use 1.20.4 / 29.1.2 | UNVERIFIED | `forbid-generated-output-dir-once.yml:20-21`; `frontier-release-plan.yml:33-34`; `gall-002-receipt.yml:32-33` |
| F4 | `forbid-generated-output-dir-once.yml` uses older action SHAs than `ci.yml` (checkout v4 `11d5960`, setup-beam v1 `0f75c29` vs v6 `d23441a`, v1.24.1 `54075bc`) | UNVERIFIED | `forbid-generated-output-dir-once.yml:14,18`; `ci.yml:38,50` |
| F5 | `rebar3-version: 3.24.0` is pinned in `ci.yml` only; not in `.tool-versions` | UNVERIFIED | `ci.yml:56` (grep for rebar in other workflows: no match) |
| F6 | `Dockerfile.e2e` base is `elixir:1.17-otp-25-slim`, not the F1 pin | UNVERIFIED | `Dockerfile.e2e:7` |
| F7 | `mix.exs` `elixir: "~> 1.17"` is the only floor; F1 pin and F6 image both satisfy it | UNVERIFIED | `mix.exs:10` |
| F8 | No workflow references `e2e`; the only hit in `.github/workflows/` is a credo comment about `test/e2e/lifecycle_test.ex` | UNVERIFIED | `grep -n e2e .github/workflows/*.yml` -> `ci.yml:151` only |
| F9 | CLAUDE.md says "mix e2e: manual only ... CI = ci.yml"; F8 is consistent with manual-only but the CI half of that sentence is ambiguous | UNVERIFIED | `CLAUDE.md` Commands block; F8 |
| F10 | `e2e` alias is `["run test/e2e/run_e2e.exs"]` | UNVERIFIED | `mix.exs:115` |
| F11 | `Dockerfile.e2e` comment says `e2e_case.ex` has a hardcoded `@ggen_igniter_path`; the file computes it with `Path.expand("../../..", __DIR__)` | UNVERIFIED | `Dockerfile.e2e:36-38` vs `test/e2e/support/e2e_case.ex:21` |
| F12 | `WORKDIR /Users/sac/ggen_igniter` and the compose bind/volume targets use a macOS home path; this is needed only if F11's premise held | UNVERIFIED | `Dockerfile.e2e:39`; `docker-compose.e2e.yml:14-20` |
| F13 | `e2e_case.ex` still mentions a `/Users/sac/.cache/tmp/...` path in a comment | UNVERIFIED | `test/e2e/support/e2e_case.ex:268` |
| F14 | Postgres: compose `postgres:15`, CI service `postgres:15`, `.tool-versions` `15.2` (minor not enforced in containers) | UNVERIFIED | `docker-compose.e2e.yml:49`; `ci.yml:238`; `.tool-versions:3` |
| F15 | No Rust toolchain pin: no `rust-toolchain*` file at root or in the crate; Cargo has only `edition = "2021"`; `ci.yml` has no rust setup step (relies on runner default); Dockerfile uses rustup default `minimal` profile, unpinned | UNVERIFIED | `ls rust-toolchain*` -> no such file; `native/ggen_graph_nif/Cargo.toml:4`; `Dockerfile.e2e:24` |
| F16 | CI installs `ggen` v26.8.28 with a pinned sha256 in two jobs (test, test-heavy); Dockerfile does not install `ggen` | UNVERIFIED | `ci.yml:~273-285`; `Dockerfile.e2e` (no ggen install) |
| F17 | `faker` is a git dep pinned to full SHA `f9d24dc2...`, `only: [:dev, :test]`; `mix.lock` records the same SHA | UNVERIFIED | `mix.exs:238-241`; `mix.lock:37` |
| F18 | `ci.yml` cache keys embed `29.1.2-1.20.4` literals, duplicating F1 in 4 places; a pin bump needs manual edits | UNVERIFIED | `ci.yml:~66,69,77,85` |
| F19 | `forbid-generated-output-dir-once.yml`, `machine-review.yml`, `risk-tier.yml` were not read in full; only grep-level facts above | UNVERIFIED | scope limit |

## Next

1. Decide whether Dockerfile.e2e should track `.tool-versions` (Elixir 1.20.4 / OTP 29) or
   stay on the documented minimum; record the decision in the Dockerfile header (F6, F7).
2. Run `docker compose -f docker-compose.e2e.yml build e2e` and `mix e2e` to move F6, F11,
   F12 from UNVERIFIED to measured; confirm whether the `/Users/sac` path is still needed.
3. Add a Rust toolchain pin (`rust-toolchain.toml`) or document runner-default reliance (F15).
4. Align `forbid-generated-output-dir-once.yml` action SHAs with `ci.yml` (F4).
5. Reword the CLAUDE.md e2e line so it states whether any CI job runs `mix e2e` (F8, F9).
6. Read the three workflows listed in F19 end to end.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/reference/docker-e2e.md` (cited by `Dockerfile.e2e:3`; not read in this lane)
- `docs/jira/v26.9.28/ci-runtime-errc.md` (cited by `ci.yml` header; not read in this lane)
- `CLAUDE.md`
