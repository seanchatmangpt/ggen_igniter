#!/bin/sh
# usage: NOTE="<disclosure>" step.sh <log> <cmd...> -- runs under the ggen_igniter .tool-versions pin
# (elixir 1.19.5-otp-27 / erlang 27.2.4), records timestamps + exit. Copy of
# receipts/v26.9.23/R1-GI-PIN.logs/step.sh with (a) the pin PATH moved to
# 1.19.5-otp-27 / 27.2.4 and (b) an optional NOTE header line (used to disclose the
# lane's one exclusion: the court file itself is relocated for the captured lane gate).
log="$1"; shift
PATH=/Users/sac/.asdf/installs/elixir/1.19.5-otp-27/bin:/Users/sac/.asdf/installs/erlang/27.2.4/bin:$PATH
export PATH
{
  echo "# cwd=$(pwd) head=$(git rev-parse HEAD) started=$(date -u +%FT%TZ)"
  echo "# cmd=$*"
  [ -n "$NOTE" ] && echo "# note=$NOTE"
  "$@"
  rc=$?
  echo "# ended=$(date -u +%FT%TZ) exit=$rc"
} > "$log" 2>&1
tail -1 "$log"
