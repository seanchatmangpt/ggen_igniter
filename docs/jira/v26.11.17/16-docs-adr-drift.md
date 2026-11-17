# Lane 16: Docs and ADR Drift

Standing: UNVERIFIED

Read-only sweep of `docs/` structure at branch `claude/kind-ptolemy-imv2b6`. The generated
ADR README matches its pack ontology row for row (23 and 23), but both omit ADR 0010
(gate convention), which exists as a file. Two numbering schemes coexist by documented
design, with two real collisions (`0010` vs `ADR-010`, two files named `ADR-006`). A stray
PR body sits in the ADR directory. A link scan of `docs/` (excluding `archive/` and `jira/`)
found 93 broken of 215 relative-form links, 89 of them absolute `file:///Users/sac/`
paths. The glossary lacks several terms used in other docs. Nothing was run beyond
read-only shell commands; no engine or sync run was attempted.

## Findings

| id | finding | standing | evidence |
|---|---|---|---|
| F1 | ADR 0010 file missing from README and ontology | UNVERIFIED | ls + grep, see E1 |
| F2 | README rows equal ontology individuals (23) | UNVERIFIED | grep -c, see E2 |
| F3 | Two numbering schemes coexist by design | UNVERIFIED | `docs/CLAUDE.md:40` |
| F4 | Collision `0010-gate...` vs `ADR-010-event...` | UNVERIFIED | ls, ttl:74, see E1 |
| F5 | Two files named `ADR-006`, index 006a/006b | UNVERIFIED | see E5 |
| F6 | `0010-pr-body.md` is a PR body inside adr/ | UNVERIFIED | head, line 1; see E6 |
| F7 | ADR 0010 cites a path outside the repo | UNVERIFIED | `0010-gate-convention...md:4` |
| F8 | ttl header comment stale vs mixed content | UNVERIFIED | ttl:13 vs ttl:66-72 |
| F9 | String sort puts future `0011` before `ADR-001` | UNVERIFIED | `readme.md.eex` sort_by |
| F10 | 89 `file:///Users/sac/` links dead off-machine | UNVERIFIED | scan: 93 of 215 broken; E10 |
| F11 | Four true relative-link breaks | UNVERIFIED | see E11 |
| F12 | Glossary lacks terms used in other docs | UNVERIFIED | grep -ci = 0; see E12 |
| F13 | Glossary intro mentions a "requested list" | UNVERIFIED | `docs/glossary.md:3-6` |

## Evidence detail

- E1: `ls docs/architecture/adr` lists `0010-gate-convention-directory-is-convention.md`.
  README rows run 0001-0009 then ADR-001..013. `grep -n "0010-"` on the ontology: no match.
- E2: `grep -c "^adr:d.* a adr:Decision" ontology.ttl` = 23; `grep -c '^| \[' README.md` = 23.
  Titles spot-read only; regeneration not run.
- E5: `ADR-006-actuation-single-boundary.md:1` and
  `ADR-006-generational-resilience-manufacture.md:1`. The ttl comment above `adr:d0009`
  says no file was renamed.
- E6: 26 `.md` files in adr/ = 23 indexed + README + 0010 + `0010-pr-body.md`.
- E10: e.g. `docs/tutorials/getting-started.md:275-277`,
  `docs/reference/evidence/receipts.md:30`.
- E11: `docs/index.md:114` (`DOCUMENTATION_AUDIT.md` missing);
  `docs/contributing/dev-setup.md:53,116` (`../jira/v26.9.28/` dir missing);
  `docs/integrations/ash/overview.md:140` (fixture receipt.json not found).
- E12: counts in `docs/glossary.md` are 0 for `CodeWorkAuthority`, `WorkOrder`, `ALIVE_`,
  `residue`, `RuntimeShape`, `definition_digest`, `delegatab*`; each appears in other docs.
  `REFUSED_*` is covered at glossary:352.

## Method and limits

- Link scan: a python script in the scratchpad walked `docs/**/*.md` excluding `docs/archive`
  and `docs/jira`, skipped fenced and inline code, tested `](target)` existence relative to
  the file. Anchors were not validated, and reference-style links were not scanned.
- Glossary term counts are case-insensitive substring counts, not definitional checks.
- Stale-file claims in F7 and F10 were not checked against whether the target repos exist.

## Next

1. Add an `adr:Decision` individual for `0010-gate-convention...` to the pack ontology, move
   `0010-pr-body.md` out of the ADR dir, then re-sync (requires lane-owned approval).
2. Decide a collision rule (e.g. index id `0010` vs `ADR-010` is already distinct) and a
   numeric sort key so new `000N` entries do not precede `ADR-001`.
3. Rewrite `file:///Users/sac/...` links to repo-relative paths; fix the four F11 links.
4. Add glossary entries for F12 terms, or point to their source docs.
5. Run `mix ggen_igniter.sync --pack adr-index-pack --engine sparql` into a temp path and
   diff against the committed README to upgrade F2 from UNVERIFIED.

## See Also

- `docs/CLAUDE.md`
- `docs/architecture/adr/README.md`
- `priv/ggen/adr-index-pack/ontology.ttl`
- `docs/jira/v26.11.17/LANES.md`
