# Archive

Superseded documentation, kept for historical record rather than deleted.

## `ggen_igniter_factory/` (archived 2026-09-01)

The former `.ggen_igniter_factory/` directory: ~26 markdown files (plus JSON/JSONL
ledgers) produced by a swarm of concurrent verification agents on 2026-08-27, timestamped
to a specific in-flight HEAD (`767bccea32d03790a1f4975596a06ecd16df365f`) during the
v26.8.27 release-closure pass. It predates this repo's current Diátaxis-structured `docs/`
tree and its content is fully superseded:

- `capability_matrix.md` / `ADVERSARIAL.md` / the `adversarial/01`–`10` reports / the
  `redteam-*.md` files → superseded by `docs/status.md` (which explicitly cites
  `docs-findings.jsonl` from this same archived directory as its source and documents,
  per capability, which since-fixed findings it supersedes — e.g. the
  `Reactor.Executor.ConcurrencyTracker` blocker and the `already_present_at?/4` arity
  mismatch, both recorded here as live defects at their assessment time, are resolved and
  re-verified in `docs/status.md`) and `docs/reviews/` (fresh reviewer passes against
  current `main`).
- The destructive-ontology-evolution findings (`adversarial/09_destructive_evolution.md`,
  `ADVERSARIAL.md` MUST FIX #3 — no orphan-file reconciliation on rename/removal) →
  superseded by `docs/testing/adversarial.md`, which documents the now-implemented
  `--on-stale refuse|prune|preserve` reconciliation manifest closing this exact gap.
- `AUTHORITY.md` (agent permission boundaries for that release-closure swarm) → superseded
  by this repo's root `CLAUDE.md` (Destructive operations, Parallel agent protocol
  sections) and `.claude/settings.json`'s `PreToolUse` guard.
- `version_check.md`, `state.json`, `zach_chris_acceptance.md`, `dogfood-self.md`,
  `GGEN-PARITY-NOTE.md`, `ggen-parity.json`, `reactor-graph.md`, and the `ledger*.jsonl`
  files → point-in-time working artifacts of that specific closure pass, not standing
  documentation; the release they concerned is closed (see `docs/architecture/adr/
  0008-evidence-ranked-multi-engine-registry.md` and surrounding ADRs for what actually
  shipped).

Current equivalents for anyone looking for what this directory used to cover:

- `docs/status.md` — real, current IMPLEMENTED / PARTIAL_ALIVE / PLANNED status per capability
- `docs/reviews/` — current reviewer passes (implementation contradictions, usability, architecture consistency)
- `docs/testing/adversarial.md` — current adversarial/destructive-verification coverage

Moved with `git mv` (history preserved), not deleted.
