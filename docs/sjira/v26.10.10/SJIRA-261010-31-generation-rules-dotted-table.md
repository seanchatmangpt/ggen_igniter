# SJIRA-261010-31: generation.rules dotted-table parsing

Date: 2026-10-10
Lane: in flight
Repo: /Users/sac/ggen
Status: IN FLIGHT.

## Context

`generation.rules` in `ggen.toml` is authored as a dotted table
(`[generation.rules.<name>]`), but the parser does not consistently accept
the dotted form — manifest authors hit silent drops or hard errors depending
on entry point. Fix normalizes dotted-table parsing to match the inline
array-of-tables form.

## Acceptance

1. Both authoring forms (`[[generation.rules]]` and
   `[generation.rules.<name>]`) parse to identical rule sets — property or
   differential court asserts equality.
2. `crates/ggen-config` manifest validation tests cover the dotted form on
   both happy and malformed paths (E0010/E0014 firing unchanged).
3. No change to the second `ggen.toml` schema (`ggen-config` only; see
   architecture.md two-schemas note).

## Falsifier

A manifest using the dotted form whose rules are silently absent from the
built Tera environment passes no court.
