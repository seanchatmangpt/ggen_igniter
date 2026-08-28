# Getting Started with GgenIgniter

Welcome to **GgenIgniter** (`ggen_igniter`). GgenIgniter is an Elixir-native semantic code generation and reconciliation toolchain. It bridges W3C RDF ontologies, SPARQL queries, and template engines to produce deterministic, verified Elixir codebases with robust safety guards and state tracking.

---

## 1. Prerequisites & Environment

Before installing GgenIgniter, verify that your development environment satisfies the runtime and build requirements.

### Elixir & Erlang/OTP Requirements

GgenIgniter requires:
* **Elixir**: `~> 1.17` (tested with Elixir 1.17, 1.18, and 1.19)
* **Erlang/OTP**: `>= 25` (tested with OTP 25, 26, 27, and 28)

Check your installed versions:

```bash
elixir --version
```

Expected output format:
```text
Erlang/OTP 27 [erts-15.2] [source] [64-bit] [smp:12:12]
Elixir 1.18.4 (compiled with Erlang/OTP 27)
```

### Rust Toolchain (Required for Native Oxigraph Engine)

GgenIgniter includes a high-performance native SPARQL engine powered by [Oxigraph](https://github.com/oxigraph/oxigraph) via a Rustler NIF (`native/ggen_graph_nif`). Because this NIF is compiled when building the library, you must have a working Rust toolchain with `cargo` in your `$PATH`.

Verify Rust and Cargo installation:

```bash
cargo --version
```

Expected output:
```text
cargo 1.80.0 (or newer)
```

> [!IMPORTANT]
> If `cargo` is missing, install the official Rust toolchain via [rustup.rs](https://rustup.rs):
> ```bash
> curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
> ```

---

## 2. Installation

Add `ggen_igniter` to your project's `mix.exs` dependencies list:

```elixir
def deps do
  [
    {:ggen_igniter, "~> 26.8.27"}
  ]
end
```

Fetch and compile the dependencies:

```bash
mix deps.get
mix compile
```

During compilation, Rustler will compile the `ggen_graph_nif` crate and place the shared object into `priv/native/ggen_graph_nif.so`.

---

## 3. Resolving Dependency Declarations

GgenIgniter relies unconditionally on `igniter` and `rdf`. In some consumer applications (such as newly generated Phoenix or Ash projects), `mix.exs` may declare `igniter` with an environment restriction such as `only: [:dev, :test]`.

Because Mix requires dependencies across all packages to have compatible environment scopes, an `only: [:dev, :test]` constraint on `igniter` in your consumer project will cause Mix to raise a dependency conflict.

Ensure your `mix.exs` declares `igniter` without environment restrictions, or let `mix ggen_igniter.doctor --fix` resolve it automatically.

---

## 4. Verifying Your Setup with `mix ggen_igniter.doctor`

GgenIgniter provides an integrated diagnostic tool: `mix ggen_igniter.doctor`. It executes a comprehensive 17-point checklist covering runtime versions, dependency integrity, NIF compilation, and SPARQL engine functionality.

Run the doctor in your terminal:

```bash
mix ggen_igniter.doctor
```

### Sample Output

```text
✔ Elixir 1.18.4 / OTP 27
✔ rdf 3.0.1, sparql 0.3.12, igniter 0.8.3
⚠ sparql 0.3.12: FILTER NOT EXISTS + BIND inside UNION raises Protocol.UndefinedError (see query/qlever.ex moduledoc) -- use --engine qlever for gate queries with this shape
✔ igniter dependency in mix.exs has no :only restriction
✔ sourceror is not directly declared in mix.exs (nothing to relax)
✔ config :dcatr, env: ... already present in config/config.exs
✔ no `use Ash.Domain` modules found under lib
✔ mix.exs version matches CHANGELOG.md -- MATCH
✔ priv/native/ggen_graph_nif.so exists and is newer than every .rs source file (skipped real build)
✔ GgenIgniter.Query.Oxigraph real SELECT query against an in-memory graph returned 1 row(s)
✔ git status clean

Notices:
* ggen_igniter.doctor: all checks passed (see output above)
```

### Automated Repairs with `--fix`

When running inside a consumer application, `mix ggen_igniter.doctor --fix` can automatically repair known configuration issues:

1. **Igniter / Sourceror Restrictions**: Removes `only: [:dev, :test]` restrictions from direct dependency declarations in `mix.exs`.
2. **DCAT-AP Environment Config**: Inserts required `config :dcatr, env: Mix.env()` into `config/config.exs` if `gno`/`dcatr` are present.
3. **Ash Domain Registration**: Detects any `use Ash.Domain` modules under `lib/` and registers them in your application's `config :my_app, ash_domains: [...]` list.
4. **Version Policy Consistency**: Syncs `mix.exs` `version:` literal with `CHANGELOG.md` topmost release heading.

To apply automated repairs:

```bash
mix ggen_igniter.doctor --fix
```

---

## 5. Choosing a Query Engine

GgenIgniter supports three distinct SPARQL query execution engines:

| Engine | Flag | Execution Model | Best Used For |
|---|---|---|---|
| **Oxigraph** (Default) | `--engine oxigraph` | Native in-process Rustler NIF (`native/ggen_graph_nif`) | **Recommended for all projects**. Standards-compliant SPARQL 1.1 execution with correct `ORDER BY` semantics. |
| **SPARQL Hex** | `--engine sparql` | Pure Elixir in-process (`sparql` package) | Light environments or testing without native compilation. Note: v0.3.12 has a known `ORDER BY` row reversal limitation. |
| **QLever** | `--engine qlever` | Remote HTTP client via `gno` | High-throughput remote triplestores with billion-triple graphs. Requires `--store-id`. |

Unless specified otherwise, GgenIgniter defaults to `--engine oxigraph`.

---

## 6. Running Your First Ad-Hoc Sync

You can generate code directly using standalone files without creating a full pack structure.

### Create Sample Input Files

Let's create a minimal ontology, query, and template:

**1. `spec.ttl` (Ontology):**
```turtle
@prefix ex: <http://example.org/demo#> .

ex:Service a ex:Application ;
    ex:moduleName "DemoApp.HealthCheck" ;
    ex:version "1.0.0" ;
    ex:endpoint "/api/v1/health" .
```

**2. `spec.rq` (SPARQL Query):**
```sparql
PREFIX ex: <http://example.org/demo#>

SELECT ?module_name ?version ?endpoint WHERE {
    ?s a ex:Application ;
       ex:moduleName ?module_name ;
       ex:version ?version ;
       ex:endpoint ?endpoint .
}
```

**3. `service.ex.eex` (EEx Template):**
```elixir
defmodule <%= module_name %> do
  @moduledoc """
  Auto-generated health check endpoint.
  Version: <%= version %>
  """

  def endpoint, do: "<%= endpoint %>"
  def status, do: :ok
end
```

### Execute Synchronization

Run `mix ggen_igniter.sync` to evaluate the query and render the template:

```bash
mix ggen_igniter.sync \
  --ontology spec.ttl \
  --query spec=spec.rq \
  --template service.ex.eex \
  --out lib/demo_app/health_check.ex
```

### Inspect the Generated Code

The output file `lib/demo_app/health_check.ex` is created:

```elixir
defmodule DemoApp.HealthCheck do
  @moduledoc """
  Auto-generated health check endpoint.
  Version: 1.0.0
  """

  def endpoint, do: "/api/v1/health"
  def status, do: :ok
end
```

### Single-Row Flattening Convention

Notice that in `service.ex.eex`, we accessed `<%= module_name %>` directly rather than `<%= hd(spec)["module_name"] %>`.

GgenIgniter adheres to the **single-row flattening convention**: when a named query result contains exactly one row, its columns are automatically exposed as top-level atom bindings in the template scope. Multi-row queries remain accessible under their bound name (e.g., `<%= for row <- spec do %>...<% end %>`).

---

## 7. Next Steps

Now that your environment is verified and your first file generated:

* [Building Your First Pack](file:///Users/sac/ggen_igniter/docs/tutorials/first-pack.md) — Learn how to organize ontologies, queries, and templates into reusable directory packages under `priv/ggen/`.
* [Understanding the Reconciliation Lifecycle](file:///Users/sac/ggen_igniter/docs/tutorials/first-reconciliation.md) — Deep dive into manifest tracking, change detection, and stale artifact pruning.
* [The Reactor Coordination Path](file:///Users/sac/ggen_igniter/docs/tutorials/reactor-path.md) — Use the transactional 9-step Reactor coordinator with automated rollback and durable process receipts.
