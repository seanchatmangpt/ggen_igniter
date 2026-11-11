#!/usr/bin/env bash
# PreToolUse guard (Edit|Write|Bash): block hardcoded credentials, private
# keys, and curl|sh pipe-to-shell patterns.
#
# ## Input protocol (follows refuse-handwritten-ash.sh doctrine)
#
# STDIN is the primary source: a PreToolUse hook receives the tool call as
# JSON (`{"tool_name":..., "tool_input":{...}}`). The body is extracted by
# RECURSIVELY WALKING `tool_input` and joining every string leaf except the
# path keys and `old_string`/`old_str` (excluding the pre-edit side is
# deliberate: an Edit that DELETES a secret must not be refused). Hardcoded
# key lookup fails on MultiEdit-shaped `edits[].new_string` payloads — the
# walk does not. Stdin primary, `$CLAUDE_TOOL_INPUT` env fallback; an
# unparseable payload falls back to a raw scan rather than failing open.
#
# Contract: exit 2 blocks the tool call and shows stderr to the agent.
# Exit 0 allows it.

set -uo pipefail

payload=""
if [ ! -t 0 ]; then
  payload="$(cat 2>/dev/null || true)"
fi

input=""

if [ -n "$payload" ]; then
  parsed="$(
    printf '%s' "$payload" | python3 -c '
import json, sys

PATH_KEYS = ("file_path", "path", "notebook_path")
SKIP_KEYS = ("old_string", "old_str")

try:
    doc = json.load(sys.stdin)
except Exception:
    sys.exit(1)  # signal unparseable; caller falls back to raw scan

tool_input = doc.get("tool_input")
if not isinstance(tool_input, dict):
    tool_input = {}

bodies = []

def walk(node, key):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, k)
    elif isinstance(node, list):
        for v in node:
            walk(v, key)
    elif isinstance(node, str):
        if key in PATH_KEYS:
            return
        if key in SKIP_KEYS:
            return
        bodies.append(node)

walk(tool_input, None)

# \x1f survives bash command substitution; NUL does not.
sys.stdout.write("\x1f".join(bodies))
' 2>/dev/null
  )"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    input="$parsed"
  fi
fi

# Unparseable payload or no recognised body -> raw scan rather than fail open.
[ -n "$input" ] || input="$payload"

# Env fallback for clients that expose the call through the environment.
[ -n "$input" ] || input="${CLAUDE_TOOL_INPUT:-}"

[ -n "$input" ] || exit 0

# --- detectors (run against the joined body) -------------------------------

violation=""

# Hardcoded credential assignments: password/secret/token/api_key/api-key style
# keys bound to a non-empty literal. Deliberately narrow: requires the secret
# name, a :=>- binding, and a quoted or long-ish literal value, so ordinary
# code (e.g. `token = opts[:token]`, `password: password`) is not touched.
if printf '%s' "$input" | grep -qiE \
  '(password|passwd|secret|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|client[_-]?secret)["'"'"']?[[:space:]]*[:==>]+[[:space:]]*["'"'"'][^"'"'"']{8,}["'"'"']'; then
  violation="hardcoded credential assignment"
fi

# PEM private keys, any header variant.
if printf '%s' "$input" | grep -qE \
  -e '-----BEGIN (RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY( BLOCK)?-----'; then
  violation="embedded private key"
fi

# curl/wget piped straight into a shell.
if printf '%s' "$input" | grep -qE \
  -e '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh'; then
  violation="curl/wget piped into a shell"
fi

[ -n "$violation" ] || exit 0

cat >&2 <<EOF
BLOCKED: $violation detected in the tool input.

Hardcoded credentials, private keys, and pipe-to-shell installers are banned
content. The admitted paths are:

  - Credentials: read from the environment or a config surface the user
    controls; never a literal in source, a test, or a command string.
  - Keys: reference the key file by path; never inline the PEM body.
  - Remote scripts: download, inspect, then execute the checked-out file
    as two steps — never \`curl ... | sh\`.

If this is a false positive (e.g. a test fixture with an obviously fake
placeholder credential), rephrase so the literal cannot match a real secret
shape (e.g. "TESTONLY-NOT-A-SECRET") or route it through a variable.
EOF
exit 2
