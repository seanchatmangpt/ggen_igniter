# Hands-free sjira autonomic loop (v26.11.19) — GAP9
Standing: UNVERIFIED

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

## GAP9 standing (beyond dry-run)

| Hop | Standing | Notes |
|---|---|---|
| observe → admit → frontier (Mix dry-run) | **UNVERIFIED** this lane (builder ran no gate) | Prior session verifier: EXIT=0, `dry_run_ok` with friday fixture + identical-`cp` `-ef` skip |
| evidence digests in `loop_receipt.json` | landed | `candidates`/`admitted`/`work_orders`/`frontier` sha256 |
| `just sjira-loop-evidence` / `SJIRA_HANDS_FREE_CROSSCHECK=1` | **UNVERIFIED** (may **REFUSE** on twin envelope drift) | Non-destructive ggen/hands-free frontier after Mix; fail-closed when enabled. Mix emits flat `work_orders[]`; Rust `ggen sjira frontier` / hands-free often wants wrapped frontier entries — a REFUSE here is lawful twin-drift evidence, not a fake green |
| live execute / complete | **BLOCKED** | See exact blockers below (prefer non-destructive) |

### Live BLOCKED — exact refuse conditions

`just sjira-loop live` exits **2** (`INVALID:…`) unless all of:

1. Backend (exactly one): `SJIRA_PACK_DIR` **or** `SJIRA_PACKS_ROOT` **or** `SJIRA_RECEIPT`
2. `SJIRA_VERIFIER_SUITE` (non-empty)
3. `SJIRA_ALIAS` (`owner/repo=alias`)
4. For local/complete: `SJIRA_TARGET_DIR` (and for complete drain: writable receipts dir)
5. For external backend without identity: refused — `SJIRA_RECEIPT` requires `SJIRA_IDENTITY`

Even with env present, live is **destructive** (pack sync / gate verify / ledger append / target HEAD check). No sealed sandbox fixture pack+target was admitted for GAP9; therefore live is documented **BLOCKED** pending operator-supplied temp target + verifier suite, not faked green.

## Authority

- Builder: fnox-planner-engineer GAP9 restore after mid-wave wipe.
- Prior dry-run evidence (verifier `d14a5308`): EXIT=0, `status: dry_run_ok`, friday `test/fixtures/semantic_jira/friday_work_orders.json`.

## Consequence

- Loop + Just recipes re-landed with `-ef` identical-path skip.
- Dry-run receipt now carries evidence digests (and optional hands-free frontier digest).
- Live not actuated this lane.

## Replay (verifier)

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

# Optional non-destructive twin (needs ggen on PATH):
export SJIRA_HANDS_FREE_CROSSCHECK=1
# export GGEN_BIN=… or SJIRA_HANDS_FREE_BIN=…/sjira-hands-free
just sjira-loop-evidence; echo EXIT:$?

# Live must stay BLOCKED without operator pack/target (expect EXIT 2):
just sjira-loop live; echo EXIT:$?
```

## Standing

UNVERIFIED — builder did not run mix/just/cargo. Verifier promotes O→A→F on EXIT=0 +
`loop_receipt.json` with digests; leaves live **BLOCKED** unless operator env is supplied
and a non-production target is used.
