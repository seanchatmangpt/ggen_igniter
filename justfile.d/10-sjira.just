# Hands-free Semantic Jira autonomic loop.
# Chain: observe → admit_candidates → frontier → execute → receipt
# Fail-closed on REFUSED. Env prerequisites: scripts/sjira/autonomic_loop.sh header.
#
# Just 1.56: pass mode as a positional recipe arg (dry-run|live), not `mode=…`
# as a single positional string (that becomes mode='mode=dry-run' and REFUSES).

# Default entry: dry-run (no execute/receipt actuation).
#   just sjira-loop
#   just sjira-loop dry-run
#   just sjira-loop live
sjira-loop mode="dry-run":
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{justfile_directory()}}"
    if [ ! -f "$root/mix.exs" ] && [ -f "$root/../mix.exs" ]; then
      root="$(cd "$root/.." && pwd)"
    fi
    cd "$root"
    case "{{mode}}" in
      dry-run|live) ;;
      *) echo "REFUSED:USAGE mode must be dry-run|live (got '{{mode}}')" >&2; exit 2 ;;
    esac
    export SJIRA_MODE="{{mode}}"
    export GGEN_IGNITER_DIR="${GGEN_IGNITER_DIR:-$root}"
    exec bash scripts/sjira/autonomic_loop.sh "--{{mode}}"

# Explicit dry-run alias (observe → admit → frontier only).
sjira-loop-dry:
    just sjira-loop dry-run

# Live actuation alias (full chain including execute + receipt).
sjira-loop-live:
    just sjira-loop live

# Non-destructive Mix dry-run + optional ggen/hands-free frontier cross-check.
# Set SJIRA_HANDS_FREE_CROSSCHECK=1 (and GGEN_BIN or SJIRA_HANDS_FREE_BIN).
sjira-loop-evidence:
    #!/usr/bin/env bash
    set -euo pipefail
    export SJIRA_HANDS_FREE_CROSSCHECK="${SJIRA_HANDS_FREE_CROSSCHECK:-1}"
    just sjira-loop dry-run

# Print env contract without running.
sjira-loop-help:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{justfile_directory()}}"
    if [ ! -f "$root/mix.exs" ] && [ -f "$root/../mix.exs" ]; then
      root="$(cd "$root/.." && pwd)"
    fi
    sed -n '2,80p' "$root/scripts/sjira/autonomic_loop.sh"
