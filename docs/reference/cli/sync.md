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
| `--engine NAME` | string | `"oxigraph"` | One of `oxigraph`, `sparql`, `qlever` — see `engines.md`. Also accepts a comma-separated list (`oxigraph,sparql`) or the literal `all`, which trigger diagnostic **comparison mode** (ADR-0008) — see below. |
| `--engine-report PATH` | string | *(none — prints a stdout summary instead)* | Only meaningful in comparison mode (`--engine` resolves to more than one engine). Writes the comparison report to `PATH`: `.json` uses `GgenIgniter.EngineComparisonReport.to_json/1`, any other extension uses `to_markdown/1`. |
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
| `--verify-cwd DIR` | string | `--manifest-dir` value, else `File.cwd!()` | Directory the Reactor pipeline's `:verify` step runs its real `mix compile --warnings-as-errors` subprocess in. Decouples verification from `--manifest-dir` for the case where the reconciliation-manifest/path-escape boundary and the actual Mix project root differ (e.g. a test writing to an isolated tmp dir outside the real project via `--manifest-dir`, while `--verify-cwd` still points at the real project so `:verify` compiles the right tree). Wired straight through to `GgenIgniter.Reactors.ReconcileReactor.run/1`'s own `:verify_cwd` opt — see that module's moduledoc, "`:verify` scope". Full worked example (including the clear error message when it's omitted by mistake) below. |
| `--allow-sh` | boolean | `false` | Required if any resolved template's frontmatter sets `sh_before:`/`sh_after:` — absent it, the WHOLE run refuses before any actuation. See "`sh_before:`/`sh_after:` shell hooks" below. |

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

## `--engine oxigraph,sparql` / `--engine all` (comparison mode, `--engine-report`) — IMPLEMENTED

Per ADR-0008 (`docs/architecture/adr/0008-evidence-ranked-multi-engine-registry.md`):
`--engine` also accepts a comma-separated list or the literal `all`, parsed
by `GgenIgniter.EngineRegistry.resolve/2`. Resolving to more than one engine
flips this task into **comparison mode**: every named `--query` runs against
every resolved engine concurrently (`GgenIgniter.EngineRegistry.run_all/4`,
real `Task.async_stream/3` fan-out, one `GgenIgniter.EngineComparisonReport.t()`
per named query). This is strictly diagnostic-additive — rendering/actuation
still use only the **primary** engine's rows (the first engine named, or
`oxigraph` for `--engine all`), so comparison mode changes no actuation,
admission, receipt, or manifest behavior; a plain single `--engine` value
(the default) never triggers this path at all.

`--engine all` expands to every `GgenIgniter.Engine.valid_names/0` engine
whose preconditions are met: `qlever` is included only when `--store-id` was
given **and** a real reachability probe against it succeeds (same real
technique as `mix ggen_igniter.doctor`'s check 8) — otherwise it is silently
excluded with a logged warning, never included and then allowed to error.

Real, verified example (`--engine-report` omitted — stdout summary):

```
mix ggen_igniter.sync --engine oxigraph,sparql \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --query sections=test/fixtures/sections.rq \
  --query entities=test/fixtures/entities.rq \
  --query fields=test/fixtures/fields.rq \
  --template test/fixtures/extension.ex.eex \
  --out /tmp/probe.ex
```

```
ggen_igniter: engine comparison for query "spec":
  oxigraph: ok, 1 rows, 35.11ms
  sparql: ok, 1 rows, 52.79ms
  oxigraph vs sparql: row-set-agreement 100% (row_count_diff: 0, order_equal?: true)
ggen_igniter: engine comparison for query "sections":
  oxigraph: ok, 1 rows, 1.67ms
  sparql: ok, 1 rows, 0.45ms
  oxigraph vs sparql: row-set-agreement DIVERGENT (row_count_diff: 0, order_equal?: false)
...
* ggen_igniter: wrote /tmp/probe.ex (engine: oxigraph, 4 queries, 7 total row(s)) (via reactor)
```

The `"sections"`/`"entities"`/`"fields"` rows above are real, disclosed
divergences (not a bug this feature introduces): `sections`/`entities`/`fields`
all `ORDER BY` a typed-integer column, hitting both the confirmed `sparql`-hex
`ORDER BY` reversal (`lib/ggen_igniter/query.ex:4-16`) and oxigraph's
plain-lexical-string vs. `sparql`-hex's native-value typed-literal encoding
(`test/ggen_igniter_engine_parity_test.exs`'s "typed-literal query" case) —
exactly the divergence classes `pairwise_agreement` exists to surface, not
hide. `"spec"` (no typed literal, no `ORDER BY`) agrees 100%.

`--engine-report PATH` writes the same data instead of printing it: `.json`
via `to_json/1`, anything else (e.g. `.md`) via `to_markdown/1` — see
`GgenIgniter.EngineComparisonReport`'s moduledoc for the exact JSON/Markdown
shape.

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

## `sh_before:`/`sh_after:` shell hooks (frontmatter-only, `--allow-sh`) — IMPLEMENTED

Status: **IMPLEMENTED**, see `igniter/1` → `run_via_reactor/3`/`run_pipeline!/3`'s
`check_allow_sh!/3` calls, `actuate_row!/11` (inline pipeline), and
`GgenIgniter.Reactors.ReconcileReactor`'s own `check_allow_sh!/2`/
`actuate_one/2` (Reactor pipeline).

A template's frontmatter may declare a real shell command to run before
(`sh_before:`) and/or after (`sh_after:`) that target's real
`write_file!/3`/`inject_content!/5` call, mirroring the real Rust ggen's own
`Frontmatter.sh_before`/`sh_after` fields (`GgenIgniter.Frontmatter`'s own
moduledoc). Execution is real: `GgenIgniter.ShellHook.run/3` — `System.cmd("sh",
["-c", cmd], cd: <project_dir>, stderr_to_stdout: true)`, wrapped in a real
`Task.async/1` + `Task.yield/2`/`Task.shutdown/2` timeout (default 60s).

**`--allow-sh` is required.** Default `false`. If ANY resolved template
declares `sh_before:`/`sh_after:` and `--allow-sh` is not passed, the WHOLE
run refuses before any actuation happens at all (fail-closed, matching
`--on-stale refuse`'s own default posture), naming the exact template and
field(s). Checked BEFORE the Reactor dispatch path (`run_via_reactor/3`)
AND BEFORE the inline pipeline's actuation loop (`run_pipeline!/3`) —
genuinely separate call paths, both covered. `GgenIgniter.Reactors.
ReconcileReactor.run/1` independently re-checks the same combination for
its own direct callers (`reconcile_opts[:allow_sh]`), not only calls
arriving through this task.

**DISCLOSED, INTENTIONAL LIMITATION** (mirrors ADR-0006's disclosure style):
a `sh_before:`/`sh_after:` command's real side effects are **NOT**
integrated into `GgenIgniter.PendingActuation`'s `operation()` type, **NOT**
inspected by `:admit`'s guards (duplicate-path/path-escape/unowned-delete
refusal), and **NOT** tracked by `undo/4`'s compensation/revert machinery —
a template author declaring `sh_before:`/`sh_after:` is trusted the same
way this repo already trusts a frontmatter `to:` path. `--allow-sh` is the
one new, deliberately small admission-adjacent mitigation this pass adds.

**Failure semantics differ between the two pipelines:**

- **Inline pipeline (`run_pipeline!/3`, used by `--for-each`)**: a nonzero
  exit or timeout does **NOT** abort the whole run — it produces a new
  per-row outcome atom instead (`:sh_before_failed` skips that row's real
  write/inject entirely; `:sh_after_failed` means the write/inject already
  genuinely happened and is NOT reverted), extending the existing
  `:written`/`:injected`/`:unchanged`/`:skipped_exists`/`:skipped_match`
  vocabulary and its `outcome_summary_suffix/2`/`summary_bucket/1`
  reporting. Other rows in the same `--for-each` run are unaffected.
- **Reactor pipeline (`ReconcileReactor`)**: a hook failure is treated as an
  ordinary actuation failure — it raises, caught by the same `rescue`
  clause that already catches a real `write_file!/3`/`inject_content!/5`
  failure, flowing through the EXISTING self-heal/`undo/4` machinery
  (whole-run revert, `:compensated` standing). This pipeline's `:actuate`
  step is deliberately all-or-nothing (see its own moduledoc); it does not
  gain a new per-target outcome vocabulary the way the inline pipeline
  does.

`--dry-run` previews a shell hook exactly like every other decision in this
module: `"planned: run sh_before: <cmd>"` / `"planned: run sh_after: <cmd>"`
is printed, and `GgenIgniter.ShellHook.run/3` is never called.

Every real invocation is appended to `GgenIgniter.Receipt.commands` — see
that module's moduledoc for the entry shape (`kind`/`cmd`/`template_path`/
`target`/`exit_code`/`output`/`duration_ms`/`status`). The inline pipeline
does not otherwise construct a `GgenIgniter.Receipt` at all; a minimal
`standing: :alive` receipt is appended only for a real (non-`--dry-run`) run
that declared `sh_before:`/`sh_after:`.

```
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/sh_after_template.ex.eex \
  --out tmp_out/probe.ex \
  --allow-sh
```

## `--verify-cwd DIR` (Reactor pipeline only)

The Reactor pipeline's terminal `:verify` step (see below) runs a real `mix
compile --warnings-as-errors` subprocess against `--verify-cwd ||
--manifest-dir || File.cwd!()`. `--verify-cwd` only matters when
`--manifest-dir` points OUTSIDE the real Mix project directory — the common
case for a caller who wants the reconciliation manifest and the `--out`
path-escape boundary scoped to an isolated tmp dir, while still wanting
`:verify` to compile the actual project.

Real, runnable example — generating into an isolated `/tmp` dir, verifying
against this repo:

```
mkdir -p /tmp/ggen_verify_cwd_demo
mix ggen_igniter.sync \
  --pack-dir priv/ggen/adr-index-pack \
  --out /tmp/ggen_verify_cwd_demo/out.md \
  --manifest-dir /tmp/ggen_verify_cwd_demo \
  --verify-cwd /Users/sac/ggen_igniter \
  --engine oxigraph
```

Real output (`use_reactor: true`, run at HEAD `6c44916`):

```
Notices:

* ggen_igniter: wrote /tmp/ggen_verify_cwd_demo/out.md (engine: oxigraph, 1 query, 6 total row(s)) (via reactor)
```

### The likely first-time mistake, and its error message

Dropping `--verify-cwd` in this exact scenario (`--manifest-dir` outside any
Mix project) makes `:verify`'s `mix compile` subprocess `cd:` into that same
non-project directory. Real, reproduced output (same command, `--verify-cwd`
flag removed):

```
** (RuntimeError) ggen_igniter: reactor reconciliation failed (build_broken): verification failed (mix compile): ggen_igniter: --verify-cwd was not set, so `:verify`'s `mix compile` ran in "/tmp/ggen_verify_cwd_demo_error" (from --manifest-dir/File.cwd!()), which is not a Mix project directory (no mix.exs found there). Pass --verify-cwd DIR pointing at the real Mix project root (the directory containing mix.exs) to fix this -- e.g. --verify-cwd "/Users/sac/ggen_igniter".

Original mix compile output:
** (Mix) Could not find a Mix.Project, please ensure you are running Mix in a directory with a mix.exs file
```

This is not a raw `Mix.Project` crash surfaced unchanged — `:verify`
(`GgenIgniter.Reactors.ReconcileReactor`'s `maybe_add_verify_cwd_hint/3`)
detects the `"Could not find a Mix.Project"` text specifically when
`--verify-cwd` was never set, and prepends the actionable pointer above
(naming the exact flag and a real fix command) before the original Mix
error text, which is preserved unchanged underneath for full diagnostics. An
explicit `--verify-cwd` that itself resolves to a non-project directory is a
genuine caller mistake and gets the bare Mix error unchanged — the hint only
fires for the "forgot to set it" case.

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
