# Lane 06: Mix.Tasks.GgenIgniter.Sync

Standing: UNVERIFIED

Read-only exploration of the sync task, its frontmatter, `--for-each`, `inject:` and
refusal paths. Method: source reading and `grep` over `test/`. No `mix` command was run
in this lane, so every row is a static observation and stays UNVERIFIED. Main findings:
moduledoc drift (stale pointers to removed or moved functions) and refusal paths with no
located test. Aliases used in the evidence column:

- S = `lib/mix/tasks/ggen_igniter.sync.ex` (1765 lines)
- I = `lib/ggen_igniter/injection.ex`
- T = `test/`

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| F1 | stale `match_spec_to_marker!` pointer | UNVERIFIED | S:199; I:75-78 |
| F2 | stale `run_pipeline!/3` references | UNVERIFIED | S:290,1127; S:1438 |
| F3 | F1 pointer repeated elsewhere | UNVERIFIED | CLAUDE.md:17; actuate.ex:18 |
| F4 | structured `skip_if:` refuses, untested | UNVERIFIED | S:1671-1676; grep empty |
| F5 | bad `--mode` refuses, untested | UNVERIFIED | S:1499-1505; grep empty |
| F6 | inject: only `occurrence: last` tested | UNVERIFIED | T:inject_test:305-322 |
| F7 | 0-row `--for-each`: refuse vs fan-out skip | UNVERIFIED | S:1251-1280 |
| F8 | `--for-each` now passes `:admit` | UNVERIFIED | S:1215-1228 |
| F9 | `sh_*` hooks gated by `--allow-sh` | UNVERIFIED | S:272-320,1460-1480 |
| F10 | `mode: eval` is arbitrary code exec | UNVERIFIED | S:238-270 |
| F11 | inject needs target and one anchor | UNVERIFIED | I:40-67 |
| F12 | Tera route ignores `--query` | UNVERIFIED | S:945-985 |
| F13 | ambiguous template / stem refusals | UNVERIFIED | S:1678-1711 |
| F14 | refusals classified by `~r/refus/i` | UNVERIFIED | S:740-752 |

Detail (all static reading; `S`, `I`, `T` as aliased above):

- F1-F3: moduledoc says the helper is private to S; it lives in I. S says
  `run_pipeline!/3` was deleted (S:1438-1451) yet S:290,1112,1127 still cite it.
- F4: grep `-rlE "not yet supported" test` returned no files. F5: grep for the
  `--mode must be "file" or "eval"` text in `test/` returned nothing.
- F6: `test/ggen_igniter_sync_inject_test.exs:305-322` covers `occurrence: last`; no
  `scope: :file` or `trim` without `exact` case found there (I:78-100 raises both).
- F7: lone template with 0 rows raises; `opts[:fan_out]` returns a notice and does not
  prune earlier outputs. "returned 0 rows" appears in
  `test/ggen_igniter_sync_for_each_reactor_test.exs`.
- F8: duplicate resolved `--out` and out-of-root `--out` are now refused; the old
  inline path last-writer-won (source comment only).
- F9: hook side effects bypass `:admit` and undo by design; hook failure is not fatal.
  Tests: `test/ggen_igniter_sync_sh_hooks_test.exs`.
- F10: `--out`, `--unless-exists`, `--skip-if` ignored under eval. Tests:
  `test/ggen_igniter_sync_eval_mode_test.exs`.
- F12: Tera route requires `--ontology`, treats `--out` as a directory, writes its own
  receipt. Tests under `test/ggen_igniter/pack_frontmatter/`.

## Refusals still in force

- structured `skip_if:` (F4)
- inject `scope: :file`, `occurrence` other than `first`, `trim: true` without `exact` (F6)
- inject with missing or multiple anchors, or a missing target file (F11)
- `sh_before:`/`sh_after:` without `--allow-sh` (F9)
- lone `--for-each` template with 0 driver rows (F7)
- duplicate or out-of-root `--for-each` outputs (F8)
- unknown `--mode` value (F5)

## Next

1. Run `mix test test/ggen_igniter_sync_inject_test.exs
   test/ggen_igniter_sync_eval_mode_test.exs` and paste output to move F6, F10, F11.
2. Add a Chicago-style subprocess test for structured `skip_if:` refusal (F4).
3. Add a test for `--mode bogus` exit code and message (F5).
4. Add inject refusal tests for `scope: file` and `trim: true` with `contains` (F6).
5. Fix moduledoc pointers to I and drop `run_pipeline!/3` references (F1-F3).
6. Replace regex-on-message classification (F14) with a typed refusal exception.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/reference/cli/sync.md`
- `lib/mix/tasks/CLAUDE.md`
- `docs/status.md`
