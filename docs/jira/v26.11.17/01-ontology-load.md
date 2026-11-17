# Ontology Load Exploration (Lane 01)

Standing: UNVERIFIED

Scope: `GgenIgniter.Ontology.load!/1`, Turtle parsing, prefix handling. Read-only static
pass; `mix`/`elixir` are not on PATH and `deps/` is absent in this checkout, so nothing
below was executed. Every row is a source read (`file:line`), never a run. The module is
19 lines: extension dispatch to `rdf` readers with Turtle as fallback. Main risks found:
the declared `Graph | Dataset` return reaches callers that only accept `Graph`, errors are
not normalized, and prefix/base-IRI handling is delegated entirely to `rdf` with no test.

## Findings

Paths are under `lib/` unless prefixed `test/` or `docs/`; `ontology.ex` is
`lib/ggen_igniter/ontology.ex`. All rows are static reads, none executed.

| id | finding | standing | evidence |
|---|---|---|---|
| F01 | Dispatch by `Path.extname`: .nt, .nq, else Turtle | UNVERIFIED | ontology.ex:13-17 |
| F02 | Dispatch is case-sensitive: `.NT` goes to Turtle | UNVERIFIED | ontology.ex:13-17 |
| F03 | `.nq` gives Dataset; `Oxigraph.run` matches only Graph (FunctionClauseError) | UNVERIFIED | query/oxigraph.ex:112-113,128-129; sync.ex:1241,1414 |
| F04 | Only shacl task merges Dataset to Graph; others pass it raw | UNVERIFIED | shacl.ex:126-133; pack_frontmatter/sync.ex:99 |
| F05 | Graph re-serialized to Turtle per query; source prefixes not kept | UNVERIFIED | query/oxigraph.ex:129-131 |
| F06 | No `base_iri:` or prefix map passed to any reader | UNVERIFIED | ontology.ex:14-16; grep `base_iri` no hits |
| F07 | .trig/.jsonld/.rdf/.n3 fall to Turtle, fail as parse error | UNVERIFIED | ontology.ex:3-8 |
| F08 | 4 tests: ttl, nt, nq, unknown ext raises RuntimeError | UNVERIFIED | test/ggen_igniter_ontology_multiformat_test.exs:14,29,53,78 |
| F09 | Untested: missing/empty/malformed file, bad prefix, @base, .NT | UNVERIFIED | absence in F08 test names |
| F10 | assert_raise pins `rdf` exception type; rdf pinned `~> 3.0` | UNVERIFIED | multiformat_test.exs:~66; mix.exs:174 |
| F11 | Callers differ: shacl rescues, semantic_work_order propagates | UNVERIFIED | shacl.ex:134-135; semantic_work_order.ex:33 |
| F12 | Missing file: only pack_frontmatter checks exists; load! does not | UNVERIFIED | pack_frontmatter/sync.ex:96-99 |
| F13 | status.md says IMPLEMENTED, 4 tests; not re-run this pass | UNVERIFIED | docs/status.md:149 |
| F14 | Toolchain absent: no `deps/`, `which mix elixir` empty | UNVERIFIED | commands `ls deps`, `which mix elixir` |
| F15 | Fixtures exist: sample.nt, .nq, .unknownext, sample-pack/ | UNVERIFIED | `ls test/fixtures` output |

## Next

1. Install toolchain (`mix deps.get`), run the multiformat test file, and move F08, F13
   off UNVERIFIED.
2. Add falsifiers: missing path, malformed `.ttl`, undeclared prefix, `@base` relative IRI,
   uppercase `.NT`.
3. Decide contract for `.nq` Dataset on the sync path (merge to Graph in `load!` or refuse
   with a typed error); run one adversarial `.nq` ontology through `Oxigraph.run` to confirm F03.
4. Normalize `load!` errors to one typed exception, or document the `rdf` exception set.
5. Document supported extensions in `docs/reference/cli/` and add a refusal for unknown ones.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/status.md`
- `lib/ggen_igniter/ontology.ex`
- `test/ggen_igniter_ontology_multiformat_test.exs`
