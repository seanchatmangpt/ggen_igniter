#!/bin/sh
# usage: run-drive.sh <GGEN_IGNITER_DIR> <log>
S=/private/tmp/claude-501/v23-scratch/R1a-R1-GI-FMT
cd $S/xaas || exit 97
exec env -i HOME=/Users/sac USER=sac LOGNAME=sac LANG=en_US.UTF-8 TERM=dumb \
  PATH=/opt/homebrew/bin:/Users/sac/.erlmcp/otp-28.3.1/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  MIX_TEST_PARTITION=r1gifmt TMPDIR=/private/tmp/claude-501/v23-scratch/R1a-R1-GI-FMT/tmp GGEN_IGNITER_DIR="$1" \
  sh -c 'echo "GGEN_IGNITER_DIR=$GGEN_IGNITER_DIR head=$(git -C "$GGEN_IGNITER_DIR" rev-parse HEAD)"; echo "xaas head=$(git rev-parse HEAD) TMPDIR=$TMPDIR"; env | grep -cE "^(ANTHROPIC|CLAUDE|OPENAI|ZAI|Z_AI|GLM|ZCODE)" ; elixir --version | tail -1; mix test test/xaas/ultracode/semantic_drive_test.exs; echo "EXIT=$?"' > "$2" 2>&1
