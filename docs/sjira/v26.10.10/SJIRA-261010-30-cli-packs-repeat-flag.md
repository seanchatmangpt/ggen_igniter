# SJIRA-261010-30: CLI `--packs` repeat flag

Date: 2026-10-10
Lane: in flight
Repo: /Users/sac/ggen
Status: IN FLIGHT.

## Context

The CLI currently accepts at most one `--packs` value where callers need to
compose multiple pack sources in a single invocation. The repeat flag
(`Vec<String>` / `num_args`-style repeat in clap) is being added.

## Acceptance

1. `ggen <verb> --packs a --packs b` (or comma form, matching house clap
   style) resolves both packs in declared order.
2. Zero-occurrence behavior unchanged (default pack set).
3. clap-noun-verb generated surface regenerated, not hand-edited; sync
   receipt lands.

## Falsifier

A two-pack invocation resolving only the first (or last) value turns the
new court red.
