# Hands-free sjira autonomic loop (v26.11.19) — GAP9 / SJ10

Standing: PASS

Subject: `ggen_igniter` hands-free observe → admit → frontier →
evidence twin. SoT is **loop-produced** `loop_receipt.json` under `receipts/`,
not agent-authored PASS claims. Dogfood SoT:
**dry PASS / evidence PASS / live-sandbox PARTIAL_ALIVE / bare live BLOCKED (env keys) / fabric BLOCKED (Tony, external)**.

Latest cloud-agent reconfirm: `receipts/L21-cloud-agent-rerun.md` (2026-11-20).

## Identity

| Surface | Path |
|---|---|
| Loop script | `scripts/sjira/autonomic_loop.sh` |
| Twin parity helper | `scripts/sjira/hands_free_twin_parity.py` |
| Twin court | `test/ggen_igniter_semantic_jira_hands_free_twin_court_test.exs` |
| Just recipes | `justfile.d/10-sjira.just` |
| Rust twin binary | ggen `fd4f99bbd` (canonical frontier authority when `--authority` absent) |
| GGEN_BIN (L21 cloud re-run) | `/home/ubuntu/.local/bin/ggen` built from `fd4f99bbd` (`ggen 26.11.5`) — no skew |
| GGEN_BIN (prior local L04) | `/Users/sac/.local/bin/ggen` tip `bc0c2caaa` (≥ `fd4f99bbd`) |

## GAP9 / SJ10 standing (loop-produced)

| Hop | Standing | Exit / notes |
|---|---|---|
| observe → admit → frontier (Mix dry-run) | **PASS** | friday fixture EXIT=0 `dry_run_ok`; admit 2/0; eligible=1 blocked=1 (L04 + L21) |
| `just sjira-loop-evidence` twin | **PASS** | EXIT=0; Mix↔hands-free eligible=`['FRI-FMT-A']`; digests match L04 (L21) |
| hands-free twin court (Chicago) | **PASS** | 3/3 EXIT=0 (supporting vacuity) |
| Friday GoalCheckpoint Chicago (`--include integration`) | **PASS** | 44/44 after hybrid-pack `tera_pack?` fix; see `receipts/L04-friday-fixture-hardening.md` |
| `just sjira-loop-live-sandbox` | **PARTIAL_ALIVE** | EXIT=0; execute → `PARTIAL_ALIVE`; see `receipts/L04-live-sandbox-residual.md` + L21 |
| bare `just sjira-loop live` (no env) | **BLOCKED** | EXIT=2; first miss `SJIRA_OUT_DIR`; with candidates → `SJIRA_PACK_DIR\|SJIRA_PACKS_ROOT\|SJIRA_RECEIPT` (+ verifier/alias/target) |
| Fabric / auth live (Tony) | **BLOCKED (Tony)** | destructive/auth live remains external; not dogfood-closed |

### Product fixes

1. **ggen** `fd4f99bbd` — CLI `sjira frontier` loads embedded canonical authority index when `--authority` absent (closes `authority_index_unavailable` → empty HF → `HANDS_FREE_TWIN_DRIFT`).
2. **igniter** hybrid pack law — `PackFrontmatter.Sync.tera_pack?/1` ignores additive `.tera` beside classic `*.eex` so `semantic-jira-pack:jira` stays on ADR-0010 EEx sync (closes FM-PACK-013 false refuse of witness gates).

## Replay

```sh
cd /path/to/ggen_igniter
export GGEN_BIN=/path/to/ggen   # must be ≥ fd4f99bbd

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
just sjira-loop-live-sandbox     # expect 0; PARTIAL_ALIVE ceiling
```

## Standing

**PASS** scoped — dry + evidence twin + Friday GoalCheckpoint drained.
live-sandbox **PARTIAL_ALIVE** (EXIT=0). Bare live remains **BLOCKED** (exact
keys in `receipts/L04-live-sandbox-residual.md` + Tony fabric). Not demoting
COMPLETE. Not fake ALIVE. See `receipts/L04-sjira-loop-twin.md`,
`receipts/L20-evidence-twin-green.md`, and `receipts/L21-cloud-agent-rerun.md`.
