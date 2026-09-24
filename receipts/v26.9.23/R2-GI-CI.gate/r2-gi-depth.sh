#!/bin/sh
# R2-GI-DEPTH gate: reproduce the CI "mix test" git-ground-truth step in a checkout
# shaped exactly as .github/workflows/ci.yml declares (actions/checkout fetch-depth,
# default 1), under ggen_igniter's .tool-versions pin, with origin = the GitHub URL
# (GitGroundTruth derives its jurisdiction from remote.origin.url).
# usage: r2-gi-depth.sh [subject-worktree]   (default: $PWD). Exit 0 iff 0 failures.
set -eu
SUBJ=$(cd "${1:-$PWD}" && pwd)
PATH=/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin:/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH
export PATH
HEAD_SHA=$(git -C "$SUBJ" rev-parse HEAD)
BRANCH=$(git -C "$SUBJ" rev-parse --abbrev-ref HEAD)
DEPTH=$(cd "$SUBJ" && ruby -ryaml -e 's=YAML.load_file(".github/workflows/ci.yml")["jobs"]["test"]["steps"].find{|x| x["uses"].to_s.start_with?("actions/checkout@")}; puts((s["with"]||{}).fetch("fetch-depth",1))')
C=/private/tmp/claude-501/v23-scratch/R2-GI-DEPTH-cishape-$(printf %s "$HEAD_SHA" | cut -c1-7)
echo "# subject=$SUBJ head=$HEAD_SHA branch=$BRANCH ci.yml fetch-depth=$DEPTH clone=$C"
rm -rf "$C"
if [ "$DEPTH" = 0 ]; then git clone -q --branch "$BRANCH" "file://$SUBJ" "$C"
else git clone -q --depth "$DEPTH" --branch "$BRANCH" "file://$SUBJ" "$C"; fi
test "$(git -C "$C" rev-parse HEAD)" = "$HEAD_SHA"
git -C "$C" remote set-url origin https://github.com/seanchatmangpt/ggen_igniter.git
echo "# shallow=$(git -C "$C" rev-parse --is-shallow-repository)"
# stage 1 (seconds): the exact git probes GitGroundTruth runs for the canonical baseSha
if git -C "$C" cat-file -e 'd84da1419a6945c6a8a64b8f6cdca9d0b2c9e0f3^{commit}' 2>/dev/null \
   && git -C "$C" merge-base --is-ancestor d84da1419a6945c6a8a64b8f6cdca9d0b2c9e0f3 HEAD; then
  echo "# probe: d84da14 reachable from HEAD"
else
  echo "# probe: d84da14 NOT reachable from HEAD (the CI checkout will refuse the honest graph)"; exit 1
fi
# stage 2: the real CI tests in that checkout
cd "$C"
elixir --version | tail -1
mix deps.get >/dev/null
mix compile >/dev/null
MIX_ENV=test mix compile >/dev/null
mix test test/ggen_igniter_semantic_jira_pack_test.exs test/ggen_igniter_semantic_jira_git_ground_truth_test.exs \
  --only 'describe:opt-in git ground truth for baseSha (residual_base_sha_wrong_commit closure)' \
  --only 'module:GgenIgniter.SemanticJiraGitGroundTruthTest'
