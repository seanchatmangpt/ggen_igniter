# Docker-based downstream-consumer validation (`mix e2e` in a container)

## What this validates

Whether the pipeline this repo generates code with actually works for a downstream
consumer — a real Ash+Phoenix app that adds `ggen_igniter` as a dependency and drives
`mix ggen_igniter.sync` through an 8-stage lifecycle (resource creation, attribute
add, relationships, custom action, `AshPhoenix.Form` round-trip, `ash_phoenix.gen.live`,
an attribute rename that must be mechanically detected as stale). This is the same
suite as `mix e2e` (`test/e2e/run_e2e.exs`) — this Docker wrapper does not modify or
duplicate that test logic, it runs it verbatim inside a clean, versioned container.

## Why a container variant, given `mix e2e` already exists

`mix e2e` is real (genuine `mix igniter.new`/`mix archive.install`/`mix deps.get`
subprocesses, no mocking) but depends on the *host machine* already having the right
Elixir/OTP/Rust toolchain and a clean environment. There is no `.github/workflows`
CI in this repo, so until now "does downstream consumption work" had exactly one
data point: it ran on one specific machine. The Docker variant gives a portable,
host-independent version of the same evidence — anyone with Docker can reproduce it,
and results aren't confounded by whatever else is installed on the host.

## How to run it

```
docker compose -f docker-compose.e2e.yml run --rm e2e
```

This builds `Dockerfile.e2e` (Elixir 1.17 / OTP 25 base + a minimal Rust/cargo
toolchain for the Rustler NIF build — see `native/CLAUDE.md`), bind-mounts the repo
at `/Users/sac/ggen_igniter` (matching `test/e2e/support/e2e_case.ex`'s hardcoded
`@ggen_igniter_path`, so the real, unmodified path-dependency logic resolves), and
runs `mix deps.get && mix e2e` inside the container. Exit code 0 means all 8 stages
passed; non-zero means a real failure (the script itself calls `System.halt/1` on
ExUnit failures).

## Cost and requirements

- **Network access is required** inside the container — `mix archive.install hex
  phx_new`/`igniter_new`, `mix igniter.new ... --install ash,ash_phoenix`, and
  `mix deps.get` are real Hex/GitHub fetches. There is no offline mode.
- **Several minutes** per run — same cost as bare `mix e2e` (a real Phoenix+Ash app
  is scaffolded and compiled/tested repeatedly across 8 stages).
- Not run in CI (there is none). This is a manually-invoked validation tool, the
  same operational status as `mix e2e` itself.
- Tests only the **path-dependency** consumption mode (matching `mix e2e`'s own
  scope). Real Hex-package publish/install as a distinct downstream-proof is a
  disclosed gap, not covered here.

## See Also

- `mix e2e` (top-level `README.md`, `test/e2e/run_e2e.exs`) — the underlying suite
  this wraps.
- `native/CLAUDE.md` — Rust NIF build/vendoring notes relevant to the container's
  Rust toolchain step.
- `docs/status.md` — real IMPLEMENTED/PARTIAL_ALIVE/PLANNED status this validation
  feeds evidence into.
