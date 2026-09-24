#!/bin/sh
# R2-GI-BLOOM gate (ggen_igniter). usage: r2-gi-bloom.sh [subject-worktree]
# The bootstrap fixture's deleted-tree corruption must stay unreadable even when a changed-path (Bloom) commit-graph
# exists (CI run 35933570910, git 2.55.0: :836 got "observed"). The regression test writes that graph explicitly;
# witnessed: without the fixture pin '27 tests, 1 failure' (covered_commit_status "observed"), with it 0 failures.
set -eu
SUBJ=$(cd "${1:-$PWD}" && pwd); cd "$SUBJ"
PATH=/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin:/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH
export PATH
F=test/ggen_igniter_semantic_jira_bootstrap_test.exs
echo "# subject=$SUBJ head=$(git rev-parse HEAD) git=$(git --version)"
elixir --version | tail -1
grep -q "stays unreadable when a changed-path commit-graph exists" "$F"
grep -q "core.commitGraph" "$F"
mix format --check-formatted
mix credo "$F"
mix test "$F"
echo "BLOOM_GATE OK"
