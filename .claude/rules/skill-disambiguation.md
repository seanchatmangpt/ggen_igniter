# Skill Trigger Disambiguation

Quick-reference for skill triggers that legitimately overlap in wording. Created by
the ERRC innovation loop (2026-08-20) from the skill-inventory audit
(`~/.claude/audit-loop/02-skills-inventory.md`, `24-prompt-simulation.md`). This is
guidance for resolving ambiguity, not a rule that changes any skill's own behavior.

## "Review my changes" — 3-way overlap

`code-review`, `simplify`, and `security-review` all plausibly match a bare "review my
changes" / "look at this diff" request.

- **Correctness bugs, general review** → `code-review` (the named catch-all)
- **Quality/reuse/simplification only, not bug-hunting** → `simplify`
- **Security-specific concerns** → `security-review`

If the request doesn't specify an axis, ask which one is wanted rather than guessing;
`code-review` is the reasonable default if a quick answer is needed and the user is
unavailable to clarify.

## "Create/edit a skill" — 4-way overlap

`superpowers:writing-skills`, `skill-creator`, `skill-development` (plugin-dev
scoped), and `hookify:writing-rules` (narrower — hookify rule syntax only, not a
general skill) all touch skill authoring.

- **Adding a skill inside a plugin you're building** → `skill-development`
  (plugin-dev), the most specific match
- **Creating/optimizing/benchmarking a standalone personal skill** → `skill-creator`
- **General skill-authoring discipline, not plugin-specific** →
  `superpowers:writing-skills`
- **A hookify prevention rule specifically (not a general skill)** →
  `hookify:writing-rules`

Disambiguating question: "is this skill part of a plugin you're building, or a
personal `~/.claude/skills` skill?"

## "Schedule/run this on an interval" — loop vs schedule

- **Session-scoped, stops when you close this session** → `loop`
- **Durable, keeps running after the session closes (cloud)** → `schedule`

`loop` itself already offers a cloud-schedule redirect for ≥60-minute or daily-cadence
requests — this ambiguity is largely self-resolving via that mechanism.

## "Find and fix issues in this config/repo" — 4-way overlap

`errc-cycle`, `innovation-explorer`, `config-audit`, and `audit-and-report` all
plausibly match a bare "clean this up" / "what should we improve here" request. Added
2026-08-24 when both `errc-cycle` and `innovation-explorer` got real `SKILL.md`
wrappers (they previously only surfaced via their Workflow `meta` exports) and their
overlap with the two audit-style skills had never been documented.

- **Categorize a known backlog into what to cut/shrink/boost/invent** → `errc-cycle`
  (Eliminate/Reduce/Raise/Create over items already named somewhere, e.g. a tracker)
- **Discover new, not-yet-listed opportunities across repos** → `innovation-explorer`
  (blind multi-lens sweep, novelty/feasibility/leverage ranked)
- **Check a config/directory tree against a fixed checklist** → `config-audit`
- **Generic one-time discover→verify→synthesize, no ERRC/innovation framing needed**
  → `audit-and-report`

Disambiguating question: "is there already a backlog to categorize (`errc-cycle`), or
are we looking for new candidates that aren't listed anywhere yet
(`innovation-explorer`)?" — if neither, it's probably `config-audit` (checklist known)
or `audit-and-report` (checklist not yet known, one-time pass).

## `superpowers:using-superpowers`

Triggers on "starting any conversation" — this is a one-time bootstrap/framing step,
not a competitor to task-specific skills. It fires alongside everything by design;
don't treat it as ambiguity to resolve.

## Artifact family — sequencing, not competing triggers

`artifact-design` (load before any artifact) → `artifact-diagramming` (only if a
diagram is needed) → `artifact-capabilities` (only if live/shared/self-update
behavior is needed) → `design` (only for a multi-artboard visual canvas). This is an
ordered pipeline, not 4 skills competing for the same prompt.

## See Also
- `~/.claude/audit-loop/02-skills-inventory.md` — full 83-skill inventory this was
  extracted from
- `~/.claude/audit-loop/24-prompt-simulation.md` — the 10-prompt simulation that
  exercised these overlaps concretely
