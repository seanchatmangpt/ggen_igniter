# ggen_igniter: land or delete remote branch `fix/v26.9.15-ephemeral-attestation-exact-head-replay`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `fix/v26.9.15-ephemeral-attestation-exact-head-replay` — not merged into `main`, no open PR
- Evidence: `git branch -r --no-merged origin/main` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/ggen_igniter --head fix/v26.9.15-ephemeral-attestation-exact-head-replay`) or delete (`git push origin --delete fix/v26.9.15-ephemeral-attestation-exact-head-replay`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/main` no longer lists `fix/v26.9.15-ephemeral-attestation-exact-head-replay`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | fix/v26.9.15-ephemeral-attestation-exact-head-replay | decision pending
