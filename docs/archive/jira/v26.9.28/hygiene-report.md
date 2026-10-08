# v26.9.28 Repo Hygiene Report (L9 / E3)

Subject: `/Users/sac/ggen_igniter`, branch `main`, HEAD `44c89aa` plus dirty tree. Measured 2026-09-28.
Nothing in this report was executed as a deletion. Only `.gitignore` and this file were edited.

## (a) Root and tree clutter

| path | tracked | ignored before | size | mtime | referenced by |
|---|---|---|---|---|---|
| `_build-*` (30 dirs) | no | yes (`/_build-*/`) | 7,919,239,168 B (7.38 GiB); 5.9 MB to 349 MB each | 2026-09-27/28 | none in `lib scripts .github mix.exs`; lane convention only |
| `_build` | no | yes | 349 MB | 2026-09-27 | canonical, keep |
| `ggen_igniter-26.9.{12,15,20,24,28}.tar` | no | yes (`*.tar`) | 10,518,528 B with the dump | 09-15 to 09-28 | no references in `.github scripts mix.exs` |
| `erl_crash.dump` | no | yes | 7 MB | 09-27 | none |
| `test/fixtures/book_library/erl_crash.dump` | no | yes | small | - | none |
| `agent..ttl.*` (4), `noagent..ttl.*` (2) | no | NO (untracked noise) | empty dirs | 09-27 | none (mktemp-style test leftovers) |
| `neg_*` (6 empty dirs at root) | no | NO (untracked noise) | empty | 09-27 | none; the two-port test uses `neg_*.ttl` file names inside temp dirs, not root dirs |
| `target/` (363 MB), `tmp/`, `tmp_out/`, `doc/` | no | yes | see left | - | build/scratch output |
| `wasm-artifacts/`, `release/` | yes (4 files each) | n/a | 19.5 MB / 36 KB | - | tracked, keep |

The `_build-lane4` and `_build-lane-ci` dirs were modified on 2026-09-28, so lanes may still be using them. Confirm no live `mix` process holds a lane root before any deletion.

## (b) .gitignore edit (done)

Appended root-anchored patterns: `/agent..ttl.*`, `/noagent..ttl.*`, `/neg_*`.

- `git check-ignore -v` shows all sampled paths matched (`.gitignore:63-65`).
- `git ls-files -ci --exclude-standard | wc -l` is `0`, so no tracked file is ignored.
- `git status --short` shows no `agent`/`neg_` entries any more.

All other clutter was already ignored (`_build-*`, `*.tar`, `erl_crash.dump`, `target`, `tmp*`, `doc`).

## (c) ADR numbering collision

Two schemes in `docs/architecture/adr/` (all tracked):

- Numeric: `0001`..`0009` (`0001-oxigraph-default-query-engine.md` .. `0009-runtime-shape-semantic-ir.md`).
- Prefixed: `ADR-001`..`ADR-012`.
- Colliding filenames (same `ADR-006` id):
  - `ADR-006-actuation-single-boundary.md`
  - `ADR-006-generational-resilience-manufacture.md`
- Near-collision by number: `0006-marker-based-injection-not-ast-patch.md` vs both `ADR-006-*`.
- Index gap: `README.md` (11 rows) lists only `0001`-`0008` and `ADR-010`, `ADR-011`, `ADR-012`. It omits `0009` and `ADR-001`..`ADR-009` (including both `ADR-006` files). The ontology `priv/ggen/adr-index-pack/ontology.ttl` has exactly those 11 `adr:Decision` individuals (lines 20-86), so the README matches its source and the gap is in the pack input.

Non-destructive fix (no renames, links stay valid):

1. Add `adr:Decision` individuals to `priv/ggen/adr-index-pack/ontology.ttl` for `0009` and `ADR-001`..`ADR-009`, with `adr:number` values `"0009"`, `"ADR-001"` ... and `"ADR-006a"` / `"ADR-006b"` (or `"ADR-006 (actuation)"` / `"ADR-006 (resilience)"`) for the two collisions. `adr:filename` copies the real filenames verbatim, and `title`/`status` come from each file's H1 and Status section.
2. Optional: add an `adr:scheme` property (`numeric`|`prefixed`) and a `adr:collidesWith` link, and extend `templates/readme.md.eex` with a "Numbering schemes" note. Note that `Enum.sort_by(& &1["number"])` sorts numeric before `ADR-` strings, which is acceptable.
3. Re-sync: `mix ggen_igniter.sync --pack adr-index-pack --engine sparql --out docs/architecture/adr/README.md`. Do not hand-edit the README.
4. New ADRs should take the next free prefixed number, `ADR-013`.

## (d) docs/status.md restated facts that drift

Line numbers are from `docs/status.md` as of this run.

| line | restated fact | re-derive |
|---|---|---|
| 20, 265 | 118 JSONL records | `wc -l < docs/archive/ggen_igniter_factory/docs-findings.jsonl` (now 118, holds) |
| 23-24 | "93" old claim vs 118 | same command |
| 27, 266 | HEAD `767bcce` snapshot | `git cat-file -t 767bcce` (historical, fixed; fine) |
| 67 | doctor is "18-check" | count check ids in `lib/mix/tasks/ggen_igniter.doctor.ex` (or run `mix ggen_igniter.doctor --json`); the grep count found 24 `check` mentions, so UNVERIFIED and likely stale |
| 70 | dogfood replay at HEAD `90c1da4` | `git cat-file -t 90c1da4`; historical SHA, not current |
| 179, 190 | 11 SPARQL gates in `ash_manufacture_pack` | `ls test/fixtures/ash_manufacture_pack/gates/*.rq \| wc -l` (measured 13 dir entries; recheck, possibly stale) |
| 190 | 21 `amp:GeneratorCapability` individuals | `grep -c 'a amp:GeneratorCapability' test/fixtures/ash_manufacture_pack/ontology.ttl` |
| 203 | StreamData "10 files" | `grep -rl StreamData test \| wc -l` (measured 16, stale) |
| 212 | dispatch test "12 tests" | `mix test test/ggen_igniter_semantic_a2a_dispatch_test.exs` |
| 216 | 78 `System.cmd("mix"` sites | `grep -rn 'System.cmd("mix"' test \| wc -l` (measured 106, stale) |
| 253-257 | EDS file/line refs (e.g. "114 lines") | `wc -l lib/ggen_igniter/eds/receipt.ex`; `ls test/ggen_igniter/eds` (5 files now) |

Recommendation for the coordinator: replace counts with the derivation command, or add these rows to a source-of-truth-check pass so drift is flagged automatically.

## Proposed osx-clnr deletion candidates (NOT EXECUTED, needs operator approval)

Regenerable build output and disposable artifacts only. Route through osx-clnr plan, approve, execute, receipt.

- `/Users/sac/ggen_igniter/_build-*` (30 dirs, all ignored, untracked): 7,919,239,168 B. Exclude `_build` itself and any lane root a live process is using (`_build-lane4`, `_build-lane-ci` were touched today).
- `/Users/sac/ggen_igniter/erl_crash.dump` and `ggen_igniter-26.9.{12,15,20,24}.tar`: about 10.0 MB (keep `26.9.28.tar` if it is the current release candidate, 1,496 KB).
- The empty dirs `agent..ttl.*` (4), `noagent..ttl.*` (2), `neg_*` (6): 0 B, now ignored.

Reminder after deleting: run `tmutil thinlocalsnapshots / <bytes> 4`, since APFS local snapshots pin deleted blocks and free space will not visibly rise otherwise.

## Coordinator edits requested

None to shared files. The `priv/ggen/adr-index-pack/ontology.ttl` change in (c) belongs to whichever lane or session owns that pack (no lane in `_LANES.md` does).
