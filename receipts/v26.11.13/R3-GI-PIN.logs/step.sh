#!/bin/sh
# usage: NOTE="<disclosure>" step.sh <log> <cmd...> -- runs under the ggen_igniter .tool-versions pin
# (elixir 1.20.4-otp-29 / erlang 29.1.2), records timestamps + exit. Derived from
# receipts/v26.10.2/R2-GI-PIN.logs/step.sh with the pin PATH moved to the new pin.
log="$1"; shift
PATH=/Users/sac/.asdf/installs/elixir/1.20.4-otp-29/bin:/Users/sac/.asdf/installs/erlang/29.1.2/bin:$PATH
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
