#!/bin/sh
# Fixed `sh_after:` runner for test/fixtures/ash_tier_matrix_pack.
#
# Why a fixed runner and not `sh_after: "mix <%= mix_task %> ..."`:
# GgenIgniter.Reactors.ReconcileReactor.render_target/3 passes
# `frontmatter.sh_after` to GgenIgniter.ShellHook.run/2 as a RAW string --
# only the body and the `to:` path are EEx-rendered per row. So the per-row
# command is rendered INTO the receipt script body instead, and this runner
# (the one fixed sh_after: line) executes every not-yet-run receipt in
# zero-padded rank order, under a mkdir lock, marking each `.done`.
#
# Runs with cwd = the reactor's project_dir (= --manifest-dir or the
# invoking cwd, i.e. test/fixtures/book_library), so `mix ash.*` below
# resolves the fixture's own mix.exs / config.exs.
#
# Marker semantics (ticket 04 two-run protocol, 04-IDEMPOTENCY-VERIFICATION-
# METHODOLOGY.md:42-59): `.done`/`.failed` markers serialize receipts WITHIN
# one `mix ggen_igniter.sync` run -- the reactor fires this hook once per
# `:written` receipt and every fire must not re-run earlier rows. They are
# NOT a cross-run cache. `.ash-validation-receipts/` is a harness artifact
# (gitignored in the fixture); bin/matrix_run.sh removes it before every sync
# so run 2 renders every receipt `:written` again, the hook fires again, and
# every `mix ash.*` task really re-executes -- def (c) is exercised by the
# task, not satisfied by this runner skipping it.
#
# Destructive receipts (`# destructive: true`, ticket 02 rows 22-26) run in a
# disposable copy of the fixture tree (02-ASH-TASK-VALIDATION-MATRIX.md:112-
# 114): sources are copied, deps/ and _build/ are symlinked, and the
# `{:ggen_igniter, path: "../../.."}` dep is rewritten to the absolute repo
# root so the copy resolves it from anywhere. The Postgres database is shared
# (config names it), so rows 23/25 do destroy book_library_dev.
set -u

dir=".ash-validation-receipts"
lock="$dir/.runner.lock"
disposable_marker="$dir/.disposable_dir"

mkdir -p "$dir"
i=0
while ! mkdir "$lock" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 300 ]; then
    echo "run_pending_receipts: lock $lock held for >30s, giving up" >&2
    exit 1
  fi
  sleep 0.1
done
trap 'rmdir "$lock" 2>/dev/null' EXIT

fixture_root=$(pwd)

disposable_copy() {
  if [ -s "$disposable_marker" ] && [ -d "$(cat "$disposable_marker")" ]; then
    cat "$disposable_marker"
    return 0
  fi
  copy=$(mktemp -d "${TMPDIR:-/tmp}/book_library_disposable.XXXXXX") || return 1
  # Copy the fixture tree minus build/dep dirs and harness artifacts.
  ( cd "$fixture_root" && tar --exclude=./deps --exclude=./_build \
      --exclude=./.ash-validation-receipts --exclude=./.ggen_igniter \
      --exclude=./.git -cf - . ) | ( cd "$copy" && tar -xf - ) || return 1
  ln -s "$fixture_root/deps" "$copy/deps"
  ln -s "$fixture_root/_build" "$copy/_build"
  repo_root=$(cd "$fixture_root/../../.." && pwd)
  # Only this one literal is rewritten; every other line of mix.exs is byte-identical.
  sed "s|path: \"../../..\"|path: \"$repo_root\"|" "$fixture_root/mix.exs" > "$copy/mix.exs"
  echo "$copy" > "$disposable_marker"
  echo "== run_pending_receipts: disposable fixture copy at $copy" >&2
  echo "$copy"
}

for f in "$dir"/[0-9][0-9]-*.sh; do
  [ -e "$f" ] || continue
  [ -e "$f.done" ] && continue
  echo "== run_pending_receipts: $f"
  if grep -q '^# destructive: *true' "$f"; then
    run_in=$(disposable_copy) || { echo "1" > "$f.failed"; echo "== run_pending_receipts: could not create disposable copy" >&2; exit 1; }
    echo "== run_pending_receipts: destructive row, cwd=$run_in"
    ( cd "$run_in" && sh "$fixture_root/$f" ) > "$f.log" 2>&1
    status=$?
  else
    sh "$f" > "$f.log" 2>&1
    status=$?
  fi
  cat "$f.log"
  if [ "$status" -ne 0 ]; then
    echo "$status" > "$f.failed"
    echo "== run_pending_receipts: $f FAILED (exit $status)" >&2
    exit "$status"
  fi
  echo "$status" > "$f.done"
done
