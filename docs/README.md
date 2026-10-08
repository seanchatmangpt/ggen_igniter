# `ggen_igniter` Documentation

Start here:

- **New to this project?** → [`../README.md`](../README.md) for what it is,
  why it exists, and how to run it.
- **Want the full documentation map?** → [`index.md`](index.md) —
  Tutorials / How-to / Reference / Explanation.
- **Want a term defined precisely?** → [`glossary.md`](glossary.md).
- **Want to know what's really implemented vs. planned?** → [`status.md`](status.md).
- **Want to know why a decision was made?** → [`architecture/adr/`](architecture/adr/).

This directory is organized [Diataxis](https://diataxis.fr)-style. Every
subtree below is owned by the specialist area it documents; `index.md`,
`glossary.md`, `status.md`, and the ADRs are the cross-cutting navigation and
synthesis layer.

```
docs/
├── tutorials/             learn by doing, step by step
├── how-to/ (diataxis/)     goal-oriented recipes (docs/diataxis/how-to/)
├── reference/              look up a fact (cli/, reactor/, reconciliation/, evidence/)
├── operations/             runtime topology, controller, debugging, recovery
├── contributing/           adding a pack, adding a reactor step, testing, rules
├── integrations/           ggen/, igniter/, ash/, phoenix/, brce/, ultracode/
├── architecture/           ownership, boundaries, control plane, state model, adr/
├── testing/                Chicago discipline, concurrency, failure injection, e2e
├── rfc/                    proposals and design RFCs (accepted ones graduate to adr/)
├── reviews/                point-in-time adversarial review outputs (historical records)
├── receipts/               machine-oriented evidence artifacts (append-only)
├── context/                machine handoff / next-obligations notes per branch
├── jira/                   live campaign ledgers (last 3 campaigns + GALL/SJ orders)
├── archive/                superseded material (incl. archive/jira/<campaign>/)
├── index.md                full Diataxis navigation
├── glossary.md             one definition per term
├── status.md               real capability status (every claim citation-backed)
└── DOCUMENTATION_AUDIT.md  per-file classification (CURRENT/STALE/...)
```

## Campaign ledgers (`docs/jira/`)

Campaign directories under `docs/jira/` are working ledgers, not permanent
records. **Only the last three campaigns stay in place**; older campaign
directories are moved (via `git mv`, history preserved) to
[`archive/jira/`](archive/jira/). Currently in place:

- [`v26.10.2/`](jira/v26.10.2/)
- [`v26.10.1-loop/`](jira/v26.10.1-loop/)
- [`v26.9.31/`](jira/v26.9.31/)

Everything from `v26.9.1` through `v26.9.30` lives in
[`archive/jira/`](archive/jira/). Loose files (`GALL-*.md`, `SJ-*.md`) are the
standing work-order corpus, not campaign ledgers — they stay.

Citations to archived campaigns use their new `docs/archive/jira/...` paths;
older documents that still cite `docs/jira/v26.9.x/...` for an archived
campaign are stale-by-path (the content exists, the prefix moved).

## See Also

Fleet documentation map (all 20 repos): `../ggen-marketplace/docs/reference/FLEET-DOC-MAP.md` (external sibling)
