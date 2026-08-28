# Semantic Compilation Pipeline

## Core Architecture: Knowledge to ManufacturingPlan

In the `ggen_igniter` system, the manufacturing lifecycle is split into two distinct halves:
1. **Semantic Compiler (`ggen`)**: Transforms declarative domain knowledge (RDF ontologies, SPARQL gate queries, EEx/Tera templates) into a structured `ManufacturingPlan` (`[%PendingActuation{}]`).
2. **Project Actuator (`Igniter`)**: Executes the admitted `ManufacturingPlan` against the Elixir project filesystem and codebase, producing the final project delta.

```
+-------------------------------------------------------------------------------+
|                       SEMANTIC COMPILATION (ggen)                             |
|                                                                               |
|  +--------------------+        +---------------------+                        |
|  |  Turtle Ontology   |        |   SPARQL Queries    |                        |
|  |   (ontology.ttl)   |        |    (gates/*.rq)     |                        |
|  +---------+----------+        +----------+----------+                        |
|            |                              |                                   |
|            v                              v                                   |
|   Ontology.load!/1             Engine.prepare!/run/2                          |
|   (RDF.Turtle parser)          (Oxigraph / Sparql / Qlever)                   |
|            |                              |                                   |
|            +--------------+---------------+                                   |
|                           |                                                   |
|                           v                                                   |
|                Multi-Query Merge & Single-Row                                 |
|                Root Promotion (build_bindings/2)                              |
|                           |                                                   |
|                           v                                                   |
|                 Fan-Out (for_each / --for-each)                               |
|                           |                                                   |
|                           v                                                   |
|              Template Evaluation (Render.render/2)                            |
|                           |                                                   |
+---------------------------+---------------------------------------------------+
                            |
                            v
          +-----------------------------------+
          |  PendingActuation Plan IR         |
          |  (Admitted ManufacturingPlan)     |
          +-----------------+-----------------+
                            |
+---------------------------+---------------------------------------------------+
|                        PROJECT ACTUATION (Igniter)                            |
|                                                                               |
|            v                                 v                                |
|  Actuate.write_file!/3             Actuate.inject_content!/5                  |
|  (Guarded whole-file write)        (Anchor-guided code injection)             |
|                                                                               |
|  +-------------------------------------------------------------------------+  |
|  |  Write-Safety Decision Table: unless_exists -> skip_if -> unchanged ->  |  |
|  |  written                                                                |  |
|  +-------------------------------------------------------------------------+  |
+-------------------------------------------------------------------------------+
```

## Implementation Status & Reality

**OBSERVED IMPLEMENTATION OUTRANKS INTENDED ARCHITECTURE.**

`ggen_igniter` implements its semantic compilation pipeline **in Elixir**, providing full behavioral compatibility with Rust `ggen`. It does **not** shell out to or link the Rust `ggen` CLI/binary (`ggen-engine` sync/write binaries). However, it **does embed one real native Rust component** from the `~/ggen` workspace: a native Rustler NIF wrapping `ggen-graph-wasm`'s `OxigraphEngine`.

Evidence:
- `grep -rn "System.cmd\|Port.open" lib/` confirms zero invocations of any external `ggen` executable.
- `lib/ggen_igniter/native/graph_nif.ex` compiles and loads `native/ggen_graph_nif`, wrapping the real `OxigraphEngine`.

---

## 1. RDF Ontology Parsing

Ontology loading is handled by `GgenIgniter.Ontology.load!/1` (`lib/ggen_igniter/ontology.ex`):

```elixir
def load!(path) do
  RDF.Turtle.read_file!(path)
end
```

- **Input**: Path to a W3C Turtle (`.ttl`) file (e.g., `priv/ggen/<pack>/ontology.ttl` or explicit `--ontology`).
- **Processing**: Parsed via `RDF.Turtle.read_file!/1` from the `rdf` Hex package into an in-memory `%RDF.Graph{}` struct.
- **Error Handling**: Raises if the file is missing or contains invalid Turtle syntax.

---

## 2. SPARQL Query Resolution & Backends

The engine stage compiles SPARQL queries against the parsed RDF graph or remote triple store. Query dispatch is managed through the `GgenIgniter.Engine` behaviour (`lib/ggen_igniter/engine.ex`), defining two callbacks:
- `prepare!(graph, opts)`: Prepares the execution context (e.g., in-memory store initialization or HTTP client creation).
- `run(context, query_string)`: Executes a SPARQL query string and returns a list of row maps `[%{"var" => value}]`.

Three query backends are supported via `GgenIgniter.Engine.registry/0`:

```elixir
%{
  "oxigraph" => GgenIgniter.Engine.Oxigraph,  # DEFAULT
  "sparql"   => GgenIgniter.Engine.Sparql,
  "qlever"   => GgenIgniter.Engine.Qlever
}
```

### Backend Comparison

| Engine | Implementation | Characteristics & Trade-offs |
|---|---|---|
| **`oxigraph`** *(Default)* | `GgenIgniter.Query.Oxigraph` via Rustler NIF (`native/ggen_graph_nif`) | In-process, spec-conformant SPARQL 1.1 engine. Correctly honors `ORDER BY` clauses. Requires Rust toolchain (`cargo`) at compile time. Raw term strings (angle-bracketed IRIs, quoted literals) are normalized by `query_turtle/2`. |
| **`sparql`** | `GgenIgniter.Query` via pure-Elixir `sparql` hex package (v0.3.12) | Pure Elixir, no Rust dependency. **Known defect**: Does not correctly preserve `ORDER BY` ordering on complex join queries (can reverse results). Unwraps `RDF.IRI` and `RDF.Literal` terms to primitive Elixir values. |
| **`qlever`** | `GgenIgniter.Query.Qlever` via HTTP client (`Tesla`/`Finch` + `gno`) | Connects to an external high-performance QLever triple store. Requires `--store-id` pointing to the `gnoa:Qlever` store resource in the configuration graph. |

---

## 3. Multi-Query Binding Merge

Templates often require data from multiple SPARQL queries (e.g., one query for entity metadata, another for fields, another for relationships).

Query text is resolved by `Mix.Tasks.GgenIgniter.Sync.resolve_named_queries!/2` (`lib/mix/tasks/ggen_igniter.sync.ex:1162-1204`), merging queries from three sources in ascending order of precedence (later sources override earlier ones):
1. **Frontmatter `sparql:` queries**: Inline queries declared in the template's YAML header.
2. **Pack gate queries**: Files matching `<pack_dir>/gates/*.rq`.
3. **Explicit `--query name=path.rq` CLI switches**.

Once executed, query results are merged into the template execution context by `Mix.Tasks.GgenIgniter.Sync.build_bindings/2` (`lib/mix/tasks/ggen_igniter.sync.ex:1296-1316`):

```elixir
def build_bindings(named_results, for_each_row \\ nil) do
  # 1. Bind each named query as an atom key pointing to its list of row maps
  list_bindings =
    Enum.map(named_results, fn {name, rows} -> {String.to_atom(name), rows} end)

  # 2. Single-row root promotion: if a query returned EXACTLY 1 row, flatten its columns
  flattened =
    named_results
    |> Enum.filter(fn {_name, rows} -> length(rows) == 1 end)
    |> Enum.flat_map(fn {_name, [row]} -> row end)
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)

  # 3. For-each driver row flattening (if in fan-out mode)
  row_flattened =
    case for_each_row do
      nil -> []
      row -> Enum.map(row, fn {k, v} -> {String.to_atom(k), v} end)
    end

  list_bindings
  |> Keyword.merge(flattened)
  |> Keyword.merge(row_flattened)
end
```

---

## 4. Single-Row Root Promotion

Mirroring Rust `ggen`'s ergonomics, when a named query result contains **exactly one row** (such as a specification, domain metadata, or global configuration query), its columns are automatically promoted to top-level, atom-keyed bindings.

### Ergonomic Benefit
Instead of forcing template authors to access fields via index/head functions:
```eex
<%= hd(@spec)["module_name"] %>
```
Root promotion allows direct variable interpolation in EEx or Tera templates:
```eex
<%= @module_name %>
```
When multiple single-row queries contain colliding column names, later queries in the resolution order win.

---

## 5. Fan-Out (`for_each:` / `--for-each`)

When code generation requires producing multiple output files from a collection of records (e.g., generating one Ash resource file per domain entity), semantic compilation uses **multi-row fan-out**.

### Specification
- **Frontmatter**: `for_each: query_name` in the template YAML header.
- **CLI**: `--for-each query_name` passed to `mix ggen_igniter.sync`.
- **Dynamic Output Path (`--out` / `to:`)**: The output destination template is evaluated as an EEx template against each row's bindings.

### Execution Flow
1. Fetch the driver query rows identified by `for_each` from `named_results`.
2. For each driver row:
   a. Construct row-specific bindings where the driver row's columns are promoted to the top level (overriding any global single-row keys).
   b. Evaluate the output path template (e.g., `"lib/my_app/resources/<%= String.downcase(resource_name) %>.ex"`).
   c. Render the template body with the row bindings.
   d. Emit a planned actuation item for that specific output path.

```elixir
# lib/mix/tasks/ggen_igniter.sync.ex:631-637
renders =
  Enum.map(rows, fn row ->
    bindings = build_bindings(named_results, row)
    content = Render.render(template_string, bindings)
    out_path = if out_template, do: Render.render(out_template, bindings)
    {bindings, content, out_path}
  end)
```

---

## 6. Template Rendering Engines

Two template rendering engines exist in the codebase:
1. **`GgenIgniter.Render` (Stdlib EEx)**:
   - Default renderer (`lib/ggen_igniter/render.ex`).
   - Evaluates Elixir EEx expressions (`<%= ... %>`) against query result bindings.
2. **`GgenIgniter.Render.Tera` (Hand-Rolled Tera Subset)**:
   - Implemented in `lib/ggen_igniter/render/tera.ex` to support marketplace packs containing Jinja2/Tera-style templates (`*.tmpl`).
   - Supports variable interpolation (`{{ var.field }}`), loops (`{% for x in list %}`), conditionals (`{% if cond %}`), comments (`{# ... #}`), and filters (`capitalize`, `filter(attribute="...", value="...")`).
