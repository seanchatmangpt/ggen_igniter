# Ecosystem-research-driven backlog — v26.9.10

Index ticket for this directory's three tickets (01-03). Source: a deep-research
workflow run in this session (5 search angles, 21 sources fetched, 79 claims
extracted, 25 adversarially verified with 3-vote checks, 17 confirmed / 8 refuted)
targeting the Ash/Reactor/Spark/Elixir/Igniter ecosystem's 2026 changes, cross-checked
against real, freshly-observed consumer behavior: `~/ash_ex4pm` (a separate Spark DSL
extension repo) built and committed a real, working `mix ash_ex4pm.ggen.sync` task
this same session (`~/ash_ex4pm` commits `59eb76f`, `d4ffb71`) that shells out to
`mix ggen_igniter.sync` to query a Hex-packaged dependency's own `priv/ontology/*.ttl`
— a live, real downstream usage pattern of this repo's own CLI, not a hypothetical.

## Status

**PLANNED / NOT STARTED.** Nothing in this directory has been implemented in
`~/ggen_igniter` itself. Every ticket below states real, verified grounding (a fetched
primary source, a real file in this repo, or a real commit in `~/ash_ex4pm`) and a
concrete Definition of Done; none of that DoD has been executed yet.

## What this ticket set is, and is not

This is **not** a continuation of `docs/status.md`'s existing v26.9.10 "10 disclosed
gaps" swarm pass (4 of 10 closed per `CHANGELOG.md`'s v26.9.10 entry — the exact
remaining 6 are not individually enumerated as a list anywhere this pass located, so
this directory does not attempt to re-derive or duplicate them). This ticket set is a
**separate, additive** work stream scoped narrowly to what the ecosystem-research pass
and the real `ash_ex4pm` consumer observation surfaced. Both streams happen to carry
the `v26.9.10` version string; read `CHANGELOG.md`'s existing v26.9.10 entry for the
other stream's scope, the same "two work streams, one version string" caveat
`docs/jira/v26.9.1/06-KNOWN-LIMITATIONS-AND-NON-GOALS.md` already states for that
directory's own two v26.9.1 streams.

## Tickets

| Ticket | Grounding | DoD summary |
|---|---|---|
| [01-CROSS-PACKAGE-ONTOLOGY-SYNC](01-CROSS-PACKAGE-ONTOLOGY-SYNC.md) | Real `~/ash_ex4pm` commit `59eb76f` | Formalize + test querying a Hex dependency's packaged ontology as a first-class supported `ggen_igniter.sync` pattern |
| [02-IGNITER-ASH-SPARK-VERSION-CONFORMANCE](02-IGNITER-ASH-SPARK-VERSION-CONFORMANCE.md) | Verified deep-research findings + real `mix.lock` reads (this repo and `~/ash_ex4pm`) | Close the real `igniter 0.8.3` vs `0.8.4` pin gap; confirm Ash 3.x notifier/Spark 2.6+ behavior assumptions this repo's own docs/templates make still hold |
| [03-ASH-NOTIFIER-LOAD2-GENERATION-PACK](03-ASH-NOTIFIER-LOAD2-GENERATION-PACK.md) | Real `~/ash_ex4pm` commit `d4ffb71` | Evaluate promoting the hand-written `Ash.Notifier.load/2` pattern into a reusable `ggen_igniter` generation pack |
| [05-GGEN-SYNC-TEMPLATE-PIPELINE-BLOCKER](05-GGEN-SYNC-TEMPLATE-PIPELINE-BLOCKER.md) | Real `~/ash_a2a/MANUFACTURING_RECEIPT.md` (refreshed commit `4f1a79e`), disclosed `/workspace` path-resolution blocker | Reproduce or refute the blocker for real, fix if real, then actually run `mix ggen_igniter.sync` against a real consumer's templates end-to-end |

## Research provenance

Full findings, confidence levels, votes, and refuted claims: the deep-research
workflow's structured result (this session, not persisted to a file in either repo —
cited inline in each ticket below by URL and date where load-bearing). Two headline,
high-confidence, unanimously-verified findings anchor tickets 01-03:

1. Ash 3.0 tightened `Ash.Notifier` semantics (post-commit-only firing,
   `requires_original_data?/2` opt-in, an optional `load/2` callback with
   cross-notifier load deduplication) — `hexdocs.pm/ash/notifiers.html`,
   `hexdocs.pm/ash/upgrading-to-3-0.html`.
2. Igniter is confirmed AST-based (Sourceror + Rewrite), not regex/text patching, with
   a composable `<package>.install`/generator task model — `igniter.hexdocs.pm/readme.html`,
   `github.com/ash-project/igniter`. This is the same mechanism `ggen_igniter` itself
   is built on; the research validates the approach, not just informs new work.

## Addendum (this session, separate from the `ash_ex4pm`-grounded work above)

Ticket 05 was added from a *different* real source: a deep-research pass into the
A2A/Reactor/Spark ecosystem plus a real `ash_a2a` requirements-implementation swarm run
in this same session (`~/ash_a2a` commits `473f9f7`..`4f1a79e`) surfaced a real,
disclosed blocker in this repo's own `mix ggen_igniter.sync` CLI. It shares this
directory because it carries the same `v26.9.10` version string and the same
research-driven-backlog shape as 01-03, but its grounding is independent — read its own
"Grounding" section rather than assuming shared provenance with 01-03.

A companion idea from that same research pass — extending `ggen_igniter`'s ontology
loader to ingest non-RDF schema sources (e.g. a `.proto` file) — was considered and
**rejected outright, not just deprioritized**: `ggen_igniter`'s ontology pipeline
(`lib/ggen_igniter/ontology.ex`) is scoped to RDF by design, not by an accidental gap.
No ticket exists for it; this line records that the idea was raised and explicitly
declined, so it isn't silently re-proposed later as an unconsidered gap.

## See Also

- `~/ash_ex4pm/lib/mix/tasks/ash_ex4pm.ggen.sync.ex`, `~/ash_ex4pm/priv/ggen/` — the
  real consumer code grounding ticket 01.
- `~/ash_ex4pm/lib/ash_ex4pm/notifier.ex` (`load/2`, committed `d4ffb71`) — the real
  code grounding ticket 03.
- `~/ash_a2a/MANUFACTURING_RECEIPT.md`, `~/ash_a2a/lib/ash_a2a/capability_index.ex`
  (commit `4f1a79e`) — the real evidence grounding ticket 05.
- `~/ggen_igniter/docs/status.md` — this repo's own real IMPLEMENTED/PARTIAL_ALIVE/
  PLANNED status ledger; the existing (separate) v26.9.10 swarm-pass gaps live here.
- `~/ggen_igniter/CHANGELOG.md`'s v26.9.10 entry — the other, already-in-progress
  v26.9.10 work stream this directory does not duplicate.
- `~/ggen_igniter/docs/jira/v26.9.8/00-OVERVIEW.md` — the ticket-set convention this
  directory follows: index+charter overview, numbered topic files, real evidence
  citations, honest PLANNED/EXECUTED status distinction, never a bare status claim.
