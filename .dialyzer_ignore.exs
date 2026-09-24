# Dialyzer suppressions. Format: {file, warning_type}.
# Audit 2026-09-20: first working `mix dialyzer` run (PLT built, Erlang 28.3.1 /
# Elixir 1.19.5); 24 raw warnings, all enumerated below. None reproduces as a
# runtime failure in the test suite. Re-run `mix dialyzer` after editing.
[
  # MapSet opaque-type mismatch: dialyzer sees the concrete `%MapSet{map: ...}`
  # shape of sets built and consumed only through the MapSet API. Known
  # Erlang 28 / Elixir 1.19 opaque-type false-positive class; the sets never
  # cross an API boundary that inspects their internals.
  {"lib/ggen_igniter/manifest.ex", :call_without_opaque},
  {"lib/ggen_igniter/manifest.ex", :contract_with_opaque},
  {"lib/ggen_igniter/pending_actuation.ex", :call_without_opaque},
  {"lib/ggen_igniter/schema_dispatch.ex", :call_without_opaque},

  # `User.t/0` is declared for a struct produced by a Reactor DSL macro
  # expansion in an example-support module; dialyzer cannot see the type
  # through the expansion. Example/support code, not a shipped code path.
  {"lib/ggen_igniter/reactors/examples/support.ex", :unknown_type},

  # Defensive `:error` clauses over Igniter return values whose current
  # specs only admit `{:error, igniter}`; kept so older Igniter versions
  # inside this repo's admitted dependency range still match.
  {"lib/ggen_igniter/refactors/safe_rename.ex", :pattern_match},
  {"lib/mix/tasks/ggen_igniter.install.ex", :pattern_match},

  # SemanticJira.Shacl: rdf 3.0.1 specs narrow `RDF.Literal.datatype_id/1`
  # and description subjects to `%RDF.IRI{}`; the binary / blank-node fallback
  # clauses are kept because hand-built graphs can supply those terms.
  {"lib/ggen_igniter/semantic_jira/shacl.ex", :guard_fail},
  {"lib/ggen_igniter/semantic_jira/shacl.ex", :pattern_match_cov}
]
