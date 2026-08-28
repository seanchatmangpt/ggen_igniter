# `docs/` — Diátaxis-organized, evidence-sourced only

## The one rule that overrides everything else here

Every status claim (IMPLEMENTED/PARTIAL_ALIVE/PLANNED/UNVERIFIED) must be
backed by a real citation: a `file:line`, a real command + its real output,
or a passing test name. Never write a status line you haven't personally
verified this pass — `docs/status.md`'s own header names its sourcing
(93 individually-verified claims from concurrent verification agents) as the
standard to match. A doc edit that changes a capability's status without new
evidence is a regression, not a documentation update.

## Structure (Diátaxis + this repo's own categories)

- `docs/tutorials/` — real, run-in-this-repo walkthroughs (commands + actual
  output), e.g. `getting-started.md`, `first-reconciliation.md`.
- `docs/reference/` — flag/check/mechanism reference, subdivided by area
  (`cli/`, `reconciliation/`, `reactor/`, `evidence/`). New CLI flags or
  Reactor steps get a reference entry in the same change, not a follow-up.
- `docs/architecture/` — `overview.md` (layer-ownership table) plus
  `adr/` (accepted decisions only — see below).
- `docs/integrations/{ash,igniter,phoenix,ggen}/` — how this repo's pipeline
  interacts with each named consumer-side or upstream system.
- `docs/operations/` — `debugging.md`, `failure-recovery.md` — practical
  triage playbooks, not conceptual explanation.
- `docs/testing/` — the Chicago-testing discipline reference (`chicago.md`).
- `docs/reviews/` — point-in-time adversarial review outputs (e.g.
  `reviewer-a-implementation-contradictions.md`); these are historical
  records of a review pass, not living docs — don't edit them to "fix" a
  finding, instead fix the underlying doc/code and note resolution in
  `docs/status.md` or the relevant ADR.
- `docs/receipts/` — machine-oriented evidence artifacts (e.g.
  `examples.jsonl`); append, don't rewrite history here.
- `docs/glossary.md` — one canonical, sourced definition per domain term.
  Check here before introducing a new term in any other doc; reuse the
  existing term instead of a near-synonym.

## `docs/architecture/adr/`

Two numbering schemes coexist (`000N-kebab-title.md` and `ADR-00N-title.md`)
— both real, both accepted; match whichever scheme the most recent ADR in
the directory uses for a new one rather than inventing a third. Every ADR
needs `## Status` (Accepted/Superseded, with a real verification citation —
see `0001-oxigraph-default-query-engine.md`'s pattern of citing the exact
source line and a real command's output), `## Context`, and the decision +
disclosed trade-offs. Never write a "Proposed" ADR into this directory —
this repo only records decisions already made and verified.

## Cross-linking

Prefer linking to the most authoritative existing doc over restating
content — e.g. link to `docs/glossary.md#admission` rather than
re-explaining admission semantics in a third document. If two docs would
otherwise say the same status-bearing sentence, that's a future drift
point (see [[source-of-truth-check]]) — pick one as the source of truth and
link to it from the other.
