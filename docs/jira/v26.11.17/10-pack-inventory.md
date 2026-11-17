# Pack Inventory (priv/ggen census)

Standing: UNVERIFIED

Lane 10 of v26.11.17. Read-only census of `priv/ggen/`: 27 pack
directories. Checked by `ls`, `find`, and `grep -rl` only; no pack was synced and no test
was run, so no pack is claimed to work. Counts below are directory facts, not behavior.
Shape drift is small: every `.rq` is under `gates/` or a named sibling dir, and every
template is `*.<ext>.eex`. The gaps are documentation and test coverage. Five packs are
absent from `docs/reference/cli/packs.md` and `docs/status.md`. One directory
(`doctrine-canonical-source`) is not a pack by the `CLAUDE.md` shape. One pack
(`dfcm-agent-pack`) has no reference in `lib/` or `test/`.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| P-01 | 27 dirs; 26 have ontology, gates/, templates/ | UNVERIFIED | `ls priv/ggen`; per-pack ls loop |
| P-02 | `doctrine-canonical-source` is only contract.json; not a pack | UNVERIFIED | `ls` of dir; grep lib test: none |
| P-03 | `dfcm-agent-pack` not named in lib/ or test/ | UNVERIFIED | `grep -rl dfcm-agent-pack test lib`: empty |
| P-04 | 5 packs missing from packs.md and status.md | UNVERIFIED | `grep -c`=0: dfcm, gall_work, castle, canon, lifecycle |
| P-05 | test-named pack `ash-lifecycle-...-dispatch-test` in priv/ | UNVERIFIED | 1 hit: sync_inprocess_dispatch_test.exs |
| P-06 | 9 of 27 have pack.toml; optional legacy, strict in Core | UNVERIFIED | `ls priv/ggen/*/pack.toml`; pack.ex:8,15-32 |
| P-07 | `gall_work` breaks the `*-pack` naming | UNVERIFIED | `ls priv/ggen` |
| P-08 | 166 .rq in gates-like dirs; 2 lack NNN_ prefix (sjira) | UNVERIFIED | `find` count; epoch_boundary.rq, uncovered_gates.rq |
| P-09 | semantic-jira-pack has extra subdirs beyond CLAUDE.md shape | UNVERIFIED | `ls priv/ggen/semantic-jira-pack` |
| P-10 | ash-manufacture-pack ships bin/ scripts, verify/, README | UNVERIFIED | `ls priv/ggen/ash-manufacture-pack/{bin,verify}` |
| P-11 | 26 and 24 gates vs 1 and 4 templates (api, installer) | UNVERIFIED | gate/template counts; gate roles unread |
| P-12 | 7 packs have 1 name hit in lib+test; hit != e2e sync test | UNVERIFIED | `grep -rl` loop; test bodies unread |
| P-13 | semantic-jira-pack: 58 lib+test refs, 21 docs | UNVERIFIED | loop output |
| P-14 | every template is `<name>.<ext>.eex`; no stray files | UNVERIFIED | `find`+grep -v, both empty |
| P-15 | castle pack: pack.toml v26.9.28, but docs=0 | UNVERIFIED | `cat pack.toml`; docs grep=0 |

## Next

1. Run `mix ggen_igniter.sync --pack <name> --dry-run` over all 26 shaped packs and record
   exit codes; none was run this pass.
2. Decide the role of `doctrine-canonical-source` (data-only fixture vs pack) and where
   `contract.json` is consumed; name the consumer or move it.
3. Add the five undocumented packs to `docs/reference/cli/packs.md` (and `docs/status.md`
   only with run evidence).
4. Find or write a test for `dfcm-agent-pack`; confirm what its 6 gates feed.
5. Rename or relocate `ash-lifecycle-pack-inprocess-dispatch-test` if it is test-only;
   check that `gall_work` naming is intentional.
6. For packs with 1 name hit, read the test to see if it syncs for real (Chicago style).
7. Hand off gate-level non-vacuity to lane 11.

## See Also

- `docs/jira/v26.11.17/LANES.md`
- `priv/ggen/CLAUDE.md`
- `docs/reference/cli/packs.md`
- `lib/ggen_igniter/pack.ex`
