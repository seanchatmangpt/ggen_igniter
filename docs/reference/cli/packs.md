# Packs: `--pack`, `--pack-dir`, and `--pack NAME:TEMPLATE`

Source: `lib/ggen_igniter/pack.ex` (`GgenIgniter.Pack`), consumed by both
`mix ggen_igniter.sync` and `mix ggen_igniter.doctor`. Status: **IMPLEMENTED**.

## The convention

```
priv/ggen/<pack-name>/
├── pack.toml              # optional, not read by GgenIgniter.Pack itself
├── ontology.ttl           # default --ontology
├── gates/*.rq             # default --query source, one named query per file
└── templates/*.{eex,tmpl} # default --template source (single-file case)
```

`GgenIgniter.Pack` is a pure helper with no `Igniter` dependency, so both
Mix tasks and the test suite call it directly.

## `--pack NAME` vs `--pack-dir DIR`

- **`--pack NAME`** resolves to `priv/ggen/NAME/` (relative to the current
  working directory `mix` is invoked from).
- **`--pack-dir DIR`** uses `DIR` directly — no `priv/ggen/` prefix
  assumed. Useful for a pack living outside the `priv/ggen/` convention (a
  fetched/cached pack, a test fixture, etc.).
- If neither is given, `Pack.resolve_dir!/1` raises
  `ArgumentError: "either --pack NAME or --pack-dir DIR is required to resolve a pack"`.
- Whichever is given, an explicit `--ontology`/`--query`/`--template` flag of
  the same kind always overrides the pack-derived default — packs supply
  *defaults*, never mandatory values.

## Discovery rules

- **`--ontology` default**: `<pack_dir>/ontology.ttl` exactly
  (`Pack.default_ontology/1`) — no fallback search, no other filename
  recognized.
- **`--query` default**: every `<pack_dir>/gates/*.rq` file
  (`Pack.discover_queries/1`), sorted lexically (so a `NNN_` numeric-prefix
  convention — `010_spec.rq`, `020_entities.rq` — controls query resolution
  order), mapped to `{name, path}` where `name` is the filename stem with
  any leading `^\d+_` digit prefix stripped: `010_spec.rq` → `"spec"`,
  `entities.rq` → `"entities"` (no prefix, no change). If no `*.rq` files are
  found in `gates/` **and** no explicit `--query` **and** no frontmatter
  `sparql:` block supplies queries either, `sync` raises.
- **`--template` default**: `Pack.discover_template/2` looks under
  `<pack_dir>/templates/` for `*.eex` and `*.tmpl` files combined, sorted.
  - Zero found → `{:error, :none}` → `sync` raises "no *.eex/*.tmpl template
    found ... pass --template explicitly".
  - Exactly one found → used automatically.
  - More than one found (no `:TEMPLATE` stem given) → `{:error,
    {:ambiguous, paths}}` → `sync` raises, naming every path found — it
    never guesses which of several is "the" template.

## `--pack NAME:TEMPLATE` — selecting one of several templates

Append `:TEMPLATE_STEM` to `--pack` (never to `--pack-dir` — see below) to
select one template explicitly, bypassing the multi-template ambiguity error
for that pack. A template's "stem" is its basename **up to its first `.`**
(`"resource.ex.eex"` → stem `"resource"`, `"domain.ex.eex"` → stem
`"domain"`) — not the extension-stripped basename, so multi-dot filenames
(`.ex.eex`) still resolve to the intuitive stem.

```
mix ggen_igniter.sync --pack ash-lifecycle-pack:resource --out lib/generated/resource.ex
```

Given `priv/ggen/ash-lifecycle-pack/templates/{resource.ex.eex,domain.ex.eex}`:

- `--pack ash-lifecycle-pack:resource` selects `resource.ex.eex`.
- `--pack ash-lifecycle-pack:domain` selects `domain.ex.eex`.
- Plain `--pack ash-lifecycle-pack` (no stem) keeps unchanged behavior:
  auto-select when exactly one template exists, raise the same
  "multiple templates found" error when there's more than one.
- A stem matching no template → `{:error, {:stem_not_found, stem, paths}}` →
  `sync` raises, listing every template actually found.
- Two templates sharing the same stem with different extensions (e.g. both
  `resource.eex` and `resource.tmpl`) is a degenerate ambiguous case →
  `{:error, {:ambiguous, paths}}`, same as the no-stem multi-template case.

`--pack-dir` does **not** accept the `:TEMPLATE_STEM` suffix at all — the
parsing (`split_pack_template_stem/1` in `Mix.Tasks.GgenIgniter.Sync`) only
ever inspects `opts[:pack]`, never `opts[:pack_dir]`. Pass `--template`
explicitly instead when using `--pack-dir` against a multi-template pack.

The `NAME:TEMPLATE` split happens on the **first** `:` only
(`String.split(raw, ":", parts: 2)`), so a bare pack name containing no
colon (every real pack name in this codebase) round-trips unchanged when no
stem is given.

## Marketplace fetch: `Pack.fetch_pack!/2` (not CLI-wired)

`GgenIgniter.Pack.fetch_pack!/2` is a real, tested function — modeled on the
real Rust `ggen`'s `ggen pack add <registry>:<id>` — that resolves a package
spec, downloads a real archive over HTTP, verifies it, and extracts it into
a local cache directory (`~/.cache/ggen_igniter/packs` by default) so
`resolve_dir!/1`-style discovery works against it. **This is a library
function only; there is no `--fetch`/`mix ggen_igniter.pack.add`-style CLI
flag or task wired to it** in either `sync` or `doctor` today — status
**PARTIAL_ALIVE** (the function is real and tested, its CLI surface is not
built). Two spec formats, with genuinely different verification strength
(disclosed honestly, not glossed over):

- **`"github:owner/repo"`** (optionally `"@ref"`, default `"main"`) —
  fetches `https://github.com/<owner>/<repo>/archive/refs/heads/<ref>.tar.gz`.
  GitHub's archive endpoint publishes **no checksum**, so this path is
  print-only: the real SHA-256 of the downloaded archive is logged so the
  caller can pin/verify it manually. Not fail-closed — there is nothing to
  fail closed against.
- **`"hex:name@version"`** (or `"hex:name"` for the latest stable release
  via the Hex API) — fetches the real Hex tarball from
  `https://repo.hex.pm/tarballs/<name>-<version>.tar` and compares its real
  SHA-256 against the `checksum` hex.pm's own API publishes for that
  release. **Fail-closed**: a mismatch raises before anything is extracted.

Both sources are exercised by `test/ggen_igniter_pack_fetch_test.exs`
(tagged `:requires_network`).

## Bundled packs in `priv/ggen/`

Each row is a pack directory under `priv/ggen/<pack-name>/`, following the
convention above (`ontology.ttl`, `gates/*.rq`, `templates/*.eex`). Source
for every row: the listed `priv/ggen/<pack>/` files themselves.

| Pack | Ontology namespace prefix | Templates | Gate queries | Example invocation |
|---|---|---|---|---|
| `incremental-discovery-pack` | `dfg:` `<https://ggen-igniter.dev/ontology/incremental-discovery#>` | `incremental.ex.eex` | `010_module.rq` | `mix ggen_igniter.sync --pack incremental-discovery-pack --out lib/generated/incremental.ex` |
| `sensor-sink-pack` | `ss:` `<https://ggen-igniter.dev/ontology/sensor-sink#>` | `sensor_sink.ex.eex` | `010_module.rq` | `mix ggen_igniter.sync --pack sensor-sink-pack --out lib/generated/sensor_sink.ex` |
| `process-discovery-pack` | `pdx:` `<https://ggen-igniter.dev/ontology/process-discovery#>` | `inductive_miner.ex.eex`, `token_replay.ex.eex` | `010_config.rq` | `mix ggen_igniter.sync --pack process-discovery-pack:inductive_miner --out lib/generated/inductive_miner.ex` |
| `ocel2-ekg-pack` | `ekg:` `<https://ggen-igniter.dev/ontology/ocel2-ekg#>` | `ocel2.ex.eex` | `010_ir_module.rq` | `mix ggen_igniter.sync --pack ocel2-ekg-pack --out lib/generated/ocel2.ex` |
| `olap-pack` | `olap:` `<https://ggen-igniter.dev/ontology/olap-pack#>` | `olap.ex.eex` | `010_olap_def.rq` | `mix ggen_igniter.sync --pack olap-pack --out lib/generated/olap.ex` |
| `chicago-fault-injection-pack` | `cfi:` `<https://ggen-igniter.dev/ontology/chicago-fault-injection#>` | `fault_injection_test.exs.eex` | `010_suites.rq` | `mix ggen_igniter.sync --pack chicago-fault-injection-pack --out test/generated/fault_injection_test.exs` |
| `beam4pm-bench-pack` | `bb:` `<https://ggen-igniter.dev/ontology/beam4pm-bench#>` | `topology.ex.eex`, `virtual_cost.ex.eex`, `wasm_engine_benchmark_test.exs.eex` | `010_virtual_cost.rq`, `020_topology.rq`, `030_wasm_bench.rq` | `mix ggen_igniter.sync --pack beam4pm-bench-pack:topology --out lib/generated/topology.ex` |

`process-discovery-pack` and `beam4pm-bench-pack` have more than one
template, so `--pack NAME` alone raises the multi-template ambiguity error
(see `--pack NAME:TEMPLATE` above) — the example invocations for those two
rows select a template stem explicitly.

## `pack_given?/1` semantics

Both `sync` and internal helper functions treat a pack as "given" when
either `--pack` or `--pack-dir` is a non-empty string
(`opts[:pack] not in [nil, ""] or opts[:pack_dir] not in [nil, ""]`) — used
to decide whether pack-derived defaults and pack-scoped `doctor` checks
(#9–#12) apply at all.
