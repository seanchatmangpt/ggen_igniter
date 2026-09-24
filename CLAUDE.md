# CLAUDE.md

Guidance for agents in this repository.

## What this is

Elixir bootstrap of [ggen](https://github.com/seanchatmangpt/ggen)'s ontology-to-code pipeline: `Ontology.load!/1` → `Engine.run/2` → `Render.render/2` → `Actuate.write_file!/3`, tracked by a reconciliation manifest so upstream renames are mechanically detected. One embedded Rust piece: the `native/ggen_graph_nif` oxigraph engine (default `--engine`; the pure-Elixir `sparql` engine has known `FILTER NOT EXISTS`/`UNION` limits). `docs/status.md` marks IMPLEMENTED / PARTIAL_ALIVE / PLANNED; never claim an unverified status.

## Commands

```
mix deps.get              # needs a Rust toolchain (compiles the NIF)
mix compile
mix test                  # default suite
mix ggen_igniter.doctor   # run first when diagnosing
mix ggen_igniter.sync --pack <name> [--for-each row]
mix e2e                   # manual only, never in mix test; CI = .github/workflows/ci.yml
```

## Non-negotiable invariants

- **Chicago-style tests only.** Real files, subprocesses, engines; state-based assertions. No Mox/:meck/Mimic/Patch/mockall in `test lib native` (grep `(use|import) +(Mox|Mimic|Patch)\b|:meck\.` — must be clean; never grep bare `patch(`/`mock(`: `test/CLAUDE.md`).
- **A summary is not a receipt.** Done = `mix compile --warnings-as-errors` + `mix test` (the `gate` skill) with real output pasted. Re-`Read` after Edit/Write. Show `git diff` of claimed hunks. Label pre-existing vs introduced failures.
- **Never hand-write Ash surfaces** (`use Ash.Resource`/`use Ash.Domain`) — the hook `.claude/hooks/refuse-handwritten-ash.sh` blocks them: hand-writing silently skips config registration, derived accept lists, repo wiring, migration snapshots. Doctrine: `AGENTS.md`.
- **Topology is transport, never ontology.** No `git worktree`, no `~/wt/` (guard refuses). Subagents get the absolute path and first echo `pwd && git remote -v && git rev-parse --abbrev-ref HEAD`; remote mismatch = stop.
- **Parallel agents are lanes in this one checkout** (operator 2026-09-23/24): disjoint file ownership in `docs/jira/<milestone>/_LANES.md`, seams pinned as RESOLUTIONS, per-lane `MIX_BUILD_ROOT=_build-lane<N>`, coordinator owns all git transitions. See `~/.claude/rules/same-checkout-fanout.md`. One autonomous loop per repo at a time.
- **Destructive ops** (`rm -rf`, `git reset --hard`, `git push --force`): enumerate exact paths/refs and confirm (Bash PreToolUse hook enforces). Fix forward; `git revert` is fine. Multi-line commit messages: `git commit -F <file>`, never `-m`.

## Architecture map (details live in docs/)

- Three entry paths — know which you edit: `Mix.Tasks.GgenIgniter.Sync` (frontmatter, `--for-each`, `inject:`), bounded `GgenIgniter.Reconcile.run/1` (no frontmatter parity), opt-in Reactor pipeline (`use_reactor: true`, default false). Layers: `docs/architecture/overview.md`. Ash is dev+test-only, never runtime.
- Manifest: `<manifest-dir>/.ggen_igniter/manifest.json` keyed by (template, out-template); `--on-stale refuse|prune|preserve` (refuse default). See `docs/reference/reconciliation/`.
- Packs: `priv/ggen/<pack>/{ontology.ttl,gates/*.rq,templates/}`; explicit `--ontology/--query/--template` beats `--pack`. Prefer an existing pack over ad-hoc scaffolding.
- sJira origin-authority law (SJ-002): work orders originate only from admitted `sj:CodeWorkAuthority`; prose is observation-only. ADR-012, `docs/jira/v26.9.24/_LANES.md`.

## Pointers

- Path rules (auto-loaded per subtree): `lib/ggen_igniter/`, `lib/mix/tasks/`, `native/`, `test/`, `docs/`, `priv/ggen/` — each has a `CLAUDE.md`.
- Docs: `docs/status.md`, `docs/glossary.md`, `docs/reference/cli/`, ADRs in `docs/architecture/adr/` (its README is generated — edit `priv/ggen/adr-index-pack`, re-sync).
- Hooks/skills: `.claude/settings.json` (formatter, Bash guard, Ash-write guard, Stop-on-red compile), `.claude/skills/{gate,defect-round}/`, `.claude/agents/ggen-reviewer.md` (adversarial diff review).
