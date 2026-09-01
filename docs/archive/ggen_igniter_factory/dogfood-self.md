# Self-Dogfood: `docs/architecture/adr/README.md`'s ADR Index Table

Real target found: `docs/architecture/adr/README.md`'s `| ADR | Title | Status |`
table (6 rows, one per `docs/architecture/adr/000N-*.md` file) was hand-maintained
markdown duplicating data already present in each ADR file (its own filename, its
`# ADR-000N: ...` H1 title, its `## Status` verdict). This is exactly the class of
repetitive, semantically-owned project structure ggen_igniter's own pack/sync
mechanism exists to generate -- so it was made the dogfood target, and actually
reconciled via a real `mix ggen_igniter.sync` invocation, not just described.

## Before

`docs/architecture/adr/README.md` (git blob `1589137`) contained a manually
authored table:

```
| ADR | Title | Status |
|---|---|---|
| [0001](0001-oxigraph-default-query-engine.md) | Oxigraph as the default SPARQL query engine | Accepted |
| [0002](0002-ash-phoenix-optional-consumer-side.md) | Ash and Phoenix remain optional, consumer-side integrations | Accepted |
| [0003](0003-plain-reactor-for-coordination.md) | Plain Reactor (not Ash.Reactor) for the target coordination pipeline | Accepted |
| [0004](0004-manifest-keyed-by-recipe-identity.md) | Reconciliation manifest keyed by `(template_path, out_template)` recipe identity | Accepted |
| [0005](0005-receipt-independent-of-manifest.md) | Receipt as an independent, append-only attempt history distinct from the Manifest | Accepted |
| [0006](0006-marker-based-injection-not-ast-patch.md) | Marker-based line splice for injection, deferring real AST-based mutation | Accepted |
```

Nothing generated this; a human (or an agent standing in for one) would need to
hand-edit this table every time an ADR was added, renamed, or re-statused, with no
mechanical link back to the real `.md` files.

## Semantic input (the pack)

New real pack at `priv/ggen/adr-index-pack/`:

- `ontology.ttl` -- 6 `adr:Decision` individuals, one per real ADR file, each with
  `adr:number`/`adr:filename`/`adr:title`/`adr:status` copied verbatim from the
  real files on disk (`number`/`filename`) and from README.md's own pre-existing
  table (`title`/`status`, cross-checked against each ADR's own H1 + `## Status`
  section -- all six are `Accepted`, confirmed by reading all six files fresh).
  This ontology is now the semantic source of truth; the README table is its
  projection, not the other way around.
- `gates/010_adrs.rq` -- `SELECT DISTINCT ?number ?filename ?title ?status`.
  Deliberately **no `ORDER BY`**: `docs/architecture/adr/0001-...md` (this
  project's own ADR-0001) documents a real, confirmed bug in the `sparql` hex
  engine (v0.3.12) where a join-shaped query with `ORDER BY` returns rows in
  reverse order. Rather than trust `ORDER BY` on either engine for this query,
  ordering is done in the template instead (`Enum.sort_by(adrs, & &1["number"])`)
  -- a real defensive choice, not an oversight.
- `templates/readme.md.eex` -- frontmatter `to: docs/architecture/adr/README.md`,
  `mode: file` (no `inject:` -- see Plan below for why). Whole-file template:
  static prose (including a new provenance note pointing back at this pack) plus
  a `<%= for row <- ... %>` loop rendering one table row per `adr:Decision`.

## Plan

Full-file generation (`mode: file`, ordinary `write_file!/3`), not
`inject: true` splice, and the choice is grounded in a real property of
`GgenIgniter.Actuate.inject_content!/5` read directly (`lib/ggen_igniter/actuate.ex`):
its idempotency check (`already_present_at?/4`) only recognizes a re-run as a
no-op when the exact same lines are *already sitting at the exact position*
this run would insert them at. If a row's title/status changes on some future
re-run, the newly rendered block no longer matches the OLD block that is
sitting right after the anchor line, so `inject_content!/5` would splice in a
SECOND, duplicate table rather than replacing the first -- append-only-if-
different semantics, not sync-in-place/replace semantics. A table that must
support real edits (title rewording, status flips, added/removed rows) needs
true replacement, which `mode: file` whole-file generation gives for real;
`inject: true` was ruled out for this specific target based on reading its
actual behavior, not assumed to work.

Engine: `--engine sparql` explicitly (not the oxigraph default), matching the
existing `ash-lifecycle-pack` fixture's precedent -- `--engine sparql` returns
plain unwrapped Elixir strings (`row["title"]` is the bare string), while the
oxigraph default returns raw N-Triples-style term strings (quoted literals,
angle-bracketed IRIs) that the template would have to unquote first. Combined
with the no-`ORDER BY` gate query above, this sidesteps the one specific,
documented `sparql`-engine defect (`ORDER BY`) while keeping the simpler
plain-string engine for everything else.

## Actuation (real command run)

```
$ mix ggen_igniter.sync --pack adr-index-pack --engine sparql --out docs/architecture/adr/README.md
ggen_igniter: wrote docs/architecture/adr/README.md (engine: sparql, 1 query, 6 total row(s))
```

Real, non-dry-run invocation against this live repo's own `docs/architecture/adr/README.md`.
A `--dry-run` preview was run first (`planned: write docs/architecture/adr/README.md`)
before the real write.

## Verification

1. **Idempotency** -- re-ran the identical command a second time:
   ```
   $ mix ggen_igniter.sync --pack adr-index-pack --engine sparql --out docs/architecture/adr/README.md
   ggen_igniter: unchanged (skipped, identical content): docs/architecture/adr/README.md (engine: sparql, 1 query, 6 total row(s))
   ```
   Confirms `Actuate.write_file!/3`'s byte-identical no-op path actually fires for
   this real recipe -- not just asserted, re-run and observed.

2. **Reconciliation manifest** -- `.ggen_igniter/manifest.json` gained a real entry
   keyed `"priv/ggen/adr-index-pack/templates/readme.md.eex=>docs/architecture/adr/README.md"`
   with the real sha256 of the written file, confirming
   `GgenIgniter.Manifest`'s recipe-identity tracking fired for this run (read
   directly from the manifest file after the run, not assumed).

3. **Docs quality gate** (`scripts/docs-gate.sh`, real run, full output):
   - Step 1 (required doc presence): PASS, all 55 files present.
   - Step 2 (internal markdown link resolution): **PASS, "Verified 179 internal
     markdown links cleanly with 0 broken links."** -- the regenerated
     `[0001](0001-oxigraph-default-query-engine.md)`-style relative links resolve
     correctly.
   - Step 3 (glossary terms): PASS, unaffected.
   - Step 4 (mix format): pre-existing WARN, unrelated to this change (fixture
     files).
   - Step 5 (mock-usage grep): pre-existing WARN (one unrelated comment string in
     `test/ggen_igniter_reactor_concurrency_test.exs`), unrelated to this change.
   - Gate summary: **"ALL DOCUMENTATION GATES PASSED CLEANLY!"**

4. **`mix compile --warnings-as-errors`** -- real run, exit code 0, no warnings
   from this change (only a pre-existing, unrelated `mix.exs` `:preferred_cli_env`
   deprecation notice from Mix itself).

5. **`mix test`** (full suite, real run):
   ```
   Finished in 150.3 seconds (3.1s async, 147.2s sync)
   12 doctests, 21 properties, 268 tests, 0 failures
   ```
   0 failures, run fresh after this change, not a memory of a prior run.

## Receipt

- Real diff actuated: `git diff --stat docs/architecture/adr/README.md` ->
  `1 file changed, 11 insertions(+)`. The 11 new lines are the provenance note
  pointing back at `priv/ggen/adr-index-pack/`; **the table's 6 data rows
  themselves are byte-identical** to what was already there before this pack took
  ownership of it -- confirming the ontology is a faithful, lossless round-trip of
  the real pre-existing content, not a rewrite that happens to look similar.
- New real files: `priv/ggen/adr-index-pack/ontology.ttl`,
  `priv/ggen/adr-index-pack/gates/010_adrs.rq`,
  `priv/ggen/adr-index-pack/templates/readme.md.eex`.
- Manifest entry: `.ggen_igniter/manifest.json`, key
  `priv/ggen/adr-index-pack/templates/readme.md.eex=>docs/architecture/adr/README.md`.
- Command to reproduce: `mix ggen_igniter.sync --pack adr-index-pack --engine sparql --out docs/architecture/adr/README.md`.

## After

`docs/architecture/adr/README.md`'s index table is no longer hand-maintained
markdown; it is a real, reconciled projection of
`priv/ggen/adr-index-pack/ontology.ttl`, generated and idempotency-verified
through ggen_igniter's own, real, current `mix ggen_igniter.sync --pack` CLI --
the tool dogfooding itself on one real, repetitive piece of its own project
structure. Adding ADR-0007+ in the future means adding one `adr:Decision`
individual to the ontology and re-running the command above, not hand-editing
the table.

## What was explicitly NOT touched (out of scope, per task)

- The `ADR-00N-*.md` files (7 files, a second/legacy ADR naming convention
  present in `docs/architecture/adr/` alongside the 6 `000N-*.md` files this
  pack indexes) were left alone -- they are not listed in README.md's table
  today either, and reconciling that naming-convention drift is a separate,
  larger docs-cleanup question outside this pass's scope (self-dogfooding one
  real repetitive structure via a real pack, not a general docs audit).
- No changes to `~/ash_r2rml`, `~/xaas`, `~/ex4pm` -- explicitly out of scope
  per task instructions.
