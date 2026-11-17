# 13 Igniter Integration

Standing: UNVERIFIED

Lane 13 of v26.11.17. Scope: Igniter codemods and AST edits, `docs/integrations/igniter`,
Igniter version pins and API usage. Method: read-only grep and file reads this pass; no
`mix` command was run, so nothing here is a runtime claim. Main result: the three
`docs/integrations/igniter/*.md` files state that Igniter AST APIs are NOT USED and that
AST mutation is PLANNED, but `lib/` calls `Igniter.Code.*`, `Igniter.Project.*` and
`Sourceror.Zipper` in several modules. The docs also mis-cite `actuate.ex` line ranges
and describe a non-atomic write that the module doc says it replaced. One tracked-doc
path (`docs/jira/v26.9.28/upstream-igniter-issues.md`) is cited by code but has moved.

## Findings

Evidence is `file:line` from grep/read output seen this pass (static only). Abbreviations:
`pa`=`docs/integrations/igniter/project-actuation`, `am`=`.../ast-mutation`, `df`=
`lib/ggen_igniter/doctor_fixes`, `sr`=`lib/ggen_igniter/refactors/safe_rename`,
`actuate.ex`=`lib/ggen_igniter/actuate.ex`, `canaries_test`/`idempotence_test`/`helper`=
`test/ggen_igniter_upstream_canaries_test.exs`, `..._igniter_idempotence_test.exs`,
`test/test_helper.exs`.

| id | finding | standing | evidence |
|---|---|---|---|
| F1 | Docs say AST APIs NOT USED; lib uses them | UNVERIFIED | pa.md:113; df.ex:358 |
| F2 | ast-mutation.md says AST rewrite PLANNED | UNVERIFIED | am.md:110; df.ex:33 |
| F3 | Real codemods: SafeRename, import_dep, deps edit | UNVERIFIED | sr.ex:99; v26_9_28.ex:13 |
| F4 | Docs list 2 Mix.Task modules; grep finds 11 | UNVERIFIED | pa.md:36; grep lib/mix/tasks |
| F5 | tasks/CLAUDE.md bans AST API; install uses | UNVERIFIED | tasks/CLAUDE.md:7; install.ex:15 |
| F6 | Cite inject_content! 115-220; actual line 283 | UNVERIFIED | am.md:15; actuate.ex:283 |
| F7 | Cite already_present_at? 347-357; actual 479/499 | UNVERIFIED | am.md:81; actuate.ex:479 |
| F8 | safety.md shows File.write!; code is temp+rename | UNVERIFIED | safety.md:20; actuate.ex:32 |
| F9 | Cite write_file!/3 at 75-101; actual 134 | UNVERIFIED | safety.md:14; actuate.ex:134 |
| F10 | :file scope/occurrence raise; docs thin | UNVERIFIED | am.md:44; sync.ex marker fn |
| F11 | Upstream-issue register is archived | UNVERIFIED | docs/archive/jira/v26.9.28 |
| F12 | Canaries tagged :integration | UNVERIFIED | canaries_test:20; helper:143 |
| F13 | mix test excludes :integration (canaries) | UNVERIFIED | mix.exs:116; helper:152 |
| F14 | Pin ~> 0.8 unconditional; lock 0.8.4 | UNVERIFIED | mix.exs:191; mix.lock:48 |
| F15 | DoctorFixes outside idempotence harness | UNVERIFIED | idempotence_test:14 |
| F16 | compose_task LIVE; tests cover other tasks | UNVERIFIED | pa.md:112; grep test/ |
| F17 | rename_options delegates AST per ban | UNVERIFIED | rename_options.ex:59 |
| F18 | Tests use igniter.rewrite internals | UNVERIFIED | canaries_test:60; sr.ex:150 |

## Notes on selected findings

- F1/F2/F3/F5: these four are one defect. The prose in `docs/integrations/igniter/` and
  `lib/mix/tasks/CLAUDE.md` predates the v26.9.28 codemod work (`status.md:153`). The
  code comments in `doctor_fixes.ex:33-53` already describe the pure-zipper approach, so
  the code is self-documenting and the integration docs are the stale side.
- F4: the 11 modules are doctor, fortune5_ready, hand_authored, install,
  manifest.dump, packs, plan, rename, shacl, sync, upgrade. The docs listing is a subset.
- F8: `actuate.ex:85-93` also says some paths still use a direct `File.write!/2`, so
  `safety.md` is partly right for those paths; which paths was not traced this pass.
- F11: the doctor task and canary test reference the register by name; whether they
  cite the old `docs/jira/v26.9.28/` path or the archive path was not checked.
- F13/F18: the canary suite is the designed tripwire for upstream Igniter fixes. If it
  never runs in default CI, an Igniter bump can retire a workaround silently. Whether
  `ci.yml` runs the `:integration` lane was not read this pass (UNVERIFIED).

## Not examined

- No `mix compile`, `mix test` or `mix ggen_igniter.doctor` was run.
- Igniter 0.8.4 source under `deps/` was not read; API shape of `add_issue`,
  `compose_task` and `Igniter.Test` is taken from the repo's own comments.
- `ggen_igniter.fortune5_ready`, `hand_authored`, `manifest.dump` Igniter usage was
  counted by grep only, not read.

## Next

1. Rewrite `project-actuation.md:106-116` and `ast-mutation.md:101-113` to separate
   the generator actuator (line splice) from the codemod tasks (AST), with citations.
2. Drop `lib/mix/tasks/CLAUDE.md:7-9` or scope it to `sync`/`doctor` only.
3. Replace stale `actuate.ex` line cites in `ast-mutation.md` and `safety.md` with
   symbol names; update the `safety.md` write snippet to the temp-then-rename flow.
4. Run `mix test --include integration test/ggen_igniter_upstream_canaries_test.exs`
   and record real output; confirm `ci.yml` runs that lane.
5. Run `mix ggen_igniter.doctor` and `mix test test/ggen_igniter_igniter_idempotence_test.exs`
   to move F14/F15 off static evidence.
6. Add an idempotence harness path for `DoctorFixes` (accept source strings) so its
   zipper rewrites get the same apply-twice falsifier as SafeRename.

## See Also

- `docs/integrations/igniter/ast-mutation.md`
- `docs/integrations/igniter/project-actuation.md`
- `docs/integrations/igniter/safety.md`
- `docs/archive/jira/v26.9.28/upstream-igniter-issues.md`
- `docs/jira/v26.11.17/LANES.md`
