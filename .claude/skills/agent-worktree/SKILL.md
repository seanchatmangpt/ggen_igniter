---
name: agent-worktree
description: Isolate a bounded implementation task in its own git worktree for ggen_igniter with an explicit cwd contract, before parallel dispatch
---

Use before dispatching more than one concurrent implementation/verification agent
against this repo, so agents never collide on the same working tree.

1. Create the worktree: `git worktree add ../ggen_igniter-wt-<name> -b <name>` from
   current `main` (or the base ref the task specifies).
2. Print and hand the dispatched agent this exact prefix as the first line of its
   prompt: "You are working in `<ABS_PATH_TO_WORKTREE>`. Before anything else, run
   `cd <ABS_PATH> && pwd && git remote -v && git rev-parse --abbrev-ref HEAD` and
   include that output verbatim at the top of your report. If the remote does not
   match `ggen_igniter`, stop and report a mismatch instead of proceeding."
3. Never let two agents target the same worktree path or write to the primary
   checkout directly during fan-out.
4. On merge back: run the `gate` skill inside the worktree first, then
   `git checkout main && git merge --no-ff <name>` (or rebase, per task), re-run the
   gate on `main`, then `git worktree remove ../ggen_igniter-wt-<name>`.
5. Serialize merges one at a time — parallel worktrees for authoring, but the
   integration/merge step itself is never concurrent.
