# Adding a Pack

A "pack" is a directory following one fixed convention that lets
`mix ggen_igniter.sync`/`.doctor` resolve `--ontology`/`--query`/`--template`
by convention instead of by explicit flags. Source of record:
`lib/ggen_igniter/pack.ex`; discovery is a pure helper with no `Igniter`
dependency, so both Mix tasks and tests call it directly.

## Directory shape

```
priv/ggen/<pack-name>/
├── pack.toml              # optional; not read by GgenIgniter.Pack itself
├── ontology.ttl            # default --ontology
├── gates/*.rq               # default --query source, one query per file
└── templates/*.{eex,tmpl}   # default --template source (single-file case)
```

`priv/ggen/<pack-name>/` is the convention for a pack shipped *inside* a
project (this project's own `priv/ggen/`, or a consumer's). An out-of-tree
pack directory (a fixture, or a pack fetched from a marketplace — see
below) is addressed via `--pack-dir DIR` instead of `--pack NAME`.

## Step by step

1. **Create the directory** at `priv/ggen/<pack-name>/` (or wherever you'll
   point `--pack-dir` at).
2. **Write `ontology.ttl`** — real Turtle, loadable by `RDF.Turtle.read_file/1`.
   `mix ggen_igniter.doctor --pack <pack-name>` check 9 verifies it parses.
3. **Write one or more gate queries** under `gates/*.rq`. Discovery
   (`GgenIgniter.Pack.discover_queries/1`) sorts filenames lexically (so an
   `NNN_` numeric prefix convention controls query ordering) and strips any
   leading `^\d+_` digit prefix to derive the query's bound name:
   `010_spec.rq` → binds as `spec`; `entities.rq` (no prefix) → binds as
   `entities`. Check 10 verifies at least one exists; check 12 verifies
   every one parses as syntactically valid SPARQL (parse-only, no
   execution).
4. **Write a template** under `templates/*.eex` (or `.tmpl`). With exactly
   one template file, plain `--pack <pack-name>` auto-selects it. Check 11
   verifies at least one exists.
   - **If your pack needs more than one template** (e.g. a resource
     template and a domain template, per `test/fixtures/ash-lifecycle-pack/`),
     bare `--pack NAME` becomes ambiguous
     (`{:error, {:ambiguous, paths}}` from `discover_template/2`). Use
     `--pack NAME:TEMPLATE_STEM` instead, where `STEM` is the template's
     basename up to its *first* dot (`resource.ex.eex` → stem `resource`;
     `domain.ex.eex` → stem `domain`) — this bypasses the ambiguity check
     entirely, even with multiple templates present, and is the documented
     path back to a single clean CLI flag for a multi-template pack. A
     stem that matches nothing gives `{:error, {:stem_not_found, stem,
     paths}}` naming every template actually found, not a silent guess.
5. **Verify with doctor**: `mix ggen_igniter.doctor --pack <pack-name>` runs
   checks 9–12 against it. Fix anything it reports before wiring the pack
   into real usage.
6. **Run a real sync**: `mix ggen_igniter.sync --pack <pack-name> --out
   <path>` (add `--pack <pack-name>:<stem>` if multi-template, and
   `--engine sparql` if you hit the disclosed oxigraph string-quoting bug —
   see `docs/operations/debugging.md`). Explicit `--ontology`/`--query`/
   `--template` flags always override the pack-derived default, at any
   granularity — you don't have to go all-or-nothing on pack discovery.

## How pack identity interacts with reconciliation (the manifest)

`GgenIgniter.Manifest` (see `docs/operations/failure-recovery.md`) keys its
tracked entries by `(template_path, out_template)` — the **resolved**
template path plus the **raw**, unrendered `--out`/`to:` string — not by
pack name or ontology path. This means:

- Re-running the same pack against the same `--out` template as you edit
  `ontology.ttl`'s *content* in place is correctly recognized as the same
  ongoing recipe (the manifest key doesn't change just because the
  ontology's content did).
- `pack_dir` is recorded in each manifest entry as **informational
  metadata only** — never part of the identity key — so a human reading
  `.ggen_igniter/manifest.json` can see which pack produced an entry
  without it affecting reconciliation.
- A pack with `--for-each NAME` fan-out (multiple rendered rows from one
  template) still has one stable `out_template` string (the *unrendered*
  path template, e.g. `"lib/support_desk/support/<%= String.downcase(resource_name) %>.ex"`)
  — only the per-row *rendered* paths differ, which is exactly what
  reconciliation diffs old-vs-new against.

If your pack's ontology can rename or remove the entity a template row
represents, read `docs/operations/failure-recovery.md`'s "Known, disclosed
limitation" section first — there is currently no cross-run cleanup of the
old, now-orphaned generated file.

## Marketplace fetch: `github:`/`hex:` sources

`GgenIgniter.Pack.fetch_pack!/2` resolves a pack from a remote registry into
a local cache directory (`~/.cache/ggen_igniter/packs` by default,
overridable via `:cache_dir`), returning a path usable directly as
`--pack-dir`. Two real sources exist, with **genuinely different
verification strength** — know which one you're using:

- **`"github:owner/repo[@ref]"`** (ref defaults to `"main"`) — fetches
  `https://github.com/<owner>/<repo>/archive/refs/heads/<ref>.tar.gz`.
  GitHub's archive endpoint publishes **no checksum**, so this is
  **print-only**: the real SHA-256 of the downloaded archive is logged so
  you can pin/verify it manually. This is *not* fail-closed verification —
  there is nothing to fail closed against.
- **`"hex:name[@version]"`** (version defaults to latest stable per the Hex
  API) — fetches the real Hex tarball and compares its SHA-256 against the
  `checksum` hex.pm's own API publishes for that release. This *is*
  fail-closed: a mismatch raises before anything is extracted.

If a pack's provenance matters (you're pulling from a registry you don't
control), prefer `hex:` for its real checksum verification, or pin and
record a `github:` archive's printed digest yourself.

Fetching requires `:tesla` — `optional: true` in `mix.exs` for exactly this
reason (a consumer that never fetches remote packs shouldn't need to
compile Tesla). Without it, `fetch_pack!/2` raises a clear, actionable
`RuntimeError` naming the missing dep rather than a cryptic compile error.

## Where pack-authored Ash/Phoenix templates fit

A pack's own templates may target Ash, Phoenix, or any other framework —
that is pack content, not core pipeline behavior (see
`docs/contributing/architecture-rules.md`'s "Ash owns application semantics
— in Ash consumers only" rule). `test/fixtures/ash-lifecycle-pack/` is the
reference example: its templates render idiomatic `use Ash.Resource`/
`use Ash.Domain` code with no `GgenIgniter.*` namespace leakage into the
generated application code itself (verified directly —
`.ggen_igniter_factory/zach_chris_acceptance.md` — the only `GgenIgniter.*`
mentions inside that pack's templates are inside a `@moduledoc`'s own
prose, explaining the pipeline to a future maintainer, never inside the
generated module's actual code body).

## See Also

- `docs/operations/failure-recovery.md` — the manifest/recipe-key identity model in full
- `docs/operations/debugging.md` — doctor checks 9–12 and the oxigraph engine caveat
- `docs/contributing/architecture-rules.md` — the ggen-owns-semantic-compilation / Ash-in-consumers-only rules this file's pack conventions follow
- `lib/ggen_igniter/pack.ex` — source of record for every discovery/fetch behavior above
