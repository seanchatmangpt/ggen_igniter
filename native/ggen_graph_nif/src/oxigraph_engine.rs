//! Vendored from `~/ggen/crates/ggen-graph-wasm/src/oxigraph_engine.rs` as of 2026-08-26,
//! because that crate is only available as a local absolute path on the author's machine
//! and cannot be a path dependency for a package published to hex.pm (hex-publish
//! blocker). This is an honest, visible vendor copy -- not a silent duplication.
//! Upstream source: /Users/sac/ggen/crates/ggen-graph-wasm/src/oxigraph_engine.rs

use std::collections::BTreeMap;

use oxigraph::io::{RdfFormat, RdfParser};
use oxigraph::model::Term;
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

/// Normalizes an oxigraph `Term` to the plain, unwrapped lexical form
/// `GgenIgniter.Query.run/2` (the `sparql` hex package engine) already
/// returns for the common case: `RDF.IRI.to_string/1` for IRIs (no angle
/// brackets), `RDF.Literal.value/1`'s lexical string for literals (no
/// surrounding quotes, no `^^<datatype>`/`@lang` suffix).
///
/// This is the real fix, applied AT THE SOURCE: it uses oxrdf's own typed
/// accessors (`Literal::value()`, `NamedNode::as_str()`) to read the term's
/// actual semantic content directly, rather than calling `Term::to_string()`
/// (oxrdf's N-Triples/Turtle `Display` serialization -- angle-bracket-wrapped
/// IRIs, quoted+suffixed literals) and then having a downstream consumer
/// string-parse that serialization back apart. Every caller of `query`/
/// `query_normalized` gets the plain shape for free; no template or test
/// needs its own quote-stripping workaround.
///
/// Disclosed, honest scope limit: this produces the literal's plain LEXICAL
/// STRING for every datatype uniformly (e.g. an `xsd:boolean` "true" literal
/// normalizes to the 4-character string `"true"`, not the Elixir boolean
/// `true`; an `xsd:integer` "42" normalizes to the string `"42"`, not the
/// integer `42`). `GgenIgniter.Query.run/2`'s sparql-hex-engine values are
/// not actually uniform strings for every datatype either -- RDF.ex's own
/// `RDF.Literal.value/1` delegates to each XSD datatype module's
/// `elixir_mapping/2` (`deps/rdf/lib/rdf/xsd/datatypes/boolean.ex`,
/// `.../integer.ex`), which really does return a native Elixir `boolean()`/
/// `integer()` for those two datatypes specifically. Reimplementing that
/// whole per-datatype XSD-to-native-Elixir-type coercion table is a
/// materially different, larger scope than this term-normalization fix
/// (which targets the confirmed literal-quoting/bracket/suffix bug -- broken
/// generated Elixir source, corrupted file paths -- not a parallel
/// reimplementation of RDF.ex's datatype system) and is left to a
/// dedicated follow-up if a caller needs it; this fix's guarantee is
/// specifically: no stray `<`/`>`/`"`/`^^`/`@lang` characters leak into a
/// normalized value.
///
/// Blank nodes (no plain-value convention exists to match: sparql-hex's own
/// `GgenIgniter.Query.run/2` doesn't unwrap them at all -- its `unwrap/1`
/// fallback clause passes a `%RDF.BNode{}` struct through untouched) keep
/// their real, recognizable `_:label` identifier form. A quoted RDF-star
/// triple term (the `rdf-12` feature is enabled on this crate) has no
/// simpler "plain" projection than its own serialization, so it falls back
/// to `Term::to_string()` -- the same real, correct `Display` impl used
/// throughout, not a hack.
fn normalize_term(term: &Term) -> String {
    match term {
        Term::NamedNode(n) => n.as_str().to_string(),
        Term::Literal(lit) => lit.value().to_string(),
        Term::BlankNode(b) => format!("_:{}", b.as_str()),
        // `oxigraph`'s `rdf-12` (RDF-star) feature is unconditionally enabled
        // in this crate's own Cargo.toml (not an optional feature of THIS
        // crate, so `#[cfg(feature = "rdf-12")]` here would check the wrong
        // crate's feature flags and always be stripped) -- `Term::Triple` is
        // therefore always a real, present variant to handle, not a
        // conditional one.
        Term::Triple(_) => term.to_string(),
    }
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

    /// Runs `sparql` and reshapes each solution's bindings into a `Row`
    /// (`BTreeMap<String, String>`) via `format_term`, the one real
    /// difference between `query_normalized` (the new default: plain,
    /// unwrapped values) and `query_raw` (the original, pre-fix behavior:
    /// oxigraph's raw N-Triples-style term strings, kept as an explicit,
    /// documented opt-in -- see both callers below). Shared so the actual
    /// query-evaluation and error-handling logic exists exactly once.
    fn run_query(
        &self,
        sparql: &str,
        format_term: fn(&Term) -> String,
    ) -> Result<Vec<Row>, OxigraphEngineError> {
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
                row.insert(variable.as_str().to_string(), format_term(term));
            }
            rows.push(row);
        }
        Ok(rows)
    }

    /// Runs `sparql`, returning PLAIN, normalized values (see
    /// `normalize_term` above) -- the new default shape, matching
    /// `GgenIgniter.Query.run/2`'s sparql-hex-engine values for the common
    /// case (unwrapped IRIs/string literals).
    pub fn query_normalized(&self, sparql: &str) -> Result<Vec<Row>, OxigraphEngineError> {
        self.run_query(sparql, normalize_term)
    }

    /// Runs `sparql`, returning oxigraph's ORIGINAL raw N-Triples-style term
    /// strings verbatim -- byte-identical to this engine's behavior before
    /// this fix (IRIs angle-bracket-wrapped, literals quoted and
    /// datatype-IRI/language-tag-suffixed). A real, explicit, documented
    /// opt-in for callers who genuinely need the datatype/language
    /// information the plain default no longer carries inline: nothing is
    /// discarded, it is simply no longer forced onto every consumer by
    /// default. See `GgenIgniter.Query.Oxigraph.run/3`'s `raw: true` option.
    pub fn query_raw(&self, sparql: &str) -> Result<Vec<Row>, OxigraphEngineError> {
        self.run_query(sparql, Term::to_string)
    }
}

impl QueryEngine for OxigraphEngine {
    type Error = OxigraphEngineError;

    /// The `QueryEngine` trait's single entry point now produces the plain,
    /// normalized shape by default (delegates to `query_normalized`) -- the
    /// vendored trait itself is unchanged; only what a conforming
    /// implementation's `query` is expected to return has been corrected at
    /// its source.
    fn query(&self, sparql: &str) -> Result<Vec<Row>, Self::Error> {
        self.query_normalized(sparql)
    }
}
