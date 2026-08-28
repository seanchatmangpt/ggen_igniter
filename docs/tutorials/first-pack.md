# Building and Running Your First Pack

In GgenIgniter, a **Pack** is a self-contained, shareable directory of semantic assets: an RDF ontology, SPARQL gate queries, and code templates. Packs eliminate verbose command-line options by standardizing file layouts and auto-discovering generation pipelines.

---

## 1. Anatomy of a Pack

Packs are located by default in your project root under `priv/ggen/<pack-name>/`:

```text
priv/ggen/audit-trail-pack/
├── pack.toml                  # Optional metadata (version, author, description)
├── ontology.ttl               # Domain model (RDF Turtle ontology)
├── gates/                     # SPARQL query files
│   ├── 010_spec.rq            # Numbered for deterministic lexical ordering
│   ├── 020_sections.rq
│   ├── 030_entities.rq
│   └── 040_fields.rq
└── templates/                 # Code templates
    └── extension.ex.eex       # EEx or Tera template
```

### Discovery Rules

When you run `mix ggen_igniter.sync --pack <pack-name>` or `mix ggen_igniter.doctor --pack <pack-name>`, GgenIgniter resolves assets using these rules:

1. **Ontology**: Defaults to `<pack_dir>/ontology.ttl`.
2. **Gate Queries (`gates/*.rq`)**: Discovered via `Path.wildcard("gates/*.rq")` and sorted lexically. Any numeric prefix (e.g. `010_`, `020_`) is stripped to form the query binding name:
   * `010_spec.rq` $\rightarrow$ bound as `"spec"` in template bindings.
   * `020_sections.rq` $\rightarrow$ bound as `"sections"`.
   * `entities.rq` $\rightarrow$ bound as `"entities"` (unchanged without numeric prefix).
3. **Template (`templates/*.{eex,tmpl}`)**:
   * If exactly **one** template file exists, it is automatically selected.
   * If **multiple** templates exist, GgenIgniter requires you to specify which template to render (via `--template` or stem syntax `--pack <name>:<stem>`).

---

## 2. Step-by-Step: Creating a Service Pack

Let's build a real, runnable pack called `service-pack`.

### Step 1: Create the Directory Layout

```bash
mkdir -p priv/ggen/service-pack/gates
mkdir -p priv/ggen/service-pack/templates
```

### Step 2: Define the Domain Ontology (`ontology.ttl`)

Write `priv/ggen/service-pack/ontology.ttl`:

```turtle
@prefix ex: <http://example.org/services#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

ex:AuthService a ex:Service ;
    ex:moduleName "DemoApp.AuthService" ;
    ex:port 4001 ;
    ex:hasEndpoint ex:LoginEndpoint, ex:LogoutEndpoint .

ex:LoginEndpoint a ex:Endpoint ;
    ex:path "/api/auth/login" ;
    ex:method "POST" ;
    ex:action "login" .

ex:LogoutEndpoint a ex:Endpoint ;
    ex:path "/api/auth/logout" ;
    ex:method "POST" ;
    ex:action "logout" .
```

### Step 3: Define the Gate Queries (`gates/*.rq`)

Gate queries extract structured facts from the ontology.

**1. `gates/010_service.rq` (Single-Row Query):**
```sparql
PREFIX ex: <http://example.org/services#>

SELECT ?module_name ?port WHERE {
    ?s a ex:Service ;
       ex:moduleName ?module_name ;
       ex:port ?port .
}
```

**2. `gates/020_endpoints.rq` (Multi-Row Query):**
```sparql
PREFIX ex: <http://example.org/services#>

SELECT ?path ?method ?action WHERE {
    ?s a ex:Service ;
       ex:hasEndpoint ?e .
    ?e ex:path ?path ;
       ex:method ?method ;
       ex:action ?action .
}
ORDER BY ?path
```

### Step 4: Author the Code Template (`templates/service.ex.eex`)

Write `priv/ggen/service-pack/templates/service.ex.eex`:

```elixir
defmodule <%= module_name %> do
  @moduledoc """
  Service generated from ontology definition.
  Default Port: <%= port %>
  """

  @endpoints [
<%= for ep <- endpoints do %>
    %{path: "<%= ep["path"] %>", method: :<%= String.downcase(ep["method"]) %>, action: :<%= ep["action"] %>},
<% end %>
  ]

  def port, do: <%= port %>
  def endpoints, do: @endpoints
end
```

---

## 3. Validating the Pack with `doctor`

Before running synchronization, validate your pack structure, syntax, and queries using `mix ggen_igniter.doctor`:

```bash
mix ggen_igniter.doctor --pack service-pack
```

### Expected Doctor Checks:

```text
✔ Elixir 1.18.4 / OTP 27
✔ rdf 3.0.1, sparql 0.3.12, igniter 0.8.3
✔ ontology.ttl parses (14 triples)
✔ 2 gate queries found: service, endpoints
✔ 1 templates found: service.ex.eex
✔ all 2 gate queries parse
✔ git status clean
✔ GgenIgniter.Query.Oxigraph real SELECT query against an in-memory graph returned 1 row(s)

Notices:
* ggen_igniter.doctor: all checks passed (see output above)
```

If a SPARQL query contains a syntax error or the Turtle file is malformed, `doctor` will fail immediately with a descriptive diagnostic message and line numbers.

---

## 4. Running Synchronization with `mix ggen_igniter.sync`

To synchronize the pack and generate code:

```bash
mix ggen_igniter.sync --pack service-pack --out lib/demo_app/auth_service.ex
```

### Output:

```text
Notices: 

* ggen_igniter: wrote lib/demo_app/auth_service.ex (engine: oxigraph, 2 queries, 3 total row(s))
```

### Inspect the Generated Code

The resulting `lib/demo_app/auth_service.ex` file:

```elixir
defmodule DemoApp.AuthService do
  @moduledoc """
  Service generated from ontology definition.
  Default Port: 4001
  """

  @endpoints [
    %{path: "/api/auth/login", method: :post, action: :login},
    %{path: "/api/auth/logout", method: :post, action: :logout},
  ]

  def port, do: 4001
  def endpoints, do: @endpoints
end
```

---

## 5. Working with Multi-Template Packs

When a pack contains more than one template in `templates/` (for example, `resource.ex.eex` and `domain.ex.eex`), running `mix ggen_igniter.sync --pack <name>` without specifying a template will raise an `ArgumentError` to prevent ambiguous writes:

```text
** (ArgumentError) multiple templates found in priv/ggen/ash-lifecycle-pack/templates/ (domain.ex.eex, resource.ex.eex) -- pass :template explicitly or use --pack NAME:STEM
```

### Template Stem Selection Syntax (`--pack NAME:STEM`)

GgenIgniter provides a convenient `:STEM` selector suffix on the `--pack` flag. The stem is the template filename up to its first period:

* `resource.ex.eex` $\rightarrow$ stem is `"resource"`
* `domain.ex.eex` $\rightarrow$ stem is `"domain"`

To select `resource.ex.eex`:

```bash
mix ggen_igniter.sync --pack ash-lifecycle-pack:resource --out lib/my_app/resource.ex
```

To select `domain.ex.eex`:

```bash
mix ggen_igniter.sync --pack ash-lifecycle-pack:domain --out lib/my_app/domain.ex
```

> [!NOTE]
> Stem selection syntax (`NAME:STEM`) is supported on `--pack`. When using an arbitrary directory via `--pack-dir DIR`, supply `--template DIR/templates/resource.ex.eex` explicitly.

---

## 6. Multi-Row Fan-Out with `--for-each`

If your ontology contains multiple entities (for example, 5 distinct microservices or database tables), you can render a template once per row of a driving query using `--for-each <query_name>`.

### Example: Generating a File Per Service

Suppose query `services.rq` returns multiple service rows with `module_name`.

```bash
mix ggen_igniter.sync \
  --pack service-pack \
  --for-each services \
  --out "lib/generated/<%= Macro.underscore(module_name) %>.ex"
```

In this mode:
1. `--for-each services` iterates over every row returned by `services.rq`.
2. Each row's fields are flattened into top-level template bindings.
3. The `--out` path template is itself rendered with the row bindings.
4. Each service is written to its own independent file path.

---

## 7. Override Rules & Precedence

Command-line flags always take precedence over pack-discovered defaults:

| Asset | Pack Default | CLI Override |
|---|---|---|
| Ontology | `<pack_dir>/ontology.ttl` | `--ontology custom_model.ttl` |
| Queries | `<pack_dir>/gates/*.rq` | `--query extra=extra.rq` (merges or overrides matching name) |
| Template | `<pack_dir>/templates/*.eex` | `--template custom_template.ex.eex` |
| Pack Directory | `priv/ggen/<name>/` | `--pack-dir /path/to/custom/pack/` |

---

## 8. Next Steps

* [Understanding the Reconciliation Lifecycle](file:///Users/sac/ggen_igniter/docs/tutorials/first-reconciliation.md) — Learn how GgenIgniter tracks files in `.ggen_igniter/manifest.json` and prunes stale artifacts when models evolve.
* [The Reactor Coordination Path](file:///Users/sac/ggen_igniter/docs/tutorials/reactor-path.md) — Learn about transactional multi-target execution with compile verification and automated rollback.
