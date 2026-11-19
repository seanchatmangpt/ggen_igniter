# Hands-free sjira autonomic loop (v26.11.19) — GAP9 / SJ10
Standing: PASS

Subject: `/Users/sac/ggen_igniter` hands-free observe → admit → frontier (+ optional
ggen/hands-free cross-check). Live execute remains operator-gated.

## Identity

| Surface | Path |
|---|---|
| Loop script | `scripts/sjira/autonomic_loop.sh` |
| Just recipes | `justfile.d/10-sjira.just` (+ root `Justfile` import) |
| Mix tasks | `lib/mix/tasks/semantic_jira.{observe,admit_candidates,frontier,execute,complete,xaas_receipt}.ex` |
| Rust hands-free twin | `/Users/sac/ggen/examples/zero-code-sjira-hands-free` (`sjira-hands-free` → `ggen sjira`) |
| EA sibling | `/Users/sac/ggen/examples/zero-code-sjira` (scaffold; not the live twin) |
| fnox | no `just sjira-loop` surface (sjira docs under `docs/sjira/`; loop SoT is ggen_igniter) |

## GAP9 / SJ10 standing (beyond dry-run)

| Hop | Standing | Notes |
|---|---|---|
| observe → admit → frontier (Mix dry-run) | **PASS** | SJ10 verifier `fe831c68`: friday fixture EXIT=0, `status: dry_run_ok`, digests present; `admit: admitted=2 refused=0`; `frontier: eligible=1 blocked=1` |
| evidence digests in `loop_receipt.json` | landed | `candidates`/`admitted`/`work_orders`/`frontier` sha256 |
| `just sjira-loop-evidence` / `SJIRA_HANDS_FREE_CROSSCHECK=1` | **PASS** | `GGEN_BIN=~/.local/bin/ggen` (**ggen 26.11.5**) EXIT=0; `hands-free frontier: ok bytes=189`; digest recorded. Missing ggen REFUSE proved: `GGEN_BIN=/nonexistent/ggen-missing` → EXIT=1 `REFUSED:HANDS_FREE frontier cross-check exited 127` |
| live execute / complete | **BLOCKED** | EXIT=2 without operator pack/target (see below) |

### Twin note (non-blocking)

Mix frontier: `eligible=1 blocked=1`. Rust `ggen sjira frontier`: both WOs
`authority_index_unavailable`, `eligible=[]`. Cross-check still EXIT=0 (JSON ok, no
REFUSED standing) — lawful Mix↔Rust twin drift, not a fake Mix green; does not
block O→A→F+evidence PASS.

### Live BLOCKED — exact refuse conditions

`just sjira-loop live` exits **2** (`INVALID:…`) unless all of:

1. Backend (exactly one): `SJIRA_PACK_DIR` **or** `SJIRA_PACKS_ROOT` **or** `SJIRA_RECEIPT`
2. `SJIRA_VERIFIER_SUITE` (non-empty)
3. `SJIRA_ALIAS` (`owner/repo=alias`)
4. For local/complete: `SJIRA_TARGET_DIR` (and for complete drain: writable receipts dir)
5. For external backend without identity: refused — `SJIRA_RECEIPT` requires `SJIRA_IDENTITY`

Even with env present, live is **destructive** (pack sync / gate verify / ledger append / target HEAD check). No sealed sandbox fixture pack+target was admitted for GAP9; therefore live is documented **BLOCKED** pending operator-supplied temp target + verifier suite, not faked green.

SJ10 replay: `just sjira-loop live` (no pack/target) → EXIT=2
`INVALID:live mode needs SJIRA_PACK_DIR|SJIRA_PACKS_ROOT|SJIRA_RECEIPT`.

## Authority

- Builder: fnox-planner-engineer GAP9 restore after mid-wave wipe.
- Prior dry-run evidence (verifier `d14a5308`): EXIT=0, `status: dry_run_ok`, friday `test/fixtures/semantic_jira/friday_work_orders.json`.
- SJ10 evidence crosscheck (verifier `fe831c68`): friday dry-run EXIT=0; evidence EXIT=0 with ggen 26.11.5; live EXIT=2 BLOCKED; missing ggen EXIT=1 REFUSE.

## Consequence

- Loop + Just recipes re-landed with `-ef` identical-path skip.
- Dry-run receipt carries evidence digests (and optional hands-free frontier digest).
- O→A→F+evidence promoted to **PASS** on SJ10 replay; live not actuated / remains **BLOCKED**.

## Replay (verifier SJ10 / `fe831c68`)

```sh
cd /Users/sac/ggen_igniter
chmod +x scripts/sjira/autonomic_loop.sh
just sjira-loop-help

# fail-closed missing env (expect EXIT 2):
just sjira-loop dry-run; echo EXIT:$?

# Mix O→A→F with fixture evidence:
export SJIRA_OUT_DIR=$(mktemp -d)
export SJIRA_LEDGER=$SJIRA_OUT_DIR/ledger.jsonl
python3 -c '
import json,sys
doc=json.load(open("test/fixtures/semantic_jira/friday_work_orders.json"))
open(sys.argv[1],"w").writelines(json.dumps(w,separators=(",",":"))+"\n" for w in doc["work_orders"])
' "$SJIRA_OUT_DIR/candidates.jsonl"
export SJIRA_CANDIDATES=$SJIRA_OUT_DIR/candidates.jsonl
just sjira-loop dry-run; echo EXIT:$?
python3 -m json.tool "$SJIRA_OUT_DIR/loop_receipt.json"

# Non-destructive twin (ggen 26.11.5):
export GGEN_BIN="$HOME/.local/bin/ggen"
just sjira-loop-evidence; echo EXIT:$?

# Live must stay BLOCKED without operator pack/target (expect EXIT 2):
just sjira-loop live; echo EXIT:$?

# Missing ggen must REFUSE (expect EXIT 1):
GGEN_BIN=/nonexistent/ggen-missing just sjira-loop-evidence; echo EXIT:$?
```

## Standing

**PASS** — O→A→F friday dry-run EXIT=0 `dry_run_ok` + `just sjira-loop-evidence` EXIT=0
with `GGEN_BIN=~/.local/bin/ggen` (ggen 26.11.5). Live remains **BLOCKED** (EXIT=2
without operator env). Missing-ggen evidence REFUSE EXIT=1 proved. Mix↔Rust
`authority_index_unavailable` twin drift is non-blocking.
