#!/bin/sh
# usage: ambient_step.sh <log> <cmd...> -- same log format as step.sh, but under the AMBIENT toolchain (no pin PATH)
log="$1"; shift
{
  echo "# cwd=$(pwd) head=$(git rev-parse HEAD) started=$(date -u +%FT%TZ)"
  echo "# cmd=$*"
  "$@"
  rc=$?
  echo "# ended=$(date -u +%FT%TZ) exit=$rc"
} > "$log" 2>&1
tail -1 "$log"
