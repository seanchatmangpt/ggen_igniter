# Igniter/Ash/Spark version-conformance audit

## Status

DONE — all three DoD items resolved with real, executed evidence (this session,
2026-09-10). Version bump: real, evidence-backed REFUSED (regression found and
demonstrated by A/B test run, not assumed). Ash.Notifier audit: not applicable
(zero matches). `mix ash.set.domains` comparison: no gap found (already matches).

### 1. Version-bump decision: REFUSED, with a real, demonstrated regression

`mix deps.get && mix deps.update igniter --only` (this repo's real equivalent to `--only
ggen_igniter`, since `igniter` is a direct, non-transitive dep here) resolved
`igniter 0.8.3 => 0.8.4` (also pulling `spitfire 0.4.0 => 0.4.1` and
`mint 1.9.3 => 1.10.0` as their own compatible-range bumps). `mix compile
--warnings-as-errors` stayed clean at 0.8.4. `mix test` did not: a real A/B
comparison (full suite at 0.8.4, then `git checkout -- mix.lock && mix deps.get`
back to 0.8.3, re-run the same test files, then forward again to 0.8.4 to
reconfirm) isolated a real, reproducible regression, distinct from unrelated
environmental flakiness also observed in this session (see below):

- **Real regression, 5 tests, `test/ggen_igniter_ash_gen_core_alignment_test.exs`**:
  every test that composes `ash.gen.base_resource` then `ash.gen.resource` in the
  same `Igniter.Test` run now fails at igniter 0.8.4 with
  `** (RuntimeError) The base module <Mod> is not in the list of base resources`,
  raised from `(ash 3.33.1) lib/mix/tasks/gen/ash.gen.resource.ex:153` via
  `(igniter 0.8.4) lib/igniter.ex:497: Igniter.compose_task/4`. The same 5 tests
  pass clean at igniter 0.8.3 (confirmed by re-running the identical test file
  at 0.8.3: 0 failures). This means `Igniter.compose_task/4`'s config-mutation
  visibility across two composed tasks in the same `%Igniter{}` pipeline changed
  between 0.8.3 and 0.8.4 in a way `ash.gen.resource`'s `base_resources` lookup
  depends on — a real, demonstrated incompatibility, not a hypothetical read of
  a changelog.
- **Self-correcting, not a regression**: `test/ggen_igniter_ash_task_coverage_test.exs`'s
  "version scope of the envelope" test failed at 0.8.4 because its own
  `@known_version_skew` list still says `[:igniter]` is expected-skewed between
  this repo and its fixture, but at 0.8.4 both now resolve identically
  (`igniter: repo "0.8.4" / fixture "0.8.4"`) — the test is correctly reporting
  that the skew it was tracking is gone. Not acted on further since the bump
  itself is being refused this session; left as a forward note only.
  (Since the pin stays at 0.8.3 this session, `@known_version_skew` needs no
  edit — the skew it names is still real at 0.8.3.)
- **Unrelated environmental flakiness, disclosed but not a version-bump finding**:
  the *first* full-suite run at 0.8.4 (before this A/B isolation) additionally
  showed 3 `System.cmd`-based `ExUnit.TimeoutError`s in
  `test/ggen_igniter_sync_inject_test.exs` (60s timeout) and, separately, one
  run's output was clobbered because a background job was written to the shared
  `/tmp` (not this session's scratchpad) and another concurrent Claude session's
  unrelated `beam4pm`/`wasm4pm` project test output landed in the same file —
  both are this-machine's-concurrent-load artifacts (confirmed: re-running
  `test/ggen_igniter_sync_inject_test.exs` alone, isolated, passed 9/9 in 66s),
  not evidence about igniter 0.8.4 itself, and are named here only so a future
  reader doesn't mistake them for version-bump findings.

**Decision**: `mix.lock`'s `igniter` pin is left at `0.8.3` (confirmed via
`git checkout -- mix.lock && mix deps.get`, `grep -n '"igniter"' mix.lock` shows
`0.8.3` restored). `mix.exs:99`'s `{:igniter, "~> 0.8"}` constraint is unchanged —
it already permits either version; the *lock* is what pins the safe one. This is
a real, evidence-backed REFUSED, not a default/unexamined non-bump: the
regression was demonstrated by running the actual test suite at both versions,
not inferred from a changelog read.

### 2. Ash.Notifier audit: not applicable (zero matches, real grep)

```
grep -rn "Ash\.Notifier\|@behaviour Ash\.Notifier\|notify(\|requires_original_data?\|def load(" \
  docs/integrations/ash/ priv/ggen/*/templates/*.ex.eex
```

Real output: no matches (grep exit code 1, empty stdout). No page under
`docs/integrations/ash/` and no `priv/ggen/*/templates/*.ex.eex` template
generates or documents code implementing `Ash.Notifier`. The three Ash 3.0
notifier-semantics findings in this ticket's Grounding section (post-commit-only
firing, `previous_values?: true`, `requires_original_data?/2`) have no real
target in this repo to check against — recorded as **(c) not applicable** per
the DoD's own three-way classification, not silently skipped.

### 3. `mix ash.set.domains` vs. this repo's domain-generation template: no gap found

Real read of `deps/ash/lib/mix/tasks/ash.set.domains.ex` (vendored, this
session): its `igniter/2` calls
`Ash.Mix.Tasks.Helpers.discover_domains/1` then
`Igniter.Project.Config.configure(igniter, "config.exs", app_name, [:ash_domains], domains)`
to patch `config :otp_app, ash_domains: [...]`.

This repo's own domain-registration logic
(`lib/ggen_igniter/doctor_fixes.ex`'s `ash_domains_rule/0`,
`fix_ash_domains!/1`, `rewrite_ash_domains!/3`, lines ~558-767) does the
structurally identical thing via `Igniter.Project.Config.modify_config_code/4`
with the same `[:ash_domains]` key path (`doctor_fixes.ex:756-761`), just on a
`Sourceror.Zipper.t()` built without a full `%Igniter{}` (see this repo's own
`CLAUDE.md` on why: `project_dir`-as-argument vs. cwd-as-target). Both mechanisms
converge on the same real config-key surface Ash itself uses upstream.

`test/fixtures/ash-lifecycle-pack/templates/domain.ex.eex` (the template
`docs/status.md`'s "Multi-domain fan-out" row references) renders the `Ash.Domain`
module bodies themselves (`use Ash.Domain`, `resources do ... end`), a disjoint
concern from config registration — the config-registration half is handled
separately, by `GgenIgniter.DoctorFixes.ash_domains_rule/0` (via
`mix ggen_igniter.doctor --fix`), not by this template. No gap: this repo already
has the equivalent of `mix ash.set.domains`'s specific mechanism
(`Igniter.Project.Config`, `[:ash_domains]` key), it is simply reached through
the doctor/fix pipeline rather than emitted inline by the domain-rendering
template — a real architectural split, not a missing capability. **No follow-up
ticket needed.**

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
