#!/usr/bin/env bash
# Hands-free Semantic Jira autonomic loop (no human prompts).
#
# Chain: observe → admit_candidates → frontier → execute → receipt
#
# Modes:
#   dry-run  (default) — observe + admit + frontier only; never actuates.
#   live               — full chain; execute (or complete drain) + receipt.
#
# Fail-closed: any mix exit ≠ 0, any admit refusal line, any REFUSED standing,
# or missing required env for the selected mode → exit 1 (typed REFUSED).
# Invalid invocation / missing inputs → exit 2.
#
# Recipe surface (from repo root; Just 1.56 positional mode arg):
#   just sjira-loop                 # dry-run
#   just sjira-loop dry-run
#   just sjira-loop live
#   just sjira-loop-dry
#   just sjira-loop-live
#   scripts/sjira/autonomic_loop.sh [--dry-run|--live]
#
# ── Env prerequisites ───────────────────────────────────────────────────────
# Always:
#   GGEN_IGNITER_DIR   checkout root (default: repo containing this script)
#   MIX_ENV            default: test (deterministic deps; override to dev if needed)
#   SJIRA_OUT_DIR      writable out dir (frontier JSON, candidates, receipts, loop receipt)
#   SJIRA_LEDGER       standing ledger path (ndjson file or ledger dir for TransitionLog)
#   elixir + mix + python3 + jq on PATH (jq optional; python3 used for JSON)
#
# Observe hop (skipped when SJIRA_CANDIDATES is set):
#   SJIRA_FINDING              process_finding JSON
#   SJIRA_BASE_WORK_ORDER      base WorkOrder JSON
#   SJIRA_ORIGIN_AUTHORITY     IRI (INVARIANT A; required for observe)
#   SJIRA_IDENTITY             optional candidate identity
#   SJIRA_ONTOLOGY             optional ontology Turtle override
#   SJIRA_REPAIR               optional repair attrs JSON
#   SJIRA_ORIGIN_OBSERVATION   optional observation IRI
#
# Admit hop:
#   SJIRA_CANDIDATES           JSONL candidates (one WO object per line). When set,
#                              observe is skipped and this file is judged as-is.
#   SJIRA_AUTHORITY_GRAPH      optional Turtle authority graph
#   SJIRA_EPOCH_MANIFEST       optional epoch watermark JSON
#   SJIRA_SOVEREIGN_KEYS       optional sovereign public-keys JSON
#
# Frontier / execute hops:
#   SJIRA_WORK_ORDERS          optional existing admitted backlog JSON (array or
#                              {"work_orders":[...]}); merged with newly admitted
#   SJIRA_IDENTITY             live: execute this identity; else drain via complete
#   SJIRA_VERIFIER_SUITE       required for live local/projection execute
#   SJIRA_ALIAS                repeatable-style "owner/repo=alias" (one alias)
#   SJIRA_PROVIDER             default recipe
#   SJIRA_COURT_MAP            optional court-map JSON
#   SJIRA_TEMPLATE             optional multi-template pack template path
#   SJIRA_MAX                  complete iteration bound (default 1000)
#
# Dry-run evidence beyond Mix frontier (optional, non-destructive):
#   SJIRA_HANDS_FREE_CROSSCHECK=1  after Mix frontier, also run ggen/hands-free
#                                  frontier against work_orders.json and attach
#                                  digests to loop_receipt.json (fail-closed).
#   SJIRA_HANDS_FREE_BIN           optional binary override.
#   SJIRA_HANDS_FREE_STYLE         nounverb|direct (default: auto — *hands-free*
#                                  basename → `system frontier`; else `frontier`).
#   GGEN_BIN                       else: `{GGEN_BIN|ggen} sjira frontier …`
#   Note: Rust frontier order envelope may differ from Mix flat WorkOrders;
#   cross-check REFUSE is lawful evidence of twin drift, not a fake pass.
#
# Live local backend (exactly one backend; same law as mix semantic_jira.execute):
#   SJIRA_PACK_DIR + SJIRA_TARGET_DIR + SJIRA_RECEIPTS_DIR
#     OR SJIRA_PACKS_ROOT + SJIRA_TARGET_DIR + SJIRA_RECEIPTS_DIR  (complete only)
#     OR SJIRA_RECEIPT (+ optional SJIRA_BRIDGE for xaas_receipt hop)
#
# External receipt hop (optional after execute when SJIRA_XAAS_RECEIPT is set):
#   SJIRA_BRIDGE               descriptor/bridge JSON for semantic_jira.xaas_receipt
#   SJIRA_XAAS_RECEIPT         sealed XaaS export path
#
# Never prompts stdin. Never reaches a non-loopback address from this script.
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
gi=${GGEN_IGNITER_DIR:-$(cd "$here/../.." && pwd)}
mode=${SJIRA_MODE:-dry-run}
mix_env=${MIX_ENV:-test}

usage() {
  cat <<'EOF' >&2
usage: scripts/sjira/autonomic_loop.sh [--dry-run|--live] [--help]

  Hands-free chain: observe → admit_candidates → frontier → execute → receipt
  Default mode: dry-run (env SJIRA_MODE=dry-run|live).

  See script header for env prerequisites.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) mode=dry-run ;;
    --live) mode=live ;;
    -h|--help) usage; exit 0 ;;
    *) echo "REFUSED:USAGE unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

case "$mode" in
  dry-run|live) ;;
  *) echo "REFUSED:USAGE SJIRA_MODE must be dry-run|live (got '$mode')" >&2; exit 2 ;;
esac

refuse() {
  echo "REFUSED:$1 $2" >&2
  exit 1
}

invalid() {
  echo "INVALID:$1" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || invalid "missing command on PATH: $1"
}

require_file() {
  [ -f "$1" ] || invalid "missing file: $1 ($2)"
}

require_env_file() {
  # $1=VAR name, $2=label
  eval "val=\${$1:-}"
  [ -n "$val" ] || invalid "env $1 required ($2)"
  require_file "$val" "$1"
}

require_cmd mix
require_cmd elixir
require_cmd python3

[ -f "$gi/mix.exs" ] || invalid "GGEN_IGNITER_DIR has no mix.exs: $gi"
[ -f "$gi/lib/mix/tasks/semantic_jira.admit_candidates.ex" ] || \
  invalid "semantic_jira.* tasks absent under $gi"

out_dir=${SJIRA_OUT_DIR:-}
[ -n "$out_dir" ] || invalid "SJIRA_OUT_DIR is required"
mkdir -p "$out_dir"

ledger=${SJIRA_LEDGER:-}
[ -n "$ledger" ] || invalid "SJIRA_LEDGER is required"
# TransitionLog accepts a file or directory; ensure parent exists for a new file.
if [ ! -e "$ledger" ]; then
  mkdir -p "$(dirname "$ledger")"
  : >"$ledger"
fi

log() { echo "== sjira-loop [$mode] $*"; }

mix_run() {
  # Capture exit; never interactive. Fail closed on non-zero.
  local logfile=$1
  shift
  set +e
  (cd "$gi" && env MIX_ENV="$mix_env" mix "$@") >"$logfile" 2>&1
  local code=$?
  set -e
  if [ "$code" -ne 0 ]; then
    echo "---- mix $* (exit $code) ----" >&2
    tail -n 80 "$logfile" >&2 || true
    if grep -Eqi 'REFUSED|"standing"[[:space:]]*:[[:space:]]*"REFUSED"|status.:.refused' "$logfile"; then
      refuse "MIX" "$* exited $code (typed REFUSED in output)"
    fi
    refuse "MIX" "$* exited $code"
  fi
  # Belt-and-suspenders: exit 0 with REFUSED in body still fails closed.
  if grep -Eqi '^REFUSED:|"standing"[[:space:]]*:[[:space:]]*"REFUSED"' "$logfile"; then
    refuse "MIX" "$* printed REFUSED despite exit 0"
  fi
  return 0
}

candidates=${SJIRA_CANDIDATES:-}
observe_json="$out_dir/observe.json"
candidates_jsonl="$out_dir/candidates.jsonl"
admitted_jsonl="$out_dir/admitted.jsonl"
work_orders_json="$out_dir/work_orders.json"
frontier_json="$out_dir/frontier.json"
admit_log="$out_dir/admit.log"
frontier_log="$out_dir/frontier.log"
execute_log="$out_dir/execute.log"
receipt_log="$out_dir/receipt.log"
loop_receipt="$out_dir/loop_receipt.json"
hands_free_frontier_json="$out_dir/hands_free_frontier.json"
hands_free_log="$out_dir/hands_free_frontier.log"
observe_skipped=0

# ── 1. observe ──────────────────────────────────────────────────────────────
if [ -n "$candidates" ]; then
  require_file "$candidates" "SJIRA_CANDIDATES"
  # macOS `cp` refuses identical src/dst; skip when same inode.
  [ "$candidates" -ef "$candidates_jsonl" ] || cp "$candidates" "$candidates_jsonl"
  observe_skipped=1
  log "observe: skipped (SJIRA_CANDIDATES=$candidates)"
else
  require_env_file SJIRA_FINDING "observe finding JSON"
  require_env_file SJIRA_BASE_WORK_ORDER "observe base WorkOrder JSON"
  [ -n "${SJIRA_ORIGIN_AUTHORITY:-}" ] || \
    invalid "SJIRA_ORIGIN_AUTHORITY required when observe runs (INVARIANT A)"

  obs_args=(
    semantic_jira.observe
    --finding "$SJIRA_FINDING"
    --base-work-order "$SJIRA_BASE_WORK_ORDER"
    --origin-authority "$SJIRA_ORIGIN_AUTHORITY"
    --out "$observe_json"
  )
  [ -n "${SJIRA_IDENTITY:-}" ] && obs_args+=(--identity "$SJIRA_IDENTITY")
  [ -n "${SJIRA_ONTOLOGY:-}" ] && obs_args+=(--ontology "$SJIRA_ONTOLOGY")
  [ -n "${SJIRA_REPAIR:-}" ] && obs_args+=(--repair "$SJIRA_REPAIR")
  [ -n "${SJIRA_ORIGIN_OBSERVATION:-}" ] && \
    obs_args+=(--origin-observation "$SJIRA_ORIGIN_OBSERVATION")

  log "observe: mix ${obs_args[*]}"
  mix_run "$out_dir/observe.log" "${obs_args[@]}"

  python3 - "$observe_json" "$candidates_jsonl" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
doc = json.load(open(src, encoding="utf-8"))
wo = doc.get("work_order")
if not isinstance(wo, dict):
    print("REFUSED:OBSERVE observe output missing work_order object", file=sys.stderr)
    sys.exit(1)
with open(dst, "w", encoding="utf-8") as f:
    f.write(json.dumps(wo, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
PY
  log "observe: wrote $candidates_jsonl"
fi

# ── 2. admit_candidates (fail closed on any refused verdict) ─────────────────
admit_args=(semantic_jira.admit_candidates --candidates "$candidates_jsonl")
[ -n "${SJIRA_AUTHORITY_GRAPH:-}" ] && admit_args+=(--authority-graph "$SJIRA_AUTHORITY_GRAPH")
[ -n "${SJIRA_EPOCH_MANIFEST:-}" ] && admit_args+=(--epoch-manifest "$SJIRA_EPOCH_MANIFEST")
[ -n "${SJIRA_SOVEREIGN_KEYS:-}" ] && admit_args+=(--sovereign-keys "$SJIRA_SOVEREIGN_KEYS")

log "admit_candidates: mix ${admit_args[*]}"
mix_run "$admit_log" "${admit_args[@]}"

# Task exits 0 even when lines are refused — loop law fails closed on refused>0.
python3 - "$admit_log" "$candidates_jsonl" "$admitted_jsonl" <<'PY'
import re, sys
log_path, cand_path, out_path = sys.argv[1:4]
text = open(log_path, encoding="utf-8", errors="replace").read()
refused_lines = [ln for ln in text.splitlines() if re.match(r"^refused\s+", ln)]
m = re.search(r"^summary admitted=(\d+) refused=(\d+)\s*$", text, re.M)
if not m:
    print("REFUSED:ADMIT missing summary line in admit output", file=sys.stderr)
    sys.exit(1)
admitted_n, refused_n = int(m.group(1)), int(m.group(2))
if refused_n > 0 or refused_lines:
    print(
        f"REFUSED:ADMIT summary admitted={admitted_n} refused={refused_n}",
        file=sys.stderr,
    )
    for ln in refused_lines[:20]:
        print(ln, file=sys.stderr)
    sys.exit(1)
if admitted_n < 1:
    print("REFUSED:ADMIT no candidates admitted", file=sys.stderr)
    sys.exit(1)

# All lines admitted: copy non-blank candidate lines as the admitted set.
lines = [ln for ln in open(cand_path, encoding="utf-8") if ln.strip()]
if len(lines) != admitted_n:
    # Still accept if counts match after blank-skip; else refuse (skew).
    print(
        f"REFUSED:ADMIT admitted={admitted_n} but candidates.jsonl has {len(lines)} lines",
        file=sys.stderr,
    )
    sys.exit(1)
open(out_path, "w", encoding="utf-8").writelines(lines)
print(f"admit: admitted={admitted_n} refused=0")
PY

# ── 3. build work_orders.json (admitted ∪ optional backlog) ──────────────────
python3 - "$admitted_jsonl" "${SJIRA_WORK_ORDERS:-}" "$work_orders_json" <<'PY'
import json, sys
admitted_path, backlog_path, out_path = sys.argv[1:4]
orders = []
seen = set()

def add(wo):
    if not isinstance(wo, dict):
        return
    ident = wo.get("identity")
    if not isinstance(ident, str) or not ident or ident in seen:
        return
    seen.add(ident)
    orders.append(wo)

for ln in open(admitted_path, encoding="utf-8"):
    ln = ln.strip()
    if not ln:
        continue
    add(json.loads(ln))

if backlog_path:
    doc = json.load(open(backlog_path, encoding="utf-8"))
    if isinstance(doc, list):
        for wo in doc:
            add(wo)
    elif isinstance(doc, dict) and isinstance(doc.get("work_orders"), list):
        for wo in doc["work_orders"]:
            add(wo)
    else:
        print("REFUSED:WORK_ORDERS backlog must be array or {work_orders:[...]}", file=sys.stderr)
        sys.exit(1)

if not orders:
    print("REFUSED:WORK_ORDERS empty after admit", file=sys.stderr)
    sys.exit(1)

with open(out_path, "w", encoding="utf-8") as f:
    json.dump({"work_orders": orders}, f, sort_keys=True, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"work_orders: {len(orders)}")
PY

# ── 4. frontier ──────────────────────────────────────────────────────────────
front_args=(
  semantic_jira.frontier
  --work-orders "$work_orders_json"
  --ledger "$ledger"
)
[ -n "${SJIRA_AUTHORITY_GRAPH:-}" ] && front_args+=(--authority-graph "$SJIRA_AUTHORITY_GRAPH")

log "frontier: mix ${front_args[*]}"
mix_run "$frontier_log" "${front_args[@]}"
# Last JSON object on stdout is the frontier payload.
python3 - "$frontier_log" "$frontier_json" <<'PY'
import json, sys
log_path, out_path = sys.argv[1], sys.argv[2]
text = open(log_path, encoding="utf-8", errors="replace").read()
# Prefer the last line that parses as a JSON object with eligible/blocked.
payload = None
for ln in text.splitlines():
    ln = ln.strip()
    if not ln.startswith("{"):
        continue
    try:
        doc = json.loads(ln)
    except json.JSONDecodeError:
        continue
    if isinstance(doc, dict) and "eligible" in doc:
        payload = doc
if payload is None:
    # Whole-file fallback (pretty-printed).
    try:
        doc = json.loads(text)
        if isinstance(doc, dict) and "eligible" in doc:
            payload = doc
    except json.JSONDecodeError:
        pass
if payload is None:
    print("REFUSED:FRONTIER could not parse frontier JSON", file=sys.stderr)
    sys.exit(1)
if payload.get("status") == "refused":
    print("REFUSED:FRONTIER " + json.dumps(payload.get("reason")), file=sys.stderr)
    sys.exit(1)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, sort_keys=True, indent=2, ensure_ascii=False)
    f.write("\n")
elig = payload.get("eligible") or []
print(f"frontier: eligible={len(elig)} blocked={len(payload.get('blocked') or [])}")
PY

# ── 4b. optional hands-free (ggen) frontier cross-check — non-destructive ────
hands_free_ran=0
if [ "${SJIRA_HANDS_FREE_CROSSCHECK:-}" = "1" ]; then
  hands_free_ran=1
  set +e
  if [ -n "${SJIRA_HANDS_FREE_BIN:-}" ]; then
    hf_bin=$SJIRA_HANDS_FREE_BIN
    hf_base=$(basename "$hf_bin")
    # zero-code-sjira-hands-free: noun-verb `system frontier`.
    # ggen-sjira / SJIRA_BIN: direct `frontier` verb (+ --format json).
    if [ "${SJIRA_HANDS_FREE_STYLE:-}" = "nounverb" ] || \
       [[ "$hf_base" == *hands-free* ]]; then
      "$hf_bin" system frontier \
        --orders-path "$work_orders_json" \
        >"$hands_free_frontier_json" 2>"$hands_free_log"
      hf_code=$?
    else
      "$hf_bin" frontier \
        --orders-path "$work_orders_json" \
        --format json \
        >"$hands_free_frontier_json" 2>"$hands_free_log"
      hf_code=$?
    fi
  else
    ggen_bin=${GGEN_BIN:-ggen}
    "$ggen_bin" sjira frontier \
      --orders-path "$work_orders_json" \
      --format json \
      >"$hands_free_frontier_json" 2>"$hands_free_log"
    hf_code=$?
  fi
  set -e
  if [ "$hf_code" -ne 0 ]; then
    echo "---- hands-free frontier (exit $hf_code) ----" >&2
    tail -n 80 "$hands_free_log" >&2 || true
    refuse "HANDS_FREE" "frontier cross-check exited $hf_code"
  fi
  python3 - "$hands_free_frontier_json" <<'PY'
import json, sys
path = sys.argv[1]
raw = open(path, encoding="utf-8", errors="replace").read().strip()
if not raw:
    print("REFUSED:HANDS_FREE empty frontier stdout", file=sys.stderr)
    sys.exit(1)
try:
    doc = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"REFUSED:HANDS_FREE non-JSON frontier stdout: {e}", file=sys.stderr)
    sys.exit(1)
if isinstance(doc, dict) and (
    doc.get("status") in ("refused", "REFUSED") or doc.get("standing") == "REFUSED"
):
    print("REFUSED:HANDS_FREE " + json.dumps(doc), file=sys.stderr)
    sys.exit(1)
print(f"hands-free frontier: ok bytes={len(raw)}")
PY
  log "hands-free frontier cross-check → $hands_free_frontier_json"
fi

if [ "$mode" = "dry-run" ]; then
  python3 - "$loop_receipt" "$mode" "$frontier_json" "$work_orders_json" "$ledger" \
    "$candidates_jsonl" "$admitted_jsonl" "$admit_log" "$observe_skipped" \
    "$hands_free_ran" "$hands_free_frontier_json" <<'PY'
import json, hashlib, sys, os

(
    out,
    mode,
    frontier_path,
    wo_path,
    ledger,
    candidates_path,
    admitted_path,
    admit_log,
    observe_skipped,
    hands_free_ran,
    hands_free_path,
) = sys.argv[1:12]


def sha256_file(path):
    if not path or not os.path.isfile(path):
        return None
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


frontier = json.load(open(frontier_path, encoding="utf-8"))
admit_text = open(admit_log, encoding="utf-8", errors="replace").read()
import re

m = re.search(r"^summary admitted=(\d+) refused=(\d+)\s*$", admit_text, re.M)
admit_summary = (
    {"admitted": int(m.group(1)), "refused": int(m.group(2))} if m else None
)
chain = []
if observe_skipped == "1":
    chain.append("observe_skipped")
else:
    chain.append("observe")
chain.extend(["admit_candidates", "frontier"])
if hands_free_ran == "1":
    chain.append("hands_free_frontier")

receipt = {
    "status": "dry_run_ok",
    "mode": mode,
    "chain": chain,
    "skipped": ["execute", "receipt"],
    "eligible_count": len(frontier.get("eligible") or []),
    "blocked_count": len(frontier.get("blocked") or []),
    "admit_summary": admit_summary,
    "work_orders": wo_path,
    "frontier": frontier_path,
    "ledger": ledger,
    "evidence": {
        "candidates_digest": sha256_file(candidates_path),
        "admitted_digest": sha256_file(admitted_path),
        "work_orders_digest": sha256_file(wo_path),
        "frontier_digest": sha256_file(frontier_path),
        "hands_free_frontier_digest": sha256_file(hands_free_path)
        if hands_free_ran == "1"
        else None,
    },
    "standing": "UNVERIFIED",
    "note": (
        "dry-run: observe→admit→frontier with file digests; "
        "no execute/receipt actuation; coordinator/verifier must promote standing"
    ),
}
body = json.dumps(
    {k: v for k, v in receipt.items() if k != "loop_digest"},
    sort_keys=True,
    separators=(",", ":"),
    ensure_ascii=False,
)
receipt["loop_digest"] = "sha256:" + hashlib.sha256(body.encode()).hexdigest()
with open(out, "w", encoding="utf-8") as f:
    json.dump(receipt, f, sort_keys=True, indent=2, ensure_ascii=False)
    f.write("\n")
print(
    json.dumps(
        {
            "status": "dry_run_ok",
            "loop_receipt": out,
            "eligible": receipt["eligible_count"],
            "evidence": receipt["evidence"],
        }
    )
)
PY
  log "dry-run complete → $loop_receipt"
  exit 0
fi

# ── 5. execute (live) ────────────────────────────────────────────────────────
# Backend selection mirrors mix semantic_jira.execute / .complete.
backend=""
exec_args=()

if [ -n "${SJIRA_RECEIPT:-}" ]; then
  backend=external
elif [ -n "${SJIRA_PACKS_ROOT:-}" ]; then
  backend=packs_root
elif [ -n "${SJIRA_PACK_DIR:-}" ]; then
  backend=local
else
  invalid "live mode needs SJIRA_PACK_DIR|SJIRA_PACKS_ROOT|SJIRA_RECEIPT"
fi

[ -n "${SJIRA_VERIFIER_SUITE:-}" ] || invalid "SJIRA_VERIFIER_SUITE required for live"
[ -n "${SJIRA_ALIAS:-}" ] || invalid "SJIRA_ALIAS=owner/repo=alias required for live"

if [ -n "${SJIRA_IDENTITY:-}" ] && [ "$backend" != "packs_root" ]; then
  # Single-order execute.
  receipt_out=${SJIRA_RECEIPT_OUT:-"$out_dir/receipt_${SJIRA_IDENTITY}.json"}
  exec_args=(
    semantic_jira.execute
    --work-orders "$work_orders_json"
    --ledger "$ledger"
    --identity "$SJIRA_IDENTITY"
    --verifier-suite "$SJIRA_VERIFIER_SUITE"
    --alias "$SJIRA_ALIAS"
    --out "$out_dir/execute_result.json"
    --out-dir "$out_dir"
  )
  [ -n "${SJIRA_PROVIDER:-}" ] && exec_args+=(--provider "$SJIRA_PROVIDER")
  [ -n "${SJIRA_COURT_MAP:-}" ] && exec_args+=(--court-map "$SJIRA_COURT_MAP")
  [ -n "${SJIRA_AUTHORITY_GRAPH:-}" ] && exec_args+=(--authority-graph "$SJIRA_AUTHORITY_GRAPH")
  [ -n "${SJIRA_TEMPLATE:-}" ] && exec_args+=(--template "$SJIRA_TEMPLATE")
  case "$backend" in
    local)
      [ -n "${SJIRA_TARGET_DIR:-}" ] || invalid "SJIRA_TARGET_DIR required for local"
      exec_args+=(--pack-dir "$SJIRA_PACK_DIR" --target-dir "$SJIRA_TARGET_DIR" --receipt-out "$receipt_out")
      ;;
    external)
      exec_args+=(--receipt "$SJIRA_RECEIPT")
      ;;
  esac
else
  # Drain via complete (frontier → execute → reconcile until empty).
  receipts_dir=${SJIRA_RECEIPTS_DIR:-"$out_dir/receipts"}
  mkdir -p "$receipts_dir"
  exec_args=(
    semantic_jira.complete
    --work-orders "$work_orders_json"
    --ledger "$ledger"
    --verifier-suite "$SJIRA_VERIFIER_SUITE"
    --alias "$SJIRA_ALIAS"
    --out "$out_dir/complete_result.json"
    --out-dir "$out_dir"
  )
  [ -n "${SJIRA_PROVIDER:-}" ] && exec_args+=(--provider "$SJIRA_PROVIDER")
  [ -n "${SJIRA_COURT_MAP:-}" ] && exec_args+=(--court-map "$SJIRA_COURT_MAP")
  [ -n "${SJIRA_AUTHORITY_GRAPH:-}" ] && exec_args+=(--authority-graph "$SJIRA_AUTHORITY_GRAPH")
  [ -n "${SJIRA_TEMPLATE:-}" ] && exec_args+=(--template "$SJIRA_TEMPLATE")
  [ -n "${SJIRA_MAX:-}" ] && exec_args+=(--max "$SJIRA_MAX")
  [ -n "${SJIRA_TARGET_DIR:-}" ] || invalid "SJIRA_TARGET_DIR required for complete"
  case "$backend" in
    local)
      exec_args+=(--pack-dir "$SJIRA_PACK_DIR" --target-dir "$SJIRA_TARGET_DIR" --receipts-dir "$receipts_dir")
      ;;
    packs_root)
      exec_args+=(--packs-root "$SJIRA_PACKS_ROOT" --target-dir "$SJIRA_TARGET_DIR" --receipts-dir "$receipts_dir")
      ;;
    external)
      # complete does not take --receipt; force single-identity execute path.
      invalid "SJIRA_RECEIPT backend requires SJIRA_IDENTITY for live single execute"
      ;;
  esac
fi

log "execute: mix ${exec_args[*]}"
mix_run "$execute_log" "${exec_args[@]}"

# ── 6. receipt (optional xaas_receipt map; always emit loop receipt) ─────────
receipt_mapped=""
if [ -n "${SJIRA_XAAS_RECEIPT:-}" ]; then
  [ -n "${SJIRA_BRIDGE:-}" ] || invalid "SJIRA_BRIDGE required with SJIRA_XAAS_RECEIPT"
  require_file "$SJIRA_XAAS_RECEIPT" "SJIRA_XAAS_RECEIPT"
  require_file "$SJIRA_BRIDGE" "SJIRA_BRIDGE"
  mapped="$out_dir/xaas_mapped_receipt.json"
  rcpt_args=(
    semantic_jira.xaas_receipt
    --bridge "$SJIRA_BRIDGE"
    --xaas-receipt "$SJIRA_XAAS_RECEIPT"
    --out "$mapped"
  )
  log "receipt: mix ${rcpt_args[*]}"
  mix_run "$receipt_log" "${rcpt_args[@]}"
  receipt_mapped=$mapped
fi

python3 - "$loop_receipt" "$mode" "$frontier_json" "$work_orders_json" "$ledger" \
  "$execute_log" "$receipt_mapped" "$out_dir" <<'PY'
import json, hashlib, sys, os
out, mode, frontier_path, wo_path, ledger, exec_log, mapped, out_dir = sys.argv[1:9]
frontier = json.load(open(frontier_path, encoding="utf-8"))
exec_text = open(exec_log, encoding="utf-8", errors="replace").read()
# Prefer written result files when present.
result = None
for name in ("complete_result.json", "execute_result.json"):
    path = os.path.join(out_dir, name)
    if os.path.isfile(path):
        result = json.load(open(path, encoding="utf-8"))
        break
if result is None:
    for ln in reversed(exec_text.splitlines()):
        ln = ln.strip()
        if ln.startswith("{") and "status" in ln:
            try:
                result = json.loads(ln)
                break
            except json.JSONDecodeError:
                continue
if isinstance(result, dict) and (
    result.get("status") in ("refused",) or result.get("standing") == "REFUSED"
):
    print("REFUSED:EXECUTE " + json.dumps(result), file=sys.stderr)
    sys.exit(1)

receipt = {
    "status": "live_ok",
    "mode": mode,
    "chain": ["observe", "admit_candidates", "frontier", "execute", "receipt"],
    "eligible_count": len(frontier.get("eligible") or []),
    "blocked_count": len(frontier.get("blocked") or []),
    "work_orders": wo_path,
    "frontier": frontier_path,
    "ledger": ledger,
    "execute_result": result,
    "xaas_mapped_receipt": mapped or None,
    "standing": "UNVERIFIED",
    "note": "live chain finished without REFUSED; verifier must promote standing from gates",
}
body = json.dumps(
    {k: v for k, v in receipt.items() if k != "loop_digest"},
    sort_keys=True,
    separators=(",", ":"),
    ensure_ascii=False,
)
receipt["loop_digest"] = "sha256:" + hashlib.sha256(body.encode()).hexdigest()
with open(out, "w", encoding="utf-8") as f:
    json.dump(receipt, f, sort_keys=True, indent=2, ensure_ascii=False)
    f.write("\n")
print(json.dumps({"status": "live_ok", "loop_receipt": out}))
PY

log "live complete → $loop_receipt"
exit 0
