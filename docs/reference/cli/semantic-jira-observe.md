# mix semantic_jira.observe --fleet

Reference for the fleet observation edge (work order GGEN_IGNITER-26922-15). It reads a
registry of git repositories and writes SHA-bound PROV-O Turtle for the rule-derivation
step (GGEN_IGNITER-26922-16) and the capability conservation court (GGEN_IGNITER-26922-18).

Status: IMPLEMENTED at the commit that adds this file. Source:
`lib/mix/tasks/semantic_jira.observe.ex`, `lib/ggen_igniter/semantic_jira/fleet_observation.ex`.
Proof: `test/ggen_igniter_semantic_jira_fleet_observe_test.exs`.

## Usage

```bash
mix semantic_jira.observe --fleet /Users/sac/wt/v26922/fleet.ttl --out /tmp/obs.ttl
```

| flag | required | meaning |
|---|---|---|
| `--fleet PATH` | yes | Registry graph: `sj:ObservedRepository` nodes with `sj:repositoryPath` |
| `--out PATH` | yes | Turtle output path (parent directories are created) |

Without `--fleet` the task raises `REFUSED:SEMANTIC_JIRA_OBSERVE_MODE_UNSUPPORTED`. The
older `--finding` observation edge (commit `92cd993`) is not on this line.

## What is observed

One `sj:RepositoryObservation` (a `prov:Activity`) per registry repository, each
`dcterms:isPartOf` one `sj:FleetObservation`. Every generated `prov:Entity` carries exactly
one `sj:observedSha`:

- `sj:RefObservation`: `refs/heads/*` and `refs/remotes/*` with `sj:aheadCount`,
  `sj:behindCount`, `sj:unpushed`, `sj:fastForwardable`, `sj:upstreamGone`.
- `sj:RemoteRefDelta`: `git ls-remote --symref` per remote against local tracking refs
  (`moved`, `remote_only`, `tracking_only`).
- `sj:WorktreeObservation`: every `git worktree list` entry with `sj:dirty` and
  `sj:dirtyEntryCount` from `git --no-optional-locks status --porcelain`.
- `sj:StashObservation`: every `git stash list` entry.
- `sj:PullRequestObservation`: open PRs from `gh pr list` with `sj:checksConclusion`.
- `sj:DefaultBranchCiObservation`: `gh api .../commits/SHA/check-runs` at the SHA the
  remote reports for `HEAD`.
- `sj:ProbeOutcome`: a probe that could not observe (`UNSUPPORTED:*`, `BLOCKED:*`), bound
  to the repository HEAD.

## Determinism and bounds

Two runs over unchanged repositories are byte-identical except for the single
`prov:endedAtTime` line. Tags are not observed; CI reads GitHub check runs only; at most
200 open PRs and 100 check runs per repository. All probes are read-only (no fetch,
`GIT_OPTIONAL_LOCKS=0`, gh GET only).

## See Also

- `priv/ggen/semantic-jira-pack/ontology.ttl` (`sj:capability-fleet-observe`,
  `sj:ledger-unsupported-002`)
- `priv/ggen/semantic-jira-pack/runtime-templates/fleet_observation.ttl.eex`
- `priv/ggen/semantic-jira-pack/runtime-queries/fleet_repositories.rq`
