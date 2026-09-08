---
name: source-of-truth-check
description: Re-derives real ground-truth facts (counts, statuses) and flags any file that restates one going stale. Use at the start of an ERRC or big-initiatives loop cycle, or whenever a status/count is about to be copied into a second file, to catch or prevent the exact drift class this loop has independently caught by hand 4 times (worktree counts, the G01-G09 gate-status table, exploration-log.md's cycle sync).
---

# source-of-truth-check

Extracted 2026-08-21 (big-loop cycle 18, innovation-explorer's top-ranked
candidate, tied for #1 at score 10) after the exact same bug class — a fact
hand-copied into a second file goes stale the moment its source changes, and
nobody re-derives it — was independently caught by hand 4 times in one
session: `errc-tracker.md`'s worktree count going stale after big-loop cycle
14 added a 7th worktree (ERRC cycle 15), recurring twice more after that
(cycle 16, then a 3rd time by cycle 18 — see `errc-tracker.md`'s own cycle 15
and 18 entries), and `cycle-1-gate-assessment.md`'s G01-G09 status table
being silently read as current for 15 cycles before big-loop cycle 15 caught
it.

## Steps

### 1. Run the checker for real

```bash
python3 ~/.claude/scripts/source-of-truth-check.py
```

Exit code 0 = every check's mirrors agree with their real, freshly-computed
source value. Exit code 1 = at least one real drift (a mirror disagrees) or a
config problem (a check's own command or regex stopped matching — report
this distinctly from a real drift, since it usually means the mirror file was
restructured, not that the fact actually changed).

Add `--json` for machine-readable output when composing this into a larger
script or workflow.

### 2. Fix any real drift found

For each `DRIFT` line, go to the named file:line and decide (matching the
judgment already exercised in ERRC cycles 15/17/18): if the disagreeing text
is a **live, current-state claim**, correct it to match the source. If it's a
**historical snapshot** (a dated cycle-log entry describing what was true at
that point in time), do NOT edit it — instead, either exclude it from the
mirror pattern (only match the file's *last* occurrence, or a specifically
"current status" section) or accept that this check only applies to live
mirrors, not dated logs.

### 3. Add new checks as new drift patterns get caught

The config at `~/.claude/scripts/source-of-truth-checks.json` is a plain JSON
list — deliberately started with one concrete check
(`pending-decisions.md`'s stated item count vs. its real `## N.` header
count) rather than trying to anticipate every future drift pattern up front.
Each entry:

```json
{
  "name": "human-readable label",
  "source_command": "a real shell command whose stdout is the ground truth",
  "mirrors": [
    {"file": "/absolute/path", "pattern": "regex with exactly one capture group"}
  ]
}
```

`pattern` must have exactly one capturing group around the value being
checked; the script compares every match's captured text (not just the
first) against `source_command`'s trimmed stdout.

When you (or a future cycle) catch a NEW instance of this bug class by hand,
add a check for it here instead of just fixing the one instance — that is
literally how this tool itself was born (see the extraction rationale
above), and is the whole point of building it rather than continuing to fix
each recurrence as a one-off.

## When NOT to use this

This is for deterministic, single-correct-answer facts (a count, an
extracted value) — not for judgment calls ("is this status assessment still
accurate?"), which stay a real Measure-phase re-verification task for a
human or an agent, not a regex.
