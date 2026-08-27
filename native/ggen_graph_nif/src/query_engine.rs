//! Vendored from `~/ggen/crates/ggen-graph-wasm/src/lib.rs` (the `QueryEngine` trait and
//! `Row` type only) as of 2026-08-26, because that crate is only available as a local
//! absolute path on the author's machine and cannot be a path dependency for a package
//! published to hex.pm (hex-publish blocker). This is an honest, visible vendor copy --
//! not a silent duplication -- kept minimal to just what `ggen_graph_nif` actually uses.
//! Upstream source: /Users/sac/ggen/crates/ggen-graph-wasm/src/lib.rs

/// One SPARQL SELECT result row, reshaped to plain owned strings.
pub type Row = std::collections::BTreeMap<String, String>;

/// A pluggable SPARQL query-execution boundary. `OxigraphEngine` (in `oxigraph_engine`,
/// also vendored) embeds a real oxigraph store.
pub trait QueryEngine {
    type Error: std::fmt::Debug;

    /// Runs `sparql` (a SPARQL SELECT query string) and returns its result rows.
    fn query(&self, sparql: &str) -> Result<Vec<Row>, Self::Error>;
}
