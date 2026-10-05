# ADR 0010: Gate scoring convention is the directory

Status: Accepted (2026-10-04, R0 of the delta-ERRC lane; decision record
lives in `/Users/sac/ash_pplan/docs/jira/ECO-GATE-CONVENTION-DECISION.md`).

## Context

Two gate-scoring conventions coexist in the pack corpus:

- **Witness-reporting** — `GgenIgniter.GateVerify` (and therefore
  `mix ggen_igniter.sync` and the gate half of `mix ggen_igniter.verify`)
  treats >= 1 row as PASS; the rows are witnesses the ontology must
  produce. 0 rows = FAIL.
- **Offender-reporting** — the `verify/*.unbound.rq` companions (and the
  vendored state-transition / evidence-standing gates) treat rows as
  violations: 0 rows = PASS, >= 1 row = FAIL. These are scored by the
  verify task through each pack's `verify/cardinality.json` contract.

## Decision

**Directory-is-convention (Option A of
`ECO-UPSTREAM-IGNITER-FIXES.md` Item 3, adopted 2026-10-04):**

- `gates/*.rq` — witness-reporting: >= 1 row = PASS, 0 rows = FAIL.
- `verify/*.unbound.rq` — offender-reporting: 0 rows = PASS,
  >= 1 row = FAIL.

The directory a query ships in IS its scoring. No per-gate flag, no
metadata. Option B (a per-gate `"mode": "offender" | "witness"` key in
`cardinality.json`, witness default) is deferred until DERIVED_ROWS mode
proves out; when promoted, `gates/` stays the witness default so packs
shipping no contract file see no behavior change.

## Consequences

- **Docs only today.** `GateVerify` already scores this way; nothing
  changes at runtime.
- **Known residual hole (accepted for now):** an offender-shaped query
  misfiled in `gates/` scores `:pass` exactly when the ontology is broken.
  Nothing types a gate, so misfiling is silent. Known live instances:
  `vendor/evidence-standing-pack/gates/` (all 8) and
  `vendor/state-transition-pack/gates/010/020/050`. Mitigated by the
  workflow-corpus mutation courts (`qualification/verify.py`, queries must
  fail on `witnesses/fail/` fixtures) and the G1 pack courts
  (`cardinality.json` + `verify/*.unbound.rq` scored 0-rows-pass by the
  verify task). Re-homing those queries is a P1 code lane, not this
  decision; the safe sequence is contract-file first, re-home second, same
  commit.
- **Promotion path to Option B** stays open: per-gate `"mode"` flag in
  `cardinality.json`, directory as default, witness as flag-default.

## Required docstring change (code lane, NOT this doc)

When the next `GateVerify` code lane opens, update
`lib/ggen_igniter/gate_verify.ex` `@moduledoc` — specifically the paragraph
beginning "A gate's pass/fail convention mirrors this pack corpus's own
`SELECT DISTINCT` existence-check style" — to read, in substance:

> A gate's pass/fail convention is the directory it ships in. `gates/*.rq`
> are witness-reporting: the query's rows are witnesses the ontology must
> produce, so a gate **passes** on >= 1 row and **fails** on zero rows.
> `verify/*.unbound.rq` are offender-reporting: the rows are violations the
> query surfaces, so they **pass** on zero rows and **fail** on >= 1 row;
> they are scored by `mix ggen_igniter.verify` through the pack's
> `verify/cardinality.json` contract, not by this module. This is ADR 0010
> (`docs/architecture/adr/0010-gate-convention-directory-is-convention.md`);
> an offender-shaped query placed in `gates/` scores inverted — ship it in
> `verify/` with a cardinality contract instead.

No behavior change accompanies that docstring edit.

## PR description text

For the `errc-promote-engine-compat-gates` PR body (copy as-is):

---

### Gate scoring convention decided: directory-is-convention (ADR 0010)

OFFENDER-vs-WITNESS is now decided per
`ash_pplan/docs/jira/ECO-GATE-CONVENTION-DECISION.md` (Option A, adopted
2026-10-04): `gates/*.rq` are **witness-reporting** (>= 1 row = PASS, 0
rows = FAIL — GateVerify's existing scoring); `verify/*.unbound.rq` are
**offender-reporting** (0 rows = PASS, >= 1 row = FAIL — scored by the
verify task via `verify/cardinality.json`). The directory is the only
signal; no per-gate flag.

- No code or pack behavior changes in this decision. GateVerify already
  scores exactly this way; the convention is now written down (ADR 0010 in
  `docs/architecture/adr/`).
- Known accepted hole: offender-shaped queries misfiled in `gates/` fail
  open (score `:pass` when broken). Live instances: evidence-standing-pack
  `gates/` (all 8), state-transition-pack `gates/010/020/050`. Mitigated by
  the workflow-corpus mutation courts and the G1 per-pack cardinality
  contracts; re-homing is a follow-up code lane (contract first, re-home
  second, same commit).
- Option B (per-gate `"mode"` flag in `cardinality.json`) is deferred
  until DERIVED_ROWS mode proves out; promotion preserves `gates/` as the
  witness default so packs without contracts are unaffected.

Inventory (ash_pplan corpus, 2026-10-04): 111 `gates/` entries, 66
`verify/*.unbound.rq` companions, 10 contract-bearing packs; 11
offender-shaped queries currently misfiled in `gates/` (evidence-standing
8, state-transition 3).

---
