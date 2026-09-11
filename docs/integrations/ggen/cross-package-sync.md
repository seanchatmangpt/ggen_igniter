# Cross-package ontology sync

A pattern where `mix ggen_igniter.sync --ontology PATH` queries an ontology
file that ships inside a **different package's** `priv/` directory, not a
file local to the project being generated into.

## Real worked example: `~/ash_ex4pm`

`~/ash_ex4pm` (a Spark DSL extension repo, not part of `ggen_igniter`) added
`{:ggen_igniter, "~> 26.9", only: [:dev, :test], runtime: false}` and
`{:ex4pm, "== 26.9.9"}` to its own `mix.exs`, then wrote
`~/ash_ex4pm/lib/mix/tasks/ash_ex4pm.ggen.sync.ex` (`mix
ash_ex4pm.ggen.sync`), a task that resolves ex4pm's packaged
`priv/ontology/ex4pm.ttl` via `Application.app_dir(:ex4pm,
"priv/ontology/ex4pm.ttl")` — real because `~/ex4pm`'s own `mix.exs`
declares `files: ["lib", "priv", "mix.exs"]`, so `priv/` ships with the Hex
package — and shells out per generation unit:

```
mix ggen_igniter.sync --ontology <resolved-ex4pm-ontology-path> \
  --query <k>=<v> --template <template> --out <out>
```

`~/ash_ex4pm/priv/ggen/manifest.json` declares one generation unit,
`automated_planning`, whose `ontology` field is the placeholder
`"{{ex4pm_ontology}}"`, resolved by the task above (see the task's own
moduledoc for the full rationale) before it ever reaches `ggen_igniter`.
`~/ash_ex4pm/lib/ash_ex4pm/ferroplan.ex` — the real generated output for
this unit — is currently an empty-function-list delegate: correct, honest
output given `ex4pm`'s `ex4pmb:AdmittedBeam4pmService` planning individuals
(`~/ex4pm/priv/ontology/ex4pm.ttl` lines ~178-194) are still
`ex4pmb:status "forward_declared"`, not `"admitted"` — not a bug. Real
commit: `~/ash_ex4pm` `59eb76f`.

## The exact resolution rule (confirmed by reading the real code)

**Two independent, parallel implementations of the same `cond`-shaped
resolution logic exist, and a plain `mix ggen_igniter.sync --ontology PATH`
(no `--for-each`, no multi-engine comparison) goes through the SECOND one,
not the one this ticket originally named:**

- `Mix.Tasks.GgenIgniter.Sync.resolve_ontology!/1`
  (`lib/mix/tasks/ggen_igniter.sync.ex`, ~line 1264-1296) — called only by
  `run_for_each_via_reactor!/7` (the `--for-each` fan-out path) and
  `run_engine_comparison!/3` (the multi-engine `--engine all`/comma-list
  comparison path).
- `GgenIgniter.Reactors.ReconcileReactor.resolve_ontology_path!/1`
  (`lib/ggen_igniter/reactors/reconcile_reactor.ex`, ~line 1687-1710) — the
  ONE actually reached by the default, single-target dispatch (the `true
  ->` branch of `Mix.Tasks.GgenIgniter.Sync.run_via_reactor/3`'s own `cond`,
  ~line 843, builds `reconcile_opts` directly from the CLI's raw `opts` —
  it never calls `resolve_ontology!/1` at all — and hands that to
  `ReconcileReactor.run/1`'s own `:load_ontology` Reactor step, which calls
  `resolve_ontology_path!/1` internally). This is the code path exercised
  by `~/ash_ex4pm`'s real usage and by this ticket's own test fixture.

This asymmetry was found empirically this session, by writing the real
test below and watching its missing-`--ontology`-file assertion fail
against the FIRST function's fix alone — the generic `%File.Error{}` was
still reaching the CLI's stdout, because the single-target path never
touches `resolve_ontology!/1`. Both functions now carry the identical
friendlier-error fix (see "Missing-file behavior" below).

Both functions pass an explicit `--ontology PATH` through **verbatim** — no
cwd-anchoring, no rewriting relative to `ggen_igniter`'s own install
location. That verbatim path reaches `GgenIgniter.Ontology.load!/1`
(`lib/ggen_igniter/ontology.ex`), which dispatches on extension to
`RDF.Turtle.read_file!/1` / `RDF.NTriples.read_file!/1` /
`RDF.NQuads.read_file!/1` — every one of which resolves a relative path
against the real OS process's current working directory via
`File.open!/2`, the same as any other Elixir file read.

**Consequence**: `--ontology` is always resolved relative to whichever
directory the `mix ggen_igniter.sync` (or `mix ash_ex4pm.ggen.sync`, or any
consumer's own wrapping task) OS process's cwd actually is at the moment it
runs — normally the consuming project's own root, since that's where `mix`
itself must be invoked from to discover the task at all (`ggen_igniter`
must be a compiled dependency of the project `mix` is run inside). It is
**never** resolved relative to `ggen_igniter`'s own install location inside
`deps/`. This holds regardless of which subdirectory within that project
`--ontology`'s own relative path happens to name — `deps/some_dep/priv/
ontology/x.ttl`, a local `priv/ontology/x.ttl`, or any other shape, all
resolve the same way: verbatim, against real OS cwd.

No defect exists in this resolution path for the cross-package case — this
was an open question this repo's own `docs/jira/v26.9.10/
01-CROSS-PACKAGE-ONTOLOGY-SYNC.md` ticket set out to answer with evidence,
not assumption, and the citations above are that evidence.

## Missing-file behavior

A missing `--ontology` path now raises a named, friendly `ArgumentError` in
BOTH resolution functions above (each one's first `cond` clause) — the same
friendlier shape the `--pack`/`--pack-dir` fallback branch already had in
each, naming both the resolved path and the real cwd it was resolved
against, and pointing at this doc for the common cross-package cause (a
missing `mix deps.get`). Before this ticket, a missing direct `--ontology`
path raised the generic `File.Error` from `RDF.Turtle.read_file!/1` instead
— functionally correct (the run still fails, non-zero exit) but without a
project-specific hint. For the default (non-`--for-each`) dispatch path,
this `ArgumentError` is raised inside `ReconcileReactor`'s `:load_ontology`
step, caught by the reactor's own step-failure handling, and surfaced via
`describe_failure/1`'s `inspect/1` fallback as part of the
`"ggen_igniter: reactor reconciliation failed (refused): ..."` message —
the friendlier text is still present as a substring of that wrapped
message, just not the top-level exception text verbatim.

## Test fixture reproducing this shape

`test/fixtures/cross_package_ontology/` — a `library/priv/ontology/*.ttl`
(the packaged ontology a library ships) and a `consumer/deps/
capability_lib/priv/ontology/*.ttl` (the same content, at the path shape a
real `mix deps.get` would produce inside a consuming project), covering
both the "individuals admitted" case (`capability.ttl`, non-empty generated
output) and the "individuals not yet admitted" case
(`capability_none_admitted.ttl`, empty-but-valid generated output,
mirroring `ferroplan.ex`'s real observed shape) — see
`test/ggen_igniter_cross_package_ontology_sync_test.exs`.

## Non-goals

Transitive `pack.toml`-level dependency resolution (fetching a pack's own
declared ontology dependencies automatically) is explicitly out of scope —
see `docs/jira/v26.9.1/06-KNOWN-LIMITATIONS-AND-NON-GOALS.md`'s non-goal 1
for the precedent. This pattern only covers `--ontology`'s own path
resolution for a single explicit flag value.

## See Also

- `docs/jira/v26.9.10/01-CROSS-PACKAGE-ONTOLOGY-SYNC.md` — the ticket this
  page answers.
- `docs/integrations/ggen/packs.md` — the `--pack`/`--pack-dir` convention,
  whose ontology-not-found error message this pattern's direct `--ontology`
  case now matches.
- `lib/mix/tasks/ggen_igniter.sync.ex` — `resolve_ontology!/1`.
- `lib/ggen_igniter/ontology.ex` — `GgenIgniter.Ontology.load!/1`.
