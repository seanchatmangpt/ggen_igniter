# `lib/mix/tasks/` — CLI entry points

- File naming mirrors the invoked task name exactly: `ggen_igniter.sync.ex` ->
  `mix ggen_igniter.sync`, `ggen_igniter.doctor.ex` -> `mix ggen_igniter.doctor`.
  A new CLI task follows the same `ggen_igniter.<verb>.ex` -> `Mix.Tasks.GgenIgniter.<Verb>`
  pattern — never a bare verb without the `ggen_igniter.` namespace prefix.
- These are `Igniter.Mix.Task` modules using CLI-plumbing only
  (`Igniter.Mix.Task`, `add_notice/2`) — do **not** reach for Igniter's
  AST-mutation API (`Igniter.Project.Module`/`Igniter.Code`/`Sourceror.Zipper`)
  here; that's real, disclosed future work tracked in `docs/status.md`, not
  something to add incidentally while touching an unrelated flag.
- Business logic (ontology load, engine run, render, actuate) belongs in
  `lib/ggen_igniter/*.ex`, not inlined in the task module — a task file should
  read as flag-parsing + orchestration calling into the library, mirroring how
  `ggen_igniter.sync.ex` delegates to `Ontology`/`Engine`/`Render`/`Actuate`.
  Exception: `sync.ex`'s frontmatter-to-actuation-spec resolution
  (`match_spec_to_marker!/2` et al.) is deliberately private to this file for
  now — see the `Reconcile.run/1` vs `sync.ex` feature-parity note in the root
  `CLAUDE.md` before assuming that logic should move.
- New flags: document every one in `docs/reference/cli/{sync,doctor}.md` in
  the same change — this repo treats an undocumented flag as an incomplete
  change, not a follow-up.
- `mix ggen_igniter.doctor`'s checklist is numbered and exhaustive (17 checks
  today) — adding a check means updating both the doctor task's own numbered
  list and `docs/reference/cli/doctor.md`'s numbered list so they can't drift.
