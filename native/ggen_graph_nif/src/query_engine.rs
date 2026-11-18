//! Owned `QueryEngine` trait + `Row` type for the Rustler NIF. Historically seeded from
//! the removed `~/ggen/crates/ggen-graph-wasm` crate (2026-08-26); kept minimal to what
//! `ggen_graph_nif` uses. See `../DRIFT.md`.

/// One SPARQL SELECT result row, reshaped to plain owned strings.
pub type Row = std::collections::BTreeMap<String, String>;

/// A pluggable SPARQL query-execution boundary. `OxigraphEngine` (in
/// `oxigraph_engine`) embeds a real oxigraph store.
pub trait QueryEngine {
    type Error: std::fmt::Debug;

    /// Runs `sparql` (a SPARQL SELECT query string) and returns its result rows.
    fn query(&self, sparql: &str) -> Result<Vec<Row>, Self::Error>;
}
