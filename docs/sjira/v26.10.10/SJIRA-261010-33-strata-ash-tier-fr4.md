# SJIRA-261010-33: strata Ash tier FR-4 — OPEN (unimplemented by design)

Date: 2026-10-10
Lane: docs (record only — no code owner assigned)
Repo: /Users/sac/strata
Status: OPEN — FR-4 is UNIMPLEMENTED BY DESIGN; recorded so the gap is
visible, not an oversight.

## Scope note

Strata wave-2 (2cbc5d7, 2026-10-10) landed courts, fuzz, valve hardening
(38/0), CI, and docs reconciliation; soak is ALIVE at Cp 6.1-6.7, CAS bugs
fixed. FR-4 (the Ash tier of the strata requirement family) was deliberately
excluded from waves 1-2 and has no owner.

## Work order (when admitted)

1. Define FR-4 acceptance as courts in the strata corpus style (wave-2
   precedent), not prose.
2. Route any Ash dependency through the ecosystem dependency ontology
   (composition Q) with a version or SHA standing, per SJIRA-03 pattern.
3. Falsifier: an FR-4 court that passes with the Ash tier's core behavior
   stubbed out is vacuous and must be killed in review.
