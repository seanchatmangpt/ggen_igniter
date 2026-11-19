# L04 live-sandbox reconfirm + bare-live residual

Standing: PARTIAL_ALIVE

Subject: `/Users/sac/ggen_igniter` @ `36cd5bd` (pre-note HEAD). Dogfood law:
live-sandbox honest PASS/PARTIAL_ALIVE; bare live may stay Tony-BLOCKED. No live PASS.

## Reconfirm (this session)

| Surface | Command | Exit | Standing / note |
|---|---|---|---|
| live-sandbox | `just sjira-loop-live-sandbox` | **0** | `live_ok`; execute `outcome=partial_alive` → `PARTIAL_ALIVE`; loop `standing=UNVERIFIED` until fabric verifier |
| bare live (no env) | `just sjira-loop live` | **2** | `INVALID:SJIRA_OUT_DIR is required` |
| bare live (OUT+LEDGER+friday candidates) | same | **2** | `INVALID:live mode needs SJIRA_PACK_DIR\|SJIRA_PACKS_ROOT\|SJIRA_RECEIPT` |

Artifacts: `L04-live-sandbox-loop_receipt.json`, `L04-bare-live-noenv.log`,
`L04-bare-live-packkeys.log`. Hybrid `tera_pack?` fix did not break sandbox.

## Residual — exact env keys for bare `just sjira-loop live` (no secrets)

Always:

- `SJIRA_OUT_DIR`
- `SJIRA_LEDGER`

Inputs (one path):

- `SJIRA_CANDIDATES` **or** observe set: `SJIRA_FINDING` + `SJIRA_BASE_WORK_ORDER` + `SJIRA_ORIGIN_AUTHORITY`

Live backend (exactly one):

- `SJIRA_PACK_DIR` **or** `SJIRA_PACKS_ROOT` **or** `SJIRA_RECEIPT`

Live always:

- `SJIRA_VERIFIER_SUITE`
- `SJIRA_ALIAS` (`owner/repo=alias`)

Local / complete backend:

- `SJIRA_TARGET_DIR`
- `SJIRA_RECEIPTS_DIR` (drain / complete)

Optional / path-specific:

- `SJIRA_IDENTITY` (single execute; required when backend is `SJIRA_RECEIPT`)
- `SJIRA_BRIDGE` + `SJIRA_XAAS_RECEIPT` (external receipt hop)

Hands-free substitute (no operator pack/target): `just sjira-loop-live-sandbox`.

Fabric / auth live remains **BLOCKED (Tony)** — not claimed PASS. Not demoting any COMPLETE.
