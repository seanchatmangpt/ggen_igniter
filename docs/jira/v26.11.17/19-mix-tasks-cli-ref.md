# Lane 19: Mix Tasks vs CLI Reference

Standing: UNVERIFIED

Static comparison (no task was invoked) of the 43 modules under `lib/mix/tasks/` (42 task
files plus `CLAUDE.md`, enumerated with `ls`) against `docs/reference/cli/` (24 files).
Flags were read from each task's `schema:`/`strict:` block and diffed against doc text
with a grep heuristic that was then hand-checked for the rows below. The largest drift is
the engine surface: `--engine`/`--store-id` were removed from `sync` and `doctor` source
but remain documented as live. Eleven `semantic_jira.*` tasks, `ggen_igniter.pack_sync`
and `ggen_igniter.verify` flags lack reference docs. Exit-code table has no rows for
several tasks. Lane scope is read-only; nothing was run.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| F1 | sync.md documents --engine/--engine-report/--store-id; sync schema has none | REFUSED | sync.ex:122-146, 55-68; sync.md:21-23 |
| F2 | doctor.md header still lists --engine/--store-id; source says removed | REFUSED | doctor.md:8 vs doctor.ex:15,128,179 |
| F3 | engines.md title advertises --engine selection (stale vs F1) | UNVERIFIED | engines.md:1 (head only read) |
| F4 | plan.ex schema still has engine and store_id, unlike sync | UNVERIFIED | plan.ex:127-128 |
| F5 | doctor --verbose/--no-color/--quiet in schema, absent from flag table | PARTIAL | doctor.ex:166-170; doctor.md:87 only |
| F6 | plan --verbose/--no-color/--quiet in schema; --json-envelope documented | UNVERIFIED | plan.ex:137-139; plan.md:60 |
| F7 | check count: CLAUDE.md 17, doctor.md numbers to 19+, doctor.ex 17 defp | UNVERIFIED | lib/mix/tasks/CLAUDE.md; doctor.md:112,126 |
| F8 | verify has no page; --strict/--cardinality no doc hit | PARTIAL | verify.ex:83-91; exit-codes.md:57 |
| F9 | pack_sync has 0 hits in docs/reference | PARTIAL | grep -rn pack_sync docs/reference (empty) |
| F10 | semantic_jira bootstrap/complete/execute/prov/xaas_receipt: 0 doc hits | PARTIAL | grep -rlF per name, 0 hits |
| F11 | semantic_jira court_map/descriptor/frontier/reconcile: index.md prose only | PARTIAL | index.md Semantic Jira bullet |
| F12 | exit-codes table lacks rows for ~13 tasks (replay, rename, shacl, ...) | PARTIAL | exit-codes.md:26-42 |
| F13 | sync rows have 5 cells vs 6 code columns (header) | UNVERIFIED | exit-codes.md:24-28 |
| F14 | verify halts 2 invocation / 1 refusal, matches doc row | ALIVE (static) | verify.ex:109,121,152-156 |
| F15 | rename documented flags all exist in source | PARTIAL | heuristic diff for rename.md |
| F16 | review.md mentions --unified; regex did not find it in review.ex | UNVERIFIED | review.ex:47-56 not fully read |
| F17 | epoch.* flags match strict: lines; one shared doc epoch.md | PARTIAL | epoch.check.ex:33; explain.ex:28 |

Heuristic caveat: the diff script reported spurious "undocumented" names (`--aliases`,
`--schema`, `--positional`, `--else`, `--do`) from non-flag keys; those are excluded above.
Rows for tasks whose docs sit in `index.md` (verify, hand_authored, ocel.seal, fortune5_ready,
frontier_release_plan, sa2a.evidence, pm4pytest) were not flag-diffed individually.

## Next

1. Remove `--engine`/`--store-id`/`--engine-report` rows from `sync.md`; fix `doctor.md:8`;
   reconcile or retitle `engines.md` (F1-F3); decide whether `plan` keeps them (F4).
2. Add `--verbose`/`--no-color`/`--quiet` to `doctor.md` and `plan.md` tables (F5, F6).
3. Run `mix ggen_igniter.doctor --json` and count checks; align CLAUDE.md, `doctor.md`,
   source (F7).
4. Write `verify.md` and `pack-sync.md`; add stubs for the unreferenced `semantic_jira.*`
   tasks (F8-F11).
5. Complete the exit-codes per-task table and fix the column-count rows (F12, F13).
6. Run one adversarial invocation per task with an unknown flag to verify exit 2 (all rows).

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `docs/reference/cli/index.md`
- `docs/reference/cli/exit-codes.md`
- `lib/mix/tasks/CLAUDE.md`
