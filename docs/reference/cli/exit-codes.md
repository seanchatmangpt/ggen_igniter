# CLI exit codes and JSON envelope

Source: `lib/ggen_igniter/task_contract.ex` (`GgenIgniter.TaskContract`). One exit-code table and
one JSON envelope shared by the `mix ggen_igniter.*` tasks, so a CI job can branch on the exit
code alone. Last updated 2026-09-28 (v26.9.30 WA2, lane F2 fixes).

## Global table

| Code | Name | Standing | Meaning |
|---|---|---|---|
| 0 | `ok` | `ALIVE` | Succeeded / clean. |
| 1 | `refusal` | `REFUSED` | A typed refusal or failed gate (`REFUSED:<CODE> <detail>`). |
| 2 | `invocation` | `UNKNOWN` | Bad invocation: missing or unknown flag, unresolvable input. |
| 3 | `unsupported` | `UNSUPPORTED` | Request outside the task's supported scope (`plan`'s read-only path). |
| 4 | `drift` | `BLOCKED` | `sync --check`: committed generated files differ from what the ontology produces. |

Collision analysis: `plan` already used 0/2/3; the `epoch.*` tasks use 0/1/2 (1 = refusal or
unknown provenance); `verify` and `doctor` use 0/1. Code 4 was unused, so drift has its own code and
never aliases a refusal (the tool refused vs. the tree is stale).

## Per-task columns

| Task | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| `sync` | ran / no-op | reactor refusal, stale outputs, `--lock` mismatch | bad invocation (incl. a missing `--ontology`/`--template` file) | — | — |
| `sync --check` | clean (or only preserved stale files) | refusal (incl. stale outputs under `--on-stale refuse`) | bad invocation | — | drift (incl. stale outputs under `--on-stale prune`) |
| `plan` | plan computed (changes pending or not) | — | bad invocation (incl. unknown flag) | unsupported capability | — |
| `verify` | pack verifies | pack failed verification | bad invocation (no `--pack`, unknown flag, missing pack dir/ontology) | — | — |
| `doctor` | all checks passed | a check failed | unknown flag | — | — |
| `epoch.check` | all `ALIVE_*` | refusal / unknown provenance | invocation | — | — |
| `epoch.explain` | always, on a judged file | — | invocation | — | — |

## JSON envelope

```json
{"data":{},"exit_code":4,"ok":false,"refusal":null,"schema_version":1,"standing":"BLOCKED","task":"sync"}
```

Keys are recursively sorted, so the same envelope always encodes to the same bytes
(`GgenIgniter.TaskContract.encode/1`). `refusal` is `null` or `{"code": "...", "detail": "..."}`;
its text form is `REFUSED:<CODE> <detail>`.

| Task | Flag | Notes |
|---|---|---|
| `sync` | `--json` (with or without `--check`) | `data`: `mode`, `drifted`, `drifted_count`, `lines`, `notices` |
| `plan` | `--json-envelope` | `data` = the legacy `--json` document; plain `--json` unchanged |
| `verify` | `--json-envelope` | `data` = the legacy `--json` document minus `ok`; plain `--json` unchanged |

On every `--json`/`--json-envelope` path the task halts directly, so no trailing Igniter footer
corrupts the single JSON document (`lib/mix/tasks/CLAUDE.md`, quirk 2).

## See also

- `docs/reference/cli/sync.md` — `--check`, `--json`, `--lock`
- `docs/reference/cli/plan.md` — `--json-envelope`
