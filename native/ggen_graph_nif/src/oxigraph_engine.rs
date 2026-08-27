//! Vendored from `~/ggen/crates/ggen-graph-wasm/src/oxigraph_engine.rs` as of 2026-08-26,
//! because that crate is only available as a local absolute path on the author's machine
//! and cannot be a path dependency for a package published to hex.pm (hex-publish
//! blocker). This is an honest, visible vendor copy -- not a silent duplication.
//! Upstream source: /Users/sac/ggen/crates/ggen-graph-wasm/src/oxigraph_engine.rs

use std::collections::BTreeMap;

use oxigraph::io::{RdfFormat, RdfParser};
use oxigraph::sparql::{QueryEvaluationError, QueryResults, SparqlEvaluator};
use oxigraph::store::{LoaderError, Store, StorageError};

use crate::query_engine::{QueryEngine, Row};

#[derive(Debug)]
pub enum OxigraphEngineError {
    Storage(StorageError),
    Load(LoaderError),
    Evaluation(QueryEvaluationError),
    NotSelectQuery,
}

impl std::fmt::Display for OxigraphEngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Storage(e) => write!(f, "oxigraph storage error: {e}"),
            Self::Load(e) => write!(f, "oxigraph load error: {e}"),
            Self::Evaluation(e) => write!(f, "oxigraph evaluation error: {e}"),
            Self::NotSelectQuery => write!(f, "query must be a SPARQL SELECT to yield rows"),
        }
    }
}

impl std::error::Error for OxigraphEngineError {}

/// Embeds a real, in-memory oxigraph `Store` -- the same construction shape
/// `ggen-graph`'s `check_sparql`/`shacl::solutions` already use.
pub struct OxigraphEngine {
    store: Store,
}

impl OxigraphEngine {
    /// Creates a fresh in-memory store and loads `turtle` into it.
    pub fn from_turtle(turtle: &str) -> Result<Self, OxigraphEngineError> {
        let store = Store::new().map_err(OxigraphEngineError::Storage)?;
        store
            .load_from_reader(RdfParser::from_format(RdfFormat::Turtle), turtle.as_bytes())
            .map_err(OxigraphEngineError::Load)?;
        Ok(Self { store })
    }
}

impl QueryEngine for OxigraphEngine {
    type Error = OxigraphEngineError;

    fn query(&self, sparql: &str) -> Result<Vec<Row>, Self::Error> {
        let results = SparqlEvaluator::new()
            .parse_query(sparql)
            .map_err(|e| OxigraphEngineError::Evaluation(e.into()))?
            .on_store(&self.store)
            .execute()
            .map_err(OxigraphEngineError::Evaluation)?;

        let QueryResults::Solutions(solutions) = results else {
            return Err(OxigraphEngineError::NotSelectQuery);
        };

        let mut rows = Vec::new();
        for solution in solutions {
            let solution = solution.map_err(OxigraphEngineError::Evaluation)?;
            let mut row: Row = BTreeMap::new();
            for (variable, term) in solution.iter() {
                row.insert(variable.as_str().to_string(), term.to_string());
            }
            rows.push(row);
        }
        Ok(rows)
    }
}
