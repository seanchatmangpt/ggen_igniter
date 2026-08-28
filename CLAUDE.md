# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Elixir bootstrap of [ggen](https://github.com/seanchatmangpt/ggen)'s ontology-to-code
pipeline: `Ontology.load!/1` -> `Engine.run/2` (once per `--query`) -> `Render.render/2`
(EEx) -> `Actuate.write_file!/3` (or `inject_content!/5` / `eval_code!/2`), tracked by a
reconciliation manifest so a rename/removal upstream in the ontology is mechanically
detected instead of silently orphaning a file. It is a from-scratch Elixir port of the
real Rust `ggen`'s pipeline *shape*, not a wrapper/shell-out to the real `ggen` binary —
the one embedded real Rust component is a Rustler NIF (`native/ggen_graph_nif`) wrapping
`ggen`'s own oxigraph query engine, used as the default `--engine`.

Read `README.md` and `docs/status.md` before assuming a capability exists — this repo is
disciplined about marking things IMPLEMENTED / PARTIAL_ALIVE / PLANNED rather than
overclaiming, and the README's "Known Limitations" section documents real, sourced gaps.

## Commands

```
mix deps.get                    # requires a working Rust/cargo toolchain — the default
                                 # --engine oxigraph compiles native/ggen_graph_nif as
                                 # part of compiling this library, regardless of which
                                 # engine is used at runtime
mix compile
mix test                        # default suite; excludes mix e2e
mix test test/some_test.exs
mix test test/some_test.exs:42  # single test by line
mix coveralls                   # ExCoveralls (test_coverage tool configured in mix.exs)
mix dialyzer                    # PLT includes :mix (see mix.exs comment — Mix.Task-based
                                 # CLI tasks need it or dialyzer reports false unknown_function)
mix e2e                         # alias for `mix run test/e2e/run_e2e.exs` — see below
mix ggen_igniter.doctor         # run first when diagnosing an environment/consumer-project issue
mix ggen_igniter.sync --ontology path.ttl --query name=path.rq --template path.eex --out path.ex
```

### `mix e2e` — not part of `mix test`, run manually

A real, sequential end-to-end lifecycle test: scaffolds a genuine throwaway Ash+Phoenix
app via real `mix archive.install`/`mix igniter.new` subprocess calls (real network,
several minutes), adds `ggen_igniter` as a `path:` dep, then drives an 8-stage lifecycle
(resource creation, attribute add, relationships, custom action, `AshPhoenix.Form`
round-trip, `ash_phoenix.gen.live`, an attribute rename) against
`test/fixtures/ash-lifecycle-pack/`, running `mix compile --warnings-as-errors`/`mix test`
inside the scaffolded app after each stage. There is no `.github/workflows` CI config in
this repo — `mix e2e` is not run by CI, only manually.

## Architecture

### The four layers and who actually owns what

| Layer | Real role here |
|---|---|
| **ggen** | Semantic compilation (ontology -> query -> render -> actuate), Elixir-native except the oxigraph NIF. |
| **Igniter** | CLI-task plumbing only (`Igniter.Mix.Task`, `add_notice/2`) for `mix ggen_igniter.sync`/`.doctor`. Does **not** use Igniter's AST-mutation API (`Igniter.Project.Module`/`Igniter.Code`/`Sourceror.Zipper`) anywhere yet — real, disclosed future work. |
| **Reactor** | Coordination/ordering/concurrency/compensation. `GgenIgniter.Reactors.ReconcileReactor` is a plain `use Reactor` module (not `Ash.Reactor`) — real and tested, but opt-in via `config :ggen_igniter, use_reactor: true` (default `false`). |
| **Ash** | Optional, consumer-side only. Not a dependency of this repo itself; `mix ggen_igniter.doctor` only scans a *consumer* project for `use Ash.Domain`. |

### Two parallel pipelines — know which one you're editing

1. **Default pipeline**: `Mix.Tasks.GgenIgniter.Sync` (`lib/mix/tasks/ggen_igniter.sync.ex`)
   drives ontology-load -> engine-run -> render -> actuate inline, with full frontmatter
   parsing, `--for-each` fan-out, and `inject: true` splicing. `GgenIgniter.Reconcile.run/1`
   is a second, deliberately bounded entry point used by `GgenIgniter.Controller`
   (persistent GenServer) — it does **not** yet implement frontmatter parsing or
   `--for-each`; don't assume feature parity between `sync.ex` and `Reconcile.run/1`.
2. **Reactor pipeline** (opt-in): observe prior manifest -> load ontology -> resolve pack
   -> run queries -> render into `[%PendingActuation{}]` -> `:admit` (fail-closed,
   whole-plan invariants: duplicate paths, unowned deletes, stale-path violations) ->
   `:actuate` (concurrent, self-healing) -> `:verify` (`mix compile
   --warnings-as-errors`) -> finalize evidence (`GgenIgniter.Receipt`, persisted **before**
   manifest promotion on every path). Supports Reactor `undo/4` rollback when `:verify`
   fails after `:actuate` already wrote files. Both call sites
   (`Mix.Tasks.GgenIgniter.Sync`, `GgenIgniter.Controller`) are byte-for-byte unchanged
   when `use_reactor: false` (the default).

### Query engines (`--engine`)

- `oxigraph` (default since v26.8.27): in-process Rustler NIF over real oxigraph, chosen
  to fix an empirically-confirmed `ORDER BY` row-reversal bug in the pure-Elixir `sparql`
  hex package — see `docs/architecture/adr/0001-oxigraph-default-query-engine.md`.
- `sparql`: pure-Elixir, in-process, via the `sparql` hex package; has known
  `FILTER NOT EXISTS`/`UNION` limitations.
- `qlever`: real HTTP against an already-running QLever endpoint; `--ontology` is still
  loaded but only to resolve the `gnoa:Qlever`-typed store named by `--store-id`
  (required with this engine) — query text never touches the loaded graph.

### Reconciliation manifest (`--on-stale refuse|prune|preserve`)

Every non-`inject:` `mode: file` write is recorded in
`<manifest-dir>/.ggen_igniter/manifest.json`, keyed by the `(template, --out-template)`
recipe pair (not by ontology path/pack name). `stale = old_paths - new_paths` is the
mechanical signature of an upstream rename/removal. `refuse` (default) aborts the whole
run before writing if any stale path exists; `prune` deletes stale paths; `preserve`
leaves them, warns, and releases them from the tracked set. A true no-op re-run
(identical path+content-hash set) does not touch the manifest file at all, not even its
timestamp. This closes the orphan-file gap only for a recipe's *own* tracked outputs —
there is no cross-file stale-reference repair (e.g. a renamed Ash attribute breaking
separately hand-generated LiveView code).

### The `--pack` convention

`priv/ggen/<pack-name>/{ontology.ttl,gates/*.rq,templates/extension.ex.eex}` — an explicit
`--ontology`/`--query`/`--template` flag always wins over the pack-derived default.
`--pack-dir DIR` bypasses the `priv/ggen/<pack>/` convention entirely. Packs can be
fetched from `github:owner/repo[@ref]` or `hex:name[@version]` via
`GgenIgniter.Pack.fetch_pack!/2`.

### Frontmatter injection (`inject: true`)

A marker-based text splice (`Actuate.inject_content!/5`), not an AST-based structural
patch — see `docs/architecture/adr/0006-marker-based-injection-not-ast-patch.md`.
Requires exactly one of `before:`/`after:`/`at_line:` alongside `inject: true`.

## Testing discipline (enforced, not just preferred)

Chicago-school only: real collaborators (real files, real subprocesses, real SPARQL
engines/oxigraph NIF), state-based assertions on real resulting state. No
`Mock`/`mock(`/`patch(`/`monkeypatch` anywhere in `test`, `lib`, or `native` — verify with
`grep -rn "Mock\|mock(\|patch(\|monkeypatch" test lib native` (expect zero matches) before
claiming a test change is done.

## How to work in this repo (explore -> plan -> implement -> verify -> commit)

- **Explore**: check `docs/status.md`/`docs/glossary.md` and
  `mcp__plugin_lumen_lumen__semantic_search` before grepping — this repo's docs are
  disciplined about real IMPLEMENTED/PARTIAL_ALIVE/PLANNED status, so they're often
  faster and more trustworthy than re-deriving from code.
- **Plan**: use plan mode for anything crossing the `sync.ex` / `Reconcile.run/1` /
  Reactor-pipeline boundary, touching the reconciliation manifest's stale-detection
  logic, or spanning more than one of these layers. Skip it for single-file,
  describable-in-one-sentence changes.
- **Implement + verify**: run the `gate` skill before claiming anything is done — it is
  this repo's "check Claude can run" (compile + test + disk-reread + diff-matches-intent
  + Chicago-mock grep). Don't substitute a narrated summary for its receipt.
- **Commit**: `git commit -F <message-file>`, never inline `-m` for multi-line messages —
  this repo's commit history routinely cites ADRs/gate output inline, which is exactly
  the backtick/parenthesis-heavy text that breaks shell-tokenized `-m` strings.
- **GitHub work**: use the `gh` CLI for issues/PRs — no project-specific MCP server is
  configured here beyond the global Lumen indexer.

## Verification discipline (non-negotiable in this repo)

- Never claim work is done without running the gate: `mix compile --warnings-as-errors`
  + `mix test` (+ `mix dialyzer` when the PLT is already built). Paste the actual command
  output as the receipt — a summary is not a receipt. Use the `gate` skill.
- After any Edit/Write, re-`Read` the file to confirm the change actually landed on
  disk before moving on or reporting it done. An edit that silently didn't land (e.g. a
  branch added to a function that was never actually written to disk) is the single
  most common real failure mode seen in this repo's history — don't trust the tool
  result, re-read.
- Before running tests after an edit, show `git diff --stat` and the `git diff` for the
  specific hunk you claim to have changed, and confirm it matches your stated intent.
  Empty diff or an unintended file touched means stop and say so, not continue.
- Distinguish PRE-EXISTING failures from ones you introduced, explicitly, every time.

## Working-directory / multi-repo discipline

- This machine runs many repos in parallel. Before dispatching any subagent or running
  a verification pass, print `pwd` and `git remote -v` and pass the **absolute path**
  to `ggen_igniter` explicitly in the subagent's prompt — never assume inherited cwd.
- Every dispatched subagent's first action must be to `cd <ABS_PATH> && pwd && git
  remote -v && git rev-parse --abbrev-ref HEAD` and echo that verbatim before doing
  anything else. If the remote doesn't match `ggen_igniter`, it must stop and report a
  mismatch rather than proceed — this has produced real false "stale" findings before.

## Parallel agent protocol

- Use `git worktree` (see the `agent-worktree` skill) to isolate concurrent
  implementation/verification agents — never point two agents at the same working
  tree in this repo.
- Fan out authoring/exploration as wide as useful; serialize only the merge/integration
  step — one merge at a time, full gate re-run on `main` after each.
- Only one autonomous/scheduled loop (ERRC/DMEDI/ultracode/defect-round) may run
  against this repo at a time. Concurrent loops on the same repo have broken tests via
  colliding config changes and produced phantom "Cannot find module"-class staleness
  from concurrent writers — check for an in-flight pass before starting another.

## Destructive operations

- `rm -rf`, `git reset --hard`, `git push --force` require enumerating the exact
  resolved paths/refs and explicit user confirmation first — never issue these based on
  a plan alone. (A `PreToolUse` hook in `.claude/settings.json` blocks the raw commands
  and prompts for this.)
- Per the global git workflow rule: fix forward only, never `git reset --hard`;
  `git revert` is the one destructive-looking operation that's actually fine (it's a
  new commit).

## Prefer in-ecosystem tooling

- For scaffolding, templates, or ontology/pack research, use `ggen`/`ggen-marketplace`
  packs first (`GgenIgniter.Pack.fetch_pack!/2`, the `--pack` convention) — don't
  `WebFetch` external material or hand-roll ad hoc scaffolding when a pack already
  covers it.

## Repo-local skills and hooks

- `.claude/skills/gate/` — the verification gate above, invokable as a skill.
- `.claude/skills/defect-round/` — one falsification-hardened defect-hunting round
  (failing test first, fix, mutate, disk-verify, ledger receipt); `/defect-round` command
  wraps it.
- `.claude/skills/agent-worktree/` — worktree isolation contract for parallel agents.
- `.claude/settings.json` — a `PostToolUse` formatter hook (`mix format`/`rustfmt` on
  edited files), a `PreToolUse` guard that blocks raw `rm -rf`/`git reset
  --hard`/`git push --force` until paths/refs are enumerated and confirmed, and a
  `Stop` hook that deterministically blocks ending a turn while
  `mix compile --warnings-as-errors` is failing (fast compile-only check; full `mix
  test` stays inside the `gate` skill, invoked explicitly before claiming completion).
- `.claude/agents/ggen-reviewer.md` — adversarial-review subagent scoped to this
  repo's real correctness surfaces (manifest staleness, Reactor admission/
  compensation, cross-engine divergence, `docs/status.md` alignment). Invoke with
  "use a subagent to review this diff" before treating multi-file changes as done.

## Path-specific rules (loaded automatically when working in that subtree)

- `lib/ggen_igniter/CLAUDE.md` — moduledoc style, behaviour/subdirectory-impl
  structure, when to add a new module here.
- `lib/mix/tasks/CLAUDE.md` — CLI task naming/structure, doctor-checklist sync rule.
- `native/CLAUDE.md` — Rust NIF doc-comment style, vendoring rule, verification.
- `test/CLAUDE.md` — required per-file test shape, fixture placement, e2e vs unit split.
- `docs/CLAUDE.md` — evidence-sourcing rule for every status claim, Diátaxis structure,
  ADR numbering/status conventions.
- `priv/ggen/CLAUDE.md` — the `--pack` convention's fixed subpath shape and naming.

## Documentation map

- `docs/status.md` — real IMPLEMENTED/PARTIAL_ALIVE/PLANNED status per capability
- `docs/glossary.md` — one sourced definition per domain term (admission, actuation,
  compensation, stale artifact, etc.)
- `docs/architecture/overview.md` — full layer-ownership table
- `docs/architecture/adr/` — accepted architecture decisions
- `docs/reference/cli/{sync,doctor}.md` — full flag/check reference
- `docs/reference/reconciliation/`, `docs/reference/reactor/` — manifest and Reactor pipeline internals
