# L04 Friday fixture hardening (hybrid pack + GoalCheckpoint court)

Standing: PASS

## Subject

- Repo: `/Users/sac/ggen_igniter`
- Parent HEAD before land: `ba31e9be666e92805c6464b5ad321702ec27150c`
- Lane: WAVE-L04 (sjira-loop O→A→F + friday fixtures)

## Defect closed

`priv/ggen/semantic-jira-pack` is a hybrid pack (classic `*.eex` + one additive
`doc_work_order.ttl.tera`). `PackFrontmatter.Sync.tera_pack?/1` treated any
Tera body as sufficient, so `mix ggen_igniter.sync --pack semantic-jira-pack:jira`
dispatched onto FM-PACK-013 **inverted** gate polarity and refused every
ADR-0010 witness `gates/*.rq` row as a "violation". Friday GoalCheckpoint
Chicago court failed 6/39 under `--include integration`.

## Fix

1. `lib/ggen_igniter/pack_frontmatter/sync.ex` — `tera_pack?/1` is true only for
   **pure** Tera packs (no `templates/*.eex`).
2. `test/.../goal_checkpoint_test.exs` — `render_ticket!/2` binds
   `Pack.discover_unbound_queries/1` (same merge as sync); census pins
   shapes=27, orders=36, sync md=37 (pack + GC-FIXTURE).
3. `test/.../dispatch_test.exs` — hybrid semantic-jira-pack must `refute tera_pack?`.

## Courts (this session)

| Court | Exit | Notes |
|---|---|---|
| `mix test …goal_checkpoint_test.exs …dispatch_test.exs --include integration` | **0** | 44 passed |
| stock `mix ggen_igniter.sync --pack semantic-jira-pack:jira` | **0** | wrote 36 md |
| friday `just sjira-loop dry-run` | **0** | `dry_run_ok` admit 2/0 eligible=1 blocked=1 |
| `just sjira-loop-evidence` (`GGEN_BIN=~/.local/bin/ggen`) | **0** | twin parity `eligible=['FRI-FMT-A']` |
| bare `just sjira-loop live` | **2** | `INVALID:live mode needs SJIRA_PACK_DIR\|SJIRA_PACKS_ROOT\|SJIRA_RECEIPT` |
| missing ggen evidence | **1** | `REFUSED:HANDS_FREE … 127` |

## Live BLOCKED — exact env keys missing locally

Refreshed residual (full key list, no secrets):
`receipts/L04-live-sandbox-residual.md`. Summary:

1. Always: `SJIRA_OUT_DIR`, `SJIRA_LEDGER`
2. Inputs: `SJIRA_CANDIDATES` **or** observe (`SJIRA_FINDING` + `SJIRA_BASE_WORK_ORDER` + `SJIRA_ORIGIN_AUTHORITY`)
3. Backend (exactly one): `SJIRA_PACK_DIR` **or** `SJIRA_PACKS_ROOT` **or** `SJIRA_RECEIPT`
4. `SJIRA_VERIFIER_SUITE`
5. `SJIRA_ALIAS` (`owner/repo=alias`)
6. Local/complete: `SJIRA_TARGET_DIR` (+ `SJIRA_RECEIPTS_DIR` when draining)
7. External receipt path: `SJIRA_IDENTITY` when backend is `SJIRA_RECEIPT`

Fabric/auth live remains **BLOCKED (Tony)**. live-sandbox stays
**PARTIAL_ALIVE** via `just sjira-loop-live-sandbox` (not bare live PASS).

## Standing

**PASS** — Friday GoalCheckpoint Chicago green; O→A→F+evidence green;
live-sandbox **PARTIAL_ALIVE**; bare live honestly **BLOCKED** with exact keys.
Not demoting COMPLETE.
