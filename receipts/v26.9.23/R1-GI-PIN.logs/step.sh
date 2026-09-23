#!/bin/sh
# usage: step.sh <log> <cmd...>  -- runs under the ggen_igniter .tool-versions pin, records timestamps + exit
log="$1"; shift
PATH=/Users/sac/.asdf/installs/elixir/1.18.4-otp-27/bin:/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH
export PATH
{
  echo "# cwd=$(pwd) head=$(git rev-parse HEAD) started=$(date -u +%FT%TZ)"
  echo "# cmd=$*"
  "$@"
  rc=$?
  echo "# ended=$(date -u +%FT%TZ) exit=$rc"
} > "$log" 2>&1
tail -1 "$log"
