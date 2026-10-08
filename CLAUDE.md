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
- **Parallel agents are lanes in this one checkout** (operator 2026-09-23/24): disjoint file ownership in `docs/jira/<milestone>/_LANES.md`, seams pinned as RESOLUTIONS, per-lane `MIX_BUILD_ROOT=_build-lane<N>`, coordinator owns all git transitions. See `~/.zcode/rules/same-checkout-fanout.md`. One autonomous loop per repo at a time.
- **Destructive ops** (`rm -rf`, `git reset --hard`, `git push --force`): enumerate exact paths/refs and confirm (Bash PreToolUse hook enforces). Fix forward; `git revert` is fine. Multi-line commit messages: `git commit -F <file>`, never `-m`.

## Architecture map (details live in docs/)

- Three entry paths — know which you edit: `Mix.Tasks.GgenIgniter.Sync` (frontmatter, `--for-each`, `inject:`), bounded `GgenIgniter.Reconcile.run/1` (no frontmatter parity), opt-in Reactor pipeline (`use_reactor: true`, default false). Layers: `docs/architecture/overview.md`. Ash is dev+test-only, never runtime.
- Manifest: `<manifest-dir>/.ggen_igniter/manifest.json` keyed by (template, out-template); `--on-stale refuse|prune|preserve` (refuse default). See `docs/reference/reconciliation/`.
- Packs: `priv/ggen/<pack>/{ontology.ttl,gates/*.rq,templates/}`; explicit `--ontology/--query/--template` beats `--pack`. Prefer an existing pack over ad-hoc scaffolding.
- sJira origin-authority law (SJ-002): work orders originate only from admitted `sj:CodeWorkAuthority`; prose is observation-only. ADR-012, `docs/archive/jira/v26.9.24/_LANES.md`.

## Epoch boundary (CalVer manufacturing law)

v26.10.1 is an epoch boundary: `Admit(f) ⟺ FreshEpoch(f)` for every implementation-plane file. Semantic reuse is not implementation carryover — `TTL_old → ggen_igniter → A_new` is the point; `A_old + Δ → A_new` is the violation.

Three commands carry the law (mechanics pinned as Contract v1 in `docs/archive/jira/v26.9.27/_LANES.md`; modules `GgenIgniter.EpochWatermark`, `GgenIgniter.EpochFreshness`, `GgenIgniter.SemanticJira.EpochPlan`):

```
mix ggen_igniter.epoch.watermark   # record pre-epoch implementation identity: path + blob sha at the boundary — identity-based, not blame-based
mix ggen_igniter.epoch.check       # the witness: proves the candidate tree; exit 0 = all ALIVE, 1 = refusal/unknown, 2 = invocation
mix ggen_igniter.epoch.explain     # the microscope: read-only per-file provenance; always exit 0 on a judged file
```

Detector law: **receipts admit; similarity falsifies; blame informs; none substitutes for exact artifact provenance.** Attribution sources: `.ggen_igniter/manifest.json` (recorded output hashes), `.ggen_igniter/receipts/*.jsonl` (counts only when `finished_at` ≥ watermark and standing is alive), and `HANDWRITTEN.md` rows dated ≥ watermark. A candidate's identity is the pure-Elixir git blob id, `:crypto.hash(:sha, "blob " <> size <> <<0>> <> content)`; the watermark persists `.ggen_igniter/epoch/<epoch>/watermark.json` (`head_sha`, `tree_sha`, path-sorted `files` with blob shas).

Closed verdict set — exactly one atom per implementation file, alive iff the name starts `ALIVE_`; the normative precedence chain is Contract v1:

| verdict | triggers when |
|---|---|
| `ALIVE_GENERATED` | a post-watermark alive receipt lists the file and its recorded output hash equals the current blob (similarity is recorded, never refuses) |
| `ALIVE_FRESH_RESIDUE` | a `HANDWRITTEN.md` row dated ≥ watermark covers the file and similarity against every pre-epoch file is below threshold |
| `REFUSED_GENERATED_ARTIFACT_MUTATED` | a post-watermark alive receipt lists the file but its recorded output hash ≠ current blob |
| `REFUSED_UNEXPLAINED_SIMILARITY` | no admission covers the file and similarity ≥ threshold (default 0.9) against a pre-epoch implementation |
| `REFUSED_LEGACY_EDIT` | the exact path appears in the watermark (implementation plane existed pre-epoch) with no attribution |
| `REFUSED_COPY_READD` | the current blob sha exactly equals some pre-epoch path's blob sha |
| `REFUSED_PRE_EPOCH_RECEIPT` | the only receipts touching the file predate the watermark or do not stand alive |
| `REFUSED_NO_ATTRIBUTION` | no receipt, residue row, legacy match, or similarity trigger — an unattributed implementation-plane byte |
| `UNKNOWN_PROVENANCE` | the file could not be judged at all — e.g. a glob-matching path that is not readable as a file; counted as refused. Unparseable receipts never take this slot: they simply never attribute, so the file falls through to `REFUSED_PRE_EPOCH_RECEIPT` or `REFUSED_NO_ATTRIBUTION` |

Two-layer binding. Admission refuses known-illegal plans before any byte is written: `semantic_jira.admit_candidates --epoch-manifest <watermark.json>` applies `EpochPlan.check/2` to order lines carrying `"epoch"` — `REFUSED_EPOCH_LEGACY_EDIT`, `REFUSED_EPOCH_UNATTRIBUTED_IMPLEMENTATION`, `REFUSED_EPOCH_PLAN_REUSES_PRE_WATERMARK_ARTIFACT`, `REFUSED_EPOCH_WATERMARK_UNAVAILABLE`; a missing/unreadable manifest with epoch lines present refuses every epoch line (fail closed), and lines without `"epoch"` pass byte-identical. `mix ggen_igniter.epoch.check` then proves the resulting bytes. Promotion requires both, because **admission ≠ proof, proof ≠ prevention**: a plan gate cannot see what a generator actually emits, and a tree check cannot un-write an illegal byte it refuses.

Exempt planes — the law binds implementations, not knowledge or evidence:

| plane | epoch-bound? |
|---|---|
| `lib/**/*.ex` | yes — the first court |
| config, migrations | named as future courts, not yet bound |
| knowledge plane: `.ttl`, `.rq`, `.eex`, `pack.toml`, docs, markdown | no |
| tests, falsifiers, evidence: `test/**`, fixtures, receipts | no |

Tests predate the new implementation on purpose: `Test_t(A_{t+1})` is an independent historical falsifier — the implementation phases while the court survives.

Honest residues:

- Similarity is line/AST Jaccard, not a compiler — a sufficiently creative rewrite defeats it. That is why receipts, not similarity, are the admission path and similarity only ever refuses.
- The first court's glob is `lib/**/*.ex`; nothing outside it is judged yet.
- Unparseable receipt timestamps never attribute (fail closed).

## Pointers

- Path rules (auto-loaded per subtree): `lib/ggen_igniter/`, `lib/mix/tasks/`, `native/`, `test/`, `docs/`, `priv/ggen/` — each has a `CLAUDE.md`.
- Docs: `docs/status.md`, `docs/glossary.md`, `docs/reference/cli/`, ADRs in `docs/architecture/adr/` (its README is generated — edit `priv/ggen/adr-index-pack`, re-sync).
- Hooks/skills: `.claude/settings.json` (formatter, Bash guard, Ash-write guard, Stop-on-red compile), `.claude/skills/{gate,defect-round}/`, `.claude/agents/ggen-reviewer.md` (adversarial diff review).
