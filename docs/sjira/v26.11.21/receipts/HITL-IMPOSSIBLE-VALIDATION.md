# HITL-IMPOSSIBLE validation (dry / evidence / frontier)

Re-derived on 2026-11-21 (UTC) in this cloud VM. SoT is the loop-produced
receipts under `hitl-impossible/` and the EXIT lines below, not agent prose.
**Fabric is not ALIVE. Bare live is not PASS. Marketplace is not a blocker.**

## Identity

| Surface | Value |
|---|---|
| ggen checkout | `/home/ubuntu/src/ggen` `origin` `seanchatmangpt/ggen` |
| ggen `HEAD` / `origin/main` | `d173cad5792e837bd4fec730d120c582b9bc5d4c` (merge PR #827) |
| hands-free floor | `fd4f99bbd4971fb1ca5a0f3a3a2382aaba32261e` |
| `merge-base --is-ancestor fd4f99bbd… origin/main` | **ancestor_exit=0** (8 commits after the floor) |
| `GGEN_BIN` | `/home/ubuntu/.local/bin/ggen` built from that tip |
| `ggen --version` | `ggen 26.11.5` |
| pre-floor falsifier binary | `/home/ubuntu/.local/bin/ggen-prefloor` — same tip with `crates/ggen-cli/src/cmds/sjira.rs` replaced by the blob at parent `31ba588e1424cfe2275e2f3fbb51fe538fb7718f` (the only production file `fd4f99bbd` changed). Source restored after the build; `git status` clean. |
| igniter checkout | `/workspace` `seanchatmangpt/ggen_igniter` |
| igniter `HEAD` / `origin/main` | `b0cb7ac725e116fe0ca73cc67789cba86c54661e` (PR #58; ancestor_exit=0) |
| Elixir / OTP / just | Mix 1.20.4, OTP 29 (`erlang 29.1.2` from `.tool-versions`), just 1.59.0 |
| xaas | this VM's GitHub token gets HTTP 404 on `seanchatmangpt/xaas`. Phase 4 was started on an approved cloud checkout and is **not pasted here yet**. |

## Phase 1 — ggen frontier without `--authority`

Happy path (friday orders, **no** authority flag):

```text
"$GGEN_BIN" sjira frontier --orders-path friday_orders.json --format json
EXIT:0
eligible ['FRI-FMT-A']
blocked [('FRI-FMT-B', 'dependencies_unsatisfied')]
eligible_count 1
```

`sjira frontier --help` states absent `--authority-path` loads the embedded
canonical index. The clap flag is `--authority-path` (not `--authority`).

Courts (`cargo test --release`, sccache wrapper disabled, `CXX=g++`):

| Command | EXIT | Result |
|---|---|---|
| `-p ggen-sjira --test reconcile_test none_authority_hands_free` | 0 | `none_authority_hands_free_admits_canonical_pack_origin` ok (1 passed) |
| `-p ggen-sjira --lib authority` | 0 | 5 passed (`canonical_index_admits_three_pack_objectives`, pack missing falls back, corrupt pack refuses, …) |
| `-p ggen-cli-lib --test cli_sjira_test hands_free` | 0 | 3 passed (`frontier_hands_free_admits_canonical_code_work_origin`, both reconcile hands-free tests) |
| `-p ggen-cli-lib --test cli_sjira_test frontier_without_authority` | 0 | `frontier_without_authority_uses_canonical_index` ok |

Falsifiers:

| Probe | EXIT | What happened |
|---|---|---|
| 1a missing `--authority-path` | 1 | `cannot read … no such file` — no prompt |
| 1a non-JSON `--authority-path` | 1 | `not valid JSON` — no prompt |
| 1a `--authority` (wrong flag name) | 1 | `unexpected argument '--authority'` — no prompt |
| 1b pre-floor binary, no authority flag | 0 JSON, empty eligible | both orders `authority_index_unavailable` |
| 1b pre-floor as `GGEN_BIN` on evidence twin | 1 | `REFUSED:HANDS_FREE_TWIN_DRIFT` `mix=['FRI-FMT-A'] hands_free=[]` |
| 1c `dialoguer` / `stdin()` / `read_line` / `Confirm` in `ggen-cli/src/cmds/sjira.rs` and `ggen-sjira/src` | — | no hits |

The pre-floor CLI still exits 0 because "blocked" is the kernel's typed JSON
answer. The floor is load-bearing because that empty eligible set **cannot**
twin with Mix: the evidence loop refuses `HANDS_FREE_TWIN_DRIFT`.

## Phase 2 — igniter dry + evidence

Friday candidates rebuilt from `test/fixtures/semantic_jira/friday_work_orders.json`
(no hand-edited eligible set). `GGEN_BIN` = the post-floor binary above.

| Command | EXIT | Receipt |
|---|---|---|
| `just sjira-loop dry-run` | **0** | `hitl-impossible/dry-loop_receipt.json` `status=dry_run_ok` admit 2/0 eligible=1 |
| `just sjira-loop-evidence` | **0** | `hitl-impossible/evidence-loop_receipt.json` |
| `mix test test/ggen_igniter_semantic_jira_hands_free_twin_court_test.exs` | **0** | 3 passed |
| `python3 scripts/sjira/hands_free_twin_parity.py --self-test` | **0** | `self-test: match PASS + mismatch REFUSED:HANDS_FREE_TWIN_DRIFT` |

Evidence stdout (loop-produced):

```text
frontier: eligible=1 blocked=1
hands-free frontier: parsed bytes=827
hands-free twin parity: ok eligible=['FRI-FMT-A']
```

Digests (byte-identical to the L04/L20/L21 frontier digests):

- candidates / admitted: `sha256:5f60b630dadedf57d71bcae80f55ca71603afda49b7cb7d1555106fbd2be8a32`
- work_orders: `sha256:ce5a049c3c653ab5fdb104231e70460c48421e69952b848b2cb081085d0c9a6f`
- frontier: `sha256:b21791675c140bd39dd1cc13d1bceb39c85026f3849f688c3d6d331efc97eeae`
- hands_free_frontier: `sha256:6f5753b0995c4f6f90c1e5d0364ae2fd2ead6388c7863ed031f20253ce80931d`

Recipes do not pass `--authority` / `--authority-path` / `--authority-graph`.
No `IO.gets`, `read -p`, or "please provide" / "run this manually" in
`scripts/sjira` or the admit/frontier/complete Mix tasks.

Falsifiers:

| Probe | EXIT | Typed result |
|---|---|---|
| 0a `GGEN_BIN` unset, PATH has no `ggen` | 1 | `ggen: command not found` then `REFUSED:HANDS_FREE frontier cross-check exited 127` |
| 0b pre-floor `ggen` earlier on PATH, `GGEN_BIN` unset | 1 | `REFUSED:HANDS_FREE_TWIN_DRIFT` (not a happy twin) |
| 0b `GGEN_BIN` = good binary, same decoy still first on PATH | 0 | `hands-free twin parity: ok eligible=['FRI-FMT-A']` (PATH ignored) |
| 2a `GGEN_BIN` = pre-floor | 1 | `REFUSED:HANDS_FREE_TWIN_DRIFT` |
| 2b real evidence `frontier.json` vs a copy of `hands_free_frontier.json` with `eligible=[]` | 1 | `REFUSED:HANDS_FREE_TWIN_DRIFT eligible-set mismatch mix=['FRI-FMT-A'] hands_free=[]` |

`autonomic_loop.sh` does `ggen_bin=${GGEN_BIN:-ggen}` when
`SJIRA_HANDS_FREE_BIN` is unset. That is a PATH lookup. It is **not**
fail-open: a missing binary is `REFUSED:HANDS_FREE`, and a pre-floor binary
cannot pass eligible-set parity. Definition 3 (silent success on the wrong
`ggen`) did not reproduce.

## Phase 3 — live-sandbox honesty

`just sjira-loop-live-sandbox` **EXIT 0**. Loop receipt
`hitl-impossible/live-sandbox-loop_receipt.json`:

- `status=live_ok`
- execute `outcome=partial_alive`
- execute `target=PARTIAL_ALIVE` / event `to=PARTIAL_ALIVE`
- `head_verified=false`
- loop `standing=UNVERIFIED`

Nothing in that receipt claims fabric ALIVE. `head_verified` is false.

Bare `just sjira-loop live` fail-closed, no wizard. Real exits, in order:

| Env state | EXIT | First typed miss |
|---|---|---|
| no env | 2 | `INVALID:SJIRA_OUT_DIR is required` |
| `SJIRA_OUT_DIR` set, ledger unset | 2 | `INVALID:SJIRA_LEDGER is required` |
| OUT + LEDGER + friday candidates | 2 | `INVALID:live mode needs SJIRA_PACK_DIR\|SJIRA_PACKS_ROOT\|SJIRA_RECEIPT` |
| plus `SJIRA_PACK_DIR` | 2 | `INVALID:SJIRA_VERIFIER_SUITE required for live` |
| plus `SJIRA_VERIFIER_SUITE=ci` | 2 | `INVALID:SJIRA_ALIAS=owner/repo=alias required for live` |
| plus `SJIRA_ALIAS` (no `SJIRA_IDENTITY`, so complete-drain) | 2 | `INVALID:SJIRA_TARGET_DIR required for complete` |

Stopped there. Did not invent `INTERNAL_API_TOKEN` or a verifier suite secret.

## Phase 4 — xaas

Not re-derived in this checkout. `gh api repos/seanchatmangpt/xaas` returned
404 and `git ls-remote` returned "Repository not found" for this VM's token.
A cloud agent was started on the already-approved `xaas` repo to re-run the
facade / dogfood courts and the `:ggen_not_found` miss. **Those exits are not
in this file.** Do not read admit-dogfood PASS as fabric ALIVE. Tony-gated
fabric remains an honest **BLOCKED** residual until that agent pastes a
receipt. This section must be amended with real exits before anyone treats
the xaas matrix rows as closed.

## Matrix

| Surface | Command | Human flag required? | Interactive? | EXIT | Receipt | HITL? |
|---|---|---|---|---|---|---|
| ggen frontier, no authority flag | `ggen sjira frontier --orders-path … --format json` | no | no | 0 | eligible `FRI-FMT-A` | no |
| igniter dry-run | `just sjira-loop dry-run` | no | no | 0 | `hitl-impossible/dry-loop_receipt.json` | no |
| igniter evidence twin | `just sjira-loop-evidence` | no | no | 0 | `hitl-impossible/evidence-loop_receipt.json` | no |
| igniter twin court | `mix test …hands_free_twin_court_test.exs` | no | no | 0 | 3 passed | no |
| igniter live-sandbox | `just sjira-loop-live-sandbox` | no | no | 0 | `partial_alive`, `head_verified=false`, `standing=UNVERIFIED` | no |
| igniter bare live | `just sjira-loop live` | no | no | 2 | `INVALID:SJIRA_OUT_DIR is required` (then the key walk above) | no |
| evidence, `GGEN_BIN` unset, no PATH `ggen` | `just sjira-loop-evidence` | no | no | 1 | `REFUSED:HANDS_FREE` / exit 127 | no |
| xaas `GGEN_BIN` miss | not re-run here | — | — | — | pending cloud checkout | not claimed |
| xaas admit dogfood | not re-run here | — | — | — | pending; admit ≠ ALIVE | not claimed |

## Residuals that are not HITL

1. **Bare live** — fail-closed on the env keys listed above. Not a prompt.
2. **live-sandbox** — `PARTIAL_ALIVE` / `outcome=partial_alive` / `standing=UNVERIFIED` / `head_verified=false`. Not ALIVE.
3. **Tony fabric / auth live** — still **BLOCKED**. This agent did not have `INTERNAL_API_TOKEN`, a registered `SJIRA_VERIFIER_SUITE`, or a real epoch worktree, and did not ask for them. Phase 4's re-run is outstanding on the xaas checkout; that does not promote fabric to ALIVE.
4. Marketplace was not treated as a finish blocker.

## Verdict

`VERDICT: HITL_IMPOSSIBLE_ON_DRY_EVIDENCE_FRONTIER`

Happy-path frontier, dry-run, and evidence twin need no `--authority` /
`--authority-path`, no hand-authored authority file, no TTY confirm, and no
human-curated eligible set. A missing or pre-floor `ggen` refuses. Fabric
ALIVE is not claimed.
