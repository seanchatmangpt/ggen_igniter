# L04 sjira-loop O→A→F + twin evidence + live sandbox

Standing: PASS

## Subject

- Repo: `/Users/sac/ggen_igniter`
- Product fix (ggen CLI canonical frontier authority): `fd4f99bbd4971fb1ca5a0f3a3a2382aaba32261e`
- Product fix (live sandbox): `scripts/sjira/live_sandbox.sh` + `just sjira-loop-live-sandbox` + `test/fixtures/semantic_jira/live_sandbox_pack/`
- Loop SoT (this directory): `L04-loop_receipt.json`, `L04-live-sandbox-loop_receipt.json`

## Hop table (loop-produced)

| Hop | Command | Exit | Evidence |
|---|---|---|---|
| Mix O→A→F dry-run | `just sjira-loop dry-run` + friday candidates | **0** | `status=dry_run_ok`; admit 2/0; eligible=1 blocked=1 |
| Twin vacuity court | `mix test …hands_free_twin_court_test.exs` | **0** | 3 passed (`L04-twin-court.log`) |
| Twin self-test | `hands_free_twin_parity.py --self-test` | **0** | match PASS + mismatch REFUSE |
| Evidence (hands-free twin) | `just sjira-loop-evidence` + ggen post-`fd4f99bbd` | **0** | twin parity ok `eligible=['FRI-FMT-A']`; digests in `L04-loop_receipt.json` |
| Bare `just sjira-loop live` (no env) | `just sjira-loop live` | **2** | `INVALID:live mode needs SJIRA_PACK_DIR|…` (honest) |
| Live sealed sandbox | `just sjira-loop-live-sandbox` | **0** | `status=live_ok`; execute `PARTIAL_ALIVE`; `L04-live-sandbox-loop_receipt.json` |

## Digests (evidence hop)

From `L04-loop_receipt.json`:

- candidates/admitted: `sha256:5f60b630dadedf57d71bcae80f55ca71603afda49b7cb7d1555106fbd2be8a32`
- work_orders: `sha256:ce5a049c3c653ab5fdb104231e70460c48421e69952b848b2cb081085d0c9a6f`
- frontier: `sha256:b21791675c140bd39dd1cc13d1bceb39c85026f3849f688c3d6d331efc97eeae`
- hands_free_frontier: `sha256:6f5753b0995c4f6f90c1e5d0364ae2fd2ead6388c7863ed031f20253ce80931d`
- loop_digest: `sha256:b49e467298bfc20e2c0da9ff522baee0b906091c28fe205afd1ba912019d16b6`

## Live sandbox (PARTIAL_ALIVE ceiling)

- identity `EXEC-SANDBOX-1` → `to=PARTIAL_ALIVE`, `head_verified=false` (honest local ceiling; not fabric ALIVE)
- See `L04-live-sandbox-loop_receipt.json` / `L04-live-sandbox-execute_result.json`

## Standing

**PASS** for WAVE-L04 sjira-loop dogfood (dry + evidence twin + sealed live sandbox).
Not wave COMPLETE. Not fabric ALIVE. Bare live without sandbox env remains EXIT=2.
