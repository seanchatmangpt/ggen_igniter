---
name: innovation-explorer
description: Standing multi-agent exploration for the v26.9.1 capstone release — surfaces innovation candidates across the ecosystem
---

# innovation-explorer

Created 2026-08-20 (`~/.claude/workflows/innovation-explorer.js`) per user directive:
"implement the innovative exploration capabilities only." This `SKILL.md` closes a
discoverability gap the 2026-08-24 config cross-reference found: like `errc-cycle`,
this only ever surfaced via its Workflow `meta` export, not a real `SKILL.md` — this
file gives it the same standing as [[source-of-truth-check]]/`config-audit`/
`mcp-doctor`.

EXPLORE-mode work (see `~/.claude/rules/explore-exploit-premises.md`): this surfaces
possibility, not a verified status claim. Its findings are CANDIDATEs, never ALIVE,
until a separate implementation pass verifies and ships one.

## Steps

### 1. Run the sweep

```
Workflow({
  scriptPath: "~/.claude/workflows/innovation-explorer.js",
  args: {
    focusRepos: ["/Users/sac/praxis", "/Users/sac/ggen", ...],  // optional, has a default set
    priorFindingsPath: "/absolute/path/to/prior-cycle-report.md", // optional, avoids re-surfacing
  },
})
```

Four real phases:

1. **Sweep** — 5 agents explore from deliberately distinct, non-overlapping angles,
   blind to each other's output so coverage doesn't collapse onto one obvious idea:
   unexploited-capability (code that exists but isn't wired up), cross-repo-
   integration (two repos that should talk but don't), ambition-vs-implementation-gap
   (stated future direction vs. what's actually built), external-facing-gap (what a
   first-time user/reader would hit), workflow-tooling-leverage (a manual pattern
   used repeatedly that could become a reusable skill/workflow — this lens is how
   `errc-cycle` itself and this skill's own `.js` predecessor were found).
2. **Dedup** — merges semantic near-duplicates surfaced by more than one lens, keeps
   genuinely distinct candidates separate.
3. **Rank** — scores each on NOVELTY × FEASIBILITY × LEVERAGE (1-5 each), skeptically
   (most candidates should not be 5s across the board), with a one-line justification
   per axis.
4. **Report** — writes a markdown cycle report: top 3 candidates in detail, the full
   ranked table, and one recommended next action stated as a concrete step.

### 2. Decide what becomes real work — a separate, explicit step

The script only proposes and ranks; it never implements. A top-ranked candidate that
is itself a categorization-ready backlog item is a natural next input to `errc-cycle`
(CREATE quadrant); a candidate needing its own scoped implementation should go through
a normal DMEDI pass (see `~/.claude/rules/dmedi-methodology.md`) rather than being
built directly from the exploration report.

### 3. Log the cycle

Append the report (or a link to it) to whatever standing tracker is running this
sweep — e.g. `~/.claude/big-loop/tracker.md`'s Explore-phase cycles — so
`priorFindingsPath` on the next run can avoid re-surfacing the same candidates.

## When NOT to use this

- There's already a known, named backlog to work through → use `errc-cycle` instead,
  which categorizes and verifies existing items rather than discovering new ones.
- You need a single deterministic fact re-derived → `source-of-truth-check`.
- A one-time discover→verify→synthesize pass against a fixed checklist, no
  novelty/feasibility/leverage ranking needed → `config-audit` or `audit-and-report`.

## See Also

- `~/.claude/workflows/innovation-explorer.js` — the script this skill wraps
- `~/.claude/skills/errc-cycle/SKILL.md` — the categorization counterpart; feed this
  skill's top candidates into errc-cycle's CREATE quadrant
- `~/.claude/rules/explore-exploit-premises.md` — the EXPLORE-mode discipline this
  skill operates under (candidates are proposals, not commitments)
- `~/.claude/rules/dmedi-methodology.md` — where a ranked candidate goes next
  (a full Define→Measure→Explore→Develop→Implement pass, not a direct build)
- `~/.claude/rules/skill-disambiguation.md` — disambiguates this from
  `errc-cycle`/`config-audit`/`audit-and-report` when the trigger is ambiguous
- `~/.claude/big-loop/tracker.md` — the standing loop this sweep runs inside
