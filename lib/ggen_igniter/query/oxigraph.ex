defmodule GgenIgniter.Query.Oxigraph do
  @moduledoc """
  Runs SPARQL queries via a real, native oxigraph engine (a Rustler NIF over
  `~/ggen/crates/ggen-graph-wasm`'s `OxigraphEngine`, `native/ggen_graph_nif`)
  instead of the pure-Elixir `sparql` hex package used by
  `GgenIgniter.Query.run/2`.

  Same `[map()]` row-list contract as `GgenIgniter.Query.run/2` and
  `GgenIgniter.Query.Qlever.run/2` -- a drop-in alternative engine, not a
  replacement API.

  Real motivation, not just "one more engine option": `GgenIgniter.Query.run/2`
  (the `sparql` 0.3.12 hex package) has a confirmed, already-pinned bug --
  it raises `Protocol.UndefinedError` on real gate queries shaped like
  `FILTER NOT EXISTS { ... }` with an unprojected variable inside a `UNION`,
  combined with `BIND` (see `test/ash_r2rml_gate_integration_test.exs`).
  Oxigraph is a full, independent SPARQL 1.1 engine -- routing that same
  query shape through this module is a real, testable way to check whether
  it resolves that blocker (see `test/ggen_igniter_oxigraph_engine_test.exs`).

  ## A third, real divergence from `GgenIgniter.Query.run/2` (confirmed)

  `GgenIgniter.Query.run/2` has no error-handling branch: it pattern-matches
  `%SPARQL.Query.Result{results: rows} = SPARQL.execute_query(graph, query)`
  unconditionally. This module, by contrast, explicitly branches on
  `{:ok, rows} | {:error, reason}` (see `run/2` below) and always raises a
  clear, named `RuntimeError`. Confirmed real consequences, proven in
  `test/ggen_igniter_ask_construct_engine_divergence_test.exs`:

  - **ASK**: `GgenIgniter.Query.run/2` does NOT return a boolean -- it
    silently returns the ASK query's WHERE-clause bindings as ordinary
    SELECT-shaped rows (a real wrong-answer divergence, not a crash). This
    module raises a clear `RuntimeError` naming why (only
    `QueryResults::Solutions` is handled; ASK's `QueryResults::Boolean` hits
    `OxigraphEngineError::NotSelectQuery`).
  - **CONSTRUCT**: `GgenIgniter.Query.run/2` raises a raw, unwrapped
    `MatchError` (the real `%RDF.Graph{}` on the wrong side of the match).
    This module raises the same clear `RuntimeError` as ASK.
  - **A malformed query**: `GgenIgniter.Query.run/2` again raises a raw
    `MatchError` against `SPARQL.execute_query/2`'s real `{:error, reason}`
    tuple. This module raises a clear `RuntimeError` naming the real reason.
  - **Bare `FILTER NOT EXISTS`** (no `UNION`, no `BIND`): `GgenIgniter.Query.run/2`
    still raises `Protocol.UndefinedError` even in this minimal shape --
    broader than the UNION+BIND-specific crash `GgenIgniter.Query.run/2`'s
    own moduledoc documents. This module evaluates it correctly.

  This module's own write-scope does not extend to fixing
  `GgenIgniter.Query.run/2` (`lib/ggen_igniter/query.ex` is a sibling file,
  not under `lib/ggen_igniter/query/`); see
  `.ggen_igniter_factory/ledger-agent5.jsonl` for the logged follow-up.

  ## Term normalization: PLAIN values by default, raw as an explicit opt-in

  Real, confirmed, already-fixed bug: this engine used to return every
  binding as oxigraph's raw N-Triples-style `Term::to_string()` serialization
  -- IRIs angle-bracket-wrapped (`<https://example.org/...>`), literals
  quoted and datatype/language-tagged (`"42"^^<http://www.w3.org/2001/XMLSchema#integer>`,
  `"hola"@es`) -- unlike `GgenIgniter.Query.run/2` (the `sparql` hex engine),
  which returns plain unwrapped values (`RDF.IRI.to_string/1`,
  `RDF.Literal.value/1`). Confirmed real consequences of the old behavior,
  pinned in `test/ggen_igniter_e2e_all_engines_test.exs` and
  `test/ggen_igniter_engine_mode_matrix_test.exs` before this fix: a
  module-name literal rendered straight into a template produced
  syntactically-invalid Elixir (`defmodule "AuditTrail.Resource" do`), and
  `--for-each`'s `<%= module_name %>`-templated output PATHS carried literal
  embedded quote characters.

  Fixed AT THE SOURCE, in the Rust NIF itself
  (`native/ggen_graph_nif/src/oxigraph_engine.rs`'s `normalize_term/1`), not
  by post-processing the NIF's string output in this Elixir wrapper: oxrdf's
  own typed accessors (`Literal::value()`, `NamedNode::as_str()`) read each
  term's real semantic content directly, so there is no string-parsing/regex
  step anywhere in this path, and no template or test needs its own
  quote-stripping workaround anymore.

  `run/2` (and `run/3` with no `raw: true`) now return these PLAIN values by
  default. The real datatype IRI and language tag are NOT silently discarded
  -- they remain available, in full, via the explicit `raw: true` opt-in
  (`run/3`), which returns oxigraph's original pre-fix raw term strings
  verbatim (the exact same shape this engine produced before this fix), for
  any caller that genuinely needs to inspect a binding's datatype/language.

  Disclosed, honest scope limit (see `normalize_term/1`'s own doc comment for
  the full reasoning): the plain default returns each literal's LEXICAL
  STRING uniformly, regardless of datatype -- an `xsd:boolean` "true" literal
  normalizes to the string `"true"`, not the Elixir boolean `true`, even
  though `GgenIgniter.Query.run/2`'s `RDF.Literal.value/1` really does return
  a native `true`/`false` (and native integers for `xsd:integer`) for those
  two datatypes specifically, via RDF.ex's own per-datatype `elixir_mapping/2`
  coercion. This fix's guarantee is that no stray `<`/`>`/`"`/`^^`/`@lang`
  wrapper syntax leaks into a value -- not a full reimplementation of RDF.ex's
  XSD-datatype-to-native-Elixir-type coercion table, which is a materially
  larger, separate scope.
  """

  alias GgenIgniter.Native.GraphNif

  @doc """
  Serializes `graph` back to Turtle (it is already fully loaded in memory by
  `GgenIgniter.Ontology.load!/1` -- no re-read from disk) and runs `query`
  against it via the native oxigraph NIF. Raises `RuntimeError` with a clear
  message on any NIF-reported error, never letting a raw `{:error, reason}`
  tuple surface uncaught (same discipline as the recent
  `GgenIgniter.Query.Qlever.run/2` bugfix).

  Returns PLAIN, normalized values by default -- see this module's own
  moduledoc ("Term normalization") for the full rationale and its one
  disclosed scope limit. Equivalent to `run(graph, query, [])`; pass
  `raw: true` (see `run/3`) for the explicit opt-in that returns oxigraph's
  original raw N-Triples-style term strings instead.
  """
  @spec run(RDF.Graph.t(), String.t()) :: [map()]
  def run(%RDF.Graph{} = graph, query) when is_binary(query) do
    run(graph, query, [])
  end

  @doc """
  Same contract as `run/2`, plus an `opts` keyword list:

    * `raw: true` -- returns oxigraph's ORIGINAL, unprocessed N-Triples-style
      term strings (IRIs angle-bracket-wrapped, literals quoted and
      datatype-IRI/language-tag-suffixed) instead of the plain, normalized
      default. A real, explicit, documented opt-in for a caller that
      genuinely needs a binding's datatype IRI or language tag -- see this
      module's moduledoc ("Term normalization") for the full rationale.
      Defaults to `false` (the plain, normalized shape).
  """
  @spec run(RDF.Graph.t(), String.t(), keyword()) :: [map()]
  def run(%RDF.Graph{} = graph, query, opts)
      when is_binary(query) and is_list(opts) do
    turtle = RDF.Turtle.write_string!(graph)

    nif_query =
      if Keyword.get(opts, :raw, false),
        do: &GraphNif.query_turtle_raw/2,
        else: &GraphNif.query_turtle/2

    case nif_query.(turtle, query) do
      {:ok, rows} -> rows
      {:error, reason} -> raise RuntimeError, message: "oxigraph engine query failed: #{reason}"
    end
  end
end
