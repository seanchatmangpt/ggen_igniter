# `native/` — Rust NIFs

## Style (match `ggen_graph_nif/src/lib.rs`)

- Module-level `//!` doc block at the top of every source file states real
  provenance: where the code was originally sourced from (e.g.
  "`~/ggen/crates/ggen-graph-wasm`") and why it's vendored rather than a path
  dependency (hex.pm publishing requires no external path deps). Never write
  a `//!` block that just restates the filename.
- Function-level `///` docs explain *why* a helper exists when it's a
  dedup/shared-step function (e.g. `encode_query_outcome`'s doc explains it
  exists so two NIF functions differ only in which engine method they call) —
  not just what it returns.
- `mod atoms { rustler::atoms! { ... } }` pattern for Erlang atom encoding —
  keep new atoms in this same block, don't scatter `rustler::atoms!` calls.
- A stubbed/incomplete path gets a real `todo!()` with a doc comment naming
  the actual blocker (see the `RemoteEngine`/wasm32 sync-async note) — never
  a silent placeholder or a `todo!()` with no explanation.

## Structural rule

- One crate per NIF under `native/<crate_name>/`, `crate-type = ["cdylib"]`,
  `publish = false` in `Cargo.toml` (the NIF itself isn't published; only the
  Elixir package wrapping it is).
- No path dependencies to anything outside the crate's own directory — vendor
  the source in instead (as `oxigraph_engine.rs`/`query_engine.rs` are
  vendored from `ggen-graph-wasm`) so `mix deps.get`/hex publishing never
  needs access to a sibling repo.
- `target/` is a build artifact directory — never hand-edit or commit files
  under it; it should already be gitignored.

## Verification

Rust changes here are exercised indirectly through `mix compile` (which
compiles the NIF as part of compiling the Elixir library) and directly via
`mix test test/*oxigraph*` — run both, not just `cargo build`, since a NIF
that compiles in isolation can still fail at the Elixir<->Rust boundary
(atom encoding, term shape mismatches).
