---
name: config-audit
description: Use when asked to audit, review, or check a directory/config tree for correctness against a checklist — runs a real discover→verify→synthesize sweep (fan out discovery, verify each item independently, write per-item findings, synthesize a ranked report) instead of one ad hoc pass. Good for config-tree audits (like the ~/.claude global config), repo-wide compliance sweeps, or any "check every X for Y" task with an enumerable item list.
---

# config-audit: discover → verify → synthesize sweep

Wraps `~/.claude/workflows/audit-and-report.js`, the reusable Workflow template
extracted 2026-08-20 from the recurring shape used across the original 25-item
`~/.claude` config audit (`~/.claude/audit-loop/*.md`).

## When to use this

A request shaped like "audit every X for Y," "check all the Z files are still
correct," or "sweep the repo for W" — where:
1. The item set is enumerable (files, rules, PRs, config entries — not "audit
   everything about this codebase" with no bound)
2. Each item can be verified independently of the others (no item's correctness
   depends on another item's verdict)
3. You want a written, ranked/summarized report at the end, not just a running
   commentary

If the audit needs custom per-item logic beyond template substitution (e.g. a verify
step that itself branches on discovered item type), don't force it through this
template — hand-author a Workflow script instead, following the pattern in
`~/.claude/workflows/audit-and-report.js` as a reference.

## How to invoke

```
Workflow({
  scriptPath: "~/.claude/workflows/audit-and-report.js",
  args: {
    discoverPrompt: "<prompt that returns {items: [...]}>",
    discoverSchema: { type: "object", properties: { items: { type: "array" } }, required: ["items"] },
    verifyPromptTemplate: "<prompt with {{item}} placeholder, substituted with JSON.stringify(item)>",
    verifySchema: { type: "object", properties: { ok: { type: "boolean" }, detail: { type: "string" } }, required: ["ok", "detail"] },
    synthesizePromptPrefix: "<prefix for the final report prompt>",
  }
})
```

## Worked example

Auditing every rule file in a directory for a specific property:

```
Workflow({
  scriptPath: "~/.claude/workflows/audit-and-report.js",
  args: {
    discoverPrompt: "List every .md file under ~/.claude/rules/ and return {items: [{path, name}]}",
    verifyPromptTemplate: "Read the file at {{item}} — does it have a See Also section? Return {ok, detail}",
    synthesizePromptPrefix: "Write a markdown report of which rule files are missing a See Also section:",
  }
})
```

## Notes

- `verifyPromptTemplate` uses plain string substitution (`{{item}}` → the JSON-
  stringified item), not a real templating engine — keep the template a single
  string, don't nest `{{item}}` inside conditional logic.
- The template runs discovery once, then verifies all items in parallel (bounded by
  the Workflow tool's own concurrency cap) — for very large item sets (100+), expect
  proportionally larger token usage; consider narrowing scope first.
- For genuinely custom multi-stage audits (e.g. the original 25-item `~/.claude`
  sweep, which needed per-item custom prompts, not one template), don't force-fit
  this skill — write a bespoke Workflow script instead.

## Reference checklist: full `~/.claude` config audit (25 items)

If asked to re-run or extend the full global-config audit rather than a narrow
single-property check, don't re-derive the item list from scratch — it's already
established (originally run 2026-08-20, findings in `~/.claude/audit-loop/NN-slug.md`):
rules/ contradictions & overlapping scope; skills inventory & trigger conflicts;
CLAUDE.md merge review; memory/ staleness scan; rules/ link verification;
settings.json permission audit; hookify rule staleness; plugin version drift;
MCP server map (global vs. project); mock-usage compliance vs. testing-chicago-style.md;
slash command collisions; rule file timeline & orphan detection; skill frontmatter
accuracy; deprecated model ID sweep; MEMORY.md index audit; workflow scripts review;
criticism-discipline/no-overclaiming compliance stress test; canonical architecture
doc; OS/shell portability; keybindings audit; TODO/FIXME sweep; rule scope
verification; tools.md LSP-rule reconciliation; skill/rule-firing prompt simulation;
prioritized cleanup plan.

Each of these 25 needed genuinely different discover/verify logic (a memory-staleness
scan and a link-verification pass have nothing in common mechanically) — they were
each their own bespoke `Workflow` call, not 25 runs of one template through this
skill's generic `discoverPrompt`/`verifyPromptTemplate` shape. Re-running any single
item from this list on a later date is a good `audit-and-report.js` candidate (one
item = one discover→verify→synthesize pass); re-running the *whole* 25-item sweep is
not — treat it as 25 separate invocations, following the pattern already recorded in
`~/.claude/audit-loop/*.md`, not one `config-audit` call.

## See Also
- `~/.claude/workflows/audit-and-report.js` — the underlying reusable template
- `~/.claude/audit-loop/16-workflow-scripts-review.md` — the original finding that
  identified this recurring pattern
- `~/.claude/audit-loop/*.md` — the 25-item audit that established the pattern this
  wraps, and the reference checklist above
- `~/.claude/audit-loop/25-prioritized-cleanup-plan.md` — ranked follow-up work from
  that audit, still partly open (see `~/.claude/errc-loop/errc-tracker.md`)
