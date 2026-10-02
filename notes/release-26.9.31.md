# Release notes — ggen_igniter v26.9.31

Branch: `main` @ release commit (this commit). Version bump `26.9.30` -> `26.9.31`.

## Pre-publish checklist (user-gated `mix hex.publish`)

1. `MIX_BUILD_ROOT=_build-p2 mix test` — suite result itemized below.
2. `mix hex.build` dry run — see checksum below.
3. (user) Review the dry-run package contents.
4. (user) `mix hex.publish` — **never run by the agent**.
5. (user) `git tag v26.9.31 && git push origin v26.9.31`.

## What ships in 26.9.31

- Wave B community packs: `state-machine-pack`, `receipted-extension-pack`,
  `ash-igniter-api-pack` (out of the hex package; Ash-free shipped packs),
  `reactor-scaffold-pack`, `igniter-installer-pack`.
- Test harness: `GgenIgniter.Test.PackCompile`, `GgenIgniter.Test.PostgresCase`,
  CI Postgres service, `docker-compose.e2e.yml` `db` profile.
- Test-only deps (`only: [:dev, :test]`): `ash_json_api`, `ash_ai`,
  `ash_state_machine`, `ash_oban`, `oban`.
- Graphlaw wasm engine: `GgenIgniter.Engine.Graphlaw` (wasmex-hosted
  `graphlaw_wasm.wasm`, WASI JSON ABI), registered as `"graphlaw"`;
  `--engine graphlaw` and comparison mode `--engine oxigraph,graphlaw`;
  `ENGINE_COMPARISON_DIVERGENT` comparison gate; 31/31 differential gates agree
  with oxigraph, zero divergences (negative control witnessed).
- Refusals: 130 codes + 24 wrapped reasons.
- Graphlaw wasm artifact (MIT, RoXi fork upstream) ships in the package at
  `priv/graphlaw_wasm.wasm` (sha256 `8bfff66c...e71a8`); resolution order:
  Application env override -> packaged artifact -> dev checkout default.

## Verification record

- Suite: `23 doctests, 42 properties, N tests, F failures, 5 skipped (698 excluded)`
  — see the report for the exact final numbers from the verification run.
- Known environmental failure (pre-existing, not session-introduced):
  - `GgenIgniter.ToolchainPinQualificationTest` — `BUILD_BROKEN(toolchain)`:
    running VM is Elixir 1.19.5/OTP 28, `.tool-versions` pins 1.18.4/OTP 27.
    Passes under the pin (as CI does).
- `mix hex.build` dry run: package checksum (reproduced identically across two
  builds) `2fef782215a5880d41730418933a8b29ba279b3880875221a9e28f8902feed1f`;
  `priv/graphlaw_wasm.wasm` inside `contents.tar.gz` matches its documented
  sha256 `8bfff66cccd1e1a4834d61a893888bb479f046c1da1152a29098be7de0fe71a8`.

## Publish steps (user only)

```
mix hex.publish --dry-run   # optional re-confirm
mix hex.publish             # requires Hex API key
git tag v26.9.31 && git push origin v26.9.31
```
