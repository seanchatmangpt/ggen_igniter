# code-alignment — ggen_igniter v26.11.17

Standing: PASS

## Identity
- Path: `/Users/sac/ggen_igniter`
- Branch at generation: main
- HEAD: df4c9f00bc08c741e4940ce71c96641a6f9062c1
- Tracked files: 1825
- Tracked docs markdown: 392

## Build manifests (tracked at the commit above)
- `mix.exs`
- `.tool-versions`
- `CLAUDE.md`
- `AGENTS.md`
- `README.md`

## Top-level layout (tracked file counts)
- `.`: 20
- `.claude`: 32
- `.github`: 12
- `bench`: 1
- `config`: 6
- `docs`: 438
- `ggen-manufactured`: 1
- `lib`: 226
- `native`: 9
- `notes`: 4
- `priv`: 322
- `receipts`: 119
- `release`: 4
- `scripts`: 5
- `test`: 622
- `wasm-artifacts`: 4

## Prior doc waves
- `docs/jira/v26.11.12`
- `docs/jira/v26.11.13`
- `docs/jira/v26.11.16`

## Falsifiers
- Any tracked path above absent at HEAD, or a count differing from `git ls-files`.
- HEAD sha not equal to or an ancestor of the live HEAD.

## Acceptance
```bash
python3 ~/zcode-cli/scripts/docs_v261117.py validate /Users/sac/ggen_igniter
```
Expected: exit 0 and `PASS`.

## See Also
- `~/zcode-cli/scripts/docs_v261117.py`
