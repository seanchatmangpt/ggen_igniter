# Hands-free sjira autonomic loop (v26.11.19) — GAP9 / SJ10
Standing: PARTIAL

Subject: `/Users/sac/ggen_igniter` hands-free observe → admit → frontier (+ optional
ggen/hands-free cross-check with mandatory eligible-set parity). Live execute
remains operator-gated. Skeptic L19 vacuity closed: JSON-ok alone is not PASS.

## Identity

| Surface | Path |
|---|---|
| Loop script | `scripts/sjira/autonomic_loop.sh` |
| Twin parity helper | `scripts/sjira/hands_free_twin_parity.py` |
| Twin court | `test/ggen_igniter_semantic_jira_hands_free_twin_court_test.exs` |
| Just recipes | `justfile.d/10-sjira.just` (+ root `Justfile` import) |
| Mix tasks | `lib/mix/tasks/semantic_jira.{observe,admit_candidates,frontier,execute,complete,xaas_receipt}.ex` |
| Rust hands-free twin | `/Users/sac/ggen/examples/zero-code-sjira-hands-free` (`sjira-hands-free` → `ggen sjira`) |
| EA sibling | `/Users/sac/ggen/examples/zero-code-sjira` (scaffold; not the live twin) |
| fnox | no `just sjira-loop` surface (sjira docs under `docs/sjira/`; loop SoT is ggen_igniter) |

## GAP9 / SJ10 standing (beyond dry-run)

| Hop | Standing | Notes |
|---|---|---|
| observe → admit → frontier (Mix dry-run) | **PASS** | friday fixture EXIT=0, `status: dry_run_ok`, digests present; `admit: admitted=2 refused=0`; `frontier: eligible=1 blocked=1` |
| evidence digests in `loop_receipt.json` | landed | `candidates`/`admitted`/`work_orders`/`frontier` sha256 |
| `just sjira-loop-evidence` / `SJIRA_HANDS_FREE_CROSSCHECK=1` | **REFUSED** | ggen 26.11.5 EXIT=1 `REFUSED:HANDS_FREE_TWIN_DRIFT eligible-set mismatch mix=['FRI-FMT-A'] hands_free=[]` (Mix↔Rust `authority_index_unavailable`). Missing ggen still REFUSE: EXIT=1 `REFUSED:HANDS_FREE … exited 127` |
| hands-free twin court (Chicago) | **PASS** | 3/3: match PASS; FLIP mismatch REFUSES `HANDS_FREE_TWIN_DRIFT`; `--self-test` PASS |
| live execute / complete | **BLOCKED** | EXIT=2 without operator pack/target (see below) |

### Twin law (blocking on evidence)

Eligible identity sets from Mix frontier and hands-free frontier must be equal
before evidence PASS. Divergence is typed `REFUSED:HANDS_FREE_TWIN_DRIFT`
(`scripts/sjira/hands_free_twin_parity.py`). Prior vacuous JSON-ok EXIT=0 with
Mix `eligible=1` vs Rust `eligible=[]` is closed.

### Live BLOCKED — exact refuse conditions

`just sjira-loop live` exits **2** (`INVALID:…`) unless all of:

1. Backend (exactly one): `SJIRA_PACK_DIR` **or** `SJIRA_PACKS_ROOT` **or** `SJIRA_RECEIPT`
2. `SJIRA_VERIFIER_SUITE` (non-empty)
3. `SJIRA_ALIAS` (`owner/repo=alias`)
4. For local/complete: `SJIRA_TARGET_DIR` (and for complete drain: writable receipts dir)
5. For external backend without identity: refused — `SJIRA_RECEIPT` requires `SJIRA_IDENTITY`

Even with env present, live is **destructive** (pack sync / gate verify / ledger append / target HEAD check). No sealed sandbox fixture pack+target was admitted for GAP9; therefore live is documented **BLOCKED** pending operator-supplied temp target + verifier suite, not faked green.

## Authority

- Builder: skeptic L19 twin-vacuity close (eligible-set parity + Chicago flip court).
- Prior O→A→F dry-run remains green on friday fixture.
- Evidence hop with live ggen 26.11.5 is now honestly REFUSED until Rust twin admits the same eligible set (authority index).

## Consequence

- `autonomic_loop.sh` invokes `hands_free_twin_parity.py` after hands-free parse.
- Court proves discrimination: match EXIT=0, mismatch EXIT=1 `HANDS_FREE_TWIN_DRIFT`.
- O→A→F dry-run PASS; evidence with current ggen REFUSED; live BLOCKED → Standing **PARTIAL**.

## Replay

```sh
cd /Users/sac/ggen_igniter

# Court (match PASS + mismatch REFUSE):
MIX_ENV=test mix test test/ggen_igniter_semantic_jira_hands_free_twin_court_test.exs
# → Result: 3 passed, EXIT=0

python3 scripts/sjira/hands_free_twin_parity.py --self-test
# → EXIT=0

# Mix O→A→F (no cross-check):
export SJIRA_OUT_DIR=$(mktemp -d)
export SJIRA_LEDGER=$SJIRA_OUT_DIR/ledger.jsonl
python3 -c '
import json,sys
doc=json.load(open("test/fixtures/semantic_jira/friday_work_orders.json"))
open(sys.argv[1],"w").writelines(json.dumps(w,separators=(",",":"))+"\n" for w in doc["work_orders"])
' "$SJIRA_OUT_DIR/candidates.jsonl"
export SJIRA_CANDIDATES=$SJIRA_OUT_DIR/candidates.jsonl
just sjira-loop dry-run; echo EXIT:$?   # expect 0

# Twin evidence with live ggen (expect REFUSE until Rust eligible matches):
export GGEN_BIN="$HOME/.local/bin/ggen"
just sjira-loop-evidence; echo EXIT:$?  # expect 1 HANDS_FREE_TWIN_DRIFT

# Live BLOCKED:
just sjira-loop live; echo EXIT:$?      # expect 2
```

## Standing

**PARTIAL** — Mix O→A→F friday dry-run EXIT=0 `dry_run_ok`. Hands-free twin court
EXIT=0 (3/3; mismatch FLIPS to `REFUSED:HANDS_FREE_TWIN_DRIFT`). Live ggen evidence
EXIT=1 twin drift (honest refuse, not vacuous JSON-ok PASS). Live execute remains
**BLOCKED** (EXIT=2). Not full-loop ALIVE.
