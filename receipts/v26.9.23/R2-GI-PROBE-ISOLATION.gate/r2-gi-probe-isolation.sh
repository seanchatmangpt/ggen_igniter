#!/bin/sh
# R2-GI-PROBE-ISOLATION gate (ggen_igniter). usage: r2-gi-probe-isolation.sh [subject-worktree]
# The exact-stdout dev-env subprocess tests must not depend on test order: BaseMixTaskEndUserTest's probe
# (lib/tmp_ex4pm_probe_N) must leave the shared checkout's dev build as it found it. Seeds 0 and 648358 (CI run
# 35925710605) failed without the fix (plan --json: Jason 'unexpected byte ... 0x47 ("G")'; plan --help: leading
# 'Generated ggen_igniter app'); 10 tests, 0 failures at seeds 0/648358/1/2 with it.
set -eu
SUBJ=$(cd "${1:-$PWD}" && pwd); cd "$SUBJ"
PATH=/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin:/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH
export PATH
echo "# subject=$SUBJ head=$(git rev-parse HEAD)"
elixir --version | tail -1
mix format --check-formatted
mix credo test/ggen_igniter_base_mix_task_end_user_test.exs
mix compile >/dev/null
for s in 0 648358 1 2; do
  mix test test/ggen_igniter_base_mix_task_end_user_test.exs test/ggen_igniter_plan_task_test.exs \
    test/ggen_igniter_cli_tasks_quirks_test.exs --seed "$s"
done
test -z "$(git status --porcelain -- lib)"
echo "PROBE_ISOLATION_GATE OK"
