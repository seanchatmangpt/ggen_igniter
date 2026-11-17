# Lane 12: Ash Integration Boundary

Standing: UNVERIFIED

Read-only exploration of the Ash dev+test-only boundary, AGENTS.md doctrine, the
`refuse-handwritten-ash.sh` hook and `docs/integrations/ash/`. The `mix.exs` scoping
matches the docs and no `lib/` module declares an Ash surface. The hook was fed
fifteen payloads by hand: four forms of Ash declaration got through (A4-A8). No
`mix test`, `mix compile` or `mix hex.build` ran, so test-backed claims are UNVERIFIED.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| A1 | Ash deps are `only: [:dev, :test]` | VERIFIED | `mix.exs:251-266` |
| A2 | overview.md cites `mix.exs:176-177`; real lines 251-252 | VERIFIED | `overview.md:172-174` |
| A3 | No `lib/` file declares `use Ash.Resource`/`Domain` | VERIFIED | grep, string text only |
| A4 | `use Elixir.Ash.Resource` passes the hook | VERIFIED | piped JSON, rc=0 |
| A5 | `alias Ash.Resource, as: R` then `use R` passes | VERIFIED | piped JSON, rc=0 |
| A6 | `Ash.Notifier`, `Ash.Type.Enum`, `Ash.Reactor` pass | VERIFIED | rc=0; regex line 209 |
| A7 | Hook wired to `Edit\|Write` only; Bash writes bypass | VERIFIED | `settings.json:27-31` |
| A8 | `*/lib/mix/tasks/*` allowlist exempts any content | VERIFIED | hook line 180; rc=0 |
| A9 | `*/test/*.exs` allowed; comment concedes it | VERIFIED | hook lines 183-188 |
| A10 | `test/**/*.ex` blocked; e2e files contain `use Ash.` | VERIFIED | rc=2; grep hits |
| A11 | Block msg cites a fixture dir that does not exist | VERIFIED | hook 232; `ls` |
| A12 | Block msg says `sync --pack-dir`; CLAUDE.md says `--pack` | UNVERIFIED | hook line 239 |
| A13 | Malformed JSON falls back to raw scan, fails closed | VERIFIED | rc=2; hook 143-147 |
| A14 | Guard test file has 25 cases; none cover A4-A6 | VERIFIED count | `grep -c 'test "'` |
| A15 | `state-machine-pack` has `use Ash.*` template, ships | UNVERIFIED | `mix.exs:157-170` |
| A16 | Ash-free hex test not run here | UNVERIFIED | `package_ash_free_test.exs` |
| A17 | Five Ash packs; docs lack per-pack coverage matrix | VERIFIED | `ls` both dirs |
| A18 | overview.md says "18 capabilities"; not re-derived | UNVERIFIED | `overview.md:145` |
| A19 | status.md: ash-igniter-api-pack drops missing `resourceOf` | UNVERIFIED | `status.md:155` |
| A20 | Doctor `--fix` Ash-absent behaviour not exercised | UNVERIFIED | `doctor_fixes.ex:563-596` |

A3 detail: `grep -rln "use Ash\.\(Resource\|Domain\)"` matched priv templates and
test files, plus `doctor_fixes.ex:563,654` and `ggen_igniter.doctor.ex:32` where the
text is a string, not a declaration. A15 detail: `mix.exs` excludes names containing
"ash", so packs without it in the name are not fenced by name.

## Next

1. Decide if A4/A5 are in scope; extend the regex at hook line 209 and add tests.
2. Decide if `Ash.Notifier`, `Ash.Type`, `Ash.Reactor` are "Ash surfaces"; state
   the answer in AGENTS.md.
3. Fix the stale block-message path (A11) and confirm `--pack-dir` (A12).
4. Fix the `mix.exs:176-177` cite in overview.md (A2).
5. Document A7 (Bash writes unguarded) in AGENTS.md, or inspect Bash content.
6. Run the guard and ash-free tests and paste output to settle A14, A16.
7. Inspect the tarball via `mix hex.build --unpack` for A15.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `AGENTS.md`
- `.claude/hooks/refuse-handwritten-ash.sh`
- `docs/integrations/ash/overview.md`
- `docs/status.md`
