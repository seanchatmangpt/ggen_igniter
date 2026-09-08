#!/bin/sh
# Ticket 03/04 harness driver: ONE run of the Tier-1 matrix against
# test/fixtures/book_library. Invoke twice, unchanged, for ticket 04's
# two-run protocol (04-IDEMPOTENCY-VERIFICATION-METHODOLOGY.md:42-59).
#
# Usage (from anywhere):
#   sh test/fixtures/ash_tier_matrix_pack/bin/matrix_run.sh [--dry-run]
#
# What it does, in order:
#   1. cd into the fixture (sibling of this pack) and confirm pwd.
#   2. rm -rf .ash-validation-receipts -- the harness artifact dir. Without
#      this, run 2's receipts are byte-identical, the reactor reports them
#      `:unchanged`, `sh_after:` never fires (reconcile_reactor.ex:2056), and
#      no mix task would be re-executed -- which would make def (c) pass by
#      construction of the harness instead of by the tasks.
#   3. Run the exact ticket-03 invocation with ELIXIR_ERL_OPTIONS="+S 1" so
#      the reactor's Task.async_stream degrades to rank order.
#   4. Print git status/diff --stat inside the fixture and the exit code.
set -u

here=$(cd "$(dirname "$0")" && pwd)
fixture="$here/../../book_library"
cd "$fixture" || exit 1
echo "== matrix_run: pwd=$(pwd)"

if [ -d .ash-validation-receipts ]; then
  if [ -s .ash-validation-receipts/.disposable_dir ]; then
    rm -rf "$(cat .ash-validation-receipts/.disposable_dir)"
  fi
  rm -rf .ash-validation-receipts
fi

ELIXIR_ERL_OPTIONS="+S 1" mix ggen_igniter.sync \
  --pack-dir ../ash_tier_matrix_pack \
  --for-each ash_tier_task_query \
  --allow-sh "$@"
status=$?
echo "== matrix_run: sync exit=$status"
echo "== matrix_run: git status --short (fixture)"
git status --short . 2>/dev/null || true
echo "== matrix_run: git diff --stat (fixture)"
git diff --stat . 2>/dev/null || true
exit "$status"
