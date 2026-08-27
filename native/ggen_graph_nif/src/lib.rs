//! Rustler NIF wrapping a real, native `OxigraphEngine`. The `QueryEngine` trait and
//! `OxigraphEngine` were originally sourced from `~/ggen/crates/ggen-graph-wasm` but are
//! now vendored directly into this crate (see `query_engine.rs` and `oxigraph_engine.rs`)
//! so this package has no path dependency outside its own directory, which is required
//! to publish to hex.pm. `RemoteEngine` (the wasm32-safe path) is out of scope here: its
//! `query()` is a real `todo!()` stub with a disclosed sync/async architecture blocker --
//! that is separate, still-in-progress work on the WASM side, not something this native
//! NIF can or should route around.

mod oxigraph_engine;
mod query_engine;

use oxigraph_engine::OxigraphEngine;
use query_engine::QueryEngine;
use rustler::{Encoder, Env, NifResult, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
    }
}

/// Shared result-encoding step for both NIF query functions below: turns a
/// `Result<Vec<Row>, String>` into the real `{:ok, [map()]} | {:error,
/// String.t()}` term both `query_turtle` and `query_turtle_raw` return,
/// exactly once, so the two functions differ only in which engine method
/// they call.
fn encode_query_outcome<'a>(
    env: Env<'a>,
    outcome: Result<Vec<query_engine::Row>, String>,
) -> NifResult<Term<'a>> {
    match outcome {
        Ok(rows) => {
            let row_maps: Vec<std::collections::HashMap<String, String>> =
                rows.into_iter().map(|row| row.into_iter().collect()).collect();
            Ok((atoms::ok(), row_maps).encode(env))
        }
        Err(reason) => Ok((atoms::error(), reason).encode(env)),
    }
}

/// Loads `turtle` into a fresh in-memory oxigraph store and runs `sparql`
/// against it, returning `{:ok, [%{binding_name => plain_value}]}` or
/// `{:error, reason_string}`. One-shot: no store is kept alive across calls
/// (mirrors `ggen_igniter`'s existing engines, which are also given the
/// whole graph per call rather than holding a long-lived connection).
///
/// Values are PLAIN and normalized (`oxigraph_engine::normalize_term`, via
/// `OxigraphEngine::query_normalized`/the `QueryEngine` trait's `query`) --
/// IRIs unwrapped (no `<...>`), literals unwrapped to their lexical value
/// (no surrounding quotes, no `^^<datatype>`/`@lang` suffix). See
/// `query_turtle_raw/2` below for the explicit opt-in that returns oxigraph's
/// original, pre-fix raw term-string shape instead.
#[rustler::nif]
fn query_turtle<'a>(env: Env<'a>, turtle: String, sparql: String) -> NifResult<Term<'a>> {
    let outcome = OxigraphEngine::from_turtle(&turtle)
        .map_err(|e| format!("oxigraph engine construction failed: {e}"))
        .and_then(|engine| {
            engine
                .query(&sparql)
                .map_err(|e| format!("oxigraph query failed: {e}"))
        });

    encode_query_outcome(env, outcome)
}

/// Same contract as `query_turtle/2`, except every value is oxigraph's
/// ORIGINAL, unprocessed N-Triples-style term string (IRIs angle-bracket-
/// wrapped, literals quoted and datatype/language-tag-suffixed) -- this
/// engine's behavior before the literal-quoting-bug fix, kept as a real,
/// explicit, documented opt-in (`GgenIgniter.Query.Oxigraph.run/3`'s
/// `raw: true`) for callers who genuinely need the datatype IRI or language
/// tag `query_turtle/2`'s plain values no longer carry inline. Nothing is
/// discarded -- this is the same real information, just no longer forced
/// onto every consumer by default.
#[rustler::nif]
fn query_turtle_raw<'a>(env: Env<'a>, turtle: String, sparql: String) -> NifResult<Term<'a>> {
    let outcome = OxigraphEngine::from_turtle(&turtle)
        .map_err(|e| format!("oxigraph engine construction failed: {e}"))
        .and_then(|engine| {
            engine
                .query_raw(&sparql)
                .map_err(|e| format!("oxigraph query failed: {e}"))
        });

    encode_query_outcome(env, outcome)
}

rustler::init!("Elixir.GgenIgniter.Native.GraphNif");
