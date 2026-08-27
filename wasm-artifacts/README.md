# `ggen-graph-wasm` build artifacts (copied, not generated here)

Copied verbatim from `~/ggen/target/wasm32-unknown-unknown/{debug,release}/ggen_graph_wasm.wasm`
on 2026-08-26, built from `~/ggen/crates/ggen-graph-wasm` (v26.8.24) via:

```
cargo build --target wasm32-unknown-unknown -p ggen-graph-wasm --no-default-features --features remote-engine        # debug
cargo build --target wasm32-unknown-unknown -p ggen-graph-wasm --no-default-features --features remote-engine --release
```

| File | Real size (bytes) | Real size |
|---|---|---|
| `ggen_graph_wasm.debug.wasm` | 16,074,277 | ≈ 15.3 MiB |
| `ggen_graph_wasm.release.wasm` | 553,699 | ≈ 541 KiB |

Both are the raw `cdylib` output of `[lib] crate-type = ["rlib", "cdylib"]`
(`ggen-graph-wasm/Cargo.toml:8`) with the `remote-engine` feature (the
`oxigraph-engine` feature is native-only and does not target `wasm32`).

**Caveat, stated plainly**: neither file is `wasm-opt`/`wasm-strip`-optimized
beyond Cargo's own `release` profile, and the crate exposes **zero**
`#[wasm_bindgen]` or `extern "C"` entry points as of this build (confirmed by
this session's own Explore agent reading `src/lib.rs`/`src/remote_engine.rs`
in full) — `RemoteEngine::query()` is a `todo!()` stub. These are real,
current build-size numbers for the crate as it stands today, not numbers for
a working, callable bundle. `ggen_igniter`'s own native integration
(`native/ggen_graph_nif/`) uses the *native* `oxigraph-engine` feature via a
Rustler NIF instead — these `wasm32` artifacts are unrelated to that path and
are kept here purely as a size reference for the separate WASM effort.
