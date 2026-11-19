# Hands-free sjira autonomic loop (v26.11.19) — GAP9 / SJ10

Standing: PASS

Subject: `/Users/sac/ggen_igniter` hands-free observe → admit → frontier →
(evidence twin) → sealed live sandbox execute. SoT is **loop-produced**
`loop_receipt.json` artifacts under `receipts/`, not agent-authored PASS claims.

## Identity

| Surface | Path |
|---|---|
| Loop script | `scripts/sjira/autonomic_loop.sh` |
| Live sandbox | `scripts/sjira/live_sandbox.sh` + `just sjira-loop-live-sandbox` |
| Sealed pack | `test/fixtures/semantic_jira/live_sandbox_pack/` |
| Twin parity helper | `scripts/sjira/hands_free_twin_parity.py` |
| Twin court | `test/ggen_igniter_semantic_jira_hands_free_twin_court_test.exs` |
| Just recipes | `justfile.d/10-sjira.just` |
| Rust twin binary | ggen `fd4f99bbd` (canonical frontier authority when `--authority` absent) |

## GAP9 / SJ10 standing (loop-produced)

| Hop | Standing | Exit / notes |
|---|---|---|
| observe → admit → frontier (Mix dry-run) | **PASS** | friday fixture EXIT=0 `dry_run_ok`; admit 2/0; eligible=1 blocked=1 |
| `just sjira-loop-evidence` twin | **PASS** | EXIT=0; Mix↔hands-free eligible=`['FRI-FMT-A']`; `receipts/L04-loop_receipt.json` |
| hands-free twin court (Chicago) | **PASS** | 3/3 EXIT=0 |
| bare `just sjira-loop live` (no env) | **BLOCKED** (honest EXIT=2) | needs pack/target OR use live-sandbox |
| `just sjira-loop-live-sandbox` | **PASS** (PARTIAL_ALIVE ceiling) | EXIT=0 `live_ok`; `receipts/L04-live-sandbox-loop_receipt.json` |

### Product fixes that unblocked the loop

1. **ggen** `fd4f99bbd` — CLI `sjira frontier` loads embedded canonical authority index when `--authority` absent (closes `authority_index_unavailable` → `HANDS_FREE_TWIN_DRIFT`).
2. **ggen_igniter** this land — sealed `live_sandbox_pack` + `live_sandbox.sh` + `just sjira-loop-live-sandbox` so live hop runs without HITL pack/target.

### Live ceiling

Local execute is honestly **PARTIAL_ALIVE** (`head_verified=false`). Fabric ALIVE remains xaas-only / external.

## Replay

```sh
cd /Users/sac/ggen_igniter
# Point GGEN_BIN at a binary built at/after fd4f99bbd (stale ~/.local/bin ggen pre-fix drifts).

export SJIRA_OUT_DIR=$(mktemp -d)
export SJIRA_LEDGER=$SJIRA_OUT_DIR/ledger.jsonl
python3 -c '
import json,sys
doc=json.load(open("test/fixtures/semantic_jira/friday_work_orders.json"))
open(sys.argv[1],"w").writelines(json.dumps(w,separators=(",",":"))+"\n" for w in doc["work_orders"])
' "$SJIRA_OUT_DIR/candidates.jsonl"
export SJIRA_CANDIDATES=$SJIRA_OUT_DIR/candidates.jsonl
just sjira-loop dry-run          # expect 0
just sjira-loop-evidence         # expect 0 (twin parity)
just sjira-loop-live-sandbox     # expect 0 live_ok PARTIAL_ALIVE
```

## Standing

**PASS** — loop drained dry + evidence twin + sealed live sandbox. Not wave COMPLETE.
Not fake ALIVE. See `receipts/L04-sjira-loop-twin.md`.
