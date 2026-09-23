#!/bin/sh
# GC23-1 cold-bootstrap court helper (GC-26.9.23, lane V23-B; PRD section 8.1,
# ARD section 16). The xaas court docs/sjira/v26.9.23/courts/GC23-1.sh (lane
# V23-K) runs this script from the xaas root with XAAS_DIR and GGEN_IGNITER_DIR
# in its env.
#
# It runs `mix semantic_jira.bootstrap` twice, in two fresh processes, each
# under
#   env -i PATH=/usr/bin:/bin:<elixir bin>:<erlang bin> HOME=$(mktemp -d)
#          MIX_HOME=<mix home> HEX_HOME=<hex home> LANG=en_US.UTF-8 MIX_ENV=<env>
# (no LLM variable, no claude/zcode binary on PATH, a HOME with nothing in it)
# over durable artifacts only, and exits 0 iff
#   1. both runs exit 0 and write byte-identical state files;
#   2. python3 recomputes each file's state_digest from its state (sha256 of
#      json.dumps(state, sort_keys=True, separators=(",", ":"),
#      ensure_ascii=False)) and gets the recorded value;
#   3. every sj:WorkOrder named in the goal graph that is not typed
#      sj:boundaryClass sj:Successor (the critical-path frontier items;
#      extracted from the Turtle independently of the task, by awk) is
#      reconstructed: present in state.orders with a frontier class
#      (eligible | blocked | settled), a standing and critical_path = true.
#
# Exit codes: 0 pass; 1 fail or typed refusal; 2 invalid invocation (inputs
# missing); 75 machinery absent (the checkout under judgement has no
# semantic_jira.bootstrap task), which the stop court maps to UNKNOWN.
#
# Refusals (typed, exit 1): REFUSED(llm_credential_present) when the invoking
# environment carries an ANTHROPIC_/CLAUDE_/OPENAI_/ZAI_/Z_AI_/GLM_/ZCODE_
# variable (broken_term mu_on_O; run the court under env -i), and
# REFUSED(llm_binary_on_path) when a court PATH directory holds a claude, zcode,
# codex or gemini executable.
#
# Inputs (defaults resolve from XAAS_DIR, the checkout under judgement):
#   BOOTSTRAP_VERSION        v26.9.23
#   BOOTSTRAP_GOAL           $XAAS_DIR/docs/sjira/$VERSION/goal.ttl
#   BOOTSTRAP_FLEET          $XAAS_DIR/docs/sjira/$VERSION/fleet/matrix.ttl
#   BOOTSTRAP_GRAPHS         space-separated work graphs; default the
#                            predecessor $XAAS_DIR/docs/sjira/v26.9.22/friday/goal.ttl
#                            when present
#   BOOTSTRAP_RECEIPTS_DIRS  space-separated; default $XAAS_DIR/receipts/$VERSION
#                            $GGEN_IGNITER_DIR/receipts/$VERSION
#                            $XAAS_DIR/docs/sjira/$VERSION/receipts
#   BOOTSTRAP_LEDGER         $XAAS_DIR/docs/sjira/$VERSION/ledger/standing-ledger.ndjson
#                            (absent = empty TransitionLog)
#   BOOTSTRAP_REGISTRY       recipe registry export JSON (optional)
#   BOOTSTRAP_CHECKOUTS      space-separated owner/repo=DIR; default
#                            seanchatmangpt/xaas=$XAAS_DIR
#                            seanchatmangpt/ggen_igniter=$GGEN_IGNITER_DIR
#   BOOTSTRAP_ELIXIR_BIN / BOOTSTRAP_ERLANG_BIN   toolchain dirs (default: the
#                            resolved dirs of `elixir` and `erl` on PATH)
#   BOOTSTRAP_MIX_ENV        dev
#   BOOTSTRAP_OUT_DIR        keep run1/ and run2/ state files there (default: a
#                            temp dir removed on exit)
# Paths containing spaces are not supported in the space-separated lists.
set -u

LLM_PREFIXES='ANTHROPIC_ CLAUDE_ OPENAI_ ZAI_ Z_AI_ GLM_ ZCODE_'
LLM_BINARIES='claude zcode codex gemini'

here=$(cd "$(dirname "$0")" && pwd)
gi=${GGEN_IGNITER_DIR:-$(cd "$here/../.." && pwd)}
xaas=${XAAS_DIR:-$(pwd)}
version=${BOOTSTRAP_VERSION:-v26.9.23}
goal=${BOOTSTRAP_GOAL:-$xaas/docs/sjira/$version/goal.ttl}
fleet=${BOOTSTRAP_FLEET:-$xaas/docs/sjira/$version/fleet/matrix.ttl}
ledger=${BOOTSTRAP_LEDGER:-$xaas/docs/sjira/$version/ledger/standing-ledger.ndjson}
registry=${BOOTSTRAP_REGISTRY:-}
mix_env=${BOOTSTRAP_MIX_ENV:-dev}

if [ -z "${BOOTSTRAP_GRAPHS+set}" ]; then
  graphs=""
  [ -f "$xaas/docs/sjira/v26.9.22/friday/goal.ttl" ] && graphs="$xaas/docs/sjira/v26.9.22/friday/goal.ttl"
else
  graphs=$BOOTSTRAP_GRAPHS
fi
receipts_dirs=${BOOTSTRAP_RECEIPTS_DIRS:-"$xaas/receipts/$version $gi/receipts/$version $xaas/docs/sjira/$version/receipts"}
checkouts=${BOOTSTRAP_CHECKOUTS:-"seanchatmangpt/xaas=$xaas seanchatmangpt/ggen_igniter=$gi"}

# -- 1. no LLM credential in the invoking environment (F3) --------------------
present=""
for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p'); do
  for prefix in $LLM_PREFIXES; do
    case "$name" in "$prefix"*) present="$present $name" ;; esac
  done
done
if [ -n "$present" ]; then
  echo "REFUSED(llm_credential_present) GC23-1: LLM credential variables set:$present" \
    "(broken_term mu_on_O); run the court under env -i"
  exit 1
fi

# -- 2. machinery and inputs -------------------------------------------------
if [ ! -f "$gi/lib/mix/tasks/semantic_jira.bootstrap.ex" ]; then
  echo "UNKNOWN: GC23-1 machinery lands in lane V23-B (no mix semantic_jira.bootstrap in $gi)"
  exit 75
fi
for input in "$goal" "$fleet"; do
  if [ ! -f "$input" ]; then
    echo "INVALID: GC23-1 bootstrap input missing: $input"
    exit 2
  fi
done

# -- 3. court PATH: /usr/bin:/bin plus the resolved elixir and erlang dirs -----
resolve_dir() {
  target=$1
  hops=0
  while [ -L "$target" ] && [ "$hops" -lt 40 ]; do
    link=$(readlink "$target")
    case "$link" in
      /*) target=$link ;;
      *) target=$(dirname "$target")/$link ;;
    esac
    hops=$((hops + 1))
  done
  (cd -P "$(dirname "$target")" 2>/dev/null && pwd)
}

elixir_bin=${BOOTSTRAP_ELIXIR_BIN:-}
[ -n "$elixir_bin" ] || { e=$(command -v elixir 2>/dev/null) && elixir_bin=$(resolve_dir "$e"); }
erlang_bin=${BOOTSTRAP_ERLANG_BIN:-}
[ -n "$erlang_bin" ] || { e=$(command -v erl 2>/dev/null) && erlang_bin=$(resolve_dir "$e"); }
if [ -z "$elixir_bin" ] || [ -z "$erlang_bin" ] || [ ! -x "$elixir_bin/mix" ] || [ ! -x "$erlang_bin/erl" ]; then
  echo "INVALID: GC23-1 cannot resolve the elixir/erlang toolchain (elixir_bin='$elixir_bin' erlang_bin='$erlang_bin')"
  exit 2
fi
court_path="/usr/bin:/bin:$elixir_bin:$erlang_bin"

# The build step may need cargo (the rustler NIF) and its rustup/cargo homes;
# state runs never get them.
build_path=$court_path
rust_env=""
if cargo=$(command -v cargo 2>/dev/null); then
  build_path="$court_path:$(dirname "$cargo")"
  rust_env="RUSTUP_HOME=${RUSTUP_HOME:-$HOME/.rustup} CARGO_HOME=${CARGO_HOME:-$HOME/.cargo}"
fi

refused_binaries=""
for dir in $(echo "$build_path" | tr ':' ' '); do
  for binary in $LLM_BINARIES; do
    [ -x "$dir/$binary" ] && refused_binaries="$refused_binaries $dir/$binary"
  done
done
if [ -n "$refused_binaries" ]; then
  echo "REFUSED(llm_binary_on_path) GC23-1: LLM binaries on the court PATH:$refused_binaries (broken_term mu_on_O)"
  exit 1
fi

mix_home=${BOOTSTRAP_MIX_HOME:-${MIX_HOME:-$HOME/.mix}}
hex_home=${BOOTSTRAP_HEX_HOME:-${HEX_HOME:-$HOME/.hex}}

# -- 4. scratch --------------------------------------------------------------
scratch=$(mktemp -d "${TMPDIR:-/tmp}/gc23-1.XXXXXX") || exit 1
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM
out_dir=${BOOTSTRAP_OUT_DIR:-$scratch/out}
mkdir -p "$out_dir/run1" "$out_dir/run2"

args="--fleet $fleet --goal $goal --ledger $ledger"
for g in $graphs; do args="$args --graphs $g"; done
for r in $receipts_dirs; do args="$args --receipts-dir $r"; done
for c in $checkouts; do args="$args --checkout $c"; done
[ -n "$registry" ] && args="$args --registry $registry"

# cold PATH MIX-ARGS [EXTRA-ENV]: one fresh process under env -i with a new HOME.
cold() {
  cold_home=$(mktemp -d "$scratch/home.XXXXXX")
  # shellcheck disable=SC2086
  (cd "$gi" && env -i PATH="$1" HOME="$cold_home" MIX_HOME="$mix_home" HEX_HOME="$hex_home" \
    LANG=en_US.UTF-8 MIX_ENV="$mix_env" ${3:-} mix $2)
}

# -- 5. build (compiles mu; reads no state) ----------------------------------
if ! cold "$build_path" "compile" "$rust_env" >"$scratch/build.log" 2>&1; then
  echo "FAIL: GC23-1 build step failed in $gi (MIX_ENV=$mix_env):"
  tail -20 "$scratch/build.log"
  exit 1
fi

# -- 6. two cold reconstructions ---------------------------------------------
for run in 1 2; do
  if cold "$court_path" "semantic_jira.bootstrap $args --out $out_dir/run$run/state.json" \
    >"$scratch/run$run.log" 2>&1; then
    echo "run$run: $(grep -E '^(STATE_DIGEST|ORDERS)' "$scratch/run$run.log" | tr '\n' ' ')"
  else
    echo "FAIL: GC23-1 cold run $run exited non-zero:"
    tail -20 "$scratch/run$run.log"
    exit 1
  fi
done

if ! cmp -s "$out_dir/run1/state.json" "$out_dir/run2/state.json"; then
  echo "FAIL: GC23-1 the two cold reconstructions differ"
  exit 1
fi

# -- 7. critical-path items named in the goal graph (independent of the task) --
required=$(awk '
  /^[^ \t#@]/ {
    if (wo && id != "" && !succ) print id
    wo = ($0 ~ / a sj:WorkOrder/); id = ""; succ = 0
  }
  wo && /dcterms:identifier "/ { line = $0; sub(/.*dcterms:identifier "/, "", line); sub(/".*/, "", line); id = line }
  wo && /sj:boundaryClass sj:Successor/ { succ = 1 }
  END { if (wo && id != "" && !succ) print id }
' "$goal" | sort -u | tr '\n' ' ')

if [ -z "$required" ]; then
  echo "FAIL: GC23-1 no critical-path WorkOrder found in $goal"
  exit 1
fi

/usr/bin/env python3 - "$out_dir/run1/state.json" "$out_dir/run2/state.json" $required <<'PY'
import hashlib, json, sys

files, required = sys.argv[1:3], sys.argv[3:]
fail = []
for path in files:
    doc = json.load(open(path, encoding="utf-8"))
    state = doc["state"]
    encoded = json.dumps(state, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    digest = "sha256:" + hashlib.sha256(encoded.encode("utf-8")).hexdigest()
    if digest != doc["state_digest"]:
        fail.append(f"{path}: state_digest {doc['state_digest']} != recomputed {digest}")
orders = json.load(open(files[0], encoding="utf-8"))["state"]["orders"]
for ident in required:
    order = orders.get(ident)
    if order is None:
        fail.append(f"critical-path order {ident} missing from the reconstruction")
    elif order.get("frontier") not in ("eligible", "blocked", "settled") \
            or not isinstance(order.get("standing"), str) or order.get("critical_path") is not True:
        fail.append(f"critical-path order {ident} not reconstructed: frontier={order.get('frontier')} "
                    f"standing={order.get('standing')} critical_path={order.get('critical_path')}")
for line in fail:
    print("FAIL: GC23-1 " + line)
sys.exit(1 if fail else 0)
PY
[ $? -eq 0 ] || exit 1

digest=$(sed -n 's/.*"state_digest":"\(sha256:[0-9a-f]*\)".*/\1/p' "$out_dir/run1/state.json")
echo "OK: GC23-1 two cold bootstrap runs byte-identical ($digest); critical-path orders reconstructed: $required"
exit 0
