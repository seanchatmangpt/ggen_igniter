---
name: run-ggen
description: Run, drive, and debug the ggen CLI (RDF/SHACL-ontology-driven code generation) -- build a manifest, run the 5-stage sync pipeline, verify output. Use when asked to run ggen, sync a ggen manifest, debug a ggen error, or generate code from an ontology.
---

`ggen` (installed at `~/.local/bin/ggen`, real version `26.8.18` as of
this writing -- **not** the same version as the source checked out at
`~/ggen` (`26.8.12`); the two have drifted, treat the installed binary
as ground truth, not the source tree) is a CLI that renders SPARQL query
results over an RDF/Turtle ontology through a Tera template into a real
output file. Everything below was run for real, this session, against
the actual installed binary -- see `smoke.sh` for the exact reproducible
sequence.

## Run (agent path) — use this first

```bash
bash ~/.claude/skills/run-ggen/smoke.sh
```

This builds a throwaway ontology + SPARQL query + Tera template in a
scratch dir, runs `ggen sync run --dry-run` then `ggen sync run` for
real, and asserts the generated file contains the expected content. Read
it top to bottom before writing your own manifest -- it's the minimal
working shape of every piece ggen needs.

## The real invocation contract (verified against v26.8.18)

- **No `--manifest` flag exists.** `ggen sync run` reads `ggen.toml`
  from its **current working directory only**. There is no way to point
  it at a manifest elsewhere. If your manifest lives somewhere other
  than the directory you want to `cd` into, stage a temporary copy:
  ```bash
  cp path/to/your-manifest.toml ggen.toml && ggen sync run && rm ggen.toml
  ```
  (Never leave that temp copy uncommitted at a project root — `rm` it
  in the same breath you create it.)
- **No `--rule` flag exists, and there is no per-rule selection at
  all.** Every `[[generation.rules]]` entry in the resolved `ggen.toml`
  renders on every `ggen sync run` invocation. If you want to run just
  one rule, it needs its own manifest file with only that rule in it
  (see `smoke.sh`'s single-rule manifest).
- **`ggen sync run` only accepts:** `--dry-run`, `--format`, `--select`,
  `--watch`, `--introspect`, `--structured-errors`, `--autonomic`. That's
  the complete flag surface — verified via `ggen sync run --help`.
- **Every `SELECT` query needs `ORDER BY`.** `strict_mode` (on by
  default) rejects any query without one at config-validation time —
  `error[E0013]`, before the pipeline even runs — not a runtime warning.
  Add `ORDER BY ?whatever` even if you don't care about row order.
- **`output_dir` and every rule's `output_file` are resolved relative to
  wherever `ggen.toml` itself lives** (which is always the cwd, per the
  point above) — not relative to the ontology/query/template files. Keep
  the whole tree (`ggen.toml`, ontology, queries, templates) under one
  directory you `cd` into.
- **`output_dir = ".."` from a subdirectory is rejected as path
  traversal** (`[FM-YIELD-002]`-style layer violation) in at least some
  manifest configurations — don't rely on parent-directory escapes; keep
  output paths inside the tree ggen.toml's directory owns.
- Successful `ggen sync run` prints a JSON summary (`written`, `skipped`,
  `graph_hash_hex`, `decisions`, `closure` — a content-hash of every
  input file) to stdout. Parse that if you're scripting around it, not
  the human-readable log lines above it (those go through `tracing` and
  can be verbose).

## Minimal manifest shape (verified working)

```toml
[project]
name = "..."
version = "1.0.0"
description = "..."
authors = ["..."]
license = "MIT"

[ontology]
source = "ontology/data.ttl"   # relative to ggen.toml's directory
standard_only = false

[generation]
output_dir = "."

[[generation.rules]]
name = "my-rule"
query = { file = "queries/extract.rq" }
template = { file = "templates/thing.tera" }
output_file = "out/thing.rs"
mode = "Overwrite"
```

Tera templates receive query results as `sparql_results` (a list of row
objects; each SPARQL `SELECT` variable becomes a field, e.g.
`row.shape`, `row.propPath`). See `~/wasm4pm-compat/ggen/templates/*.tera`
for real, larger, production-verified examples (SHACL-shape-to-Rust-struct
projection, including cardinality/optionality handling and reserved-
keyword escaping).

## Ecosystem best practices (verified via a 5-agent sweep of `~/ggen*`, not guessed)

- **Reuse a real, published, dereferenceable public RDF/OWL ontology
  wherever one exists for the domain you're modeling; author one at
  standards-submission quality (real `owl:Ontology` header, competency
  questions, `dcterms:source` citations) only where a targeted search
  confirms none exists — grounded in a real working reference
  implementation, never invented from field names alone.** This is not
  documented anywhere in the ggen ecosystem itself; it's the single
  highest-leverage discipline this session's work established. Apply it
  before authoring any new ontology.
- **Hand-authoring a local `ggen.toml` + ontology + queries + templates
  inside the consuming project is the recommended pattern, not an
  anti-pattern.** `~/ggen`'s own `examples/tpot2-wasm4pm-autoconfig`
  research explicitly labels the alternative (cross-project pack-output
  referencing without local files) "FRAGILE — NOT recommended," citing
  two real tracked bugs.
  Consuming-project layout is not universally standardized: `~/ggen`'s
  own examples put `ggen.toml` + `ontology/`/`queries/`/`templates/` at
  the project **root**; other projects (e.g. `wasm4pm-compat`) nest
  everything under a `ggen/` subdirectory instead. Either is fine —
  match whatever convention the project you're in already uses; don't
  introduce a second, parallel layout for one new feature.
- **Generated output should render as a normal, first-class sibling
  source file** (e.g. `src/foo.rs` next to hand-written `src/bar.rs`) —
  **not** into a segregated `generated/` subdirectory. The one live,
  non-archived `~/ggen` tutorial (`docs/tutorials/zero-to-generated-code.md`)
  confirms this; an archived, unconfirmed spec proposing a
  `generated_dir`/`domain_dir` split exists but nothing live implements
  it.
- **But generated files are never an independent second source of
  truth.** `~/ggen-marketplace`'s own normative rule (GGM-SRC-002):
  *"Generated files MUST NOT silently become a second source of truth
  merely because they are committed for reviewability."* If a generated
  file's content ever disagrees with what its ontology+query+template
  would currently produce, fix the source and regenerate — never
  hand-patch the generated file to make it agree.
- **Adversarially review a generation pipeline before trusting it's
  correct**, even when its own tests pass. A 20-agent adversarial review
  of one ggen-driven pipeline this session found 2 systemic template bugs
  (SHACL cardinality constraints — `sh:maxCount`, `sh:minCount` — silently
  discarded during Tera rendering) that a fully-green `cargo make test`
  run had not caught, because the tests were written against the buggy
  output rather than against the ontology's actual stated constraints.

## Gotchas (things that looked like they should work and didn't)

- Tera template syntax: chaining a filter pipeline inside a `{% set %}`
  concatenation (e.g. `{% set x = a ~ (b | filter) %}`) fails to parse —
  `Failed to parse ... expected identifier` at the exact character of
  the `(`. Fix: compute the filtered value in its own `{% set %}` first,
  then concatenate the two plain variables.
- Accessing an optional SPARQL-result field with a bare `==` comparison
  (e.g. `f.maxCount == "1"`) throws `Variable not found in context` when
  the field is absent from some rows (SPARQL `OPTIONAL` that didn't
  bind) — guard with `f.maxCount is defined and (...)` first.
- `GROUP_CONCAT(DISTINCT ?x; separator="|")` over a SPARQL `OPTIONAL`
  variable throws `NotBoundError` on rows where `?x` never binds — wrap
  with `COALESCE(?x, "")` inside the aggregate.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `unexpected argument '--manifest' found` / `'--rule' found` | Those flags don't exist on this CLI version. Use the cwd-based invocation above. |
| `error[E0013]: ... SELECT query lacks ORDER BY` | Add `ORDER BY` to the query, even a trivial one. |
| `[FM-CONFIG-003] declarative ggen.toml ... failed to parse or validate` | Read the nested error under it — it's always specific (missing ORDER BY, bad path, etc.), not a generic parse failure. |
| `Template rejected by Tera: Failed to parse ...` | Almost always a filter-chaining-inside-`{% set %}` issue — see Gotchas above. |
| `Variable X not found in context` mid-render | An `OPTIONAL`-bound SPARQL variable is absent on this row; guard with `is defined`. |
