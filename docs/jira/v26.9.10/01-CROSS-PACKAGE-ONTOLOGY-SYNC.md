# Formalize cross-package ontology sync as a first-class `ggen_igniter.sync` pattern

## Status

COMPLETE. Real fixture, real passing tests (both the individuals-admitted
and individuals-not-yet-admitted cases, plus a direct cwd-relative
resolution proof), a real doc page, and a real small enhancement all
landed -- see the Definition-of-Done checklist below with citations.

No defect was found in `--ontology`'s own path-resolution logic: it already
resolves a cross-package `deps/<library>/priv/ontology/<file>.ttl` path
correctly, because `--ontology` is passed through verbatim and
`RDF.Turtle.read_file!/1` (reached via `GgenIgniter.Ontology.load!/1`,
`lib/ggen_igniter/ontology.ex`) resolves a relative path against the real
OS process cwd. This was confirmed by reading the real code (this session)
and is now additionally backed by a real, passing test that changes the
real OS cwd via `File.cd!/2` and calls `GgenIgniter.Ontology.load!/1`
directly, with a control assertion showing the same relative path does NOT
resolve from a different real cwd (see
`test/ggen_igniter_cross_package_ontology_sync_test.exs`, describe block
"the real cwd-relative resolution mechanism").

**Correction found empirically this session, real and worth recording**:
this ticket's original grounding named ONE resolution function,
`Mix.Tasks.GgenIgniter.Sync.resolve_ontology!/1`
(`lib/mix/tasks/ggen_igniter.sync.ex` ~line 1264-1296) -- but that function
is reached only by the `--for-each` and multi-engine-comparison paths. A
plain `mix ggen_igniter.sync --ontology PATH` (the shape `~/ash_ex4pm`
actually uses, and this ticket's own test fixture exercises) goes through a
SEPARATE, parallel implementation of the identical `cond` logic:
`GgenIgniter.Reactors.ReconcileReactor.resolve_ontology_path!/1`
(`lib/ggen_igniter/reactors/reconcile_reactor.ex` ~line 1687-1710). The
real, passing test below caught this directly: fixing only the first
function left the missing-file test failing, because the CLI's actual
stdout still showed the generic `%File.Error{}` wrapped inside a
`"reactor reconciliation failed"` message. Both functions now carry the
identical friendlier-error fix -- see
`docs/integrations/ggen/cross-package-sync.md`'s "The exact resolution
rule" section for the full citation and mechanism.

### Definition-of-Done checklist, with citations

- [x] Fixture under `test/fixtures/cross_package_ontology/`: a `library/
  priv/ontology/*.ttl` (the library's own packaged ontology) and a
  `consumer/deps/capability_lib/priv/ontology/*.ttl` (the same content at
  the real `deps/<library>/...` path shape), covering both the
  individuals-admitted case (`capability.ttl`) and the
  individuals-not-yet-admitted case (`capability_none_admitted.ttl`).
- [x] Real, passing Chicago-style test:
  `test/ggen_igniter_cross_package_ontology_sync_test.exs` -- real
  `mix ggen_igniter.sync` subprocesses (no mocks) for both cases, plus the
  direct `GgenIgniter.Ontology.load!/1` cwd-proof test above.
- [x] `docs/integrations/ggen/cross-package-sync.md` -- new page
  documenting this pattern by name, citing `~/ash_ex4pm`'s real usage and
  the exact lines of BOTH real resolution functions (see the correction
  above).
- [x] Missing-file friendliness: both `resolve_ontology!/1`
  (`lib/mix/tasks/ggen_igniter.sync.ex`) and `resolve_ontology_path!/1`
  (`lib/ggen_igniter/reactors/reconcile_reactor.ex`) now raise the same
  friendlier named `ArgumentError` shape the `--pack`/`--pack-dir` branch
  already had (naming the resolved path and the real cwd), rather than
  letting the generic `File.Error` from `RDF.Turtle.read_file!/1`
  propagate. Covered by a real subprocess test asserting the new message
  text is present (as a substring of the reactor's wrapped failure
  message, for the default dispatch path).
- [x] `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test`, and the mock-hygiene grep all clean -- see the session's
  real command output (pasted in the delivering commit/PR, not restated
  here to avoid a second copy going stale -- see `docs/CLAUDE.md`'s
  cross-document-consistency rule).

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
