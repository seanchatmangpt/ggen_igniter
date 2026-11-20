# L21 cloud-agent autonomic ladder re-run

Standing: PASS (dry + evidence) / PARTIAL_ALIVE (live-sandbox) / BLOCKED (bare live + fabric)

Subject: `/agent/repos/ggen_igniter` cloud-agent checkout
`cursor/sjira-residue-finish-6fdc`. Replay of WAVE-L04 / L20 courts in this
environment. SoT is loop-produced receipts under `L21-cloud-agent-rerun/`, not
agent-authored PASS claims. **PARTIAL_ALIVE ceiling stands. Fabric not ALIVE.**

## Identity

| Surface | Value |
|---|---|
| Repo HEAD (pre-receipt commit) | this branch tip |
| `GGEN_BIN` | `/home/ubuntu/.local/bin/ggen` built from ggen `fd4f99bbd4971fb1ca5a0f3a3a2382aaba32261e` (`ggen 26.11.5`) |
| Skew | none — binary is exactly the canonical frontier-authority fix commit |
| Elixir / OTP | 1.20.4 / 29.1.2 (matches `.tool-versions`) |
| just | 1.46.0 |

## Ladder (this session)

| Hop | Command | Exit | Standing / note |
|---|---|---|---|
| Mix dry-run | `just sjira-loop dry-run` + friday candidates | **0** | `dry_run_ok`; admit 2/0; eligible=1 blocked=1 |
| Evidence twin | `just sjira-loop-evidence` + `GGEN_BIN`@`fd4f99bbd` | **0** | twin parity ok `eligible=['FRI-FMT-A']` |
| Twin vacuity court | `mix test …hands_free_twin_court_test.exs` | **0** | 3/3 |
| Twin self-test | `hands_free_twin_parity.py --self-test` | **0** | match PASS + mismatch REFUSE |
| live-sandbox | `just sjira-loop-live-sandbox` | **0** | `live_ok`; execute `outcome=partial_alive` → **PARTIAL_ALIVE**; loop `standing=UNVERIFIED` |
| bare live (no env) | `just sjira-loop live` | **2** | `INVALID:SJIRA_OUT_DIR is required` |
| bare live (OUT+LEDGER+friday candidates) | same | **2** | `INVALID:live mode needs SJIRA_PACK_DIR\|SJIRA_PACKS_ROOT\|SJIRA_RECEIPT` |
| Fabric / auth live (Tony) | — | — | **BLOCKED (Tony)** — external; not dogfood-closed |

## Digests (evidence hop)

From `L21-cloud-agent-rerun/evidence-loop_receipt.json` — byte-identical to L04/L20
frontier digests:

- candidates/admitted: `sha256:5f60b630dadedf57d71bcae80f55ca71603afda49b7cb7d1555106fbd2be8a32`
- work_orders: `sha256:ce5a049c3c653ab5fdb104231e70460c48421e69952b848b2cb081085d0c9a6f`
- frontier: `sha256:b21791675c140bd39dd1cc13d1bceb39c85026f3849f688c3d6d331efc97eeae`
- hands_free_frontier: `sha256:6f5753b0995c4f6f90c1e5d0364ae2fd2ead6388c7863ed031f20253ce80931d`

## In-repo code residue closed this pass

- **Gate census drift** — `priv/ggen/semantic-jira-pack/gates/` has **19**
  witnesses after `070_cli_tasks.rq` + `071_cli_options.rq` (v26.11.19
  gap-close), but `test/ggen_igniter_pack_test.exs` and
  `test/ggen_igniter_semantic_jira_pack_test.exs` still asserted `== 17`.
  Updated to `== 19`. Hybrid `tera_pack?` law and twin parity already landed
  (L04/L20). No Ash hand-writes. No fabric ALIVE claim.

## Full-suite gate note (this VM)

`mix compile --warnings-as-errors` EXIT 0. Full `mix test` once reported 7
failures under load: pack census (fixed above), mutual frontier-shape court
(needs sibling `../ggen` checkout — ENV), and 4 mix-subprocess timeouts that
pass in isolation. Not introduced by L21 doc/receipt edits.

## Residuals that belong outside this repo

1. **ggen / xaas fabric verifier** — live-sandbox stays PARTIAL_ALIVE until an
   exact-head fabric receipt can promote standing; Tony fabric/auth live remains
   BLOCKED.
2. **Bare `just sjira-loop live`** — fail-closed on missing pack/target keys by
   design; not an igniter defect (env contract in `L04-live-sandbox-residual.md`).
3. **PR open** — branch pushed; `gh`/`ManagePullRequest` create blocked
   (`Resource not accessible by integration`). Operator: open from
   https://github.com/seanchatmangpt/ggen_igniter/pull/new/cursor/sjira-residue-finish-6fdc

## Standing

Autonomic ladder green in this checkout. live-sandbox **PARTIAL_ALIVE**. Bare
live + fabric remain **BLOCKED**. Not demoting COMPLETE. Not fake ALIVE.
