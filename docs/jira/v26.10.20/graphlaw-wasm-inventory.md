# GraphLaw WASM Artifact Inventory

Measured: 2026-10-20, read-only lane over the local machine. All shas are real
`shasum -a 256` output; manifests read from disk.

## Summary

There are TWO distinct GraphLaw WASM artifacts on this machine, two separate
provenance chains, and three consumer repos. They must not be conflated.

| artifact | file | sha256 (16) | size | version | ABI |
|---|---|---|---|---| MANIFEST |
| A: vendored praxis-graphlaw-wasm | `~/ash_a2a/priv/graphlaw/praxis_graphlaw.wasm` | `187688d9e7e33a57` | 3,249,361 B | praxis-graphlaw v26.7.5 | wasm-bindgen exports (`graph_hash`, `blake3_hex`, `run_hooks`, `validate_all`), imports `./praxis_graphlaw_wasm_bg.js::__wbindgen_*` |
| B: ash_graphlaw release wasm | `~/ash_graphlaw/priv/graphlaw/graphlaw.wasm` | `7bb2a7e5ebcef758` | 6,641,876 B | graphlaw 26.9.29 | WASI (`wasi_snapshot_preview1`: fd_write, random_get, clock_time_get, ...); exports `gl_alloc`/`gl_call`/`gl_free` |

## Chain A: praxis-graphlaw-wasm (wasm-bindgen, wasmex/wasmtime)

Provenance: crates `praxis-graphlaw` + `praxis-graphlaw-wasm` v26.7.5, built
2026-07-08 23:31Z with wasm-pack 0.13.1, target `wasm32-unknown-unknown`,
wasm-bindgen bundler target. No local source: `~/praxis` consumes
`praxis-graphlaw` as a **git dependency**
(`https://github.com/seanchatmangpt/graphlaw` rev `f5781cc`, version req 26.7.9,
`~/praxis/Cargo.toml:128`), so `~/praxis/crates/praxis-graphlaw-wasm/` holds no
`Cargo.toml` — only the wasm-pack output `pkg/` (mtime Jul 8 16:31).

- `~/praxis/crates/praxis-graphlaw-wasm/pkg/praxis_graphlaw_wasm_bg.wasm` —
  sha256 `187688d9…` — **byte-identical to the ash_a2a vendored copy** (same
  3,249,361 bytes, same hash).
- `~/ash_a2a/priv/graphlaw/praxis_graphlaw.wasm` — vendored 2026-09-16
  (RFC-SA2A-001 v26.9.16 S12/S27/S79); source_path recorded in
  `WASMEX_HOST_MANIFEST.json` as the pkg path above.
- Build provenance is INFERRED, per the manifest's own honesty note: praxis git
  sha `bf96ea56d4055b5accd3f5124e559805f6502e2f` derived from mtime bracket
  [bf96ea5 15:47, 7765777 17:40] on 2026-07-08; rustc/wasm-pack versions of the
  original build NOT recorded. A pinned-SHA rebuild (rustc 1.97.0,
  wasm-bindgen 0.2.126) is **semantically equivalent but not byte-reproducible**
  (3,248,401 B, sha256 `0582d595…`). Rebuild at praxis HEAD (c78783b, 2026-09-27)
  is BLOCKED: E0599 oxigraph `Store::open` at
  `crates/praxis-graphlaw/src/chatman/engine.rs:597` (patch on file:
  `~/ash_a2a/priv/graphlaw/defects/praxis-head-wasm32-overlay.patch`).
- Self-reported version: `graphlaw_version()` = `praxis-graphlaw v26.7.5`.

### Hosts (runtime: wasmex ~> 0.15.1 over wasmtime)

- `AshA2A.GraphLaw.WasmexHost` (`~/ash_a2a/lib/ash_a2a/graph_law/wasmex_host.ex`),
  declared in `~/ash_a2a/mix.exs:522` `{:wasmex, "~> 0.15.1"}`.
- Node .mjs verification drivers, all Sep 30 14:07:45 2026:
  `~/ash_a2a/priv/graphlaw/{graphlaw_host.mjs, graphlaw_host_peer.mjs,
  graphlaw_host_probe.mjs, graphlaw_driver.mjs, graphlaw_invoke.mjs,
  host/graphlaw_host.mjs}`. Conformance vectors
  (`conformance_vectors.json`, suite `sa2a-portable-semantic-execution/v26.9.16`,
  9 vectors, produced by wasmtime 48.0.3 / graphlaw_host 0.1.0, pinned to wasm
  sha `187688d9…`) last verified 2026-09-16.

## Chain B: ash_graphlaw release wasm (WASI, gl_* ABI)

Provenance: **not a local build** — a pinned GitHub release asset,
`https://github.com/seanchatmangpt/graphlaw/releases/download/v26.9.29/graphlaw.wasm`,
sha256 `7bb2a7e5…` pinned in
`~/ash_graphlaw/priv/graphlaw/MANIFEST.json` (schema
`ash_graphlaw.graphlaw.manifest/v1`, abi_version 1) and by ontology.ttl.
`~/ash_graphlaw/mix.exs` is not checked here; the repo is the hex source for
`{:ash_graphlaw, "~> 26.10"}` consumed by ash_a2a (`~/ash_a2a/mix.exs:347`).

- Consumers: smalt consumes ash_graphlaw as a **path dep**
  (`{:ash_graphlaw, path: "../ash_graphlaw", only: :dev, optional: true}`,
  `~/smalt/mix.exs:103`); engine selected at runtime by
  `Application.get_env(:smalt, :graphlaw_engine) == :ash_graphlaw`
  (`~/smalt/lib/smalt/graphlaw/validator.ex:410`), else pure-Elixir fallback.
  Other smalt wasm config: `affidavit_wasm_path`
  (`~/smalt/lib/smalt/config.ex:536-541`) — a SEPARATE artifact
  (`affidavit_wasm.wasm`, 2 copies under `_build`), not graphlaw.
- Build-artifact copies: 82 `_build-lane-*` dirs under `~/smalt` contain an
  `Elixir.AshGraphLaw.*.beam` build of ash_graphlaw (dev); verified lanes
  (c1, c14, w2a, w6z) each carry `priv/graphlaw/graphlaw.wasm` with sha
  `7bb2a7e5…` — byte-identical to the repo copy. These are **mix build
  artifacts of the path dep, not sources**; per the lane-lease cleanup law
  they are orphaned lane build roots, not canonical copies.

## Run summary

- wasmex identity pinned `~> 0.15.1` in both ash_a2a (`mix.exs:522`) and smalt
  (`mix.exs:150-152`, "graphlaw and affidavit share one wasmex identity").
- Node host driver: `host/graphlaw_host.mjs` (wasmtime 48.0.3) is the
  conformance-vector producer.
- Defect ledger: `~/ash_a2a/priv/graphlaw/defects/GL-DEFECT-001..004.json` +
  `praxis-head-refresh.json` / overlay patch.
- Fixtures: `~/ash_a2a/priv/graphlaw/fixtures/{base,mutated,reordered}.ttl`
  (canonical-order invariant: reordered == base hash).

## Drift risks (observed, not fixed)

1. Chain A is frozen at v26.7.5 with an inferred git sha; HEAD rebuild is
   blocked (oxigraph wasm32). Any wasmex consumer of `praxis_graphlaw.wasm`
   is pinned to a non-reproducible artifact.
2. Two ABI families (wasm-bindgen vs WASI/gl_*) under one "graphlaw" name;
   `AshGraphLaw` (chain B) is a different engine surface than
   `AshA2A.GraphLaw.WasmexHost` (chain A) despite shared wasmex version pin.
3. 82 orphaned `_build-lane-*` roots in smalt each embed a full ash_graphlaw
   build + wasm copy — cleanup-law exposure (disk), verified identical bytes
   so no correctness risk.
