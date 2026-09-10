# Igniter/Ash/Spark version-conformance audit

## Status

PLANNED / NOT STARTED.

## Grounding (real, this session)

A deep-research pass (5 angles, 21 sources, 25 claims adversarially verified 3-vote)
plus direct `mix.lock` reads in this repo and `~/ash_ex4pm` surfaced a real,
currently-unreconciled version gap and several behavior assumptions worth confirming
against this repo's own templates/docs, which were not re-read as part of the research
itself:

- **This repo's own `mix.lock`** pins `igniter` at **`0.8.3`**
  (`~/ggen_igniter/mix.lock:30`), while `mix.exs:99` allows `~> 0.8` (so `0.8.3` is
  simply what was last resolved, not a hard ceiling). The research (3-0 verified
  against `igniter.hexdocs.pm/readme.html`, fetched this session) found current stable
  Igniter documented at `v0.8.4`. This is a one-patch-version gap, not confirmed to
  contain a behavior change relevant to this repo — that confirmation is this ticket's
  job, not assumed here.
- **`ash`/`spark` pins already match what `~/ash_ex4pm` uses in production** —
  `ash 3.33.1`, `spark 2.7.2` in both repos' `mix.lock` (confirmed by direct read of
  both files this session). No version gap here; recorded as a real, positive finding
  worth stating rather than silently assuming.
- **Ash 3.0's `Ash.Notifier` semantics** (3-0 verified against
  `hexdocs.pm/ash/notifiers.html`, `hexdocs.pm/ash/upgrading-to-3-0.html`):
  notifications fire only post-commit; the default PubSub payload no longer includes
  both old and new values (`previous_values?: true` restores it); a custom notifier
  needs `requires_original_data?/2` to opt into original-record access, which then
  disables atomic/bulk-action compatibility for that resource/action; an optional
  `load/2` callback lets a notifier request related data pre-`notify/1`, deduplicated
  across notifiers. **This repo's own Ash-integration templates/docs
  (`docs/integrations/ash/`, any `priv/ggen/*/templates/*.ex.eex` that generates
  `Ash.Notifier`-implementing code) have not been checked against this ticket's
  grounding for whether they state or assume pre-3.0 notifier semantics** — that check
  is this ticket's scope, not performed as part of the research pass itself.
- **Ash v3.30.0 (2026-07-21, 2-1 verified against
  `github.com/ash-project/ash/blob/main/CHANGELOG.md`)** shipped `mix
  ash.set.domains`, an Igniter-based domain-configuration codegen task — a concrete,
  dated precedent of Ash itself using the exact Igniter mechanism this repo is built
  on. Worth a direct comparison: does `mix ash.set.domains`'s real implementation
  (`deps/ash/lib/mix/tasks/ash.set.domains.ex` once fetched, or its Hex-published
  source) suggest any Igniter API surface or pattern this repo's own Ash-domain
  generation (`test/fixtures/ash-lifecycle-pack/templates/domain.ex.eex`, per
  `docs/status.md`'s "Multi-domain fan-out" row) should adopt or already matches.

## Definition of Done

- Real command output pasted: `mix deps.get && mix deps.update igniter --only`
  (or equivalent) run, and a real decision recorded — either bump the resolved
  `igniter` pin to `0.8.4` with a clean `mix test` run after, or a stated, evidence-
  backed reason not to (e.g. a real, cited incompatibility found by reading
  `0.8.4`'s real changelog against this repo's actual Igniter API usage).
- A real grep-and-read pass over every `docs/integrations/ash/*.md` page and every
  `priv/ggen/*/templates/*.ex.eex` template that generates code implementing
  `Ash.Notifier` (or documents doing so), checking each against the three real Ash
  3.0 notifier-semantics findings above. Each page/template gets one of: (a) already
  correct, cited by the specific line confirming it; (b) needs an update, with the
  real fix landed in this ticket; (c) not applicable (the page/template doesn't touch
  notifier semantics), stated explicitly rather than silently skipped.
- A real, cited comparison between `mix ash.set.domains`'s actual implementation and
  this repo's own multi-domain generation template, resulting in either a stated "no
  gap found, here is why" or a real, scoped follow-up ticket if a gap is found (this
  ticket does not have to close that follow-up itself, only name it with evidence).
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, and
  this repo's hygiene grep all clean, pasted as real output.

## Non-goals

- Does not perform a full ecosystem-wide dependency upgrade sweep (Elixir/OTP version,
  every other Hex dependency) — scoped to `igniter`/`ash`/`spark`, the three packages
  the research pass and the grounding above actually cover with verified findings.
- Does not re-litigate or re-run the deep-research workflow itself — this ticket
  consumes its already-verified findings and checks them against this repo's own real
  code, it does not re-search the web.
- The Elixir 1.19 claims the research pass checked (lazy module loading, an AST escape
  mechanism for quoted structs) were both **refuted** (1-2 and 0-3 votes respectively)
  — this ticket does not act on them; they are recorded here only so a future reader
  does not re-surface them as unverified rumor.

## See Also

- `~/ggen_igniter/mix.lock`, `~/ash_ex4pm/mix.lock` — the real pinned-version evidence
  this ticket's grounding cites.
- `docs/status.md`'s "Multi-domain fan-out" row — the existing real capability this
  ticket's `mix ash.set.domains` comparison targets.
- `00-OVERVIEW.md` — this directory's charter and cross-references.
- `github.com/ash-project/ash/blob/main/CHANGELOG.md`, `hexdocs.pm/ash/notifiers.html`,
  `hexdocs.pm/ash/upgrading-to-3-0.html`, `igniter.hexdocs.pm/readme.html` — the
  primary sources this ticket's grounding cites; re-fetch rather than trust this
  ticket's summary if more than a few weeks have passed.
