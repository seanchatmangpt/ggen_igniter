---
name: errc-cycle
description: Reusable ERRC (Eliminate/Reduce/Raise/Create) improvement cycle: categorize a backlog, verify current state, propose bounded actions, park ambiguous items
---

# errc-cycle

Extracted 2026-08-21 (`~/.claude/workflows/errc-cycle.js`, per innovation-explorer
cycle 6's top-ranked candidate, score 10/15): the same 4-phase shape had already run 9
times by hand in `~/.claude/errc-loop/errc-tracker.md` before being turned into a
script. This `SKILL.md` closes a discoverability gap the 2026-08-24 config
cross-reference found: `errc-cycle` only ever surfaced via its Workflow `meta` export,
unlike [[source-of-truth-check]], `config-audit`, and `mcp-doctor`, which each have a
real `SKILL.md` wrapper — this file gives it the same standing.

## Steps

### 1. Run the cycle

```
Workflow({
  scriptPath: "~/.claude/workflows/errc-cycle.js",
  args: {
    trackerPath: "/absolute/path/to/tracker.md",       // required
    pendingDecisionsPath: "/absolute/path/to/pending-decisions.md", // optional
    scopeNote: "what this cycle is bounded to, e.g. '~/.claude/* config hygiene only'",
  },
})
```

The script runs four real phases against the tracker you point it at:

1. **Categorize** — reads the tracker (+ pending-decisions file if given), buckets
   every still-open backlog item into exactly one ERRC quadrant (ELIMINATE/REDUCE/
   RAISE/CREATE), and judges each as `safeToVerify` or needing to be parked.
2. **Verify** — for every safe item, spawns a parallel agent that re-checks the
   *actual current state* with real Bash/Read/grep calls (never trusts the tracker's
   own framing) and proposes a concrete next action, or reports the item already
   stale/resolved.
3. **Park** — unconditional for anything touching security posture or an ambiguous
   user-preference tension; these are logged, never auto-resolved.
4. **Report** — writes a markdown cycle report: quadrant counts, per-item verified
   state + proposed action, parked items formatted for appending to the
   pending-decisions file, and one clear recommendation for what to execute next.

### 2. Act on the report — a separate, explicit step

The script itself never mutates files. Reviewing the report and deciding what to
actually execute is a distinct step, done by whoever ran the cycle (a human, or a
calling script/loop that has its own execution policy) — the same judgment exercised
in every prior hand-run cycle (e.g. "is this a real orphan, or did an earlier
subagent's search just fail?", per `errc-tracker.md` cycle 4/15's correction).

### 3. Log the cycle

Append the report to `trackerPath` as the next dated `## Cycle N` entry, and append
any parked items to `pendingDecisionsPath` — matching the format both files already
use (see `~/.claude/errc-loop/errc-tracker.md` for a live example of 26 such entries).

## When NOT to use this

- No existing backlog to categorize → use `innovation-explorer` instead, which
  discovers new candidates rather than categorizing known ones.
- A single deterministic fact needs re-deriving (a count, a status table entry) →
  use `source-of-truth-check`, which is narrower and regex-based, not agent-judged.
- A one-time discover→verify→synthesize pass with no ELIMINATE/REDUCE/RAISE/CREATE
  framing needed → use `audit-and-report`.

## See Also

- `~/.claude/workflows/errc-cycle.js` — the script this skill wraps
- `~/.claude/skills/innovation-explorer/SKILL.md` — the discovery-phase counterpart;
  its own candidates are a natural source of new errc-cycle backlog items
- `~/.claude/skills/source-of-truth-check/SKILL.md` — run before or during Verify
  when a claim is a deterministic fact rather than a judgment call
- `~/.claude/rules/dmedi-methodology.md` — frames ERRC as a complementary lens
  (what to change) alongside DMEDI (how one change gets shipped)
- `~/.claude/rules/skill-disambiguation.md` — disambiguates this from
  `innovation-explorer`/`config-audit`/`audit-and-report` when the trigger is ambiguous
- `~/.claude/errc-loop/errc-tracker.md` — the standing config-hygiene tracker this
  skill was extracted from
