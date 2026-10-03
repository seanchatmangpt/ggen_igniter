# Reference: `mix ggen_igniter.*` CLI surface

Every flag below was transcribed from the task source in
`lib/mix/tasks/` at working-tree version `26.10.4` (`mix.exs`). The tasks
follow the `GgenIgniter.TaskContract` exit-code table (0 `:ok`, 1
`:refusal`, 2 `:invocation`, 3 `:unsupported`, 4 `:drift` — see
`lib/ggen_igniter/task_contract.ex`).

## `mix ggen_igniter.sync`

```
mix ggen_igniter.sync --ontology path.ttl --query name=path.rq (repeatable) \
  --template path.eex --out path.ex
```

Pipeline: `Ontology.load!/1` -> `Query.run/2` (once per `--query`) ->
`Render.render/2` -> `Actuate` writes, tracked by the reconciliation
manifest. Each query result is bound under `name` as the full row list
(string-keyed maps); a single-row query's columns are also flattened into
top-level atom-keyed bindings (later `--query` flags win collisions).

Option schema (verbatim from `info/2`'s `schema:`,
`lib/mix/tasks/ggen_igniter.sync.ex`):

| flag | type | notes |
|---|---|---|
| `--ontology` | string | Turtle ontology path |
| `--query` | string, repeatable (`:keep`) | `name=path.rq` |
| `--template` | string | EEx template |
| `--out` | string | output path (rendered as EEx under `--for-each`) |
| `--engine` | string | one of `graphlaw, oxigraph, qlever, sparql` (`GgenIgniter.Engine.valid_names/0`), a comma-separated list (comparison mode), or `all` |
| `--engine-report` | string | report path; `.json` ext = JSON, else Markdown |
| `--store-id` | string | required for `--engine qlever` |
| `--pack` | string | pack name under `priv/ggen/`; `NAME:STEM` selects one of several templates |
| `--pack-dir` | string | pack directory used directly (no `:STEM` suffix) |
| `--skip-if` | string | skip guard |
| `--unless-exists` | boolean | write guard |
| `--for-each` | string | render once per row of the named query |
| `--dry-run` | boolean | plan only; prints `planned: write|skip|inject|prune` lines |
| `--mode` | string | write mode |
| `--on-stale` | string | `refuse` (default) \| `prune` \| `preserve` for stale manifest artifacts |
| `--manifest-dir` | string | where `.ggen_igniter/` lives |
| `--verify-cwd` | string | post-run `mix compile --warnings-as-errors` directory |
| `--verify-base-sha` | boolean | post-run verification option |
| `--allow-sh` | boolean | admit `sh`-family actuation |
| `--check` | boolean | drift mode: forces the `--dry-run` pipeline, reports drift, exits 4 on drift; mutually exclusive with `--dry-run` |
| `--json` | boolean | uniform `TaskContract` envelope on stdout |
| `--lock` | string | pack digest lockfile; requires `--pack`/`--pack-dir` |
| `--help`, `-h` / `--version`, `-v` | boolean | aliases `h:`/`v:` only |

## `mix ggen_igniter.doctor`

```
mix ggen_igniter.doctor [--pack NAME | --pack-dir DIR] [--engine sparql|qlever] \
  [--store-id ID] [--hex-check] [--fix]
```

Runs a fixed checklist of environment checks: Elixir/OTP version,
dependency wiring, the `sparql` version advisory, consumer-project fix
rules (`:igniter`/`:sourceror`/`:dcatr`/`ash_domains`, `--fix`-able),
pack shape (only with `--pack`/`--pack-dir`), git status, native oxigraph
NIF build freshness plus a real functional smoke test, an optional hex
readiness check (`--hex-check`), and a version-policy check against
`CHANGELOG.md`. Exits 0 only if no check returns `:error`; exit 2 for
invalid invocation; exit 3 for an unsupported capability on this
platform/toolchain (exit-code comment block,
`lib/mix/tasks/ggen_igniter.doctor.ex`).

Schema flags: `--pack`, `--pack-dir`, `--engine`, `--store-id`,
`--hex-check`, `--fix`, `--strict`, `--json`, `--help`, `--version`,
`--quiet`, `--verbose`, `--no-color` (aliases `h`, `v`, `q`).

## `mix ggen_igniter.verify`

Fail-CLOSED pack checks: inverted `verify/*.unbound.rq` queries (zero rows
= pass) plus `verify/cardinality.json` per-gate contracts.

| flag | alias | meaning |
|---|---|---|
| `--pack PATH` | `-p` | required |
| `--ontology PATH` | `-o` | default `<pack>/ontology.ttl` |
| `--cardinality PATH` | | default `<pack>/verify/cardinality.json` |
| `--json` | | JSON report on stdout |
| `--json-envelope` | | `TaskContract` envelope |
| `--help` | `-h` | usage |

Exits 0 pass / 1 pack did not verify / 2 invocation
(`lib/mix/tasks/ggen_igniter.verify.ex`).

## `mix ggen_igniter.replay`

```
mix ggen_igniter.replay <receipt_file> [--verify-only] [--json] [--manifest-dir DIR]
```

`<receipt_file>`: a `.jsonl` receipt partition (last line replayed) or a
single JSON receipt object. Drift categories: `output state changed`,
`ontology changed`, `work order changed` / `work order absent`. The
template's current hash is informational only — no baseline is recorded.
Exits 0 no drift / 1 drift / 2 invocation
(`lib/mix/tasks/ggen_igniter.replay.ex`).

## Other tasks in `lib/mix/tasks/`

Also shipped (see each task's moduledoc for its own flags):
`ggen_igniter.install`, `ggen_igniter.plan`, `ggen_igniter.shacl`,
`ggen_igniter.upgrade`, `ggen_igniter.rename`, `ggen_igniter.packs`,
`ggen_igniter.pack.fetch`, `ggen_igniter.pack.lock`,
`ggen_igniter.manifest.dump`, `ggen_igniter.hand_authored`,
`ggen_igniter.ocel.seal`, `ggen_igniter.fortune5_ready`,
`ggen_igniter.frontier_release_plan`, `ggen_igniter.epoch`,
`ggen_igniter.epoch.check`, `ggen_igniter.epoch.explain`,
`ggen_igniter.epoch.watermark`, `ggen_igniter.sa2a.evidence`, and the
`semantic_jira.*` family (`bootstrap`, `observe`, `observe_prose`,
`admit_candidates`, `execute`, `frontier`, `court_map`, `descriptor`,
`prov`, `reconcile`, `xaas_receipt`).

## Engines (library surface)

- `GgenIgniter.Engine` behaviour — `prepare!(graph, opts)` and
  `run(context, query)`; registry `%{"sparql" => Engine.Sparql,
  "qlever" => Engine.Qlever, "oxigraph" => Engine.Oxigraph,
  "graphlaw" => Engine.Graphlaw}` (`lib/ggen_igniter/engine.ex`).
- `GgenIgniter.EngineRegistry.resolve/1,2` / `run_all/4` — comparison-mode
  parsing and fan-out (`lib/ggen_igniter/engine_registry.ex`).
- `GgenIgniter.Engine.Graphlaw` — wasm artifact resolution order:
  `:graphlaw_wasm_path` app env override, packaged `priv/graphlaw_wasm.wasm`
  (sha256 `8bfff66cccd1e1a4834d61a893888bb479f046c1da1152a29098be7de0fe71a8`),
  dev default `~/graphlaw/target/wasm32-wasip1/wasm/graphlaw_wasm.wasm`
  (`lib/ggen_igniter/engine/graphlaw.ex`).

## Receipts

`GgenIgniter.Receipt` appends one JSON object per admitted attempt to
`<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`. Standings:
`:alive`, `:refused`, `:compensated`, `:build_broken`,
`:compensation_failed` (`lib/ggen_igniter/receipt.ex`).
