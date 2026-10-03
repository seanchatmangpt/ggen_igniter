# Tutorial: Your first `ggen_igniter.sync` run

Learn `ggen_igniter`'s core loop — ontology in, generated file out — by
running it end to end with the repo's own fixtures and then inspecting the
receipt and manifest it leaves behind.

Everything here is verified against the code in `lib/` at the working tree's
version (`mix.exs` `version: "26.10.4"`).

## Prerequisites

- Elixir `~> 1.17` and OTP `>= 25` (checked by `mix ggen_igniter.doctor`'s
  version check, `lib/mix/tasks/ggen_igniter.doctor.ex`).
- A working Rust/`cargo` toolchain: the native oxigraph Rustler NIF
  (`native/ggen_graph_nif`) is compiled when the library is compiled,
  regardless of which `--engine` you use at runtime
  (`lib/ggen_igniter/native/graph_nif.ex`).
- This repository checked out locally.

## 1. Install and sanity-check the environment

```
mix deps.get
mix ggen_igniter.doctor
```

`mix ggen_igniter.doctor` runs a fixed checklist of environment checks
(Elixir/OTP version, dependency wiring, the `sparql` version advisory, the
native NIF's build freshness plus a real functional smoke test, a version
policy check against `CHANGELOG.md`, and more). It exits 0 only when no
check comes back `:error` (`lib/mix/tasks/ggen_igniter.doctor.ex`).

## 2. Run one sync against the repo's audit-trail fixtures

```
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex
```

What happened, in order (`lib/mix/tasks/ggen_igniter.sync.ex`):

1. `Ontology.load!/1` parsed the Turtle file into a `%RDF.Graph{}`.
2. `Query.run/2` ran `spec.rq` once per `--query` flag. The query result is
   bound in the template under `spec` as the list of result rows
   (string-keyed maps). Because the result had exactly one row, that row's
   columns were *also* flattened into the top-level template bindings,
   atom-keyed — so the template can say bare `<%= module_name %>` instead of
   `hd(spec)["module_name"]`.
3. `Render.render/2` rendered the EEx template with those bindings.
4. `Actuate` wrote `tmp_out/probe.ex` under the write-safety guards
   (idempotent no-op detection, `unless_exists`, `skip_if`).

Open `tmp_out/probe.ex` — that is generated Elixir derived from the
ontology.

## 3. See `--dry-run` before you let it write

```
mix ggen_igniter.sync \
  --ontology test/fixtures/audit_trail_ontology.ttl \
  --query spec=test/fixtures/spec.rq \
  --template test/fixtures/extension.ex.eex \
  --out tmp_out/probe.ex \
  --dry-run
```

Nothing is written; each planned action prints as `planned: write <path>`.
A true no-op re-run also does not rewrite the reconciliation manifest file —
not even its timestamp (`lib/ggen_igniter/manifest.ex`).

## 4. Look at the two durable records

- **Manifest** — `<manifest-dir>/.ggen_igniter/manifest.json`, the
  current-state cache: what this recipe's most recent *successful* run
  wrote (`lib/ggen_igniter/manifest.ex`).
- **Receipt** — `<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`, one
  JSON object per admitted attempt, appended on *every* run regardless of
  outcome (`lib/ggen_igniter/receipt.ex`).

A receipt's `standing` is one of `:alive`, `:refused`, `:compensated`,
`:build_broken`, or `:compensation_failed` (`lib/ggen_igniter/receipt.ex`).
`:compensation_failed` is the operator-facing incident standing: files were
written, verification failed, and the undo itself failed.

## 5. Fan out one file per row

```
mix ggen_igniter.sync \
  --ontology test/fixtures/for_each_ontology.ttl \
  --query modules=test/fixtures/modules.rq \
  --for-each modules \
  --template test/fixtures/for_each_module.ex.eex \
  --out "lib/generated/<%= module_name %>.ex"
```

`--for-each NAME` renders the template once per row of the named query,
with the row's columns merged into the bindings; because the output path is
now per-row, `--out` is itself rendered as an EEx path template
(`lib/mix/tasks/ggen_igniter.sync.ex` moduledoc).

## Next steps

- Diátaxis how-to: `docs/diataxis/how-to/run-a-differential-engine-comparison.md`
- Diátaxis how-to: `docs/diataxis/how-to/verify-and-replay-a-pack.md`
- Reference: `docs/diataxis/reference/cli-tasks.md`
