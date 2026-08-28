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
├── tutorials/        learn by doing, step by step
├── reference/         look up a fact (cli/, reactor/, reconciliation/, evidence/)
├── operations/         runtime topology, controller, debugging, recovery
├── contributing/        adding a pack, adding a reactor step, testing, rules
├── integrations/         ggen/, igniter/, ash/, phoenix/
├── architecture/         ownership, boundaries, control plane, state model, adr/
├── testing/               Chicago discipline, concurrency, failure injection, e2e
├── index.md               full Diataxis navigation
├── glossary.md            one definition per term
├── status.md              real capability status
└── DOCUMENTATION_AUDIT.md  per-file classification (CURRENT/STALE/...)
```
