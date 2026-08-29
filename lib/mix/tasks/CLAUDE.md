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

## Known `Igniter.Mix.Task` base-class quirks (already fixed here — keep them fixed)

Two real quirks in `Igniter.Mix.Task`'s generated `run/1`/runner behavior bit
this repo's CLI tasks and were fixed for real in commits `6c2f109` (DX/QoL
swarm) and `b184d907` (AR-11 closure). Both fixes are already live in
`sync.ex`/`plan.ex`/`doctor.ex` today — this section exists so a future change
doesn't silently reintroduce either one. The regression coverage lives in
`test/ggen_igniter_cli_tasks_quirks_test.exs`, parametrized over every real
task so a reintroduction on any one of them (or a missing fix on a new 5th
task) fails that one shared file.

1. **`--help` vs `-h` split.** `Igniter.Mix.Task`'s generated `run/1` (see
   `deps/igniter/lib/mix/task.ex:80`) calls
   `Igniter.Mix.Task.help_requested?/1` (`deps/igniter/lib/mix/task.ex:333`,
   literally `def help_requested?(argv), do: "--help" in argv`) BEFORE this
   module's own `igniter/1` callback ever runs, and on a match dispatches to
   Mix's own generic `mix help <task>` renderer (the full raw `@moduledoc`)
   instead of the task's own concise help text. Critically, `help_requested?/1`
   checks ONLY the literal string `"--help"` — it never matches `-h`, even
   though `-h` is aliased to `--help` in every one of these tasks' own
   `info/2` schema (`aliases: [h: :help, ...]`). Without an explicit fix,
   `mix ggen_igniter.sync -h` (56 lines, this task's own concise USAGE block)
   and `mix ggen_igniter.sync --help` (184 lines, Mix's raw moduledoc dump)
   produce visibly different output for what a user expects to be the same
   flag — confirmed directly this way during the `6c2f109` swarm before the
   fix landed.

   **The fix (canonical example: `lib/mix/tasks/ggen_igniter.sync.ex`'s
   `@impl Mix.Task def run(argv)`):** override the generated `run/1` (it is
   `defoverridable run: 1`) to check for literal `"--help"` in `argv` and
   dispatch to the task's own help-and-halt function directly, falling
   through to `super(argv)` for every other argv (including bare `-h`, which
   still reaches `igniter/1` normally and is handled there via
   `opts[:help]`):

   ```elixir
   @impl Mix.Task
   def run(argv) do
     if "--help" in argv do
       print_help_and_halt()
     else
       super(argv)
     end
   end
   ```

   `doctor.ex`'s version of this override additionally checks
   `first_unknown_flag(argv)` in the same `cond` (a pre-existing, unrelated
   fix for a different exit-code bug) — see that file's own `run/1` for the
   combined shape. `plan.ex` mirrors `sync.ex`'s shape exactly. `replay.ex` is
   a plain `use Mix.Task` module with its own hand-rolled `OptionParser.parse/2`
   (not `Igniter.Mix.Task`) — it never had this bug in the first place, since
   there is no `Igniter.Mix.Task`-generated `run/1` intercepting anything for
   it; `--help`/`-h` both flow through its own `cond` in `run/1` identically.
   A brand-new CLI task built on `use Igniter.Mix.Task` needs this same
   `run/1` override; a task built on plain `use Mix.Task` (like `replay.ex`)
   does not.

2. **`--json` success path must `System.halt(0)` directly, never return
   normally to the Igniter runner.** `Igniter.Mix.Task`'s generated runner
   prints its own trailing notice/footer text (e.g.
   `"Igniter: No proposed content changes!"`) to stdout AFTER whatever the
   task itself already printed, whenever `igniter/1` returns an `%Igniter{}`
   with a clean diff (the case for every one of these read-only-to-the-target
   or notice-only tasks). For ordinary human output this is just extra noise
   at the end; for `--json` output it corrupts a single, validly-closed JSON
   document with trailing non-JSON bytes, which a strict single-document JSON
   parser (e.g. `python3 -m json.tool`) rejects outright.

   **The fix (canonical example: `lib/mix/tasks/ggen_igniter.doctor.ex`'s
   `run_checks/2`, all-checks-passed branch):**

   ```elixir
   opts[:json] ->
     # ... returning `igniter` here would let Igniter print its own
     # "No proposed content changes!" footer AFTER the JSON document
     # already written above, corrupting --json output.
     System.halt(0)
   ```

   `mix ggen_igniter.plan`'s `run_plan/2` success branch (`{:ok,
   pending_actuations}`) does the identical thing for the same reason — see
   that file's own comment for the parallel writeup. Both were fixed in
   `6c2f109` (`plan.ex` first) and `b184d907` (`doctor.ex`, closing the gap
   `6c2f109`'s own commit message explicitly disclosed as an open caveat).
   `sync.ex` does not need this fix: its success path always calls
   `Igniter.add_notice/2` and lets normal Igniter-runner printing happen —
   `sync` has no `--json` mode at all, so the corruption case never arises
   for it. A brand-new task with a `--json` success path must halt directly
   on that path the same way, rather than returning to the Igniter runner.

## See also

- `test/ggen_igniter_cli_tasks_quirks_test.exs` — the parametrized regression
  test for both quirks above, across all real CLI tasks.
