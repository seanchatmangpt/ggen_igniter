# `ggen sync run` template-pipeline verification blocker (real, disclosed, unresolved)

## Status

PLANNED / NOT STARTED.

## Grounding (real, this session)

`ash_a2a`'s own `MANUFACTURING_RECEIPT.md` (refreshed commit `4f1a79e`, this session)
discloses a real, unresolved blocker in **this repo's** (`ggen_igniter`'s) own CLI, not
just an `ash_a2a`-side gap — quoted verbatim from that receipt's "Remaining open
blockers" §3.8.4:

> **`ggen sync run` template verification (PRD §3.8.4) — still not executed.** ... the
> EEx template under `priv/ggen/ash_a2a/templates/` has never been run through `ggen
> sync`; the previously-reported `/workspace` path-resolution blocker in the installed
> `ggen` binary was not re-tested this session. This run's own generation-vs-handwrite
> gap is exactly this item: every module the test suite actually exercises was
> hand-written directly, not produced by the `ggen` pipeline the PRD designs around —
> the pipeline exists only as unexecuted input material (ontology + query + template).

This means `ash_a2a` — a real, disclosed consumer of `ggen_igniter`'s own generation
pipeline (`mix.exs` pins `{:ggen_igniter, "~> 26.9"}`) — has never actually exercised
`mix ggen_igniter.sync` end-to-end against its own ontology/template material. The
blocker is described as a path-resolution issue in the installed `ggen` binary
("`/workspace` path-resolution blocker") that was reported once, previously, and never
re-tested. This is a real gap in dogfooding this repo's own core CLI task, independent
of the A2A protocol content itself (ticket 04 covers the protocol-content side; this
ticket covers the tool-level blocker).

## Definition of Done

- Reproduce the `/workspace` path-resolution blocker for real: run `mix
  ggen_igniter.sync` (or the equivalent real command `ash_a2a`'s PRD/ARD names) against
  `~/ash_a2a`'s real `priv/ggen/ash_a2a/` ontology/query/template material, from
  `~/ash_a2a`'s own working directory, and paste the real error output. If it does not
  reproduce (e.g. was already fixed by an unrelated change since it was last observed),
  say so explicitly with the real successful output as evidence — do not assume the old
  report is still accurate without re-running it.
- If it reproduces: root-cause the actual path-resolution logic in this repo (likely
  `lib/ggen_igniter/reactors/reconcile_reactor.ex`'s `:load_ontology`/`:render` steps,
  or wherever a `/workspace`-relative path gets constructed — confirm by reading the
  real code, don't guess the file) and land a real, targeted fix plus a real regression
  test that exercises the same failure shape (a consumer project invoking `ggen_igniter`
  from its own root, not `ggen_igniter`'s own root) so this exact blocker cannot
  silently return.
- Once the blocker is fixed (or confirmed already-fixed), actually run `mix
  ggen_igniter.sync` against `~/ash_a2a`'s real templates and paste the real generated
  output/diff. This ticket's DoD includes closing the "generation-vs-handwrite gap"
  named in `ash_a2a`'s receipt — i.e., demonstrating the pipeline can produce at least
  one of `ash_a2a`'s hand-written modules for real, even if the hand-written version is
  kept as the shipped implementation pending a full migration decision.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` clean
  in `ggen_igniter`, pasted as real output.

## Non-goals

- Does not migrate `ash_a2a` off its hand-written modules onto generated code in this
  ticket — that is a separate, larger decision (and a separate repo's call) once the
  pipeline is proven to work at all. This ticket's job is proving the pipeline works,
  not switching `ash_a2a` over to it.
- Does not address the A2A protocol's own content drift against `~/ash_a2a`'s
  hand-written types — that is `~/ash_a2a`'s and `:a2a`'s concern, not
  `ggen_igniter`'s; this ticket is scoped purely to the tool-level path-resolution
  blocker in `ggen_igniter`'s own CLI.

## See Also

- `~/ash_a2a/MANUFACTURING_RECEIPT.md` §"Remaining open blockers", item 4 — the primary
  source disclosing this blocker.
- `~/ash_a2a/priv/ggen/ash_a2a/templates/` — the real, never-yet-executed template
  material this ticket's DoD runs the pipeline against.
- `lib/ggen_igniter/reactors/reconcile_reactor.ex` — likely location of the real
  path-resolution logic to audit (confirm by reading, not assumed here).
- `00-OVERVIEW.md` — this directory's charter and cross-references, including the note
  that a proto-ingestion capability for `ggen_igniter` was considered and explicitly
  rejected (RDF-only by design), not merely deferred.
