# Pack Format & Marketplace Integration

## Overview

In the `ggen` ecosystem, a **Pack** is a self-contained unit of semantic manufacturing knowledge. It encapsulates domain ontologies, validation/gate queries, and code generation templates.

`ggen_igniter` achieves full architectural and structural compatibility with the Rust `ggen` pack ecosystem, enabling packs to be used natively across both Elixir and Rust tooling.

---

## 1. Pack Directory Layout

A standard pack directory follows the convention resolved by `GgenIgniter.Pack` (`lib/ggen_igniter/pack.ex`):

```
priv/ggen/<pack-name>/           # (or an explicit directory passed via --pack-dir)
├── pack.toml                    # Pack metadata and manifest definition
├── ontology.ttl                 # RDF Turtle domain ontology
├── gates/                       # SPARQL queries for validation and data extraction
│   ├── 010_spec.rq
│   ├── 020_entities.rq
│   └── 030_relationships.rq
└── templates/                   # Code generation templates
    ├── resource.ex.eex          # Elixir EEx template
    └── report.md.tmpl           # Tera/Jinja2 template
```

### Directory Resolution
`GgenIgniter.Pack.resolve_dir!/1` resolves the pack root directory from CLI/runtime options:
1. `opts[:pack_dir]`: Explicit directory path override.
2. `opts[:pack]`: Lookup under `priv/ggen/<pack-name>/`.
3. Raises `ArgumentError` if neither option is provided.

---

## 2. Pack Components & Conventions

### `ontology.ttl`
- Default ontology path: `<pack_dir>/ontology.ttl`.
- Provides the formal schema and facts (classes, properties, domain models) in W3C RDF Turtle format.

### `gates/*.rq` (SPARQL Query Discovery)
- `GgenIgniter.Pack.discover_queries/1` scans `<pack_dir>/gates/*.rq`.
- **Lexical Ordering**: Files are sorted lexically, allowing numeric prefixes (`010_`, `020_`) to enforce execution order.
- **Prefix Stripping**: Leading numeric prefixes matching `^\d+_` are stripped to create the query's binding name:
  - `gates/010_spec.rq` -> `"spec"`
  - `gates/020_entities.rq` -> `"entities"`
  - `gates/custom.rq` -> `"custom"`

### `templates/*.{eex,tmpl}` (Template Discovery & Selection)
`GgenIgniter.Pack.discover_template/2` locates templates under `<pack_dir>/templates/`:
- **Single Template Pack (`--pack NAME`)**:
  - If exactly one `*.eex` or `*.tmpl` file exists, returns `{:ok, path}`.
  - If zero exist, returns `{:error, :none}`.
  - If multiple exist, returns `{:error, {:ambiguous, paths}}` to prevent accidental template selection.
- **Multi-Template Pack (`--pack NAME:STEM`)**:
  - Accepts a template stem selector (the filename up to its first `.`):
    - `--pack ash-lifecycle-pack:resource` -> matches `templates/resource.ex.eex`
    - `--pack ash-lifecycle-pack:domain` -> matches `templates/domain.ex.eex`
  - Bypasses ambiguity errors by selecting the exact matching template.

---

## 3. Marketplace Packaging & Fetch (`fetch_pack!/2`)

`GgenIgniter.Pack.fetch_pack!/2` implements marketplace pack acquisition over HTTP, caching downloaded packs in `~/.cache/ggen_igniter/packs` (or a custom `:cache_dir`).

It mirrors Rust `ggen`'s `ggen pack add <registry>:<id>` (`crates/ggen-marketplace/src/marketplace/install.rs`).

### Registry Sources & Verification Models

| Spec Scheme | Source URL | Verification Model | Fail-Closed? |
|---|---|---|---|
| `github:owner/repo[@ref]` | `https://github.com/<owner>/<repo>/archive/refs/heads/<ref>.tar.gz` | **Print-Only SHA-256**: GitHub does not publish pre-signed archive checksums. The real SHA-256 hash is computed and logged so the caller can pin/verify it. | No (Audit-only) |
| `hex:name[@version]` | `https://repo.hex.pm/tarballs/<name>-<version>.tar` | **Fail-Closed Verification**: Fetches expected SHA-256 checksum from Hex.pm API (`/api/packages/<name>/releases/<version>`). Compares against the downloaded tarball. Rejects and raises before extraction if mismatch occurs. | **Yes** (Strict) |

### Extraction Pipeline
- **GitHub (`.tar.gz`)**: Uses Erlang `:erl_tar` to extract gzipped tar archives. Automatically strips the single top-level repository folder so the pack root contains `ontology.ttl` and `templates/` directly.
- **Hex (`.tar`)**: Extracts the outer POSIX tar archive to inspect `metadata.config` and extracts the inner `contents.tar.gz` into the target destination directory.

### Compile-Time Isolation (`:tesla`)
HTTP requests use `Tesla` when available. `lib/ggen_igniter/pack.ex` uses compile-time checking (`Code.ensure_loaded?(Tesla)`) to ensure consuming applications compile cleanly without warnings even if `:tesla` is omitted from their dependencies.

---

## 4. Rust Data Model Alignment

`ggen_igniter` mirrors the Rust `ggen` AST and manifest structs with 1:1 structural fidelity:

### Manifest & Config Types
- `GgenIgniter.PackManifest` (`lib/ggen_igniter/pack_manifest.ex`): Mirrors `ggen_marketplace::packs_registry::types::Pack`. Includes `id`, `name`, `version`, `category`, `templates`, `sparql_queries`, `dependencies`, and `metadata`.
- `GgenIgniter.PackRef` (`lib/ggen_igniter/pack_manifest.ex`): Mirrors `ggen_config::manifest::PackRef` from `ggen.toml [[packs]]`.
- `GgenIgniter.PackageToml` (`lib/ggen_igniter/pack_manifest.ex`): Mirrors `ggen_config::manifest::PackageToml`.
- `GgenIgniter.ProjectConfig` (`lib/ggen_igniter/project_config.ex`): Mirrors `ggen_config::manifest::GgenManifest`, including `[project]`, `[ontology]`, `[inference]`, `[generation]`, `[validation]`, and `[law]` sections.

### Template Frontmatter
- `GgenIgniter.Frontmatter` (`lib/ggen_igniter/frontmatter.ex`): Hand-maintained 1:1 field mirror of Rust `ggen::Frontmatter` (`ggen-engine/src/template.rs`):
  - `to`, `sparql`, `for_each`, `construct`, `inject`, `before`, `after`, `at_line`, `skip_if`, `unless_exists`, `unattended_write_eligible`, `force`, `when`, `skip_empty`, `shape`, `freeze_policy`, `prefixes`.
  - Additional Elixir-specific execution mode: `mode: :file | :eval`.
