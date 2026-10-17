# SJIRA-261010-04 — ambient ggen 26.9.28 stale install hazard (USER-RUN)

- **Repo/base**: `/Users/sac/.local/bin/ggen` (ambient install); consumer repo `/Users/sac/ggen`
- **Priority**: P1 (user action; agent cannot execute)
- **Blocked-by**: none
- **Status** (2026-10-09 refresh #6): workspace binary staged at 26.10.8,
  smoke healthy — the install step itself remains USER action (stale
  ambient 26.9.28 still on PATH until then).

## Task

The ambient binary at `/Users/sac/.local/bin/ggen` is version **26.9.28** — stale
relative to the tree. `CliHarness` PATH fallback (env var → workspace
`target/{debug,release}/ggen` → PATH) can silently pick this stale binary in
environments where the workspace binary is absent, which was the root cause of
the OCEL determinism flake (DoD #9). User must reinstall/upgrade the ambient
install, or remove it so the fallback never resolves to it.

## Acceptance

- `/Users/sac/.local/bin/ggen --version` reports the current release (≥ current tree version), or the file is absent.
- OCEL 3-test determinism court (`book_gap` 2/0, dry-run 1/0, invariant matrix 13/0) passes on a machine where only the ambient PATH binary exists.

## Constraints

- Do not delete/rebuild the binary from an agent lane without user confirmation.
- Do not "fix" by hard-coding PATHs in tests; the fallback pattern is repo-standard.
