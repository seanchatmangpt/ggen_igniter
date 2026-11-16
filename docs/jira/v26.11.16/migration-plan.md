# ggen_igniter migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- Path: /Users/sac/ggen_igniter
- Remote: https://github.com/seanchatmangpt/ggen_igniter.git (origin, 101 remote branches)
- Branch: main@1fa6dc7 — last commit 2026-11-13 — 708 commits — 1301 MB (.git 138 MB)
- Languages/build: Elixir (mix.exs, .tool-versions Elixir 1.20.4/OTP 29) with Rust NIF
  (native/ggen_graph_nif → target/), Dockerfile.e2e, docker-compose.e2e.yml
- Nested repos: none

## Observed state
- Dirty 4: docs/jira/v26.11.10/{00-OVERVIEW,05,06,07-REVIEW-LENS-*}.md
- Untracked 9: docs/jira/v26.11.10/11..17 and 20 review-lens docs, docs/jira/v26.11.12/
- ahead 0 / behind 0 origin/main; stash 193 (!) ; 69 local branches, 55 without upstream
  (archive/wip/..., closure/gi-*, errc/*, errc-igniter-*, ...)
- Build dirs: target/ 355 MB, _build-coord/ 354 MB, doc/ 18 MB, wasm-artifacts/ 19 MB,
  .oclnr-cache 520 KB, tmp/ tmp_out/ tmp-bp-validation/
- Stray files at root: erl_crash.dump (5.7 MB), ggen_igniter-26.11.10.tar (3.9 MB hex
  package), noagent..ttl.H0pnk4 / .qMF3Mj temp files, neg_* fixture dirs

## What it is
Ontology-driven semantic compilation engine for Elixir (RDF + SPARQL + EEx + Igniter AST
codemods) producing Ash/Spark/OTP code with reconciliation memory and receipts. Published
on hex.pm; README reports 1763+ tests green at v26.11.10.

## Classification
ACTIVE (census agrees; most recently touched repo in this lane).

## Migration risk
- 193 stashes — unknown content, cannot be inspected without `git stash` (banned here)
- 55 local-only branches
- Uncommitted v26.11.10/v26.11.12 jira docs
- No .env observed; config/ is standard mix config
Rate: HIGH

## Recommended action
COMMIT-PUSH
1. `cd /Users/sac/ggen_igniter && git add docs/jira &&
   git commit -m "docs(jira): v26.11.10 review lenses + v26.11.12" && git push origin main`
2. DECISION: the 193 stashes — Sean must triage personally (`git stash list` then
   `git stash show -p stash@{N}`); either drop or convert keepers to branches
   (`git stash branch keep/<name> stash@{N}`). Do not migrate stashes implicitly.
3. `git bundle create <archive>/ggen_igniter.bundle --all` — this also captures stash refs
   only if converted to branches first; bundle is the safety net for 55 local branches
4. Push branches worth keeping: `git push -u origin <branch>`; the archive/wip/* ones are
   already snapshot commits and can go to the bundle only
5. Cleanup before any copy: `rm -rf target _build-coord doc wasm-artifacts tmp tmp_out
   tmp-bp-validation .oclnr-cache erl_crash.dump ggen_igniter-26.11.10.tar noagent..ttl.*`
   (~750 MB reclaimed); DECISION on neg_* fixture dirs (tracked or scratch?)
6. On the new machine clone fresh; needs Rust toolchain for the NIF

## First commands on the new machine
`mix deps.get && mix compile && mix ggen_igniter.doctor && mix test` (stated, not run).

## See Also
- ../v26.11.13/
- /Users/sac/docs/jira/v26.11.16/README.md
