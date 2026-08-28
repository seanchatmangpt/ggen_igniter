# `mix ggen_igniter.sync`

Source: `lib/mix/tasks/ggen_igniter.sync.ex` (`Mix.Tasks.GgenIgniter.Sync`). Status:
**IMPLEMENTED** — every flag below is a real entry in that module's
`info/2` → `%Igniter.Mix.Task.Info{schema: [...]}` (lines 185–201), cross-checked
against the moduledoc (lines 1–424) and the `igniter/1` implementation.

Pipeline: `Ontology.load!/1` → `Query`/`Engine.run/2` (once per `--query`) →
`Render.render/2` → an actuation step (`Actuate.write_file!/3`,
`Actuate.inject_content!/5`, or `Actuate.eval_code!/2`, depending on
`--mode`/`inject:`).

## Flag reference

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--ontology PATH` | string | *(required unless `--pack`/`--pack-dir`)* | Turtle file loaded via `GgenIgniter.Ontology.load!/1`. |
| `--query NAME=PATH` | string, repeatable (`:keep`) | *(none)* | One `.rq` file per flag; repeat for multiple named queries. |
| `--template PATH` | string | *(required unless `--pack`/`--pack-dir` resolves exactly one)* | EEx template; may start with a `---` frontmatter fence. |
| `--out PATH` | string | *(required for `mode: file`, unless frontmatter `to:` is set)* | An EEx template itself — rendered once per row with that row's bindings. Not used/required for `mode: eval`. |
| `--engine NAME` | string | `"oxigraph"` | One of `oxigraph`, `sparql`, `qlever` — see `engines.md`. |
| `--store-id ID` | string | *(required only when `--engine qlever`)* | Names the `gnoa:Qlever`-typed store resource in the ontology graph. |
| `--pack NAME` or `NAME:TEMPLATE` | string | *(none)* | Resolves `priv/ggen/<NAME>/` as the default ontology/queries/template source. See `packs.md`. |
| `--pack-dir DIR` | string | *(none)* | Same as `--pack` but uses `DIR` directly (no `priv/ggen/` prefix, no `:TEMPLATE` stem suffix). |
| `--for-each NAME` | string | *(none — single static `--out`)* | Fan out one render per row of the named query result; see below. |
| `--dry-run` | boolean | `false` | Preview every actuation and reconciliation decision with zero filesystem writes. |
| `--mode file\|eval` | string | `"file"` (or the template's own frontmatter `mode:`, default `"file"`) | Explicit `--mode` always overrides frontmatter. |
| `--on-stale refuse\|prune\|preserve` | string | `"refuse"` | Reconciliation-manifest stale-path policy; see below. |
| `--unless-exists` | boolean | `false` | Skip the write unconditionally if the target already exists (any content). |
| `--skip-if PATTERN` | string | `nil` | Skip the write if the existing target's content contains this substring (no regex from the CLI flag itself — see Notes). |
| `--manifest-dir DIR` | string | `File.cwd!()` | Where `.ggen_igniter/manifest.json` is read/written, and (when `--verify-cwd` is absent) the authorized-project-root boundary `GgenIgniter.ArtifactIdentity.within_root?/2` enforces against every `--out` target. |
| `--verify-cwd DIR` | string | `--manifest-dir` value, else `File.cwd!()` | Directory the Reactor pipeline's `:verify` step runs its real `mix compile --warnings-as-errors` subprocess in. Decouples verification from `--manifest-dir` for the case where the reconciliation-manifest/path-escape boundary and the actual Mix project root differ (e.g. a test writing to an isolated tmp dir outside the real project via `--manifest-dir`, while `--verify-cwd` still points at the real project so `:verify` compiles the right tree). Wired straight through to `GgenIgniter.Reactors.ReconcileReactor.run/1`'s own `:verify_cwd` opt — see that module's moduledoc, "`:verify` scope". |

## `--ontology`, `--query`, `--template`, `--out`

- `--ontology PATH` is required directly, or resolved from a pack's
  `<pack_dir>/ontology.ttl` when `--pack`/`--pack-dir` is given (an explicit
  `--ontology` always wins over the pack default).
- `--query NAME=PATH` may be repeated (schema `[:string, :keep]`); each names
  one `.rq` file. Parsed by splitting on the first `=` only
  (`parse_named_query!/1`) — a query with no `=` raises.
  Every named query's result is bound in the template as `NAME` (the full row
  list, string-keyed maps). **A query whose result is exactly one row** also
  has that row's own columns merged into the top-level, atom-keyed bindings
  (ggen's own single-row-flattening convention), so a singleton `spec` query
  lets a template write bare `<%= module_name %>` instead of
  `<%= hd(spec)["module_name"] %>`. When more than one named query is
  single-row, later `--query` flags win on key collisions in the flattened
  namespace.
- Three sources of named queries merge by ascending priority (later
  overrides same name): frontmatter inline `sparql:` block → pack
  `gates/*.rq` files → explicit `--query` flags. At least one of these three
  must supply queries or the task raises.
- `--template PATH` is required directly, or resolved from a pack's
  `templates/` directory when exactly one `*.eex`/`*.tmpl` file exists there
  (or via the `--pack NAME:TEMPLATE` stem-selection syntax — see `packs.md`).
- `--out PATH` is required for `mode: file` (directly, or via the template's
  own frontmatter `to:` field) and is itself rendered through
  `GgenIgniter.Render.render/2` using each row's bindings — so it must be a
  valid EEx template, e.g. `"lib/generated/<%= module_name %>.ex"`. Not
  required/used for `mode: eval`.

Example:

```
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex
```

## `--for-each NAME` (multi-row fan-out)

Mirrors the real Rust ggen's `for_each:` frontmatter field
(`ggen-engine/src/template.rs`'s `Frontmatter.for_each`). `NAME` must be one
of the named `--query` results (`fetch_driver_rows!/2` raises a clear error
naming the known query names if it is not). The template — and the `--out`
path template — are rendered once **per row** of that query's result, with
that row's own columns merged into the top-level bindings using the same
atom-keyed flattening convention as the single-row case, so a for-each
render's own row is referenced as bare `module_name`, never
`hd(modules)["module_name"]`.

```
mix ggen_igniter.sync \
  --ontology test/fixtures/for_each_ontology.ttl \
  --query modules=test/fixtures/modules.rq \
  --for-each modules \
  --template test/fixtures/for_each_module.ex.eex \
  --out "lib/generated/<%= module_name %>.ex"
```

Three rows (`Multi.Alpha`, `Multi.Beta`, `Multi.Gamma`) produce three separate
files. Without `--for-each`, behavior is unchanged: `--out` is one static
path, rendered and written once.

`--for-each` interacts with reconciliation (`--on-stale`): the manifest's
"new paths" set for a for-each recipe is every row's own rendered `--out`,
so a row that disappears between runs (a renamed/removed driving resource)
is exactly the case `--on-stale` is designed to catch.

## `--engine oxigraph|sparql|qlever` and `--store-id`

See `engines.md` for the full comparison (row-value shape, the `sparql` hex
package's known `ORDER BY` bug, the Rust toolchain requirement, and `qlever`'s
remote-store model). In short: `--engine oxigraph` (default) and
`--engine sparql` both evaluate every named query in-process against the
loaded `%RDF.Graph{}`; `--engine qlever` sends every query instead to a
real, already-running remote QLever SPARQL endpoint over HTTP and requires
`--store-id`, which must name a `gnoa:Qlever`-typed resource resolvable in the
`--ontology` graph (the ontology is still loaded via `Ontology.load!/1` for
this lookup — the query text itself never touches that graph's data under
`--engine qlever`).

## `--pack NAME[:TEMPLATE]` and `--pack-dir DIR`

See `packs.md` for the full directory convention, discovery rules, and the
`--pack NAME:TEMPLATE` template-disambiguation syntax. In short: given
`priv/ggen/<pack-name>/{ontology.ttl,gates/*.rq,templates/*.eex}`, `--pack
<pack-name>` supplies default `--ontology`/`--query`/`--template` values — any
explicit flag of the same kind always overrides the pack-derived default.
`--pack-dir DIR` uses `DIR` directly instead of resolving
`priv/ggen/<pack-name>/`, and does **not** accept the `:TEMPLATE` stem suffix
(pass `--template` explicitly against a multi-template pack when using
`--pack-dir`).

```
mix ggen_igniter.sync --pack audit-trail-pack --out lib/generated.ex
mix ggen_igniter.sync --pack ash-lifecycle-pack:resource --out lib/generated/resource.ex
```

## Template frontmatter (hygen/ggen parity)

If `--template`'s file starts with a `---` fence on its own first line
(leading whitespace before it means "no header", not "malformed header"),
everything between that fence and the closing `---` is parsed as YAML
frontmatter (`GgenIgniter.Frontmatter.split_template/1`), and the remainder is
the template body. A template's header supplies defaults for `to:`
(`--out`), `for_each:`, `unless_exists:`, `skip_if:` (literal-string form
only), `mode:`, and `sparql:` (named queries as inline query text, not file
paths) — so a self-contained template needs only `--template`/`--ontology`,
no repeated `--out`/`--for-each`/`--query` flags. **Any explicit CLI flag
always overrides the same-named frontmatter field.** A template with no
`---` header behaves exactly as if this feature did not exist.

## `mode: file` vs `mode: eval` (`--mode`)

`--mode` (or frontmatter `mode:` — explicit `--mode` always wins) selects
what happens to the rendered template body:

- **`mode: file`** (default) — written to disk via the guarded actuation
  path described under `inject: true` / write-safety below.
- **`mode: eval`** — the rendered body is real Elixir source, evaluated
  in-process via `GgenIgniter.Actuate.eval_code!/2` using the exact same
  bindings the template body renders with. Nothing is ever written to disk
  under this mode: `--out`/`to:` is not required, and
  `--unless-exists`/`--skip-if` do not apply (ignored). With `--for-each`,
  the eval'd body runs once per row. `--dry-run` shows `"planned: evaluate
  ..."` and evaluates nothing.

```
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/eval_mode_module.exs.eex \
  --mode eval
```

This is a deliberate, disclosed arbitrary-code-execution capability: an
ontology-driven query result becomes literally-executed Elixir code under
`mode: eval`. Threading one eval's return value into a later
query/render/write stage is **not implemented** — each named query's results
and each eval's return value are independent within a single `sync` run.

## `inject: true` (frontmatter-only — no CLI flag)

There is no `--inject` CLI flag; injection is driven entirely by a `mode:
file` template's frontmatter (`inject: true` plus exactly one of `before:`,
`after:`, or `at_line:`). When present, the rendered body is spliced into the
resolved `--out` path's **existing** content via
`GgenIgniter.Actuate.inject_content!/5` instead of being written whole via
`write_file!/3`.

- `before: "marker"` / `after: "marker"` (a literal string) — a plain
  "contains" substring match against a single line; splices immediately
  before/after that line.
- `before:`/`after:` as a structured map (`pattern:`, `matcher:`
  (`contains`/`exact`/`regex`), `case_sensitive:`, `scope:`, `occurrence:`,
  `trim:`) — converted to a marker by `match_spec_to_marker!/2`.
  `scope: "file"`, any `occurrence:` other than `"first"`, and `trim: true`
  paired with a `matcher` other than `"exact"` have **no equivalent** in
  `inject_content!/5`'s real behavior (always exactly one matched line, no
  whole-file mode, no nth-occurrence picking) — using one of these raises a
  clear, named error rather than silently proceeding as if honored.
- `at_line: N` — anchor-free: splices at the 1-based line number `N`
  (`before`/`after` must both be unset).

Exactly one anchor is required — zero or more than one raises. Injection
always requires the target file to **already exist** (fail-closed, mirroring
`inject_content!/5` itself) — it is never a substitute for file creation.
`--dry-run` previews an injection with the real anchor-resolution and
idempotency check, writing nothing (`"planned: inject PATH"` /
`"planned: skip PATH (unchanged)"`). A real run reports `"injected PATH"` or,
on an idempotent re-run, `"unchanged (skipped, identical content): PATH"` —
distinct from `write_file!/3`'s `"wrote PATH"`, since these are different
actuation paths. Injected outputs are **never** reconciliation-manifest
tracked (see `--on-stale` below) — an inject target is a pre-existing file
this pack does not own.

```
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/inject_before_marker.ex.eex \
  --out lib/existing_module.ex
```

## `--unless-exists` / `--skip-if` (write-safety guards)

Apply only to `mode: file` writes (not `inject:`, not `mode: eval`); an
explicit CLI flag overrides the same-named frontmatter field
(`unless_exists:`, literal-string `skip_if:` only — a structured frontmatter
`skip_if:` raises a clear "not yet supported" error rather than being
silently dropped). Decision order in `Actuate.write_file!/3` (first match
wins):

1. `--unless-exists` and the target exists → skip (`:skipped_exists`),
   regardless of content.
2. `--skip-if PATTERN` and the target exists and its content contains
   `PATTERN` → skip (`:skipped_match`).
3. Target exists and is byte-identical to the new content → no-op
   (`:unchanged`) — unconditional, not gated by any flag.
4. Otherwise → written (`:written`).

## `--dry-run`

Previews the exact decision every actuation path would make — write vs.
skip vs. inject vs. evaluate, and every `--on-stale` decision — with **zero**
filesystem writes and the manifest file itself never touched. Notice lines
are prefixed `"planned: "` (e.g. `"planned: write PATH"`, `"planned: skip
PATH (unchanged)"`, `"planned: inject PATH"`, `"planned: evaluate PATH (mode:
eval)"`, `"planned: prune PATH"`, `"planned: preserve N stale path(s)..."`).
A `refuse`-triggering stale set still raises even under `--dry-run` — a dry
run previews a real decision, including a real refusal, it does not suppress
one.

## `--on-stale refuse|prune|preserve` and `--manifest-dir`

Every real `mode: file`, non-`inject:` write is recorded in a reconciliation
manifest at `<manifest-dir>/.ggen_igniter/manifest.json` (default
`manifest-dir` = `File.cwd!()`), keyed by the `(template, --out-template)`
"recipe" pair. Before writing, this run's real new-output-path set is
compared against the manifest's existing entry for that recipe;
`stale = old_paths - new_paths` (paths a prior run of this exact recipe wrote
that this run does not — the mechanical signature of a rename/removal
upstream in the ontology).

- **`refuse`** (default) — if `stale` is non-empty, raises before writing
  *anything* this run (not even the non-stale outputs), naming every exact
  stale path. Re-run with `prune` or `preserve` to proceed.
- **`prune`** — proceeds with this run's writes, then really deletes
  (`File.rm/1`) every stale path, reporting each (`"pruned: PATH"` or
  `"pruned (already absent): PATH"`).
- **`preserve`** — proceeds, leaves every stale path untouched on disk,
  prints a warning naming each one, and drops them from the manifest's
  tracked output set for this recipe (this pack no longer claims ownership
  of a path it isn't producing this run).

The manifest is persisted only after this run's writes (and, for `prune`,
deletions) fully succeed — a raised exception mid-run never touches the
manifest, so it always reflects the last known-good run. A true no-op
re-run (identical output-path-plus-content-hash set) does not rewrite the
manifest file at all.

Reconciliation applies **only** to `mode: file` writes with no `inject:` —
`mode: eval` (nothing written to disk) and `inject: true` targets
(pre-existing files this pack does not own) are excluded. A path this run
only skipped (`--unless-exists`/`--skip-if`) is also excluded from the
manifest — recording it would let a later rename's `--on-stale prune` delete
a file this pack never actually wrote.

```
mix ggen_igniter.sync --pack-dir priv/ggen/ash-lifecycle-pack \
  --ontology priv/ggen/ash-lifecycle-pack/ontology.ttl \
  --template priv/ggen/ash-lifecycle-pack/templates/resource.ex.eex \
  --for-each resource \
  --out "lib/support_desk/support/<%= String.downcase(resource_name) %>.ex" \
  --on-stale prune
```

## Reactor dispatch (opt-in, `config :ggen_igniter, use_reactor`) — PARTIAL_ALIVE

There is no CLI flag for this — it is gated entirely by
`Application.get_env(:ggen_igniter, :use_reactor, false)` (default `false`).
When set `true`, `mix ggen_igniter.sync` first attempts to run through the
real `GgenIgniter.Reactors.ReconcileReactor` pipeline instead of the inline
pipeline described above; when the flag is left at its default, the inline
pipeline runs unconditionally, byte-for-byte the same as before Reactor
dispatch existed.

Reactor dispatch only ever applies within `GgenIgniter.Reconcile.run/1`'s
bounded scope: the resolved template must have **no** frontmatter header,
and `--for-each` must not be requested (by flag or frontmatter). Any call
outside that scope (`inject: true`, `mode: eval`'s frontmatter defaults,
frontmatter present at all, `--for-each` given) falls back to the exact same
inline pipeline, unconditionally — never a silent behavior change. See
`docs/reference/reactor/**` for the Reactor pipeline's own internals.

## Controller delegation (opt-in, thin-adapter mode)

Also not a CLI flag. When a `GgenIgniter.Controller` `GenServer` is already
registered under that name (`Process.whereis/1`), this run's reconciliation
is delegated to it (`Controller.reconcile/3`) instead of running the inline
pipeline directly — subject to the identical bounded-scope guard as Reactor
dispatch (no frontmatter, no `--for-each`) and a live
`function_exported?(Controller, :reconcile, 3)` guard. The delegated path's
notice line additionally reports a real, controller-only
`reconciliation_count`. One disclosed trade-off: the reconciliation
manifest (`--on-stale`/`manifest.json`) is **not** consulted or updated on
the delegated path — the controller's own in-process state (keyed on
`{template_path, --out}`) is the reconciliation record for that call
instead.

## Notice line shape

Every successful run adds one Igniter notice summarizing the run:

```
ggen_igniter: <per-row notices joined by "; "> (engine: <name>, <N> quer(y|ies), <M> total row(s))
```
