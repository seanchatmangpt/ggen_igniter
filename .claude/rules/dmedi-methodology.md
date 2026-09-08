# DMEDI as the Standing Work Framework

Per user directive (2026-08-20): structure work through Design for Lean Six Sigma's
DMEDI phases — Define, Measure, Explore, Develop, Implement — as the default shape
for substantive tasks, not just one-off deliverables. Source: the DFLSS Black Belt
curriculum outline the user provided (DMEDI-based, not the more common DMAIC).

## The five phases, mapped to concrete practice

**Define** — state the charter before starting: what problem, what scope, what "done"
looks like, who/what depends on it. Risk and communication implications named up
front, not discovered mid-work. Corresponds to: writing a tracker file with a stated
scope *before* dispatching agents, not after.

**Measure** — establish real current-state baseline before proposing anything.
Corresponds to: real evidence-gathering (grep/read/run actual tests, cite file:line
and command+output) — never a status claim without a measurement backing it. This is
where `no-overclaiming-rust.md`/`no-overclaiming-conversational.md`'s evidence
discipline and DMEDI's Measure phase are the same discipline under different names.

**Explore** — generate and evaluate multiple concepts/options before committing to
one, skeptically scored (novelty/feasibility/leverage or equivalent), not the first
idea that comes to mind. Corresponds to: multi-lens/multi-agent exploration sweeps —
invoke via the [[innovation-explorer]] skill (`~/.claude/skills/innovation-explorer/
SKILL.md`, wrapping `~/.claude/workflows/innovation-explorer.js`) — concept generation
+ concept selection (Pugh/AHP-equivalent: rank, don't just list).

**Develop** — detailed design and build, with real experimentation/testing before
declaring something works (DOE-equivalent: vary one thing, observe the real effect,
don't assume). Corresponds to: actual implementation work, with verification against
the Measure-phase baseline, not a fresh unverified claim.

**Implement** — pilot before full rollout, plan for control/monitoring after
shipping, not just "ship and walk away." Corresponds to: staged execution (a
worktree-isolated trial before a merge to main; a single gate closed and re-verified
before moving to the next) plus a standing check that catches regression (a cron
loop, a re-verification pass) rather than a one-time fix assumed to hold forever.

## Applying this to the standing loops already running

- `~/.claude/big-loop/` (ggen v26.9.1 gate assessment + innovation exploration) is
  already DMEDI-shaped without having been named that: Define = the gate
  requirements themselves (G01-G09); Measure = the real evidence-gathering per gate;
  Explore = the `innovation-explorer` cycles; Develop/Implement = not yet reached for
  most gates — this is itself an honest DMEDI-phase status (most work is currently
  in Measure/Explore, not Develop/Implement).
- `~/.claude/errc-loop/` (Eliminate-Reduce-Raise-Create) is a *complementary*
  framework, not a competitor — ERRC is a lens for *what* to change (cut/shrink/
  boost/invent), DMEDI is a *process* for how any one change gets taken from problem
  to shipped-and-monitored. An ERRC "Create" candidate still needs a DMEDI pass
  (Define its charter, Measure the baseline, Explore alternatives, Develop it for
  real, Implement with a follow-up check) before being called done. Invoke the
  categorization step itself via the [[errc-cycle]] skill (`~/.claude/skills/
  errc-cycle/SKILL.md`, wrapping `~/.claude/workflows/errc-cycle.js`) rather than
  re-deriving the Categorize/Verify/Park/Report shape by hand each time.

## What this changes going forward

Before starting substantive work: state phase-shaped intent, even briefly (what's
being defined, what's being measured, what's being explored) rather than jumping
straight to implementation. Don't retrofit DMEDI labels onto work after the fact as
decoration — use the phases to decide what's missing (e.g. "we have Explore output
but no Measure baseline to test it against" is a real, actionable gap, not a
formality).

## See Also
- `~/.claude/rules/no-overclaiming-conversational.md` — the Measure-phase evidence
  discipline this framework assumes
- `~/.claude/big-loop/tracker.md` — the standing loop currently operating in this
  shape
- `~/.claude/skills/innovation-explorer/SKILL.md` — the Explore-phase capability
  (wraps `~/.claude/workflows/innovation-explorer.js`)
- `~/.claude/skills/errc-cycle/SKILL.md` — the ERRC categorization capability (wraps
  `~/.claude/workflows/errc-cycle.js`)
