#!/usr/bin/env bash
# Stop hook: fail-closed gate receipt requirement.
#
# A session may not stop (report "done") unless a real gate receipt exists:
# `.claude/receipts/latest.json`, written by the `gate` skill / gate loop.
#
# Fail-closed contract — the session is BLOCKED unless ALL of:
#   1. .claude/receipts/latest.json exists
#   2. it parses as JSON shaped {"status":"green","commands":[...]}
#      (status must be exactly "green"; commands must be a non-empty array)
#   3. its mtime is NEWER than the newest tracked source file's mtime
#      (a receipt older than the code it would certify certifies nothing)
#
# Exit 2 blocks the stop and shows stderr to the agent. Exit 0 allows it.

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
[ -f mix.exs ] || exit 0   # not the Elixir project root -> not our gate

receipt=".claude/receipts/latest.json"

fail() {
  echo "BLOCKED: $*" >&2
  echo "ACTION: run the 'gate' skill now (mix compile --warnings-as-errors + mix test), then write the receipts block to .claude/receipts/latest.json as {\"status\":\"green\",\"commands\":[{\"command\":...,\"exit\":...}]}. A receipt older than your newest tracked source change is not a receipt — re-run the gate after your last edit." >&2
  exit 2
}

# 1. existence
[ -f "$receipt" ] || fail "no gate receipt at $receipt — 'done' was claimed without running the gate."

# 2. shape: status=="green" and commands non-empty array
python3 - "$receipt" <<'PY' || fail "receipt at $receipt does not parse as {\"status\":\"green\",\"commands\":[...]} — re-run the gate."
import json, sys
try:
    doc = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if not isinstance(doc, dict) or doc.get("status") != "green":
    sys.exit(1)
cmds = doc.get("commands")
if not isinstance(cmds, list) or len(cmds) == 0:
    sys.exit(1)
sys.exit(0)
PY

# 3. freshness: receipt must be newer than the newest tracked source file
newest_src=$(git ls-files -- 'lib/*.ex' 'lib/*.exs' 'test/*.exs' 'native/*' 'priv/*' 'mix.exs' 'config/*' '.claude/**' 2>/dev/null \
  | while IFS= read -r f; do [ -f "$f" ] && stat -f '%m' "$f"; done | sort -rn | head -1)
[ -n "$newest_src" ] || newest_src=0
receipt_mtime=$(stat -f '%m' "$receipt" 2>/dev/null || echo 0)

if [ "$receipt_mtime" -le "$newest_src" ]; then
  newest_file=$(git ls-files -- 'lib/*.ex' 'lib/*.exs' 'test/*.exs' 'native/*' 'priv/*' 'mix.exs' 'config/*' '.claude/**' 2>/dev/null \
    | while IFS= read -r f; do [ -f "$f" ] && echo "$(stat -f '%m' "$f") $f"; done | sort -rn | head -1 | cut -d' ' -f2-)
  fail "gate receipt ($receipt, mtime $receipt_mtime) is OLDER than newest tracked source change ($newest_file, mtime $newest_src). The receipt does not certify this code."
fi

exit 0
