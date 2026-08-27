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

/// Loads `turtle` into a fresh in-memory oxigraph store and runs `sparql`
/// against it, returning `{:ok, [%{binding_name => term_string}]}` or
/// `{:error, reason_string}`. One-shot: no store is kept alive across calls
/// (mirrors `ggen_igniter`'s existing engines, which are also given the
/// whole graph per call rather than holding a long-lived connection).
#[rustler::nif]
fn query_turtle<'a>(env: Env<'a>, turtle: String, sparql: String) -> NifResult<Term<'a>> {
    let outcome = OxigraphEngine::from_turtle(&turtle)
        .map_err(|e| format!("oxigraph engine construction failed: {e}"))
        .and_then(|engine| {
            engine
                .query(&sparql)
                .map_err(|e| format!("oxigraph query failed: {e}"))
        });

    match outcome {
        Ok(rows) => {
            let row_maps: Vec<std::collections::HashMap<String, String>> =
                rows.into_iter().map(|row| row.into_iter().collect()).collect();
            Ok((atoms::ok(), row_maps).encode(env))
        }
        Err(reason) => Ok((atoms::error(), reason).encode(env)),
    }
}

rustler::init!("Elixir.GgenIgniter.Native.GraphNif");
