# SJIRA-261010-29: FM-PACK-018 two-tier unit court

Date: 2026-10-10
Lane: in flight (gate-engine-2b)
Repo: /Users/sac/ggen (main, post-5c9da7a3e)
Status: IN FLIGHT.

## Context

The FM-PACK-018 H2 fix landed as a two-tier pack resolution
(`pack.rs:454-528`). The unit court covering the two-tier path is being
converted via gate-engine-2b; until it lands, the fix is unreceipted at the
unit level.

## Acceptance

1. Unit court over `pack.rs:454-528` covers both tiers: primary resolution
   and fallback, plus the miss path.
2. Court runs green on a quiet machine (not against shared stale `target/`
   — see SJIRA-24/26 for the masking lesson).
3. SJIRA-16 status updates to reflect the adjudicated FM-PACK-018; G2 of
   SJIRA-22 flips GREEN.

## Falsifier

Reverting the two-tier block while leaving the old single-tier path must
turn the unit court red.
