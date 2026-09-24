# ggen_igniter: land or delete remote branch `feat/calver-ticket-day-pack`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `feat/calver-ticket-day-pack` — not merged into `main`, no open PR
- Evidence: `git branch -r --no-merged origin/main` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/ggen_igniter --head feat/calver-ticket-day-pack`) or delete (`git push origin --delete feat/calver-ticket-day-pack`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/main` no longer lists `feat/calver-ticket-day-pack`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | feat/calver-ticket-day-pack | decision pending
