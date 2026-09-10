# Formalize cross-package ontology sync as a first-class `ggen_igniter.sync` pattern

## Status

PLANNED / NOT STARTED.

## Grounding (real, this session)

`~/ash_ex4pm` (a separate Spark DSL extension repo, not part of `ggen_igniter`) just
built and committed a real generation unit that queries a **different package's**
packaged ontology, not a local file:

- `~/ash_ex4pm/mix.exs` added `{:ggen_igniter, "~> 26.9", only: [:dev, :test],
  runtime: false}` and `{:ex4pm, "== 26.9.9"}` (already present).
- `~/ash_ex4pm/lib/mix/tasks/ash_ex4pm.ggen.sync.ex` (new `mix ash_ex4pm.ggen.sync`
  task) reads `~/ash_ex4pm/priv/ggen/manifest.json` and, per unit, shells:
  `mix ggen_igniter.sync --ontology <ontology> --query <k>=<v> --template <template>
  --out <out>`.
- `~/ash_ex4pm/priv/ggen/manifest.json`'s one unit names `ontology:
  "{{ex4pm_ontology}}"` — a placeholder resolved (per the task's own moduledoc,
  `~/ash_ex4pm/lib/ash_ex4pm/ferroplan.ex`'s generated header comment) to
  `ex4pm`'s **packaged** `priv/ontology/ex4pm.ttl`, reachable because `ex4pm`'s own
  `mix.exs` declares `files: ["lib", "priv", "mix.exs"]` (confirmed this session —
  `priv/` ships with the Hex package), not a path relative to `ash_ex4pm`'s own
  working tree.
- Real receipts exist for this run: `~/ash_ex4pm/.ggen_igniter/manifest.json`,
  `~/ash_ex4pm/.ggen_igniter/receipts/2026-09-10.jsonl`.
- The generated output, `~/ash_ex4pm/lib/ash_ex4pm/ferroplan.ex`, is currently an
  empty-function-list delegate — correct, honest output given `ex4pm`'s ontology
  individuals for this capability are still marked `forward_declared` (not yet
  admitted with a live `beam4pm` route), not a bug.
- Commit: `~/ash_ex4pm` `59eb76f` "feat: ferroplan capability generation via
  ggen_igniter".

This is a real, live pattern this repo's CLI was actually asked to do — resolve an
`--ontology` path that lives inside a **different package's** `priv/` directory,
reached via the calling project's own dependency resolution (`Mix.Project.deps_path/1`
or equivalent), not a path relative to the project being generated into.

## Open question this ticket must answer with real evidence, not assumption

Does `mix ggen_igniter.sync --ontology <path>` **today** correctly resolve a path like
`deps/ex4pm/priv/ontology/ex4pm.ttl` (or however `ash_ex4pm`'s task actually resolved
the `{{ex4pm_ontology}}` placeholder — read the real code, don't assume) when invoked
from a consumer project, including:

- A relative path resolution that is correct regardless of which directory `mix` was
  invoked from within the consumer project (a known general Igniter/Mix footgun).
  What is the real cwd base `GgenIgniter.Sync`'s `--ontology` flag resolves against —
  the consumer project's root, or ggen_igniter's own path? Read
  `lib/mix/tasks/ggen_igniter.sync.ex`'s real handling of the `--ontology` option to
  answer this, do not guess.
- A dependency that has NOT yet run `mix deps.get` (the ontology file genuinely absent
  under `deps/`) — does the real error message name the actual missing path and the
  actual missing-dependency cause, or something generic?
- A dependency pinned to a version whose `priv/ontology/*.ttl` doesn't yet contain the
  individuals a consumer's SPARQL query expects (the exact "empty generated output"
  case `ash_ex4pm`'s `ferroplan.ex` already exercises for real) — confirm this fails
  open (empty, valid output) rather than crashing, matching what was actually observed.

## Definition of Done

- A new, real fixture under `test/fixtures/` (or an addition to an existing fixture)
  that reproduces the cross-package shape: a "library" fixture package with its own
  `priv/ontology/*.ttl`, and a "consumer" fixture package with a `mix.exs` path (or
  Hex-style) dependency on it, running `mix ggen_igniter.sync --ontology
  deps/<library>/priv/ontology/<file>.ttl` for real.
- A real, passing Chicago-style test (real files on disk, real `mix ggen_igniter.sync`
  subprocess or direct task invocation, real generated output asserted by content) —
  covering both the success case (individuals present, non-empty generated output) and
  the "individuals not yet admitted" case (empty-but-valid generated output, matching
  `ash_ex4pm.ferroplan.ex`'s real observed shape).
- `docs/integrations/` gains a real doc page (or a section on an existing relevant
  page) documenting this pattern by name, citing `ash_ex4pm`'s real usage as the
  worked example, including the exact path-resolution rule confirmed by reading the
  real code above (not restated from this ticket's open question, which must be
  answered with a citation to the real line(s) in `lib/mix/tasks/ggen_igniter.sync.ex`).
- If the path-resolution behavior is found to NOT already handle the cross-package
  case correctly (e.g. it silently resolves relative to the wrong root, or fails with
  an unhelpful error), a real fix lands, gated by the new test above — this ticket is
  not closed by documentation alone if a real defect is found.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`,
  and this repo's existing hygiene grep (`grep -rn "Mock\|mock(\|patch(\|monkeypatch"
  test lib native` → zero matches) all clean, pasted as real command output, not a
  narrated summary.

## Non-goals

- Does not change `ash_ex4pm`'s own `mix ash_ex4pm.ggen.sync` task — that task already
  works (verified this session: `mix test` 56/56 in `~/ash_ex4pm` after adding it).
  This ticket is about `ggen_igniter` formally supporting and testing the pattern that
  task already depends on, not modifying the consumer.
- Does not implement general `pack.toml`-level dependency resolution (see
  `docs/jira/v26.9.1/06-KNOWN-LIMITATIONS-AND-NON-GOALS.md`'s non-goal 1 for the
  precedent this repo already declined that scope under). This ticket is scoped to
  `--ontology` path resolution for a single explicit flag value, not automatic
  transitive pack pulls.

## See Also

- `~/ash_ex4pm/lib/mix/tasks/ash_ex4pm.ggen.sync.ex`, `~/ash_ex4pm/priv/ggen/`,
  `~/ash_ex4pm/lib/ash_ex4pm/ferroplan.ex` — the real worked example.
- `lib/mix/tasks/ggen_igniter.sync.ex` — the real task whose `--ontology` handling
  this ticket must read and, if needed, fix.
- `~/ex4pm/priv/ontology/ex4pm.ttl` — the real, packaged ontology `ash_ex4pm`'s task
  queries; its `ex4pmb:AdmittedBeam4pmService` individuals (lines ~178-194) are the
  ones currently `forward_declared`.
- `00-OVERVIEW.md` — this directory's charter and cross-references.
