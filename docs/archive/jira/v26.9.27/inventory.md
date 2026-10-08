# v26.9.27 legacy implementation inventory (epoch-004)

Method: `git ls-files -- 'lib/**/*.ex'` at HEAD 5ac166b6ae62753d96331c73d8ab3ccac6d0da38 (boundary candidate tree) → **104 files**. Classification per the epoch law: everything under `lib/` is the implementation plane the v26.10.1 boundary binds; `config/` and migrations are named future courts (not yet bound); knowledge plane (`.ttl`, `.rq`, `.eex`, `pack.toml`, docs) and tests are exempt and out of this inventory's scope.

Full per-file list is the stamp itself: `.ggen_igniter/epoch/v26.9.27-pre/watermark.json` (path + blob sha per file — identity, not blame). This document records the family rollup the extraction backlog (epoch-005) consumes.

## Family rollup (count by directory)

| family (lib/…) | files | classification |
|---|---:|---|
| `ggen_igniter/*.ex` (core: sync/engine/render/pack/receipt/manifest/actuate/ontology/query/artifact_identity/digest/epoch_* …) | 41 | implementation — extraction backlog epoch-005 |
| `ggen_igniter/semantic_jira/*` incl. `bootstrap/` (admission kernel, authority, shacl, descriptor, transition_log, git_ground_truth, epoch_plan …) | 18 | implementation — extraction backlog epoch-005 |
| `mix/tasks/*` (ggen_igniter.* + semantic_jira.* CLI shells, incl. the 3 epoch tasks) | 21 | implementation — thin shells over lib; extraction backlog epoch-005 (CLI task template row in HANDWRITTEN ledger) |
| `ggen_igniter/reactors/*` incl. `examples/` | 6 | implementation |
| `ggen_igniter/eds/*` | 4 | implementation |
| `ggen_igniter/telemetry/*` | 2 | implementation |
| `ggen_igniter/render/*` | 2 | implementation |
| `ggen_igniter/query/*` | 2 | implementation |
| `ggen_igniter/discovery/*` | 2 | implementation |
| `ggen_igniter/{stream,refactors,pack,native,gall,ea}` singles | 6 | implementation |
| **total** | **104** | |

Cross-check: `git ls-files -- 'lib/**/*.ex' | wc -l` = 104 = stamp's `files` count at head 5ac166b = family rollup sum. ✓

## Named future courts (recorded, not bound)

- `config/*.exs` — runtime wiring (epoch law table: bound)
- `priv/**/migrations/` — persistence implementation (epoch law table: bound)
- Neither is enumerated by the first court's glob (`lib/**/*.ex`); binding them is a `_LANES.md` Contract v1 change, not a silent widening.

## Note on the 6 untracked epoch files

At stamp time the epoch machinery itself (`lib/ggen_igniter/epoch_{watermark,freshness}.ex`, `lib/ggen_igniter/semantic_jira/epoch_plan.ex`, `lib/mix/tasks/ggen_igniter.epoch.{watermark,check,explain}.ex`) was untracked, hence absent from the stamp and present as candidates → REFUSED_NO_ATTRIBUTION in the witnessed firing. This is the correct reading: untracked pre-epoch implementation is invisible to the boundary — commit everything before the real v26.10.1 stamp.
