# L20 evidence twin green
Standing: PASS

Subject: close `REFUSED:HANDS_FREE_TWIN_DRIFT` so dogfood dry→evidence EXIT=0.

## Root cause

Installed `ggen` CLI left `--authority` unset → kernel `None` → every order
`authority_index_unavailable` → HF `eligible=[]` while Mix `eligible=['FRI-FMT-A']`.

## Fix (ggen product)

`crates/ggen-cli/src/cmds/sjira.rs` `frontier`: absent `--authority`, load
`ggen_sjira::canonical_index()` (Elixir `Authority.index_from/1` / reconcile
parity). Commit `fd4f99bbd4971fb1ca5a0f3a3a2382aaba32261e`. Binary installed to
`~/.local/bin/ggen`.

## Loop exits (tool, friday fixture)

| Hop | EXIT |
|---|---|
| `just sjira-loop-dry` | 0 |
| `just sjira-loop-evidence` | 0 |

Parity line from tool: `hands-free twin parity: ok eligible=['FRI-FMT-A']`

## loop_receipt excerpt (tool)

Path: `docs/sjira/v26.11.19/receipts/L20-evidence-loop_receipt.json`

```json
{
  "status": "dry_run_ok",
  "standing": "UNVERIFIED",
  "eligible_count": 1,
  "blocked_count": 1,
  "chain": [
    "observe_skipped",
    "admit_candidates",
    "frontier",
    "hands_free_frontier"
  ],
  "evidence": {
    "admitted_digest": "sha256:5f60b630dadedf57d71bcae80f55ca71603afda49b7cb7d1555106fbd2be8a32",
    "candidates_digest": "sha256:5f60b630dadedf57d71bcae80f55ca71603afda49b7cb7d1555106fbd2be8a32",
    "frontier_digest": "sha256:b21791675c140bd39dd1cc13d1bceb39c85026f3849f688c3d6d331efc97eeae",
    "hands_free_frontier_digest": "sha256:6f5753b0995c4f6f90c1e5d0364ae2fd2ead6388c7863ed031f20253ce80931d",
    "work_orders_digest": "sha256:ce5a049c3c653ab5fdb104231e70460c48421e69952b848b2cb081085d0c9a6f"
  },
  "loop_digest": "sha256:1a4ccb86ad56068a7bd2b62a26ae6a10badf08e9e573984654c72c0d782ba652",
  "mode": "dry-run"
}
```

(`standing: UNVERIFIED` is the dry-run tool ceiling; hop EXIT=0 + parity ok is the
dogfood progress bar.)

## SHA

- ggen: `fd4f99bbd4971fb1ca5a0f3a3a2382aaba32261e`
- ggen_igniter: (this land commit)
