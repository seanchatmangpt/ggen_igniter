#!/bin/sh
# R2-GI-TIMEOUT gate: jobs.test.timeout-minutes in .github/workflows/ci.yml must be >= 1.5x the
# longest COMPLETE cold CI job of this workflow at the release candidate. Defaults: runs
# 35925710605 (3ed6a7a+DEPTH+TIMEOUT, 54.6 min) and 35933570910 (+CACHESEED+PROBE-ISOLATION, 56.5 min),
# both on refs with no prior cache.
# usage: r2-gi-timeout.sh [subject-worktree] [run_id ...]
set -eu
SUBJ=$(cd "${1:-$PWD}" && pwd); [ $# -gt 0 ] && shift
RUNS=${*:-"35925710605 35933570910"}
T=$(cd "$SUBJ" && ruby -ryaml -e 'puts YAML.load_file(".github/workflows/ci.yml")["jobs"]["test"]["timeout-minutes"].to_i')
MAXS=0
for R in $RUNS; do
  J=$(gh run view "$R" -R seanchatmangpt/ggen_igniter --json jobs -q '.jobs[0] | "\(.startedAt) \(.completedAt)"')
  S=$(ruby -rtime -e 'puts (Time.parse(ARGV[1])-Time.parse(ARGV[0])).to_i' $J)
  echo "run $R job [$J] ${S}s"
  [ "$S" -gt "$MAXS" ] && MAXS=$S
done
NEED=$(ruby -e 'puts (1.5*ARGV[0].to_f/60.0).ceil' "$MAXS")
echo "timeout-minutes=$T longest_job_s=$MAXS required_min(1.5x)=$NEED"
[ "$T" -ge "$NEED" ]
