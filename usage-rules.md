<!--
SPDX-FileCopyrightText: 2026 ggen_igniter contributors

SPDX-License-Identifier: MIT

GENERATED from priv/ggen/usage-rules-pack/ontology.ttl -- edit the ontology and re-run
  mix ggen_igniter.sync --pack usage-rules-pack --engine sparql --out usage-rules.md
-->

# Rules for working with ggen_igniter

## Understanding ggen_igniter

Elixir bootstrap of ggen's ontology-to-code pipeline: Ontology.load! -> Engine.run -> Render.render -> Actuate.write_file!, tracked by a reconciliation manifest so upstream renames are mechanically detected.

## Tasks

### `mix ggen_igniter.sync`

Load a Turtle ontology, run named SPARQL queries, render an EEx template with the rows, and write (or inject) the output; reconciles against the manifest.

```
mix ggen_igniter.sync --pack adr-index-pack --engine sparql --out docs/architecture/adr/README.md
```

- `--dry-run` (boolean) -- Preview without writing.
- `--engine` (string) -- Query engine; oxigraph is the default, sparql is pure Elixir with FILTER NOT EXISTS/UNION limits.
- `--for-each` (string) -- Render one output per row of the named query.
- `--manifest-dir` (string) -- Directory whose .ggen_igniter/manifest.json is reconciled.
- `--on-stale` (string) -- refuse (default), prune, or preserve stale manifest outputs.
- `--ontology` (string) -- Path to the Turtle ontology.
- `--out` (string) -- Output path (may contain EEx expressions).
- `--pack` (string) -- Pack name under priv/ggen; explicit --ontology/--query/--template beat it.
- `--pack-dir` (string) -- Explicit pack directory.
- `--query` (string (repeatable)) -- NAME=path.rq; the rows bind as @NAME in the template.
- `--template` (string) -- EEx template path.

### `mix ggen_igniter.plan`

Plan-only counterpart of sync: reports what would be written without touching disk.

```
mix ggen_igniter.plan --pack ash-lifecycle-pack --query resource=gates/resource.rq
```

- `--json` (boolean) -- Machine-readable plan.
- `--pack` (string) -- Pack name under priv/ggen.
- `--query` (string (repeatable)) -- NAME=path.rq.

### `mix ggen_igniter.doctor`

Run the numbered environment/project/pack checklist; run this first when diagnosing.

```
mix ggen_igniter.doctor --json
```

- `--fix` (boolean) -- Auto-fix the fixable subset of checks.
- `--json` (boolean) -- Machine-readable report.
- `--pack` (string) -- Check a specific pack.
- `--strict` (boolean) -- Treat warnings as failures.

### `mix ggen_igniter.install`

Igniter installer: imports the :ggen_igniter formatter dep; Ash wiring only with --with-ash-domain.

```
mix igniter.install ggen_igniter
```

- `--domain` (string) -- Domain module (default <OtpApp>.Ash.Domain).
- `--otp-app` (string) -- Consumer OTP app name.
- `--with-ash-domain` (boolean) -- Opt in to adding :ash, registering the domain, and supervising it.
- `--yes` (boolean) -- Apply without prompting.

### `mix ggen_igniter.rename`

Rename a function across the consumer project, optionally leaving a deprecated delegate.

```
mix ggen_igniter.rename --from Old.fun --to New.fun --arity 2 --deprecate soft
```

- `--arity` (integer) -- Restrict to one arity.
- `--deprecate` (string) -- soft or hard: leave a deprecated delegate at the old name.
- `--from` (string) -- Existing Module.function.
- `--to` (string) -- New Module.function.

### `mix ggen_igniter.manifest.dump`

Emit a stable, sorted JSON export of .ggen_igniter/manifest.json plus receipts for third-party replay (byte-identical for identical input).

```
mix ggen_igniter.manifest.dump --path . --out manifest-export.json
```

- `--out` (string) -- Write the export to FILE instead of stdout.
- `--path` (string) -- Directory holding .ggen_igniter/ (default .).

## Invariants

- Generate, do not hand-write: model reusable structure in a pack ontology and render it with ggen_igniter.sync; never hand-edit a generated file, edit the ontology and re-sync.
- Never hand-write Ash surfaces (use Ash.Resource / use Ash.Domain); generate them from packs or upstream generators.
- Tests are Chicago-style: real files, subprocesses, and engines with state-based assertions; no Mox, Mimic, Patch, or :meck.
- A summary is not a receipt: done means mix compile --warnings-as-errors and mix test pass with real output.
- Stale outputs are refused by default (--on-stale refuse); the manifest at <dir>/.ggen_igniter/manifest.json is the ownership memory.
- Ash is dev and test only in this package and never a runtime dependency; the shipped package stays Ash-free.

