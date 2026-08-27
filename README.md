# GgenIgniter

An Elixir bootstrap of [ggen](https://github.com/seanchatmangpt/ggen)'s
ontology-to-code pipeline: load an RDF ontology, run one or more named SPARQL
queries against it, render the results through an EEx template, and write the
result to disk with the same write-safety guards (idempotent no-op detection,
`unless_exists`, `skip_if`) as the real Rust `ggen`'s `ggen-engine/src/write.rs`.

Pipeline: `Ontology.load!/1` -> `Engine.run/2` (once per `--query`) ->
`Render.render/2` -> `Actuate.write_file!/3`.

## Installation

Add `ggen_igniter` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:ggen_igniter, "~> 26.8.26"}
  ]
end
```

## Usage

### `mix ggen_igniter.sync`

```
mix ggen_igniter.sync --ontology path.ttl --query name=path.rq (repeatable) --template path.eex --out path.ex
```

Each `--query name=path.rq` result is bound in the EEx template under `name`
as the full list of result rows (string-keyed maps). A query whose result has
exactly one row also has that row's own columns merged directly into the
top-level bindings, atom-keyed, so a single-row query like `spec` can be
referenced as bare `module_name`/`package_name` instead of
`hd(spec)["module_name"]`.

#### Engines: `--engine sparql` / `--engine qlever` / `--engine oxigraph`

`--engine sparql` (default) runs every query in-process against the loaded
`%RDF.Graph{}` via the `sparql` hex package:

```
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --query sections=test/fixtures/sections.rq \
  --query entities=test/fixtures/entities.rq \
  --query fields=test/fixtures/fields.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex
```

`--engine oxigraph` runs every query in-process too, but via a real native
[oxigraph](https://github.com/oxigraph/oxigraph) engine (a Rustler NIF over
`ggen`'s `ggen-graph-wasm` `OxigraphEngine`) instead of the pure-Elixir
`sparql` hex package. No extra required option — it works directly off the
already-loaded graph, same as `sparql`. Useful when a query shape trips the
`sparql` hex package's known `FILTER NOT EXISTS`/`UNION` limitation:

```
mix ggen_igniter.sync \
  --engine oxigraph \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex
```

`--engine qlever` runs every query instead against a real, already-running
[QLever](https://github.com/ad-freiburg/qlever) SPARQL endpoint (real HTTP,
no in-process SPARQL evaluation). `--ontology` is still read as a
`%RDF.Graph{}`, but only to look up the `gnoa:Qlever`-typed store resource
named by `--store-id` — the query text itself never touches this graph's
data, it runs on the remote QLever store. `--store-id` is required with this
engine:

```
mix ggen_igniter.sync \
  --engine qlever \
  --ontology config/gno/test/store.ttl \
  --store-id http://example.com/Qlever \
  --query spec=priv/ggen/some-pack/gates/010.rq \
  --template priv/ggen/some-pack/templates/out.ex.eex \
  --out lib/generated.ex
```

#### Multi-row fan-out (`--for-each NAME`)

Mirroring the real Rust ggen's `for_each:` frontmatter field, pass
`--for-each NAME` where `NAME` is one of the named `--query` results to
render the template once **per row** of that query, with that row's own
columns merged into the top-level bindings. Because there is no longer one
static output path, `--out` is itself rendered through
`GgenIgniter.Render.render/2` using each row's bindings, so it must be an
EEx-renderable path template:

```
mix ggen_igniter.sync \
  --ontology test/fixtures/for_each_ontology.ttl \
  --query modules=test/fixtures/modules.rq \
  --for-each modules \
  --template test/fixtures/for_each_module.ex.eex \
  --out "lib/generated/<%= module_name %>.ex"
```

With three rows in the `modules` query result, this writes three separate
files, one per row.

#### `--dry-run`

Pass `--dry-run` to preview what would be written (or skipped) without
touching disk — each planned action is printed as `planned: write <path>` or
`planned: skip <path> (...)` instead of being executed.

#### The `--pack` convention

Given `priv/ggen/<pack-name>/{ontology.ttl,gates/*.rq,templates/extension.ex.eex}`:

```
mix ggen_igniter.sync --pack audit-trail-pack --out lib/generated.ex
```

`--ontology`/`--query`/`--template` are all still overridable explicitly; an
explicit flag always wins over the pack-derived default. `--pack-dir DIR`
uses `DIR` directly instead of resolving `priv/ggen/<pack>/`. Packs can also
be fetched from a marketplace source (`github:owner/repo[@ref]` or
`hex:name[@version]`) via `GgenIgniter.Pack.fetch_pack!/2`.

### `mix ggen_igniter.doctor`

```
mix ggen_igniter.doctor [--pack NAME | --pack-dir DIR] [--engine sparql|qlever] [--store-id ID]
```

Runs a fixed checklist of real checks (no fabricated pass output):

1. Elixir/OTP version satisfies this project's `mix.exs` requirement.
2. Required deps (`rdf`, `sparql`, `igniter`, and `gno` when `--engine qlever`)
   are loaded with resolvable `:vsn`.
3. Advisory for the known `sparql` 0.3.12 `FILTER NOT EXISTS` + `BIND` inside
   `UNION` bug.
4. (only with `--engine qlever`, or a pack ontology naming a `gnoa:Qlever`
   store via `--store-id`) the QLever endpoint is really reachable via a real
   `ASK` query.
5. Pack `ontology.ttl` exists and parses as valid Turtle.
6. At least one gate query (`gates/*.rq`) is present.
7. At least one template (`templates/*.{eex,tmpl}`) is present.
8. Every gate query is syntactically valid SPARQL (parse-only, no execution).
9. Target (cwd) git status — clean vs dirty is reported, never fails the run
   by itself.

Checks 5-8 only run when `--pack`/`--pack-dir` is given. Exits non-zero only
if any check comes back `:error`.

## Testing

### `mix e2e`

`mix e2e` (alias for `mix run test/e2e/run_e2e.exs`) is a real, sequential
end-to-end lifecycle test, kept separate from the default `mix test` suite
because it needs real network access and takes several minutes: it scaffolds
a genuine, throwaway Ash + Phoenix application in a temp directory via real
`mix archive.install hex phx_new`/`mix archive.install hex igniter_new`/
`mix igniter.new` subprocess calls (hex/GitHub fetches, no mocking), adds
`ggen_igniter` itself as a `path:` dependency, and runs `mix deps.get`.

Against that one scaffolded app it then drives a multi-stage lifecycle with
real `mix ggen_igniter.sync` subprocess invocations against the
`test/fixtures/ash-lifecycle-pack/` fixture pack — resource creation,
attribute addition, a `belongs_to`/`has_many` relationship, a custom action,
an `AshPhoenix.Form` create/update/validate/submit round-trip, a real
`mix ash_phoenix.gen.live`-generated Phoenix LiveView, and finally an
attribute rename — running `mix compile --warnings-as-errors`/`mix test`
inside the scaffolded app after each stage.

Run it with:

```
mix e2e
```

It requires network access (hex/GitHub fetches via `mix archive.install`),
runs for several minutes, and uses real disk space in a temp directory
(cleaned up via `on_exit` when the test finishes). It is not part of the
default `mix test` suite — there is no `.github/workflows` CI config in this
repo, so it is not run by CI either; run it manually when you need to verify
the full lifecycle.

What it proves: that ggen_igniter-generated code stays consistent across a
real Ash resource, its `AshPhoenix.Form`, and its Phoenix LiveView through a
realistic edit lifecycle, including a rename.

#### `mix e2e` wall-clock baseline (real, cited)

Two real `mix e2e` runs captured this session (scratchpad
`e2e_run.log`, `e2e_output2.log`) both failed at Stage 5 (the scoped
`mix test test/ggen_igniter_form_lifecycle_test.exs` subprocess — an
`AshPhoenix.Form.submit/2` assertion issue unrelated to timing) after
**281.5s** and **299.0s** respectively (`ExUnit`'s own `"Finished in ..."`
line). Both runs therefore measure real wall-clock cost for Stages 0–5 only
(14 of the 20 real `mix`/subprocess invocations `lifecycle_test.ex` makes
end to end), not the full 8-stage lifecycle.

Neither log carries per-subprocess timestamps (each stage's stdout is
merged into one `cmd!/3` capture with no per-line clock), so the
per-subprocess breakdown below is a structural estimate — call-count and
known Elixir/Mix cost class, not measured — from reading
`test/e2e/lifecycle_test.ex` and `test/e2e/support/e2e_case.ex` directly:

| Stage | Real subprocess calls | Cost class |
|---|---|---|
| 0 (scaffold + dep wiring) | `archive.install hex phx_new`, `archive.install hex igniter_new`, `igniter.new ... --install ash,ash_phoenix --with phx.new` (runs 3 installers), `deps.get`, `compile!`, `test!` = **6** | Heaviest stage by far — `igniter.new` alone triggers 3 chained installers (Ash, AshPhoenix, Phoenix) each doing their own codegen + potential fresh `mix.exs` deps, and `deps.get` does a cold Hex/Git dependency resolution across the whole tree (the `:igniter`/`:sourceror`/`:gno`/`:dcatr` relaxations exist precisely because this resolution is fragile — see (c) below) |
| 1 (sync x2 + compile + test) | `ggen_igniter.sync` x2, `compile!`, `test!` = **4** | Each `sync` is itself an `Igniter.Mix.Task` subprocess (its own BEAM boot); `compile!`/`test!` are incremental after Stage 0's cold compile, so cheaper than Stage 0's |
| 2 (sync x1 + compile + test) | **3** | Same class as Stage 1, one fewer `sync` call |
| 3–4 (pure assertions) | **0** | Free — no subprocess, checks Stage 2's already-generated files |
| 5 (Form round-trip, scoped `mix test`) | **1** | Where both captured real runs actually failed/stopped |
| 6 (`ash_phoenix.gen.live` + compile x2 + scoped `mix test`) | **4** | `ash_phoenix.gen.live` is a real Igniter-driven LiveView generator subprocess; two `compile!` calls bracket the hand-edited router |
| 7 (sync + expected-failing compile) | **2** | The `compile!` here is expected to raise (rename leaves a stale `ticket.assignee` reference) |
| **Total (full 8-stage run)** | **20** | Only 14 of these were exercised by the two captured real runs |

**Conclusion for the in-memory-vs-subprocess architecture decision** (not
attempted here — out of scope per this task): Stage 0 is the dominant cost
by call count and by known Mix/Hex cost class (3 chained Igniter installers
plus one cold `deps.get` resolution, none of which touch `ggen_igniter`'s
own sync/render logic at all). Stages 1–2 and 7's `sync!`/`compile!`/
`test!` calls are the ones actually exercising `ggen_igniter` behavior, and
`compile!`/`test!` there run against an *already-scaffolded* app, i.e. the
part of the pipeline most amenable to swapping in an in-memory
`Igniter.Test.test_project/1` if a scaffold's on-disk state can be
faked convincingly enough for Ash to compile against it — Stage 0 itself
(real `phx.new`/`ash`/`ash_phoenix` installers + real `deps.get`) is the
part most resistant to that swap, since it is exactly the real, on-disk,
network-resolved dependency graph this suite exists to catch drift in (see
(c) below).

## Known Limitations

Three previously-disclosed gaps, re-verified fresh in this repo on
2026-08-27 (not carried forward from any prior claim):

1. **Frontmatter `inject`/`before`/`after`/`at_line` wiring — STILL OPEN.**
   `GgenIgniter.Frontmatter` parses these four fields from a template's YAML
   frontmatter (`lib/ggen_igniter/frontmatter.ex`), and
   `GgenIgniter.Actuate.inject_content!/5` (`lib/ggen_igniter/actuate.ex`) is
   fully implemented and tested — but `lib/mix/tasks/ggen_igniter.sync.ex`
   contains no call to `inject_content!` and no branch on `:inject` at all
   (confirmed by grep: zero matches). Setting `inject: true` (or
   `before`/`after`/`at_line`) in a template's frontmatter today has no
   observable effect on `mix ggen_igniter.sync`'s behavior; a consumer that
   needs injection must call `GgenIgniter.Actuate.inject_content!/5`
   directly. `frontmatter.ex`'s own moduledoc documents this same gap
   in-source (search "Disclosed gap" there) — this README entry mirrors
   that verified, current state, not a stale summary of it.

2. **`test/e2e/run_e2e.exs` exit-code masking — CLOSED.** The script starts
   `ExUnit.start(timeout: 300_000, autorun: false)`, runs the suite via a
   real `%{failures: failures} = ExUnit.run()`, and calls `System.halt/1`
   keyed directly off that real `failures` count (`System.halt(1)` /
   `System.halt(0)`) — verified by reading the file's actual 13 lines
   directly; `autorun: false` is present and `ExUnit.run/0`'s return value,
   not a fixed exit code, drives the halt.

3. **Scaffolded-consumer dependency conflicts
   (`igniter`/`sourceror`/`gno`/`dcatr`/`ash_domains`) — CLOSED.** All four
   fix functions this gap depends on are real, present, and actually
   invoked in `test/e2e/support/e2e_case.ex` and
   `test/e2e/lifecycle_test.ex`: `relax_scaffolded_igniter_dep!/1` and
   `relax_scaffolded_sourceror_dep!/1` strip the scaffolded app's own
   generated `only: [:dev, :test]` restrictions so they no longer diverge
   from `ggen_igniter`'s unrestricted `:igniter`/`:sourceror` requirements;
   `add_dcatr_env_config!/1` writes `config :dcatr, env: Mix.env()` into the
   scaffolded app's own `config/config.exs` (required because Mix never
   loads a path dependency's own config); and `add_ash_domains_config!/3`
   registers the pack's `SupportDesk.Support` domain module in `config
   :support_desk, ash_domains: [...]`. All four are called from
   `add_ggen_igniter_dep!/1` (itself called from `lifecycle_test.ex` Stage
   0) or directly from `lifecycle_test.ex` line 102, before the first real
   `mix compile`.

## License

MIT — see [LICENSE](LICENSE).
