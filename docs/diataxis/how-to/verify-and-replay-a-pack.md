# How to: verify a pack fail-closed and replay its receipts

Two companion workflows: `mix ggen_igniter.verify` proves a pack's gates
cannot silently drop individuals; `mix ggen_igniter.replay` proves a past
run's outputs have not drifted since.

## Fail-closed verification: `mix ggen_igniter.verify`

`mix ggen_igniter.sync` scores a gate as passing when it returns **at least
one row** — fail-open for conjunctive SELECT gates: one missing triple
silently drops an individual from the plan
(`lib/mix/tasks/ggen_igniter.verify.ex` moduledoc). The verify task closes
that with two complementary checks that always both run:

1. **Inverted companion queries** — `<pack>/verify/*.unbound.rq`: zero rows
   is the pass condition (`GgenIgniter.GateVerify.verify_unbound/2`). Each
   finding names the gate, subject, and missing property.
2. **Per-gate cardinality contracts** — `<pack>/verify/cardinality.json`:
   a gate must emit exactly its contracted row count
   (`GgenIgniter.GateVerify.run/3` with `cardinality:`).

```
mix ggen_igniter.verify --pack test/fixtures/ash_manufacture_pack
```

Flags (verified against the task's `OptionParser.parse/2` `strict:` list,
`lib/mix/tasks/ggen_igniter.verify.ex`):

| flag | alias | meaning |
|---|---|---|
| `--pack PATH` | `-p` | required; pack directory holding `gates/` and `verify/` |
| `--ontology PATH` | `-o` | default `<pack>/ontology.ttl` |
| `--cardinality PATH` | | default `<pack>/verify/cardinality.json`; missing file = verified without contracts (not a failure) |
| `--json` | | one JSON document on stdout |
| `--json-envelope` | | same report inside the `GgenIgniter.TaskContract` envelope |
| `--help` | `-h` | usage text |

Exit codes: 0 both checks pass; 1 pack did not verify; 2 invalid invocation
(unknown flag, missing `--pack`, missing directory/ontology file).

Contracts are additive: gates absent from `cardinality.json` keep the
documented `>= 1 row` rule.

## Replay a receipt: `mix ggen_igniter.replay`

Load one `GgenIgniter.Receipt` and recompute *current* hashes of the inputs
it recorded, to answer: has anything this receipt depended on drifted?

```
mix ggen_igniter.replay .ggen_igniter/receipts/2026-10-03.jsonl
mix ggen_igniter.replay tmp/one_receipt.json --json --manifest-dir priv/ggen/audit-trail-pack
```

The receipt file can be either shape (`lib/mix/tasks/ggen_igniter.replay.ex`):

- a date-partitioned `.jsonl` partition
  (`<base_dir>/.ggen_igniter/receipts/<yyyy-mm-dd>.jsonl`) — the LAST line
  (most recent attempt) is replayed;
- a single JSON object file (one receipt extracted from a partition).

Drift categories, each only reported when the schema actually recorded a
comparable baseline (`build_report/2`):

- **output state changed** — `GgenIgniter.Receipt.hash_files/1` re-run over
  the receipt's `files` vs. the recorded `post_run_hash`.
- **ontology changed** — only when the recipe resolves to a manifest entry
  recording a `pack_dir` AND `metadata["graph_hash"]` is present;
  `<pack_dir>/ontology.ttl` is re-hashed with the same
  `"sha256:" <> hex` algorithm.
- **work order changed / work order absent** — when
  `metadata["work_order"]` recorded `{path, source_digest}`.

The template's *current* hash is reported informationally
(`template_current_hash`) but never counted as drift — no baseline was
recorded for it.

Flags: `--verify-only` (read-only comparison; the only mode implemented),
`--json` (`%{"drift" => bool, "categories" => [...], ...}` — also emitted
for invalid invocations), `--manifest-dir DIR` (default cwd), `--help`,
`--version`.

Exit codes: 0 no drift; 1 drift found; 2 invalid invocation.

## Machine contract for CI

Both tasks speak the `GgenIgniter.TaskContract` convention
(`lib/ggen_igniter/task_contract.ex`):

| code | name | standing | meaning |
|---|---|---|---|
| 0 | `:ok` | `ALIVE` | succeeded / clean |
| 1 | `:refusal` | `REFUSED` | typed refusal or failed gate |
| 2 | `:invocation` | `UNKNOWN` | bad invocation |
| 3 | `:unsupported` | `UNSUPPORTED` | outside the task's scope |
| 4 | `:drift` | `BLOCKED` | generated files differ from what the ontology produces (`sync --check`) |

`mix ggen_igniter.sync --check` forces the same dry-run pipeline as
`--dry-run` and turns planned writes into a drift set — exit 4 when
committed generated files differ from what the ontology now produces.
`--json` gives the uniform envelope
(`{"schema_version": 1, "task": ..., "ok": ..., "exit_code": ..., "standing": ..., "refusal": ..., "data": ...}`);
`--lock PATH` requires the pack directory's content digest to match the
lockfile (`GgenIgniter.PackLock.check/2`) and requires `--pack`/`--pack-dir`.
`--check` and `--dry-run` are mutually exclusive.
